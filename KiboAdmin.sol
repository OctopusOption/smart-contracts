// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;


import "./SafeERC20.sol";
import "./Ownable.sol";
import "./KiboStorage.sol";
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
    
    function _enableUnderlying(address _underlying, address _cToken, bool _stakeCollateral, address _priceConsumer) external onlyOwner {
        underlyings[_underlying].isActive = true;
        underlyings[_underlying].cToken = _cToken;
        underlyings[_underlying].stakeCollateral = _stakeCollateral;
        underlyings[_underlying].priceConsumer = _priceConsumer;
    }

    function _disableUnderlying(address _underlying) external onlyOwner {
        underlyings[_underlying].isActive = false;
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
        address underlying = IKToken(_optionAddress).getUnderlying();
        require(underlyings[underlying].isActive, "Invalid underlying");

        options[_optionAddress].isValid = true;

        IKToken(_optionAddress).mint(address(this), _uniswapInitialTokens); // This has 4 decimals
        
        Seller storage seller = options[_optionAddress].sellers[msg.sender];
        seller.collateral = _usdtCollateral;
        seller.isValid = true;
        
        uint256 decimals = 18;
        if (underlying != address(0)) {
            decimals = ERC20(underlying).decimals();
        }
        seller.notional = _uniswapInitialTokens * 10 ** (decimals-4);
        
        SafeERC20.safeTransferFrom(KiboConstants.usdtToken, msg.sender, address(this), _uniswapInitialUSDT + _usdtCollateral);
        //seller.cTokens += supplyErc20ToCompound(usdtToken, cUSDT, _usdtCollateral);

        createPairInUniswap(_optionAddress, _uniswapInitialTokens, _uniswapInitialUSDT);
    }
    
    function _activateCallOption(address _optionAddress, uint256 _uniswapInitialUSDT, uint256 _uniswapInitialTokens, uint256 _collateral) external validOption(_optionAddress) payable onlyOwner {
        require(_uniswapInitialUSDT > 0, "Uniswap USDT cannot be zero");
        require(_uniswapInitialTokens > 0, "Uniswap tokens cannot be zero");
        require(!IKToken(_optionAddress).isPut(), "Option is not CALL");
        address underlying = IKToken(_optionAddress).getUnderlying();
        require(underlyings[underlying].isActive, "Invalid underlying");
        
        if (underlying != address(0)) {
            require(_collateral > 0, "Collateral cannot be zero");
        } else  {
            require(msg.value > 0, "Collateral cannot be zero");
        }

        options[_optionAddress].isValid = true;

        IKToken(_optionAddress).mint(address(this), _uniswapInitialTokens);
        
        //seller.cTokens += supplyEthToCompound(cETH, msg.value);

        SafeERC20.safeTransferFrom(KiboConstants.usdtToken, msg.sender, address(this), _uniswapInitialUSDT);

        Seller storage seller = options[_optionAddress].sellers[msg.sender];

        uint256 decimals = 18;
        if (underlying != address(0)) {
            decimals = ERC20(underlying).decimals();
            SafeERC20.safeTransferFrom(ERC20(underlying), msg.sender, address(this), _collateral);
        } else  {
            seller.collateral = msg.value;
        }

        seller.isValid = true;
        seller.notional = _uniswapInitialTokens * 10 ** (decimals-4); // KToken has 4 decimals. We deduce 4 from the underlying's number of decimals
        
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