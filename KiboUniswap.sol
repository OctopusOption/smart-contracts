// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;


import "./SafeERC20.sol";
import "./IUniswapV2Router02.sol";
import "./KiboConstants.sol";


contract KiboUniswap {
    IUniswapV2Router02 uniswapRouter = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    
    // Returns the amount in USDT if you sell 1 KiboToken in Uniswap
    function getKiboSellPrice() external view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(KiboConstants.kiboToken);
        path[1] = address(KiboConstants.usdtToken);
        uint[] memory amounts = uniswapRouter.getAmountsOut(1e18, path);
        return amounts[1];
    }
    
    // Returns the amount in USDT if you buy 1 KiboToken in Uniswap
    function getKiboBuyPrice() external view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(KiboConstants.usdtToken);
        path[1] = address(KiboConstants.kiboToken);
        uint[] memory amounts = uniswapRouter.getAmountsIn(1e18, path);
        return amounts[0];
    }
    
    function sellKTokensInUniswap(address _optionAddress, uint256 _tokensAmount) internal returns (uint256)  {
        address[] memory path = new address[](2);
        path[0] = _optionAddress;
        path[1] = address(KiboConstants.usdtToken);
        IERC20(_optionAddress).approve(address(uniswapRouter), _tokensAmount);
        // TODO: uint256[] memory amountsOutMin = uniswapRouter.getAmountsOut(_tokensAmount, path);
        // Use amountsOutMin[1]
        uint[] memory amounts = uniswapRouter.swapExactTokensForTokens(_tokensAmount, 0, path, msg.sender, block.timestamp);
        return amounts[1];
    }
    
    function createPairInUniswap(address _optionAddress, uint256 _totalTokens, uint256 _totalUSDT) internal returns (uint amountA, uint amountB, uint liquidity) {
        uint256 allowance = KiboConstants.usdtToken.allowance(address(this), address(uniswapRouter));
        if (allowance > 0 && allowance < _totalUSDT) {
            SafeERC20.safeApprove(KiboConstants.usdtToken, address(uniswapRouter), 0);
        }
        if (allowance == 0) {
            SafeERC20.safeApprove(KiboConstants.usdtToken, address(uniswapRouter), _totalUSDT);
        }
        IERC20(_optionAddress).approve(address(uniswapRouter), _totalTokens);
        (amountA, amountB, liquidity) = uniswapRouter.addLiquidity(_optionAddress, address(KiboConstants.usdtToken), _totalTokens, _totalUSDT, 0, 0, msg.sender, block.timestamp);
    }
}