// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

interface ICETH {
    function balanceOf(address owner) external view returns (uint256);
    
    function mint() external payable;

    function exchangeRateCurrent() external returns (uint256);

    function supplyRatePerBlock() external returns (uint256);

    function redeem(uint) external returns (uint);

    function redeemUnderlying(uint) external returns (uint);

    function transfer(address recipient, uint256 amount) external returns (bool);
}
