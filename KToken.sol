// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./ERC20.sol";

contract KToken is ERC20 {
    address _underlying = ?; //Use 0x0000000000000000000000000000000000000000 for ETH
    uint _strike = ?; // This has 8 decimals and represents the value in USD
    uint _maturity = ?;
    uint _expiresOn = ?;
    bool _isPut = ?;
    
    address public minter = ?; //This is the KiboFinance smart contract
    
    function getUnderlying() public view returns (address) {
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