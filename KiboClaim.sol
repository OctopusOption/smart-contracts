// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;


import "./SafeERC20.sol";
import "./KiboStorage.sol";
import "./KiboConstants.sol";
import "./IKToken.sol";


contract KiboClaim is KiboStorage {
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
        uint8 underlying = IKToken(_optionAddress).getUnderlying();
        if (underlying == KiboConstants.ETH || underlying == KiboConstants.POLYGON) {
            amountToSubstract = seller.notional * optionWorth / 1e18; // I take out the decimals from the notional
        }
        else if (underlying == KiboConstants.WBTC) {
            amountToSubstract = seller.notional * optionWorth / 1e8; // I take out the decimals from the notional
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
            
            uint8 underlying = IKToken(_optionAddress).getUnderlying();
            if (underlying == KiboConstants.ETH) {
                payable(msg.sender).transfer(totalToReturn);
            }
            else if (underlying == KiboConstants.WBTC) {
                SafeERC20.safeTransfer(KiboConstants.wBTCToken, msg.sender, totalToReturn); // + interests
            }
            else if (underlying == KiboConstants.POLYGON) {
                SafeERC20.safeTransfer(KiboConstants.polygonToken, msg.sender, totalToReturn); // + interests
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
}