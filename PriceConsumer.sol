// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

interface IPriceConsumer {
    function getLatestPrice() external view returns (int);
}

contract PriceConsumer {
    IPriceConsumer priceConsumerETH = IPriceConsumer(?);
    IPriceConsumer priceConsumerwBTC = IPriceConsumer(?);
    IPriceConsumer priceConsumerPolygon = IPriceConsumer(?);

    uint8 constant ETH = 1;
    uint8 constant WBTC = 2;
    uint8 constant POLYGON = 3;

    function getSpotPrice(uint8 underlying) external view returns (uint256) {
        // Feeds always return a number with 8 decimals, that represents the price of 1 asset in USD
        
        if (underlying == ETH) {
            return uint256(priceConsumerETH.getLatestPrice());
        }
        else if (underlying == WBTC) {
            return uint256(priceConsumerwBTC.getLatestPrice());
        }
        else if (underlying == POLYGON) {
            return uint256(priceConsumerPolygon.getLatestPrice());
        }
        
        return 0;
    }
}