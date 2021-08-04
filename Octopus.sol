// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./PriceConsumer.sol";
import "./IUniswapV2Router02.sol";
import "./ICETH.sol";
import "./ICERC20.sol";
import "./IKToken.sol";


contract Octopus is Ownable {
    PriceConsumer priceConsumer = PriceConsumer(?);
    IUniswapV2Router02 uniswapRouter = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IERC20 kiboToken =  IERC20(?);
    ERC20 usdtToken = ERC20(?);
    ERC20 wBTCToken = ERC20(?);
    ERC20 polygonToken = ERC20(?);

    address payable cETH = payable(?);
    address cUSDT = ?;
    address cwBTC = ?;

    uint8 constant ETH = 1;
    uint8 constant WBTC = 2;
    uint8 constant POLYGON = 3;

    uint256 public totalETHFees; // 18 decimals
    uint256 public totalWBTCFees; // 8 decimals
    uint256 public totalPOLYFees; // 18 decimals
    uint256 public totalUSDTFees; // 6 decimals

    struct Seller {
        bool isValid;
        uint256 collateral; // This is in USDT (6 decimals) for PUT and in the underlying (same decimals) for CALL
        uint256 notional; // This has the same number of decimals as the underlying
        bool claimed;
        uint256 cTokens; // All decimals
    }
    
    struct Option {
        bool isValid;
        uint256 spotPrice; // This has 6 decimals (we remove 2 when moving from USD to USDT)
        uint256 optionWorth; // This has 6 decimals (same as above)
        mapping(address => Seller) sellers;
    }
    
    mapping(address => Option) options;
    mapping(address => uint256) public kiboRewards;

    event OptionPurchase(address indexed option, address indexed buyer, uint256 weiNotional, uint256 usdtCollateral, uint256 premium);
    event RewardsIncreased(address indexed beneficiary, uint256 total);
    event RewardsWithdrawn(address indexed beneficiary, uint256 total);
    event ReturnedToSeller(address indexed option, address indexed seller, uint256 totalUSDTReturned, uint256 collateral, uint256 notional);
    event ReturnedToBuyer(address indexed option, address indexed buyer, uint256 totalUSDTReturned, uint256 _numberOfTokens);
    event OptionFinalPriceSet(address indexed option, uint256 assetPriceInUsdt, uint256 optionWorthInUsdt);
    
    modifier validOption(address _optionAddress) {
        require(options[_optionAddress].isValid, "Invalid option");
        require(IKToken(_optionAddress).getExpiresOn() > block.timestamp, "Expired option");
        _;
    }

    // Notional has the number of decimals of the underlying
    function sell(address _optionAddress, uint256 _notional) payable external validOption(_optionAddress) {
        Seller storage seller = options[_optionAddress].sellers[msg.sender];
        uint8 underlying = IKToken(_optionAddress).getUnderlying();

        uint256 usdtCollateral;
        uint256 feesToCollect;

        if (IKToken(_optionAddress).isPut()) {
            usdtCollateral = calculateCollateralForPut(_optionAddress, _notional);
            SafeERC20.safeTransferFrom(usdtToken, msg.sender, address(this), usdtCollateral);
            //seller.cTokens += supplyErc20ToCompound(usdtToken, cUSDT, usdtCollateral);
        } 
        else {
            if (underlying == ETH) {
                require(msg.value == _notional, 'Invalid collateral');
                //seller.cTokens += supplyEthToCompound(cETH, _notional);
            }
            else if (underlying == WBTC) {
                SafeERC20.safeTransferFrom(wBTCToken, msg.sender, address(this), _notional);
                //seller.cTokens += supplyErc20ToCompound(wBTCToken, cwBTC, _notional);
            }
            else if (underlying == POLYGON) {
                SafeERC20.safeTransferFrom(polygonToken, msg.sender, address(this), _notional);
                // There's no Polygon pool in Compound yet
            }
        }   
        
        if (underlying == ETH || underlying == POLYGON) {
            IKToken(_optionAddress).mint(address(this), _notional / 1e14); // ETH and POLY have 18 decimals while KToken has 4
        }
        else if (underlying == WBTC) {
            IKToken(_optionAddress).mint(address(this), _notional / 1e4); // WBTC has 8 decimals while KToken has 4
        }
        
        //We sell the tokens for USDT in Uniswap, which is sent to the user
        uint256 premium = sellKTokensInUniswap(_optionAddress, _notional);
        
        if (IKToken(_optionAddress).isPut()) {
            feesToCollect = usdtCollateral / 100;
            seller.collateral += usdtCollateral - feesToCollect;
            totalUSDTFees += feesToCollect;
        } else {
            feesToCollect = _notional / 100;
            seller.collateral += _notional - feesToCollect;
            if (underlying == ETH) {
                totalETHFees += feesToCollect;
            }
            else if (underlying == WBTC) {
                totalWBTCFees += feesToCollect;
            }
            else if (underlying == WBTC) {
                totalPOLYFees += feesToCollect;
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
        
        if (IKToken(_optionAddress).getUnderlying() == ETH || IKToken(_optionAddress).getUnderlying() == POLYGON) {
            return collateral / 1e20;
        }
        
        return collateral / 1e10; // WBTC
    }
    
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
        if (underlying == ETH || underlying == POLYGON) {
            amountToSubstract = seller.notional * optionWorth / 1e18; // I take out the decimals from the notional
        }
        else if (underlying == WBTC) {
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

            SafeERC20.safeTransfer(usdtToken, msg.sender, totalToReturn); // + interests
        } else {
            //ICETH cToken = ICETH(cETH);
            //uint256 interests = seller.cTokens * cToken.exchangeRateCurrent() - seller.collateral;
            //uint256 redeemResult = redeemICETH(totalToReturn + interests, true, cETH);
            //require(redeemResult == 0, "An error occurred");
            
            uint8 underlying = IKToken(_optionAddress).getUnderlying();
            if (underlying == ETH) {
                payable(msg.sender).transfer(totalToReturn);
            }
            else if (underlying == WBTC) {
                SafeERC20.safeTransfer(wBTCToken, msg.sender, totalToReturn); // + interests
            }
            else if (underlying == POLYGON) {
                SafeERC20.safeTransfer(polygonToken, msg.sender, totalToReturn); // + interests
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
        SafeERC20.safeTransfer(usdtToken, msg.sender, totalToReturn);

        emit ReturnedToBuyer(_optionAddress, msg.sender, totalToReturn, _numberOfKTokens);
    }
    
    function withdrawKiboTokens() external {
        require(kiboRewards[msg.sender] > 0, "Nothing to withdraw");
        uint256 total = kiboRewards[msg.sender];
        kiboRewards[msg.sender] = 0;
        SafeERC20.safeTransfer(kiboToken, msg.sender, total);
        emit RewardsWithdrawn(msg.sender, total);
    }

    // Public functions
    
    // Returns the amount in USDT if you sell 1 KiboToken in Uniswap
    function getKiboSellPrice() external view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(kiboToken);
        path[1] = address(usdtToken);
        uint[] memory amounts = uniswapRouter.getAmountsOut(1e18, path);
        return amounts[1];
    }
    
    // Returns the amount in USDT if you buy 1 KiboToken in Uniswap
    function getKiboBuyPrice() external view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(usdtToken);
        path[1] = address(kiboToken);
        uint[] memory amounts = uniswapRouter.getAmountsIn(1e18, path);
        return amounts[0];
    }
    
    // Internal functions
    
    function sellKTokensInUniswap(address _optionAddress, uint256 _tokensAmount) internal returns (uint256)  {
        address[] memory path = new address[](2);
        path[0] = _optionAddress;
        path[1] = address(usdtToken);
        IERC20(_optionAddress).approve(address(uniswapRouter), _tokensAmount);
        // TODO: uint256[] memory amountsOutMin = uniswapRouter.getAmountsOut(_tokensAmount, path);
        // Use amountsOutMin[1]
        uint[] memory amounts = uniswapRouter.swapExactTokensForTokens(_tokensAmount, 0, path, msg.sender, block.timestamp);
        return amounts[1];
    }
    
    function createPairInUniswap(address _optionAddress, uint256 _totalTokens, uint256 _totalUSDT) internal returns (uint amountA, uint amountB, uint liquidity) {
        uint256 allowance = usdtToken.allowance(address(this), address(uniswapRouter));
        if (allowance > 0 && allowance < _totalUSDT) {
            SafeERC20.safeApprove(usdtToken, address(uniswapRouter), 0);
        }
        if (allowance == 0) {
            SafeERC20.safeApprove(usdtToken, address(uniswapRouter), _totalUSDT);
        }
        IERC20(_optionAddress).approve(address(uniswapRouter), _totalTokens);
        (amountA, amountB, liquidity) = uniswapRouter.addLiquidity(_optionAddress, address(usdtToken), _totalTokens, _totalUSDT, 0, 0, msg.sender, block.timestamp);
    }

    //Admin functions
    
    function _addKiboRewards(address _beneficiary, uint256 _total) external onlyOwner {
        kiboRewards[_beneficiary] += _total;
        emit RewardsIncreased(_beneficiary, _total);
    }
    
    function _deactivateOption(address _optionAddress) external onlyOwner {
        require(options[_optionAddress].isValid, "It is not activated");
        options[_optionAddress].isValid = false;
    }
    
    function _activatePutOption(address _optionAddress, uint256 _usdtCollateral, uint256 _uniswapInitialUSDT, uint256 _uniswapInitialTokens) external validOption(_optionAddress) onlyOwner {
        require(_usdtCollateral > 0, "Collateral cannot be zero");
        require(_uniswapInitialUSDT > 0, "Uniswap USDT cannot be zero");
        require(_uniswapInitialTokens > 0, "Uniswap tokens cannot be zero");
        require(IKToken(_optionAddress).isPut(), "Option is not PUT");

        options[_optionAddress].isValid = true;

        IKToken(_optionAddress).mint(address(this), _uniswapInitialTokens); // This has 4 decimals
        
        Seller storage seller = options[_optionAddress].sellers[msg.sender];
        seller.collateral = _usdtCollateral;
        seller.isValid = true;
        
        uint8 underlying = IKToken(_optionAddress).getUnderlying();
        if (underlying == ETH || underlying == POLYGON) {
            seller.notional = _uniswapInitialTokens * 1e14; // KToken has 4 decimals and ETH and POLY have 18 decimals
        }
        else if (underlying == WBTC)
        {
            seller.notional = _uniswapInitialUSDT * 1e4; // KToken has 4 decimals and WBTC has 4 decimals            
        }
        else {
            revert("Invalid underlying");
        }
        
        SafeERC20.safeTransferFrom(usdtToken, msg.sender, address(this), _uniswapInitialUSDT + _usdtCollateral);
        //seller.cTokens += supplyErc20ToCompound(usdtToken, cUSDT, _usdtCollateral);

        createPairInUniswap(_optionAddress, _uniswapInitialTokens, _uniswapInitialUSDT);
    }
    
    function _activateEthCallOption(address _optionAddress, uint256 _uniswapInitialUSDT, uint256 _uniswapInitialTokens) external validOption(_optionAddress) payable onlyOwner {
        require(msg.value > 0, "Collateral cannot be zero");
        require(_uniswapInitialUSDT > 0, "Uniswap USDT cannot be zero");
        require(_uniswapInitialTokens > 0, "Uniswap tokens cannot be zero");
        require(!IKToken(_optionAddress).isPut(), "Option is not CALL");
        require(IKToken(_optionAddress).getUnderlying() == ETH, "Wrong underlying");

        options[_optionAddress].isValid = true;

        IKToken(_optionAddress).mint(address(this), _uniswapInitialTokens);
        
        //seller.cTokens += supplyEthToCompound(cETH, msg.value);

        SafeERC20.safeTransferFrom(usdtToken, msg.sender, address(this), _uniswapInitialUSDT);

        Seller storage seller = options[_optionAddress].sellers[msg.sender];
        seller.collateral = msg.value;
        seller.isValid = true;
        seller.notional = _uniswapInitialTokens * 1e14; // KToken has 4 decimals and ETH has 18 decimals
        
        createPairInUniswap(_optionAddress, _uniswapInitialTokens, _uniswapInitialUSDT);
    }
    
    function _activatewBTCCallOption(address _optionAddress, uint256 _collateral, uint256 _uniswapInitialUSDT, uint256 _uniswapInitialTokens) external validOption(_optionAddress) payable onlyOwner {
        require(_collateral > 0, "Collateral cannot be zero");
        require(_uniswapInitialUSDT > 0, "Uniswap USDT cannot be zero");
        require(_uniswapInitialTokens > 0, "Uniswap tokens cannot be zero");
        require(!IKToken(_optionAddress).isPut(), "Option is not CALL");
        require(IKToken(_optionAddress).getUnderlying() == WBTC, "Wrong underlying");

        options[_optionAddress].isValid = true;

        IKToken(_optionAddress).mint(address(this), _uniswapInitialTokens);
        
        //seller.cTokens += supplyErc20ToCompound(wBTCToken, cwBTC, _collateral);

        SafeERC20.safeTransferFrom(wBTCToken, msg.sender, address(this), _collateral);
        SafeERC20.safeTransferFrom(usdtToken, msg.sender, address(this), _uniswapInitialUSDT);

        Seller storage seller = options[_optionAddress].sellers[msg.sender];
        seller.collateral = _collateral;
        seller.isValid = true;
        seller.notional = _uniswapInitialTokens * 1e4; // KToken has 4 decimals and ETH has 8 decimals
        
        createPairInUniswap(_optionAddress, _uniswapInitialTokens, _uniswapInitialUSDT);
    }
    
    function _activatePolygonCallOption(address _optionAddress, uint256 _collateral, uint256 _uniswapInitialUSDT, uint256 _uniswapInitialTokens) external validOption(_optionAddress) payable onlyOwner {
        require(_collateral > 0, "Collateral cannot be zero");
        require(_uniswapInitialUSDT > 0, "Uniswap USDT cannot be zero");
        require(_uniswapInitialTokens > 0, "Uniswap tokens cannot be zero");
        require(!IKToken(_optionAddress).isPut(), "Option is not CALL");
        require(IKToken(_optionAddress).getUnderlying() == POLYGON, "Wrong underlying");

        options[_optionAddress].isValid = true;

        IKToken(_optionAddress).mint(address(this), _uniswapInitialTokens);
        
        SafeERC20.safeTransferFrom(polygonToken, msg.sender, address(this), _collateral);
        SafeERC20.safeTransferFrom(usdtToken, msg.sender, address(this), _uniswapInitialUSDT);

        Seller storage seller = options[_optionAddress].sellers[msg.sender];
        seller.collateral = _collateral;
        seller.isValid = true;
        seller.notional = _uniswapInitialTokens * 1e14; // KToken has 4 decimals and POLY has 18 decimals
        
        createPairInUniswap(_optionAddress, _uniswapInitialTokens, _uniswapInitialUSDT);
    }
    
    function _setFinalPriceAtMaturity(address _optionAddress) external onlyOwner {
        require(options[_optionAddress].isValid, "Invalid option");
        require(options[_optionAddress].spotPrice == 0, "Already set");
        require(IKToken(_optionAddress).getExpiresOn() < block.timestamp, "Still not expired");
        
        uint256 spotPrice = priceConsumer.getSpotPrice(IKToken(_optionAddress).getUnderlying()); // In USD, 8 decimals
        uint256 strike = IKToken(_optionAddress).getStrike(); // In USD, 8 decimals
        bool isPut = IKToken(_optionAddress).isPut();
        
        uint256 optionWorth = 0;
    
        if (isPut && spotPrice < strike) {
            optionWorth = strike - spotPrice;
        }
        else if (!isPut && spotPrice > strike) {
            optionWorth = spotPrice - strike;
        }
        
        optionWorth = optionWorth / 100; // I remove the extra 2 decimals to make it in USDT
        spotPrice = spotPrice / 100; // I remove the extra 2 decimals to make it in USDT
        
        options[_optionAddress].spotPrice = spotPrice;
        options[_optionAddress].optionWorth = optionWorth;
        
        emit OptionFinalPriceSet(_optionAddress, spotPrice, optionWorth);
    }
    
    function _withdrawUSDTFees() external onlyOwner {
        require(totalUSDTFees > 0, 'Nothing to claim');
        uint256 amount = totalUSDTFees;
        totalUSDTFees = 0;
        SafeERC20.safeTransfer(usdtToken, msg.sender, amount);
    }
    
    function _withdrawWBTCFees() external onlyOwner {
        require(totalWBTCFees > 0, 'Nothing to claim');
        uint256 amount = totalWBTCFees;
        totalWBTCFees = 0;
        SafeERC20.safeTransfer(wBTCToken, msg.sender, amount);
    }

    function _withdrawPOLYFees() external onlyOwner {
        require(totalPOLYFees > 0, 'Nothing to claim');
        uint256 amount = totalPOLYFees;
        totalPOLYFees = 0;
        SafeERC20.safeTransfer(polygonToken, msg.sender, amount);
    }

    function _withdrawETHFees() external onlyOwner {
        require(totalETHFees > 0, 'Nothing to claim');
        uint256 amount = totalETHFees;
        totalETHFees = 0;
        payable(msg.sender).transfer(amount);
    }

    function _withdrawKibo(uint256 _amount) external onlyOwner {
        SafeERC20.safeTransfer(kiboToken, msg.sender, _amount);
    }
    
    function getOption(address _optionAddress) external view returns (bool _isValid, bool _isPut, uint256 _spotPrice, uint256 _optionWorth) {
        return (options[_optionAddress].isValid, IKToken(_optionAddress).isPut(), options[_optionAddress].spotPrice, options[_optionAddress].optionWorth);
    }
    
    function getSeller(address _optionAddress, address _seller) external view returns (bool _isValid, uint256 _collateral, uint256 _notional, bool _claimed, uint256 _cTokens) {
        Seller memory seller = options[_optionAddress].sellers[_seller];
        return (seller.isValid, seller.collateral, seller.notional, seller.claimed, seller.cTokens);
    }

    //Compound
    
     function supplyEthToCompound(address payable _cEtherContract, uint256 _total)
        internal
        returns (uint256)
    {
        // Create a reference to the corresponding cToken contract
        ICETH cToken = ICETH(_cEtherContract);

        uint256 balance = cToken.balanceOf(address(this));

        cToken.mint{value:_total, gas: 250000}();
        return cToken.balanceOf(address(this)) - balance;
    }
    
    function supplyErc20ToCompound(
        ERC20 _erc20Contract,
        address _ICERC20Contract,
        uint256 _numTokensToSupply
    ) internal returns (uint) {
        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(_ICERC20Contract);

        uint256 balance = cToken.balanceOf(address(this));

        // Approve transfer on the ERC20 contract
        SafeERC20.safeApprove(_erc20Contract, _ICERC20Contract, _numTokensToSupply);

        // Mint cTokens
        cToken.mint(_numTokensToSupply);
        
        uint256 newBalance = cToken.balanceOf(address(this));

        return newBalance - balance;
    }
    
    function redeemICERC20Tokens(
        uint256 amount,
        bool redeemType,
        address _ICERC20Contract
    ) internal returns (uint256) {
        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(_ICERC20Contract);

        // `amount` is scaled up, see decimal table here:
        // https://compound.finance/docs#protocol-math

        uint256 redeemResult;

        if (redeemType == true) {
            // Retrieve your asset based on a cToken amount
            redeemResult = cToken.redeem(amount);
        } else {
            // Retrieve your asset based on an amount of the asset
            redeemResult = cToken.redeemUnderlying(amount);
        }

        return redeemResult;
    }

    function redeemICETH(
        uint256 amount,
        bool redeemType,
        address _cEtherContract
    ) internal returns (uint256) {
        // Create a reference to the corresponding cToken contract
        ICETH cToken = ICETH(_cEtherContract);

        // `amount` is scaled up by 1e18 to avoid decimals

        uint256 redeemResult;

        if (redeemType == true) {
            // Retrieve your asset based on a cToken amount
            redeemResult = cToken.redeem(amount);
        } else {
            // Retrieve your asset based on an amount of the asset
            redeemResult = cToken.redeemUnderlying(amount);
        }

        // Error codes are listed here:
        // https://compound.finance/docs/ctokens#ctoken-error-codes
        return redeemResult;
    }

    receive() external payable {
        revert();
    }
}