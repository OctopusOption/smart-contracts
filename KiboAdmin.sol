// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;


import "./SafeERC20.sol";
import "./Ownable.sol";
import "./KiboStorage.sol";
import "./IKToken.sol";
import "./KiboConstants.sol";
import "./KiboUniswap.sol";
import "./PriceConsumer.sol";


contract KiboAdmin is Ownable, KiboStorage, KiboUniswap {
    event OptionFinalPriceSet(address indexed option, uint256 assetPriceInUsdt, uint256 optionWorthInUsdt);

    modifier validOption(address _optionAddress) {
        require(options[_optionAddress].isValid, "Invalid option");
        require(IKToken(_optionAddress).getExpiresOn() > block.timestamp, "Expired option");
        _;
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
        if (underlying == KiboConstants.ETH || underlying == KiboConstants.POLYGON) {
            seller.notional = _uniswapInitialTokens * 1e14; // KToken has 4 decimals and ETH and POLY have 18 decimals
        }
        else if (underlying == KiboConstants.WBTC)
        {
            seller.notional = _uniswapInitialUSDT * 1e4; // KToken has 4 decimals and WBTC has 4 decimals            
        }
        else {
            revert("Invalid underlying");
        }
        
        SafeERC20.safeTransferFrom(KiboConstants.usdtToken, msg.sender, address(this), _uniswapInitialUSDT + _usdtCollateral);
        //seller.cTokens += supplyErc20ToCompound(usdtToken, cUSDT, _usdtCollateral);

        createPairInUniswap(_optionAddress, _uniswapInitialTokens, _uniswapInitialUSDT);
    }
    
    function _activateEthCallOption(address _optionAddress, uint256 _uniswapInitialUSDT, uint256 _uniswapInitialTokens) external validOption(_optionAddress) payable onlyOwner {
        require(msg.value > 0, "Collateral cannot be zero");
        require(_uniswapInitialUSDT > 0, "Uniswap USDT cannot be zero");
        require(_uniswapInitialTokens > 0, "Uniswap tokens cannot be zero");
        require(!IKToken(_optionAddress).isPut(), "Option is not CALL");
        require(IKToken(_optionAddress).getUnderlying() == KiboConstants.ETH, "Wrong underlying");

        options[_optionAddress].isValid = true;

        IKToken(_optionAddress).mint(address(this), _uniswapInitialTokens);
        
        //seller.cTokens += supplyEthToCompound(cETH, msg.value);

        SafeERC20.safeTransferFrom(KiboConstants.usdtToken, msg.sender, address(this), _uniswapInitialUSDT);

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
        require(IKToken(_optionAddress).getUnderlying() == KiboConstants.WBTC, "Wrong underlying");

        options[_optionAddress].isValid = true;

        IKToken(_optionAddress).mint(address(this), _uniswapInitialTokens);
        
        //seller.cTokens += supplyErc20ToCompound(wBTCToken, cwBTC, _collateral);

        SafeERC20.safeTransferFrom(KiboConstants.wBTCToken, msg.sender, address(this), _collateral);
        SafeERC20.safeTransferFrom(KiboConstants.usdtToken, msg.sender, address(this), _uniswapInitialUSDT);

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
        require(IKToken(_optionAddress).getUnderlying() == KiboConstants.POLYGON, "Wrong underlying");

        options[_optionAddress].isValid = true;

        IKToken(_optionAddress).mint(address(this), _uniswapInitialTokens);
        
        SafeERC20.safeTransferFrom(KiboConstants.polygonToken, msg.sender, address(this), _collateral);
        SafeERC20.safeTransferFrom(KiboConstants.usdtToken, msg.sender, address(this), _uniswapInitialUSDT);

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
        
        uint256 spotPrice = PriceConsumer.getSpotPrice(IKToken(_optionAddress).getUnderlying()); // In USD, 8 decimals
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
}