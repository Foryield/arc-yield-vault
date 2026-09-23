// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {YieldVault} from "../../src/YieldVault.sol";
import {MorphoYieldVault} from "../../src/MorphoYieldVault.sol";

/// @notice Runs the vault against a real, curated Morpho Vault V2 on a local fork of Arc mainnet.
///         Nothing is broadcast. Requires Arc Foundry, which implements Arc's USDC precompile:
///
///         arc-forge test --isolate --match-path test/fork/MorphoArcMainnet.fork.t.sol \
///             --fork-url https://rpc.mainnet.arc.io
///
///         `--isolate` is required: a Morpho Vault V2 freezes its valuation for the rest of a
///         transaction (transient `firstTotalAssets`), and without it the whole test is one
///         transaction, so no interest could ever show.
///
///         Skipped on any other chain, so the regular `forge test` stays network-free.
contract MorphoArcMainnetForkTest is Test {
    uint256 internal constant ARC_MAINNET = 5042;
    /// @dev Predeployed USDC: native gas balance (18 decimals) exposed as an ERC-20 (6 decimals).
    IERC20 internal constant USDC = IERC20(0x3600000000000000000000000000000000000000);
    /// @dev Galaxy USDC, Morpho Vault V2 on Arc mainnet, no access gates (checked 2026-09-21).
    IERC4626 internal constant GALAXY_USDC = IERC4626(0x8E357432CC12ff425c36432F312968aEb16112AF);

    MorphoYieldVault internal vault;
    address internal owner = makeAddr("owner");
    address internal receiver = makeAddr("receiver");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        if (block.chainid != ARC_MAINNET) vm.skip(true);
        vault = new MorphoYieldVault(
            USDC,
            "ForYield Arc USDC",
            "fyUSDC",
            owner,
            makeAddr("guardian"),
            makeAddr("recovery"),
            true, // as on mainnet: deposits reserved to the owner
            GALAXY_USDC
        );
        // Credit 10,000 USDC: on Arc the ERC-20 balance is the native balance, scaled by 1e12.
        vm.deal(owner, 10_000e18);
        vm.deal(stranger, 10_000e18);
    }

    function test_fork_depositSuppliesGalaxyAndRedeemReturnsUsdc() public {
        assertEq(GALAXY_USDC.maxDeposit(address(vault)), 0); // Vault V2 trait, never relied upon
        assertEq(USDC.balanceOf(owner), 10_000e6);

        // The owner keeps a little USDC back: on Arc the same balance also pays its gas.
        vm.startPrank(owner);
        USDC.approve(address(vault), 9_000e6);
        uint256 shares = vault.deposit(9_000e6, owner);
        vm.stopPrank();

        assertGt(GALAXY_USDC.balanceOf(address(vault)), 0);
        assertEq(USDC.balanceOf(address(vault)), 0);
        assertEq(USDC.allowance(address(vault), address(GALAXY_USDC)), 0);
        assertApproxEqAbs(vault.totalAssets(), 9_000e6, 2);

        // Galaxy's rate was about 0.0025 % a year on 2026-09-21: a year of interest on 9,000 USDC
        // is roughly 0.2 USDC, well above the two units of rounding dust.
        vm.warp(block.timestamp + 365 days);
        uint256 valueAfterYear = vault.totalAssets();
        assertGt(valueAfterYear, 9_000e6); // real Morpho interest, not a mock

        vm.prank(owner);
        uint256 out = vault.redeem(shares, receiver, owner);
        assertEq(USDC.balanceOf(receiver), out);
        assertLe(out, valueAfterYear); // rounding stays in the vault's favor
        assertApproxEqAbs(out, valueAfterYear, 2);
        assertEq(vault.totalSupply(), 0);
    }

    function test_fork_strangerCannotDeposit() public {
        vm.startPrank(stranger);
        USDC.approve(address(vault), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.DepositNotAllowed.selector, stranger));
        vault.deposit(1_000e6, owner);
        vm.stopPrank();
        assertEq(vault.totalSupply(), 0);
    }
}
