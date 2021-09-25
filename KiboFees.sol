// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;


import "./SafeERC20.sol";
import "./Ownable.sol";
import "./KiboConstants.sol";

contract KiboFees is Ownable {
    uint256 public totalETHFees; // 18 decimals
    
    mapping(address => uint256) fees;
    
    function _withdrawFees(address _token) external onlyOwner {
        require(fees[_token] > 0, 'Nothing to claim');
        uint256 amount = fees[_token];
        fees[_token] = 0;
        SafeERC20.safeTransfer(ERC20(_token), msg.sender, amount);
    }
    
    function _withdrawETHFees() external onlyOwner {
        require(totalETHFees > 0, 'Nothing to claim');
        uint256 amount = totalETHFees;
        totalETHFees = 0;
        payable(msg.sender).transfer(amount);
    }
}