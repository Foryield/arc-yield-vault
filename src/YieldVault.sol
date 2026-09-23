// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

/// @title YieldVault
/// @notice ERC-4626 base vault: proportional shares, owner and guardian roles, emergency pause,
///         and an evacuation path whose destination is fixed at deployment.
/// @dev Venue-specific subclasses hook into OpenZeppelin's `_transferIn` / `_transferOut` and
///      override `totalAssets`. Deposits and withdrawals are non-reentrant end to end.
///
///      Roles are held by three distinct addresses, enforced on-chain:
///      - owner (two-step transfer): configuration, unpause;
///      - guardian: pause, evacuation;
///      - RECOVERY_ADDRESS (immutable): the only place the evacuation can send funds.
///
///      OWNER_ONLY_DEPOSITS, fixed at deployment, reserves deposits to the owner: open for a
///      public demonstration, closed for an instance that only runs the operator's own capital.
abstract contract YieldVault is ERC4626, Ownable2Step, Pausable, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    /// @notice Sole destination of `emergencyWithdraw`. Immutable, so a compromised owner or
    ///         guardian key cannot redirect an evacuation.
    address public immutable RECOVERY_ADDRESS;

    /// @notice When set, only the current owner can deposit or mint, and only to itself. Exits stay
    ///         open to any share holder. Immutable, so no key can open a restricted vault later.
    bool public immutable OWNER_ONLY_DEPOSITS;

    /// @notice Can pause the vault and trigger the evacuation. Cannot unpause or move funds elsewhere.
    address public guardian;

    /// @notice Set by the first evacuation. A terminated vault stays paused forever.
    bool public terminated;

    event GuardianUpdated(address indexed previousGuardian, address indexed newGuardian);
    event EmergencyWithdrawal(address indexed recovery, uint256 assets);

    error ZeroAddress();
    error RoleCollision();
    error NotOwnerOrGuardian();
    error VaultTerminated();
    error RenounceDisabled();
    error DepositNotAllowed(address caller);

    modifier onlyOwnerOrGuardian() {
        if (msg.sender != owner() && msg.sender != guardian) revert NotOwnerOrGuardian();
        _;
    }

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_,
        address guardian_,
        address recovery_,
        bool ownerOnlyDeposits_
    ) ERC4626(asset_) ERC20(name_, symbol_) Ownable(owner_) {
        if (guardian_ == address(0) || recovery_ == address(0)) {
            revert ZeroAddress();
        }
        if (guardian_ == owner_ || recovery_ == owner_ || recovery_ == guardian_) {
            revert RoleCollision();
        }
        RECOVERY_ADDRESS = recovery_;
        OWNER_ONLY_DEPOSITS = ownerOnlyDeposits_;
        guardian = guardian_;
        emit GuardianUpdated(address(0), guardian_);
    }

    // ─── ERC-4626 ─────────────────────────────────────────────────────

    /// @dev Pausing closes every entry and exit: OpenZeppelin's deposit/mint/withdraw/redeem
    ///      revert when the matching max* returns 0. A restricted vault also closes entries to any
    ///      receiver other than the owner.
    function maxDeposit(address receiver) public view virtual override returns (uint256) {
        return _entryClosed(receiver) ? 0 : super.maxDeposit(receiver);
    }

    function maxMint(address receiver) public view virtual override returns (uint256) {
        return _entryClosed(receiver) ? 0 : super.maxMint(receiver);
    }

    function maxWithdraw(address holder) public view virtual override returns (uint256) {
        return paused() ? 0 : super.maxWithdraw(holder);
    }

    function maxRedeem(address holder) public view virtual override returns (uint256) {
        return paused() ? 0 : super.maxRedeem(holder);
    }

    /// @dev Six virtual decimals: a first-depositor donation attack costs the attacker about a
    ///      million times what it can take from the next depositor.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    function _entryClosed(address receiver) private view returns (bool) {
        return paused() || (OWNER_ONLY_DEPOSITS && receiver != owner());
    }

    /// @dev OpenZeppelin checks max* against the receiver only; a restricted vault also refuses
    ///      any caller other than the owner, so nobody can fund the owner's position either.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        virtual
        override
        nonReentrant
    {
        if (OWNER_ONLY_DEPOSITS && caller != owner()) revert DepositNotAllowed(caller);
        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address holder,
        uint256 assets,
        uint256 shares
    ) internal virtual override nonReentrant {
        super._withdraw(caller, receiver, holder, assets, shares);
    }

    // ─── Pause and evacuation ─────────────────────────────────────────

    function pause() external onlyOwnerOrGuardian {
        _pause();
    }

    function unpause() external onlyOwner {
        if (terminated) revert VaultTerminated();
        _unpause();
    }

    /// @notice Sends every idle asset to RECOVERY_ADDRESS and terminates the vault. Paused vault
    ///         only. Callable again after termination, to sweep assets recalled later from a venue.
    function emergencyWithdraw() external onlyOwnerOrGuardian whenPaused nonReentrant {
        terminated = true;
        IERC20 token = IERC20(asset());
        uint256 assets = token.balanceOf(address(this));
        token.safeTransfer(RECOVERY_ADDRESS, assets);
        emit EmergencyWithdrawal(RECOVERY_ADDRESS, assets);
    }

    // ─── Roles ────────────────────────────────────────────────────────

    function setGuardian(address newGuardian) external onlyOwner {
        if (newGuardian == address(0)) revert ZeroAddress();
        if (
            newGuardian == owner() || newGuardian == pendingOwner()
                || newGuardian == RECOVERY_ADDRESS
        ) {
            revert RoleCollision();
        }
        emit GuardianUpdated(guardian, newGuardian);
        guardian = newGuardian;
    }

    /// @dev The incoming owner can hold neither of the other two roles.
    function transferOwnership(address newOwner) public virtual override onlyOwner {
        if (newOwner == guardian || newOwner == RECOVERY_ADDRESS) revert RoleCollision();
        super.transferOwnership(newOwner);
    }

    /// @dev An ownerless vault could never be unpaused or reconfigured.
    function renounceOwnership() public view override onlyOwner {
        revert RenounceDisabled();
    }
}
