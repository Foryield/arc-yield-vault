// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {YieldVault} from "./YieldVault.sol";

/// @title MorphoYieldVault
/// @notice YieldVault that supplies every deposit to a single Morpho Vault V2, fixed at deployment.
///         totalAssets() = value of the Morpho shares held + idle underlying.
/// @dev A Morpho Vault V2 returns 0 from every max* function by design (its gates cannot be
///      checked revert-free), so this contract never reads them: it supplies the full deposit and
///      lets the whole transaction revert if Morpho refuses. No deposit is ever left idle silently.
contract MorphoYieldVault is YieldVault {
    using SafeERC20 for IERC20;

    /// @notice The Morpho Vault V2 receiving every deposit. One vault, one target.
    IERC4626 public immutable MORPHO_VAULT;

    event EmergencyDeallocation(uint256 morphoShares, uint256 assets);

    error AssetMismatch(address expected, address actual);
    error AllowanceNotConsumed(uint256 remaining);
    error ShortWithdrawal(uint256 requested, uint256 received);

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_,
        address guardian_,
        address recovery_,
        bool ownerOnlyDeposits_,
        IERC4626 morphoVault_
    ) YieldVault(asset_, name_, symbol_, owner_, guardian_, recovery_, ownerOnlyDeposits_) {
        if (address(morphoVault_) == address(0)) revert ZeroAddress();
        address targetAsset = morphoVault_.asset();
        if (targetAsset != address(asset_)) revert AssetMismatch(address(asset_), targetAsset);
        MORPHO_VAULT = morphoVault_;
    }

    /// @dev Morpho's convertToAssets rounds down and is net of its fees: the valuation is
    ///      conservative, in the vault's favor.
    function totalAssets() public view override returns (uint256) {
        uint256 supplied = MORPHO_VAULT.convertToAssets(MORPHO_VAULT.balanceOf(address(this)));
        return supplied + IERC20(asset()).balanceOf(address(this));
    }

    /// @notice Redeems the whole Morpho position into idle assets held by this vault. Funds never
    ///         leave the vault; pair with pause + emergencyWithdraw to evacuate. Callable after
    ///         termination too, so a position recovered later can still be swept.
    /// @dev Two ways this can revert. If Morpho lacks liquidity, anyone can call Morpho's
    ///      permissionless forceDeallocate to move liquidity back to Morpho's idle balance, then
    ///      retry. If Morpho's curator gates this vault's address (sendSharesGate or
    ///      receiveAssetsGate), every exit reverts, forceDeallocate included, and nothing in this
    ///      contract can route around it: choosing and monitoring an ungated target is an
    ///      operational requirement.
    function emergencyDeallocate() external onlyOwnerOrGuardian nonReentrant {
        uint256 morphoShares = MORPHO_VAULT.balanceOf(address(this));
        uint256 assets = MORPHO_VAULT.redeem(morphoShares, address(this), address(this));
        emit EmergencyDeallocation(morphoShares, assets);
    }

    /// @dev Runs inside the non-reentrant deposit flow: pull from the caller, then supply exactly
    ///      that amount. The approval is exact and must be fully consumed.
    function _transferIn(address from, uint256 assets) internal override {
        super._transferIn(from, assets);
        if (assets == 0) return;
        IERC20 token = IERC20(asset());
        token.forceApprove(address(MORPHO_VAULT), assets);
        // The shares minted are valued through balanceOf in totalAssets; what must be proven here
        // is that Morpho took the full amount, which the allowance check below does.
        // slither-disable-next-line unused-return
        MORPHO_VAULT.deposit(assets, address(this));
        uint256 remaining = token.allowance(address(this), address(MORPHO_VAULT));
        if (remaining != 0) revert AllowanceNotConsumed(remaining);
    }

    /// @dev Runs inside the non-reentrant withdrawal flow, after the shares are burned: idle
    ///      assets are used first, the shortfall is recalled from Morpho and checked on arrival.
    function _transferOut(address to, uint256 assets) internal override {
        IERC20 token = IERC20(asset());
        uint256 idle = token.balanceOf(address(this));
        if (idle < assets) {
            uint256 needed = assets - idle;
            // The shares burned are irrelevant here: the assets actually received are checked.
            // `idle` is read before the call on purpose, to measure that arrival; the whole
            // withdrawal flow is nonReentrant.
            // slither-disable-next-line unused-return,reentrancy-balance
            MORPHO_VAULT.withdraw(needed, address(this), address(this));
            uint256 received = token.balanceOf(address(this)) - idle;
            if (received < needed) revert ShortWithdrawal(needed, received);
        }
        super._transferOut(to, assets);
    }
}
