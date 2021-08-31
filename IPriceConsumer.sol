// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;


interface IPriceConsumer {
    function getLatestPrice() external view returns (int);
}