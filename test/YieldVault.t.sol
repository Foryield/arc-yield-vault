// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {YieldVault} from "../src/YieldVault.sol";
import {IdleYieldVault} from "./mocks/IdleYieldVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract YieldVaultTest is Test {
    MockERC20 internal usdc;
    IdleYieldVault internal vault;

    address internal owner = makeAddr("owner");
    address internal guardian = makeAddr("guardian");
    address internal recovery = makeAddr("recovery");
    // Sender, receiver and share owner are always three distinct addresses in these tests.
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal mallory = makeAddr("mallory");

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        vault = new IdleYieldVault(usdc, owner, guardian, recovery, false);
        usdc.mint(alice, 1_000_000e6);
        usdc.mint(mallory, 1_000_000e6);
    }

    function _deposit(address from, uint256 assets, address receiver)
        internal
        returns (uint256 shares)
    {
        vm.startPrank(from);
        usdc.approve(address(vault), assets);
        shares = vault.deposit(assets, receiver);
        vm.stopPrank();
    }

    // ─── Construction ─────────────────────────────────────────────────

    function test_constructor_setsRoles() public view {
        assertEq(vault.owner(), owner);
        assertEq(vault.guardian(), guardian);
        assertEq(vault.RECOVERY_ADDRESS(), recovery);
        assertEq(vault.asset(), address(usdc));
        assertFalse(vault.terminated());
        assertFalse(vault.OWNER_ONLY_DEPOSITS());
    }

    function test_constructor_sharesCarryDecimalsOffset() public view {
        assertEq(vault.decimals(), 12); // 6 asset decimals + 6 virtual offset
    }

    function test_constructor_revertsOnZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new IdleYieldVault(usdc, address(0), guardian, recovery, false);
    }

    function test_constructor_revertsOnZeroGuardian() public {
        vm.expectRevert(YieldVault.ZeroAddress.selector);
        new IdleYieldVault(usdc, owner, address(0), recovery, false);
    }

    function test_constructor_revertsOnZeroRecovery() public {
        vm.expectRevert(YieldVault.ZeroAddress.selector);
        new IdleYieldVault(usdc, owner, guardian, address(0), false);
    }

    function test_constructor_revertsOnRoleCollision() public {
        vm.expectRevert(YieldVault.RoleCollision.selector);
        new IdleYieldVault(usdc, owner, owner, recovery, false);
        vm.expectRevert(YieldVault.RoleCollision.selector);
        new IdleYieldVault(usdc, owner, guardian, owner, false);
        vm.expectRevert(YieldVault.RoleCollision.selector);
        new IdleYieldVault(usdc, owner, guardian, guardian, false);
    }

    // ─── Deposit and withdrawal ───────────────────────────────────────

    function test_deposit_pullsFromSenderAndMintsToReceiver() public {
        uint256 shares = _deposit(alice, 100e6, bob);
        assertEq(vault.balanceOf(bob), shares);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(alice), 1_000_000e6 - 100e6);
        assertEq(vault.totalAssets(), 100e6);
        assertEq(shares, 100e6 * 1e6);
    }

    function test_redeem_byShareOwner_paysReceiver() public {
        uint256 shares = _deposit(alice, 100e6, bob);
        vm.prank(bob);
        uint256 assets = vault.redeem(shares, carol, bob);
        assertEq(assets, 100e6);
        assertEq(usdc.balanceOf(carol), 100e6);
        assertEq(vault.totalSupply(), 0);
    }

    function test_withdraw_byThirdPartyWithoutAllowance_reverts() public {
        uint256 shares = _deposit(alice, 100e6, bob);
        vm.prank(mallory);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, mallory, 0, shares
            )
        );
        vault.withdraw(100e6, mallory, bob);
        assertEq(vault.balanceOf(bob), shares);
    }

    function test_redeem_byApprovedThirdParty_spendsAllowance() public {
        uint256 shares = _deposit(alice, 100e6, bob);
        vm.prank(bob);
        vault.approve(carol, shares);
        vm.prank(carol);
        vault.redeem(shares, alice, bob);
        assertEq(vault.allowance(bob, carol), 0);
        assertEq(usdc.balanceOf(alice), 1_000_000e6);
    }

    function test_deposit_cannotPullFromAnotherAccount() public {
        // alice approved the vault; mallory tries to deposit alice's funds to herself.
        vm.prank(alice);
        usdc.approve(address(vault), 100e6);
        // The vault only ever pulls from the caller: without her own approval, mallory's call fails.
        vm.prank(mallory);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(vault), 0, 100e6
            )
        );
        vault.deposit(100e6, mallory);
        assertEq(usdc.balanceOf(alice), 1_000_000e6);
        assertEq(usdc.allowance(alice, address(vault)), 100e6);
        assertEq(vault.balanceOf(mallory), 0);
    }

    function test_firstDepositInflation_isUnprofitable() public {
        // Attacker front-runs with a dust deposit, then donates to inflate the share price.
        _deposit(mallory, 1, mallory);
        vm.prank(mallory);
        assertTrue(usdc.transfer(address(vault), 10_000e6));

        uint256 victimShares = _deposit(alice, 10_000e6, alice);
        assertGt(victimShares, 0);

        vm.prank(alice);
        uint256 victimOut = vault.redeem(victimShares, alice, alice);
        uint256 malloryShares = vault.balanceOf(mallory);
        vm.prank(mallory);
        uint256 attackerOut = vault.redeem(malloryShares, mallory, mallory);

        // The victim keeps at least 99.99 % of the deposit; the attacker loses most of the donation.
        assertGe(victimOut, 10_000e6 * 9_999 / 10_000);
        assertLt(attackerOut, 10_000e6 + 1);
    }

    // ─── Owner-only deposits ──────────────────────────────────────────

    function _restrictedVault() internal returns (IdleYieldVault restricted) {
        restricted = new IdleYieldVault(usdc, owner, guardian, recovery, true);
        usdc.mint(owner, 1_000e6);
        vm.prank(owner);
        usdc.approve(address(restricted), type(uint256).max);
        vm.prank(mallory);
        usdc.approve(address(restricted), type(uint256).max);
    }

    function test_ownerOnly_maxReportsZeroForAnyOtherReceiver() public {
        IdleYieldVault restricted = _restrictedVault();
        assertTrue(restricted.OWNER_ONLY_DEPOSITS());
        assertEq(restricted.maxDeposit(owner), type(uint256).max);
        assertEq(restricted.maxMint(owner), type(uint256).max);
        assertEq(restricted.maxDeposit(mallory), 0);
        assertEq(restricted.maxMint(mallory), 0);
    }

    function test_ownerOnly_ownerDepositsAndRedeemsToAnotherAddress() public {
        IdleYieldVault restricted = _restrictedVault();
        vm.prank(owner);
        uint256 shares = restricted.deposit(100e6, owner);
        vm.prank(owner);
        uint256 minted = 50e6 * 1e6;
        assertEq(restricted.mint(minted, owner), 50e6);
        shares += minted;
        assertEq(restricted.balanceOf(owner), shares);

        // Exits are not restricted: the owner can be paid anywhere.
        vm.prank(owner);
        restricted.redeem(shares, carol, owner);
        assertEq(usdc.balanceOf(carol), 150e6);
    }

    function test_ownerOnly_strangerCannotDepositForHimself() public {
        IdleYieldVault restricted = _restrictedVault();
        vm.prank(mallory);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, mallory, 100e6, 0)
        );
        restricted.deposit(100e6, mallory);
        vm.prank(mallory);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxMint.selector, mallory, 1e12, 0)
        );
        restricted.mint(1e12, mallory);
    }

    function test_ownerOnly_strangerCannotDepositForTheOwner() public {
        IdleYieldVault restricted = _restrictedVault();
        vm.prank(mallory);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.DepositNotAllowed.selector, mallory));
        restricted.deposit(100e6, owner);
        vm.prank(mallory);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.DepositNotAllowed.selector, mallory));
        restricted.mint(1e12, owner);
        assertEq(restricted.totalSupply(), 0);
        assertEq(usdc.balanceOf(mallory), 1_000_000e6);
    }

    function test_ownerOnly_ownerCannotMintSharesToAnotherAddress() public {
        IdleYieldVault restricted = _restrictedVault();
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, carol, 100e6, 0)
        );
        restricted.deposit(100e6, carol);
    }

    function test_ownerOnly_followsOwnershipTransfer() public {
        IdleYieldVault restricted = _restrictedVault();
        address nextOwner = makeAddr("nextOwner");
        vm.prank(owner);
        restricted.transferOwnership(nextOwner);
        vm.prank(nextOwner);
        restricted.acceptOwnership();

        assertEq(restricted.maxDeposit(owner), 0);
        assertEq(restricted.maxDeposit(nextOwner), type(uint256).max);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.DepositNotAllowed.selector, owner));
        restricted.deposit(100e6, nextOwner);
    }

    function test_ownerOnly_pauseStillClosesTheOwner() public {
        IdleYieldVault restricted = _restrictedVault();
        vm.prank(guardian);
        restricted.pause();
        assertEq(restricted.maxDeposit(owner), 0);
        assertEq(restricted.maxMint(owner), 0);
    }

    // ─── Pause ────────────────────────────────────────────────────────

    function test_pause_byGuardianOrOwner() public {
        vm.prank(guardian);
        vault.pause();
        assertTrue(vault.paused());
        vm.prank(owner);
        vault.unpause();
        vm.prank(owner);
        vault.pause();
        assertTrue(vault.paused());
    }

    function test_pause_byOther_reverts() public {
        vm.prank(mallory);
        vm.expectRevert(YieldVault.NotOwnerOrGuardian.selector);
        vault.pause();
    }

    function test_unpause_byGuardian_reverts() public {
        vm.prank(guardian);
        vault.pause();
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, guardian)
        );
        vault.unpause();
    }

    function test_paused_blocksDepositsAndWithdrawals() public {
        uint256 shares = _deposit(alice, 100e6, alice);
        vm.prank(guardian);
        vault.pause();

        assertEq(vault.maxDeposit(alice), 0);
        assertEq(vault.maxMint(alice), 0);
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxRedeem(alice), 0);

        vm.startPrank(alice);
        usdc.approve(address(vault), 1e6);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, alice, 1e6, 0)
        );
        vault.deposit(1e6, alice);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxRedeem.selector, alice, shares, 0)
        );
        vault.redeem(shares, alice, alice);
        vm.stopPrank();
    }

    // ─── Emergency evacuation ─────────────────────────────────────────

    function test_emergencyWithdraw_requiresPause() public {
        vm.prank(guardian);
        vm.expectRevert(Pausable.ExpectedPause.selector);
        vault.emergencyWithdraw();
    }

    function test_emergencyWithdraw_byOther_reverts() public {
        vm.prank(guardian);
        vault.pause();
        vm.prank(mallory);
        vm.expectRevert(YieldVault.NotOwnerOrGuardian.selector);
        vault.emergencyWithdraw();
    }

    function test_emergencyWithdraw_sweepsToRecoveryAndTerminates() public {
        _deposit(alice, 100e6, alice);
        vm.startPrank(guardian);
        vault.pause();
        vm.expectEmit(address(vault));
        emit YieldVault.EmergencyWithdrawal(recovery, 100e6);
        vault.emergencyWithdraw();
        vm.stopPrank();

        assertEq(usdc.balanceOf(recovery), 100e6);
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertTrue(vault.terminated());

        vm.prank(owner);
        vm.expectRevert(YieldVault.VaultTerminated.selector);
        vault.unpause();
    }

    function test_emergencyWithdraw_canSweepAgainAfterTermination() public {
        vm.startPrank(owner);
        vault.pause();
        vault.emergencyWithdraw();
        vm.stopPrank();

        usdc.mint(address(vault), 5e6); // late arrival, e.g. funds recalled from a venue
        vm.prank(owner);
        vault.emergencyWithdraw();
        assertEq(usdc.balanceOf(recovery), 5e6);
    }

    // ─── Roles ────────────────────────────────────────────────────────

    function test_setGuardian_byOwner() public {
        address newGuardian = makeAddr("newGuardian");
        vm.expectEmit(address(vault));
        emit YieldVault.GuardianUpdated(guardian, newGuardian);
        vm.prank(owner);
        vault.setGuardian(newGuardian);
        assertEq(vault.guardian(), newGuardian);
    }

    function test_setGuardian_byOther_reverts() public {
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, guardian)
        );
        vault.setGuardian(mallory);
    }

    function test_setGuardian_rejectsZeroAndCollisions() public {
        address nextOwner = makeAddr("nextOwner");
        vm.startPrank(owner);
        vm.expectRevert(YieldVault.ZeroAddress.selector);
        vault.setGuardian(address(0));
        vm.expectRevert(YieldVault.RoleCollision.selector);
        vault.setGuardian(owner);
        vm.expectRevert(YieldVault.RoleCollision.selector);
        vault.setGuardian(recovery);
        vault.transferOwnership(nextOwner);
        vm.expectRevert(YieldVault.RoleCollision.selector);
        vault.setGuardian(nextOwner);
        vm.stopPrank();
    }

    function test_transferOwnership_isTwoStep() public {
        address nextOwner = makeAddr("nextOwner");
        vm.prank(owner);
        vault.transferOwnership(nextOwner);
        assertEq(vault.owner(), owner);
        vm.prank(nextOwner);
        vault.acceptOwnership();
        assertEq(vault.owner(), nextOwner);
    }

    function test_transferOwnership_rejectsCollisions() public {
        vm.startPrank(owner);
        vm.expectRevert(YieldVault.RoleCollision.selector);
        vault.transferOwnership(guardian);
        vm.expectRevert(YieldVault.RoleCollision.selector);
        vault.transferOwnership(recovery);
        vm.stopPrank();
    }

    function test_renounceOwnership_isDisabled() public {
        vm.prank(owner);
        vm.expectRevert(YieldVault.RenounceDisabled.selector);
        vault.renounceOwnership();
        assertEq(vault.owner(), owner);
    }
}
