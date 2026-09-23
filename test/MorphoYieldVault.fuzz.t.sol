// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MorphoYieldVault} from "../src/MorphoYieldVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockMorphoVaultV2} from "./mocks/MockMorphoVaultV2.sol";

contract MorphoYieldVaultFuzzTest is Test {
    MockERC20 internal usdc;
    MockMorphoVaultV2 internal morpho;
    MorphoYieldVault internal vault;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal receiver = makeAddr("receiver");

    /// @dev Upper bound on the value a depositor can lose to rounding, in asset units: one floor
    ///      in Morpho's valuation plus one in this vault's conversion.
    uint256 internal constant ROUNDING_DUST = 2;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        morpho = new MockMorphoVaultV2(usdc);
        vault = new MorphoYieldVault(
            usdc,
            "ForYield Arc USDC",
            "fyUSDC",
            makeAddr("owner"),
            makeAddr("guardian"),
            makeAddr("recovery"),
            false,
            IERC4626(address(morpho))
        );
    }

    function _deposit(address from, uint256 assets) internal returns (uint256 shares) {
        usdc.mint(from, assets);
        vm.startPrank(from);
        usdc.approve(address(vault), assets);
        shares = vault.deposit(assets, from);
        vm.stopPrank();
    }

    function _assertSolvent() internal view {
        assertGe(vault.totalAssets(), vault.convertToAssets(vault.totalSupply()));
    }

    function testFuzz_depositYieldRedeem_staysSolventAndFair(
        uint256 aliceAssets,
        uint256 bobAssets,
        uint256 yieldBps
    ) public {
        aliceAssets = bound(aliceAssets, 1, 1e15); // up to 1 billion units of a 6-decimal asset
        bobAssets = bound(bobAssets, 1, 1e15);
        yieldBps = bound(yieldBps, 0, 5_000); // 0 to 50 % yield

        uint256 aliceShares = _deposit(alice, aliceAssets);
        uint256 bobShares = _deposit(bob, bobAssets);
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(usdc.allowance(address(vault), address(morpho)), 0);
        _assertSolvent();

        usdc.mint(address(morpho), (aliceAssets + bobAssets) * yieldBps / 10_000);
        _assertSolvent();

        uint256 previewed = vault.previewRedeem(aliceShares);
        vm.prank(alice);
        uint256 aliceOut = vault.redeem(aliceShares, receiver, alice);
        assertLe(aliceOut, previewed);
        assertGe(aliceOut + ROUNDING_DUST, aliceAssets);
        _assertSolvent();

        vm.prank(bob);
        uint256 bobOut = vault.redeem(bobShares, bob, bob);
        assertGe(bobOut + ROUNDING_DUST, bobAssets);

        assertEq(vault.totalSupply(), 0);
        assertEq(usdc.balanceOf(receiver), aliceOut);
    }

    function testFuzz_partialWithdrawals_neverOverpay(uint256 assets, uint256 fractionBps) public {
        assets = bound(assets, 1e6, 1e15);
        fractionBps = bound(fractionBps, 1, 10_000);
        _deposit(alice, assets);
        _deposit(bob, assets);

        uint256 target = assets * fractionBps / 10_000;
        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 burnPreview = vault.previewWithdraw(target);

        vm.prank(alice);
        uint256 burned = vault.withdraw(target, receiver, alice);

        assertEq(usdc.balanceOf(receiver), target);
        assertEq(burned, burnPreview);
        assertEq(vault.balanceOf(alice), sharesBefore - burned);
        _assertSolvent();
    }
}
