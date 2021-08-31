// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;


import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ICETH.sol";
import "./ICERC20.sol";


contract KiboCompound {
    address payable cETH = payable(?);
    address cUSDT = ?;
    address cwBTC = ?;

    function supplyEthToCompound(address payable _cEtherContract, uint256 _total)
        internal
        returns (uint256)
    {
        // Create a reference to the corresponding cToken contract
        ICETH cToken = ICETH(_cEtherContract);

        uint256 balance = cToken.balanceOf(address(this));

        cToken.mint{value:_total, gas: 250000}();
        return cToken.balanceOf(address(this)) - balance;
    }
    
    function supplyErc20ToCompound(
        ERC20 _erc20Contract,
        address _ICERC20Contract,
        uint256 _numTokensToSupply
    ) internal returns (uint) {
        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(_ICERC20Contract);

        uint256 balance = cToken.balanceOf(address(this));

        // Approve transfer on the ERC20 contract
        SafeERC20.safeApprove(_erc20Contract, _ICERC20Contract, _numTokensToSupply);

        // Mint cTokens
        cToken.mint(_numTokensToSupply);
        
        uint256 newBalance = cToken.balanceOf(address(this));

        return newBalance - balance;
    }
    
    function redeemICERC20Tokens(
        uint256 amount,
        bool redeemType,
        address _ICERC20Contract
    ) internal returns (uint256) {
        // Create a reference to the corresponding cToken contract, like cDAI
        ICERC20 cToken = ICERC20(_ICERC20Contract);

        // `amount` is scaled up, see decimal table here:
        // https://compound.finance/docs#protocol-math

        uint256 redeemResult;

        if (redeemType == true) {
            // Retrieve your asset based on a cToken amount
            redeemResult = cToken.redeem(amount);
        } else {
            // Retrieve your asset based on an amount of the asset
            redeemResult = cToken.redeemUnderlying(amount);
        }

        return redeemResult;
    }

    function redeemICETH(
        uint256 amount,
        bool redeemType,
        address _cEtherContract
    ) internal returns (uint256) {
        // Create a reference to the corresponding cToken contract
        ICETH cToken = ICETH(_cEtherContract);

        // `amount` is scaled up by 1e18 to avoid decimals

        uint256 redeemResult;

        if (redeemType == true) {
            // Retrieve your asset based on a cToken amount
            redeemResult = cToken.redeem(amount);
        } else {
            // Retrieve your asset based on an amount of the asset
            redeemResult = cToken.redeemUnderlying(amount);
        }

        // Error codes are listed here:
        // https://compound.finance/docs/ctokens#ctoken-error-codes
        return redeemResult;
    }
}