// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./KiboFees.sol";
import "./KiboRewards.sol";
import "./KiboCompound.sol";
import "./KiboStorage.sol";
import "./KiboAdmin.sol";

contract KiboFinance is KiboFees, KiboRewards, KiboCompound, KiboStorage, KiboAdmin {
    event OptionPurchase(address indexed option, address indexed buyer, uint256 weiNotional, uint256 usdtCollateral, uint256 premium);
    event ReturnedToSeller(address indexed option, address indexed seller, uint256 totalUSDTReturned, uint256 collateral, uint256 notional);
    event ReturnedToBuyer(address indexed option, address indexed buyer, uint256 totalUSDTReturned, uint256 _numberOfTokens);
    
    function getHowMuchToClaimForSellers(address _optionAddress, address _seller) public view returns (uint256) {
        Seller memory seller = options[_optionAddress].sellers[_seller];
        if (seller.claimed) {
            return 0;
        }
        
        uint256 optionWorth = options[_optionAddress].optionWorth; // This has 6 decimals as it is in USDT
        // For CALL I need to convert the price from USDT to the underlying
        if (!IKToken(_optionAddress).isPut()) {
            optionWorth = optionWorth / options[_optionAddress].spotPrice;
        }
        
        uint256 amountToSubstract;
        address underlying = IKToken(_optionAddress).getUnderlying();
        if (underlying == address(0)) {
            amountToSubstract = seller.notional * optionWorth / 1e18; // I take out the decimals from the notional
        }
        else {
            uint256 decimals = ERC20(underlying).decimals();
            amountToSubstract = seller.notional * optionWorth / (10 ** (decimals)); // I take out the decimals from the notional
        }
        
        return seller.collateral - amountToSubstract;
    }
    
    function claimCollateralAtMaturityForSellers(address _optionAddress) external {
        require(options[_optionAddress].isValid, "Invalid option");
        require(options[_optionAddress].spotPrice > 0, "Still not ready");
        
        Seller storage seller = options[_optionAddress].sellers[msg.sender];
        
        require(seller.isValid, "Seller not valid");
        require(!seller.claimed, "Already claimed");
        
        uint256 totalToReturn = getHowMuchToClaimForSellers(_optionAddress, msg.sender); // This is in USDT for PUT and in the underlying for CALL
        require(totalToReturn > 0, 'Nothing to return');
        
        seller.claimed = true;

        if (IKToken(_optionAddress).isPut()) {
            //ICERC20 cToken = ICERC20(cUSDT);
            //uint256 interests = seller.cTokens * cToken.exchangeRateCurrent() - seller.collateral;

            //uint256 redeemResult = redeemICERC20Tokens(totalToReturn + interests, true, cUSDT);
            //require(redeemResult == 0, "An error occurred");

            SafeERC20.safeTransfer(KiboConstants.usdtToken, msg.sender, totalToReturn); // + interests
        } else {
            //ICETH cToken = ICETH(cETH);
            //uint256 interests = seller.cTokens * cToken.exchangeRateCurrent() - seller.collateral;
            //uint256 redeemResult = redeemICETH(totalToReturn + interests, true, cETH);
            //require(redeemResult == 0, "An error occurred");
            
            address underlying = IKToken(_optionAddress).getUnderlying();
            if (underlying == address(0)) {
                payable(msg.sender).transfer(totalToReturn);
            }
            else {
                SafeERC20.safeTransfer(ERC20(underlying), msg.sender, totalToReturn); // + interests
            }
        }
        
        emit ReturnedToSeller(_optionAddress, msg.sender, totalToReturn, seller.collateral, seller.notional);
    }
    
    function getHowMuchToClaimForBuyers(address _optionAddress, uint256 _numberOfKTokens) public view returns (uint256) {
        uint256 optionWorth = options[_optionAddress].optionWorth; // This has 6 decimals as it is in USDT
        return _numberOfKTokens * optionWorth / 1e4; // As KToken has 4 decimals
    }
    
    function claimCollateralAtMaturityForBuyers(address _optionAddress, uint256 _numberOfKTokens) external {
        require(options[_optionAddress].isValid, "Invalid option");
        require(options[_optionAddress].spotPrice > 0, "Still not ready");
        require(_numberOfKTokens > 0, "Invalid number of tokens");
        
        require(IERC20(_optionAddress).transferFrom(msg.sender, address(this), _numberOfKTokens), "Transfer failed");
        
        uint256 totalToReturn = getHowMuchToClaimForBuyers(_optionAddress, _numberOfKTokens);
        SafeERC20.safeTransfer(KiboConstants.usdtToken, msg.sender, totalToReturn);

        emit ReturnedToBuyer(_optionAddress, msg.sender, totalToReturn, _numberOfKTokens);
    }
    
    // Notional has the number of decimals of the underlying
    function sell(address _optionAddress, uint256 _notional) payable external validOption(_optionAddress) {
        Seller storage seller = options[_optionAddress].sellers[msg.sender];
        address underlying = IKToken(_optionAddress).getUnderlying();

        uint256 usdtCollateral;
        uint256 feesToCollect;
        uint256 decimals = 18;

        if (IKToken(_optionAddress).isPut()) {
            usdtCollateral = calculateCollateralForPut(_optionAddress, _notional);
            SafeERC20.safeTransferFrom(KiboConstants.usdtToken, msg.sender, address(this), usdtCollateral);
            //seller.cTokens += supplyErc20ToCompound(usdtToken, cUSDT, usdtCollateral);
        } 
        else {
            if (underlying != address(0)) {
                decimals = ERC20(underlying).decimals();
                SafeERC20.safeTransferFrom(ERC20(underlying), msg.sender, address(this), _notional);
                //seller.cTokens += supplyErc20ToCompound(wBTCToken, cwBTC, _notional);
            } else  {
                require(msg.value == _notional, 'Invalid collateral');
                //seller.cTokens += supplyEthToCompound(cETH, _notional);
            }
        }   
        
        IKToken(_optionAddress).mint(address(this), _notional / 10 ** (decimals-4));  // KToken has 4 decimals. We deduce 4 from the underlying's number of decimals
        
        //We sell the tokens for USDT in Uniswap, which is sent to the user
        uint256 premium = sellKTokensInUniswap(_optionAddress, _notional);
        
        if (IKToken(_optionAddress).isPut()) {
            feesToCollect = usdtCollateral / 100;
            seller.collateral += usdtCollateral - feesToCollect;
            fees[address(KiboConstants.usdtToken)] += feesToCollect;
        } else {
            feesToCollect = _notional / 100;
            seller.collateral += _notional - feesToCollect;
            
            if (underlying != address(0)) {
                fees[underlying] += feesToCollect;
            }
            else {
                totalETHFees += feesToCollect;
            }
        }

        seller.isValid = true;
        seller.notional += _notional;
        
        //We emit an event to be able to send KiboTokens offchain, according to the difference against the theoretical Premium
        emit OptionPurchase(_optionAddress, msg.sender, _notional, usdtCollateral, premium);
    }
    
    // Collateral is always kept in USDT
    function calculateCollateralForPut(address _optionAddress, uint256 _notional) public view returns (uint256) {
        uint256 collateral = IKToken(_optionAddress).getStrike() * _notional;

        // I still need to remove 2 decimals from the strike (as it is in USD, not USDT) and the notional decimals, which depend on the underlying

        uint256 decimals = 20;
        address underlying = IKToken(_optionAddress).getUnderlying();
        if (underlying != address(0)) {
            decimals = 2 + ERC20(underlying).decimals();
        }
            
        return collateral / (10 ** decimals);
    }

    receive() external payable {
        revert();
    }
}