// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./IKToken.sol";


contract KiboStorage {
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
    
    struct Underlying {
        bool isActive;
        address cToken;
        bool stakeCollateral;
        address priceConsumer;
    }
    
    mapping(address => Option) options;
    mapping(address => Underlying) underlyings;
    
    function getOption(address _optionAddress) external view returns (bool _isValid, bool _isPut, uint256 _spotPrice, uint256 _optionWorth) {
        return (options[_optionAddress].isValid, IKToken(_optionAddress).isPut(), options[_optionAddress].spotPrice, options[_optionAddress].optionWorth);
    }
    
    function getSeller(address _optionAddress, address _seller) external view returns (bool _isValid, uint256 _collateral, uint256 _notional, bool _claimed, uint256 _cTokens) {
        Seller memory seller = options[_optionAddress].sellers[_seller];
        return (seller.isValid, seller.collateral, seller.notional, seller.claimed, seller.cTokens);
    }
}