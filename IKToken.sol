// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

interface IKToken {
    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(address from, address to, uint256 value) external returns (bool);

    function totalSupply() external view returns (uint256);

    function balanceOf(address who) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    function mint(address account, uint256 amount) external;
    
    function getUnderlying() external view returns (uint8);
    
    function getStrike() external view returns (uint);

    function getExpiresOn() external view returns (uint);
    
    function isPut() external view returns (bool);
}
