// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;


import "./SafeERC20.sol";
import "./Ownable.sol";
import "./KiboConstants.sol";

contract KiboFees is Ownable {
    uint256 public totalETHFees; // 18 decimals
    uint256 public totalWBTCFees; // 8 decimals
    uint256 public totalPOLYFees; // 18 decimals
    uint256 public totalUSDTFees; // 6 decimals
    
    function _withdrawUSDTFees() external onlyOwner {
        require(totalUSDTFees > 0, 'Nothing to claim');
        uint256 amount = totalUSDTFees;
        totalUSDTFees = 0;
        SafeERC20.safeTransfer(KiboConstants.usdtToken, msg.sender, amount);
    }
    
    function _withdrawWBTCFees() external onlyOwner {
        require(totalWBTCFees > 0, 'Nothing to claim');
        uint256 amount = totalWBTCFees;
        totalWBTCFees = 0;
        SafeERC20.safeTransfer(KiboConstants.wBTCToken, msg.sender, amount);
    }

    function _withdrawPOLYFees() external onlyOwner {
        require(totalPOLYFees > 0, 'Nothing to claim');
        uint256 amount = totalPOLYFees;
        totalPOLYFees = 0;
        SafeERC20.safeTransfer(KiboConstants.polygonToken, msg.sender, amount);
    }

    function _withdrawETHFees() external onlyOwner {
        require(totalETHFees > 0, 'Nothing to claim');
        uint256 amount = totalETHFees;
        totalETHFees = 0;
        payable(msg.sender).transfer(amount);
    }
}