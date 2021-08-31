// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;


import "./Ownable.sol";
import "./SafeERC20.sol";
import "./KiboConstants.sol";


contract KiboRewards is Ownable {
    event RewardsIncreased(address indexed beneficiary, uint256 total);
    event RewardsWithdrawn(address indexed beneficiary, uint256 total);

    mapping(address => uint256) public kiboRewards;
    
    function withdrawKiboTokens() external {
        require(kiboRewards[msg.sender] > 0, "Nothing to withdraw");
        uint256 total = kiboRewards[msg.sender];
        kiboRewards[msg.sender] = 0;
        SafeERC20.safeTransfer(KiboConstants.kiboToken, msg.sender, total);
        emit RewardsWithdrawn(msg.sender, total);
    }
    
    function _addKiboRewards(address _beneficiary, uint256 _total) external onlyOwner {
        kiboRewards[_beneficiary] += _total;
        emit RewardsIncreased(_beneficiary, _total);
    }
    
    function _withdrawKibo(uint256 _amount) external onlyOwner {
        SafeERC20.safeTransfer(KiboConstants.kiboToken, msg.sender, _amount);
    }
}