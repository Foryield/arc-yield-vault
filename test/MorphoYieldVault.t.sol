// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {YieldVault} from "../src/YieldVault.sol";
import {MorphoYieldVault} from "../src/MorphoYieldVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockMorphoVaultV2} from "./mocks/MockMorphoVaultV2.sol";

contract MorphoYieldVaultTest is Test {
    MockERC20 internal usdc;
    MockMorphoVaultV2 internal morpho;
    MorphoYieldVault internal vault;

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
        morpho = new MockMorphoVaultV2(usdc);
        vault = _newVault(IERC4626(address(morpho)));
        usdc.mint(alice, 1_000_000e6);
        usdc.mint(bob, 1_000_000e6);
    }

    function _newVault(IERC4626 target) internal returns (MorphoYieldVault) {
        return new MorphoYieldVault(
            usdc, "ForYield Arc USDC", "fyUSDC", owner, guardian, recovery, target
        );
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

    function _idle() internal view returns (uint256) {
        return usdc.balanceOf(address(vault));
    }

    // ─── Construction ─────────────────────────────────────────────────

    function test_constructor_setsTarget() public view {
        assertEq(address(vault.MORPHO_VAULT()), address(morpho));
        assertEq(vault.asset(), address(usdc));
    }

    function test_constructor_revertsOnZeroTarget() public {
        vm.expectRevert(YieldVault.ZeroAddress.selector);
        _newVault(IERC4626(address(0)));
    }

    function test_constructor_revertsOnAssetMismatch() public {
        MockERC20 eurc = new MockERC20("Euro Coin", "EURC", 6);
        MockMorphoVaultV2 eurcTarget = new MockMorphoVaultV2(eurc);
        vm.expectRevert(
            abi.encodeWithSelector(
                MorphoYieldVault.AssetMismatch.selector, address(usdc), address(eurc)
            )
        );
        _newVault(IERC4626(address(eurcTarget)));
    }

    // ─── Deposit ──────────────────────────────────────────────────────

    function test_deposit_suppliesEverythingToMorphoDespiteZeroMax() public {
        assertEq(morpho.maxDeposit(address(vault)), 0); // Vault V2 trait: never relied upon
        uint256 shares = _deposit(alice, 100e6, bob);

        assertEq(vault.balanceOf(bob), shares);
        assertEq(_idle(), 0);
        assertEq(morpho.totalAssets(), 100e6);
        assertEq(vault.totalAssets(), 100e6);
        assertEq(usdc.allowance(address(vault), address(morpho)), 0);
    }

    function test_deposit_refusedByMorpho_revertsWholeDeposit() public {
        morpho.setRejectDeposits(true);
        vm.startPrank(alice);
        usdc.approve(address(vault), 100e6);
        vm.expectRevert(MockMorphoVaultV2.DepositRejected.selector);
        vault.deposit(100e6, bob);
        vm.stopPrank();

        assertEq(usdc.balanceOf(alice), 1_000_000e6);
        assertEq(vault.totalSupply(), 0);
        assertEq(_idle(), 0);
    }

    function test_deposit_targetPullingLessThanApproved_reverts() public {
        morpho.setPullLessThanApproved(true);
        vm.startPrank(alice);
        usdc.approve(address(vault), 100e6);
        vm.expectRevert(abi.encodeWithSelector(MorphoYieldVault.AllowanceNotConsumed.selector, 1));
        vault.deposit(100e6, bob);
        vm.stopPrank();
    }

    function test_deposit_zero_skipsMorpho() public {
        morpho.setRejectDeposits(true); // any call to Morpho would revert
        vm.prank(alice);
        uint256 shares = vault.deposit(0, bob);
        assertEq(shares, 0);
        assertEq(morpho.balanceOf(address(vault)), 0);
    }

    function test_mint_alsoSupplies() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), 100e6);
        uint256 assets = vault.mint(100e6 * 1e6, bob);
        vm.stopPrank();
        assertEq(assets, 100e6);
        assertEq(_idle(), 0);
        assertEq(morpho.totalAssets(), 100e6);
    }

    // ─── Valuation ────────────────────────────────────────────────────

    function test_totalAssets_followsMorphoYield() public {
        uint256 shares = _deposit(alice, 100e6, alice);
        usdc.mint(address(morpho), 5e6); // 5 % yield accrues inside Morpho

        assertApproxEqAbs(vault.totalAssets(), 105e6, 1);
        vm.prank(alice);
        uint256 out = vault.redeem(shares, carol, alice);
        // Two floor roundings stack (Morpho's convertToAssets, then this vault's previewRedeem),
        // each worth at most one unit and each in favor of the vault that rounds.
        assertLe(out, 105e6);
        assertApproxEqAbs(out, 105e6, 2);
        assertEq(usdc.balanceOf(carol), out);
    }

    function test_totalAssets_countsIdleDonation() public {
        _deposit(alice, 100e6, alice);
        usdc.mint(address(vault), 3e6);
        assertEq(vault.totalAssets(), 103e6);
    }

    // ─── Withdrawal ───────────────────────────────────────────────────

    function test_withdraw_pullsFromMorphoAndPaysReceiver() public {
        _deposit(alice, 100e6, bob);
        vm.prank(bob);
        vault.withdraw(40e6, carol, bob);

        assertEq(usdc.balanceOf(carol), 40e6);
        assertEq(_idle(), 0);
        assertApproxEqAbs(vault.totalAssets(), 60e6, 1);
    }

    function test_withdraw_usesIdleFirst() public {
        _deposit(alice, 100e6, alice);
        usdc.mint(address(vault), 10e6);
        uint256 morphoSharesBefore = morpho.balanceOf(address(vault));

        vm.prank(alice);
        vault.withdraw(10e6, carol, alice);

        assertEq(morpho.balanceOf(address(vault)), morphoSharesBefore);
        assertEq(usdc.balanceOf(carol), 10e6);
    }

    function test_withdraw_withoutMorphoLiquidity_revertsWithoutEffect() public {
        uint256 shares = _deposit(alice, 100e6, alice);
        morpho.setLiquidity(10e6);

        vm.prank(alice);
        vm.expectRevert(MockMorphoVaultV2.NotEnoughLiquidity.selector);
        vault.withdraw(50e6, carol, alice);

        assertEq(vault.balanceOf(alice), shares);
        assertEq(usdc.balanceOf(carol), 0);
        assertEq(vault.totalAssets(), 100e6);
    }

    function test_withdraw_targetPayingShort_reverts() public {
        _deposit(alice, 100e6, alice);
        morpho.setPayLessThanRequested(true);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(MorphoYieldVault.ShortWithdrawal.selector, 50e6, 50e6 - 1)
        );
        vault.withdraw(50e6, carol, alice);
    }

    function test_redeem_neverPaysMoreThanPreviewed() public {
        _deposit(alice, 100e6, alice);
        _deposit(bob, 333_333_333, bob);
        usdc.mint(address(morpho), 7_777_777);

        uint256 shares = vault.balanceOf(alice);
        uint256 previewed = vault.previewRedeem(shares);
        vm.prank(alice);
        uint256 out = vault.redeem(shares, carol, alice);

        assertLe(out, previewed);
        assertEq(usdc.balanceOf(carol), out);
        assertGe(vault.totalAssets(), vault.convertToAssets(vault.totalSupply()));
    }

    function test_withdraw_byThirdPartyWithoutAllowance_reverts() public {
        _deposit(alice, 100e6, bob);
        uint256 shares = vault.previewWithdraw(100e6);
        vm.prank(mallory);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, mallory, 0, shares
            )
        );
        vault.withdraw(100e6, mallory, bob);
        assertEq(vault.totalAssets(), 100e6);
    }

    // ─── Pause and emergency ──────────────────────────────────────────

    function test_paused_blocksDeposit() public {
        vm.prank(guardian);
        vault.pause();
        vm.startPrank(alice);
        usdc.approve(address(vault), 1e6);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, alice, 1e6, 0)
        );
        vault.deposit(1e6, alice);
        vm.stopPrank();
    }

    function test_emergencyDeallocate_recallsEverythingToIdle() public {
        _deposit(alice, 100e6, alice);
        usdc.mint(address(morpho), 2e6);

        uint256 morphoShares = morpho.balanceOf(address(vault));
        vm.expectEmit(address(vault));
        emit MorphoYieldVault.EmergencyDeallocation(morphoShares, 102e6 - 1);
        vm.prank(guardian);
        vault.emergencyDeallocate();

        assertEq(morpho.balanceOf(address(vault)), 0);
        assertEq(_idle(), 102e6 - 1);
        assertEq(vault.totalAssets(), 102e6 - 1);
    }

    function test_emergencyDeallocate_byOther_reverts() public {
        _deposit(alice, 100e6, alice);
        vm.prank(mallory);
        vm.expectRevert(YieldVault.NotOwnerOrGuardian.selector);
        vault.emergencyDeallocate();
    }

    function test_emergency_fullEvacuationToRecovery() public {
        _deposit(alice, 100e6, alice);
        vm.startPrank(guardian);
        vault.pause();
        vault.emergencyDeallocate();
        vault.emergencyWithdraw();
        vm.stopPrank();

        assertEq(usdc.balanceOf(recovery), 100e6);
        assertEq(vault.totalAssets(), 0);
        assertTrue(vault.terminated());
    }

    function test_emergencyWithdraw_leavesMorphoPositionUntouched() public {
        // The evacuation only sweeps idle assets; recalling from Morpho is a separate, explicit step.
        _deposit(alice, 100e6, alice);
        vm.startPrank(guardian);
        vault.pause();
        vault.emergencyWithdraw();
        vm.stopPrank();

        assertEq(usdc.balanceOf(recovery), 0);
        assertEq(vault.totalAssets(), 100e6);

        vm.startPrank(guardian);
        vault.emergencyDeallocate();
        vault.emergencyWithdraw();
        vm.stopPrank();
        assertEq(usdc.balanceOf(recovery), 100e6);
    }
}
