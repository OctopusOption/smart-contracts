// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./KiboFees.sol";
import "./KiboRewards.sol";
import "./KiboCompound.sol";
import "./KiboClaim.sol";
import "./KiboAdmin.sol";

contract KiboFinance is KiboFees, KiboRewards, KiboCompound, KiboClaim, KiboAdmin {
    event OptionPurchase(address indexed option, address indexed buyer, uint256 weiNotional, uint256 usdtCollateral, uint256 premium);

    // Notional has the number of decimals of the underlying
    function sell(address _optionAddress, uint256 _notional) payable external validOption(_optionAddress) {
        Seller storage seller = options[_optionAddress].sellers[msg.sender];
        uint8 underlying = IKToken(_optionAddress).getUnderlying();

        uint256 usdtCollateral;
        uint256 feesToCollect;

        if (IKToken(_optionAddress).isPut()) {
            usdtCollateral = calculateCollateralForPut(_optionAddress, _notional);
            SafeERC20.safeTransferFrom(KiboConstants.usdtToken, msg.sender, address(this), usdtCollateral);
            //seller.cTokens += supplyErc20ToCompound(usdtToken, cUSDT, usdtCollateral);
        } 
        else {
            if (underlying == KiboConstants.ETH) {
                require(msg.value == _notional, 'Invalid collateral');
                //seller.cTokens += supplyEthToCompound(cETH, _notional);
            }
            else if (underlying == KiboConstants.WBTC) {
                SafeERC20.safeTransferFrom(KiboConstants.wBTCToken, msg.sender, address(this), _notional);
                //seller.cTokens += supplyErc20ToCompound(wBTCToken, cwBTC, _notional);
            }
            else if (underlying == KiboConstants.POLYGON) {
                SafeERC20.safeTransferFrom(KiboConstants.polygonToken, msg.sender, address(this), _notional);
                // There's no Polygon pool in Compound yet
            }
        }   
        
        if (underlying == KiboConstants.ETH || underlying == KiboConstants.POLYGON) {
            IKToken(_optionAddress).mint(address(this), _notional / 1e14); // ETH and POLY have 18 decimals while KToken has 4
        }
        else if (underlying == KiboConstants.WBTC) {
            IKToken(_optionAddress).mint(address(this), _notional / 1e4); // WBTC has 8 decimals while KToken has 4
        }
        
        //We sell the tokens for USDT in Uniswap, which is sent to the user
        uint256 premium = sellKTokensInUniswap(_optionAddress, _notional);
        
        if (IKToken(_optionAddress).isPut()) {
            feesToCollect = usdtCollateral / 100;
            seller.collateral += usdtCollateral - feesToCollect;
            totalUSDTFees += feesToCollect;
        } else {
            feesToCollect = _notional / 100;
            seller.collateral += _notional - feesToCollect;
            if (underlying == KiboConstants.ETH) {
                totalETHFees += feesToCollect;
            }
            else if (underlying == KiboConstants.WBTC) {
                totalWBTCFees += feesToCollect;
            }
            else if (underlying == KiboConstants.POLYGON) {
                totalPOLYFees += feesToCollect;
            }
        }

        seller.isValid = true;
        seller.notional += _notional;
        
        //We emit an event to be able to send KiboTokens offchain, according to the difference against the theoretical Premium
        emit OptionPurchase(_optionAddress, msg.sender, _notional, usdtCollateral, premium);
    }
    
    // Collateral is always kept in USDT
    function calculateCollateralForPut(address _optionAddress, uint256 _notional) public view returns (uint256) {
        uint256 collateral = IKToken(_optionAddress).getStrike() * _notional;
        
        // I still need to remove 2 decimals from the strike (as it is in USD, not USDT) and the notional decimals, which depend on the underlying
        
        if (IKToken(_optionAddress).getUnderlying() == KiboConstants.ETH || IKToken(_optionAddress).getUnderlying() == KiboConstants.POLYGON) {
            return collateral / 1e20;
        }
        
        return collateral / 1e10; // WBTC
    }

    receive() external payable {
        revert();
    }
}