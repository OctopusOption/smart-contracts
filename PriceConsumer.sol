// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./KiboConstants.sol";

interface IPriceConsumer {
    function getLatestPrice() external view returns (int);
}

library PriceConsumer {
    IPriceConsumer constant priceConsumerETH = IPriceConsumer(?);
    IPriceConsumer constant priceConsumerwBTC = IPriceConsumer(?);
    IPriceConsumer constant priceConsumerPolygon = IPriceConsumer(?);

    function getSpotPrice(uint8 underlying) external view returns (uint256) {
        // Feeds always return a number with 8 decimals, that represents the price of 1 asset in USD
        
        if (underlying == KiboConstants.ETH) {
            return uint256(priceConsumerETH.getLatestPrice());
        }
        else if (underlying == KiboConstants.WBTC) {
            return uint256(priceConsumerwBTC.getLatestPrice());
        }
        else if (underlying == KiboConstants.POLYGON) {
            return uint256(priceConsumerPolygon.getLatestPrice());
        }
        
        return 0;
    }
}