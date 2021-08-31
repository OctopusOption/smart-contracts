// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "./ERC20.sol";

contract KToken is ERC20 {
    uint8 constant ETH = 1;
    uint8 constant WBTC = 2;
    uint8 constant POLYGON = 3;
    
    uint8 _underlying = ETH; 
    
    uint _strike = ?; // This has 8 decimals and represents the value in USD
    uint _maturity = ?;
    uint _expiresOn = ?;
    bool _isPut = ?;
    
    address public minter = ?; //This is the Octopus smart contract
    
    function getUnderlying() public view returns (uint8) {
        return _underlying;
    }
    
    function getStrike() public view returns (uint) {
        return _strike;
    }
    
    function getMaturity() public view returns (uint) {
        return _maturity;
    }

    function getExpiresOn() public view returns (uint) {
        return _expiresOn;
    }
    
    function isPut() public view returns (bool) {
        return _isPut;
    }

    function getDecimals() public pure returns (uint) {
        return 4;
    }
    
   function mint(address to, uint256 value) public {
       require(msg.sender == minter, "Invalid caller");
       
        _mint(to, value);
    }
    
    constructor() ERC20('K-Token', 'KTK')
    {
    }
}