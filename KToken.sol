// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract KToken is ERC20 {
    //ETH-USD=1, wBTC-USD=2, Polygon-USD=3
    uint8 _underlying = 1; 
    
    uint _strike = 1234;
    uint _maturity = 30;
    uint _expiresOn = 1234;
    bool _isPut = false;
    
    address public minter = 0x1234; //This is the Octopus smart contract
    
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

    function getDecimals() public view returns (uint) {
        return decimals();
    }
    
   function mint(address to, uint256 value) public {
       require(msg.sender == minter, "Invalid caller");
       
        _mint(to, value);
    }
    
    constructor() ERC20('K-Token', 'KTK')
    {
        
    }
}
