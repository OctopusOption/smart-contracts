// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;


import "./ERC20.sol";


library KiboConstants {
    uint8 constant public ETH = 1;
    uint8 constant public WBTC = 2;
    uint8 constant public POLYGON = 3;
    
    IERC20 constant public kiboToken =  IERC20(?);

    IERC20 constant public usdtToken = IERC20(?);
    IERC20 constant public wBTCToken = IERC20(?);
    IERC20 constant public polygonToken = IERC20(?);
}