// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/// @notice ERC-4626 target reproducing the Morpho Vault V2 traits the adapter must survive:
///         max* always return 0, 18-decimal shares, deposits that can be refused, limited
///         liquidity on exit. Failure knobs cover a misbehaving target.
contract MockMorphoVaultV2 is ERC4626 {
    bool public rejectDeposits;
    bool public pullLessThanApproved;
    bool public payLessThanRequested;
    uint256 public liquidity = type(uint256).max;

    error DepositRejected();
    error NotEnoughLiquidity();

    constructor(IERC20 asset_) ERC4626(asset_) ERC20("Mock Morpho Vault V2", "mmv2") {}

    function setRejectDeposits(bool value) external {
        rejectDeposits = value;
    }

    function setPullLessThanApproved(bool value) external {
        pullLessThanApproved = value;
    }

    function setPayLessThanRequested(bool value) external {
        payLessThanRequested = value;
    }

    function setLiquidity(uint256 value) external {
        liquidity = value;
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 12;
    }

    function maxDeposit(address) public pure override returns (uint256) {
        return 0;
    }

    function maxMint(address) public pure override returns (uint256) {
        return 0;
    }

    function maxWithdraw(address) public pure override returns (uint256) {
        return 0;
    }

    function maxRedeem(address) public pure override returns (uint256) {
        return 0;
    }

    function deposit(uint256 assets, address onBehalf) public override returns (uint256 shares) {
        if (rejectDeposits) revert DepositRejected();
        uint256 pulled = pullLessThanApproved ? assets - 1 : assets;
        shares = previewDeposit(pulled);
        _deposit(msg.sender, onBehalf, pulled, shares);
    }

    function withdraw(uint256 assets, address receiver, address onBehalf)
        public
        override
        returns (uint256 shares)
    {
        if (assets > liquidity) revert NotEnoughLiquidity();
        shares = previewWithdraw(assets);
        _withdraw(
            msg.sender, receiver, onBehalf, payLessThanRequested ? assets - 1 : assets, shares
        );
    }

    function redeem(uint256 shares, address receiver, address onBehalf)
        public
        override
        returns (uint256 assets)
    {
        assets = previewRedeem(shares);
        if (assets > liquidity) revert NotEnoughLiquidity();
        _withdraw(msg.sender, receiver, onBehalf, assets, shares);
    }
}
