// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {YieldVault} from "../../src/YieldVault.sol";
import {MorphoYieldVault} from "../../src/MorphoYieldVault.sol";

/// @dev What a Morpho Vault V2 can pay out right now: its idle assets, plus the free liquidity
///      of the Morpho Blue market behind its liquidity adapter when one is set.
interface IVaultV2Liquidity {
    function liquidityAdapter() external view returns (address);
}

interface IMarketV1Adapter {
    function morpho() external view returns (address);
    function marketIds(uint256 index) external view returns (bytes32);
}

interface IMorphoBlue {
    function market(bytes32 id)
        external
        view
        returns (
            uint128 totalSupplyAssets,
            uint128 totalSupplyShares,
            uint128 totalBorrowAssets,
            uint128 totalBorrowShares,
            uint128 lastUpdate,
            uint128 fee
        );
}

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
        _skipUnlessTargetCanPay(GALAXY_USDC, 10e6); // a day of interest on 9,000 USDC, with margin
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

        // A day of real Morpho interest: well above the two units of rounding dust at any rate
        // Galaxy has shown (0.05 % to 0.5 % a year in September 2026), and small enough for the
        // exit to stay payable when the curated market is almost fully lent out.
        vm.warp(block.timestamp + 1 days);
        uint256 valueAfterDay = vault.totalAssets();
        assertGt(valueAfterDay, 9_000e6); // real Morpho interest, not a mock

        vm.prank(owner);
        uint256 out = vault.redeem(shares, receiver, owner);
        assertEq(USDC.balanceOf(receiver), out);
        assertLe(out, valueAfterDay); // rounding stays in the vault's favor
        assertApproxEqAbs(out, valueAfterDay, 2);
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

    /// @dev Exits are paid from the target's idle assets, then from the free liquidity of the
    ///      market behind its liquidity adapter. A test that accrues interest needs that much on
    ///      top of its own principal (which is always there: nobody else trades on the fork). When
    ///      the live market is fully lent out, the test is skipped with a message, before it
    ///      changes any state; any other failure still fails it.
    function _skipUnlessTargetCanPay(IERC4626 target, uint256 needed) internal {
        uint256 available = IERC20(target.asset()).balanceOf(address(target));
        address adapter = IVaultV2Liquidity(address(target)).liquidityAdapter();
        if (adapter != address(0)) {
            IMorphoBlue morpho = IMorphoBlue(IMarketV1Adapter(adapter).morpho());
            (uint128 supplied,, uint128 borrowed,,,) =
                morpho.market(IMarketV1Adapter(adapter).marketIds(0));
            available += supplied - borrowed;
        }
        if (available < needed) {
            emit log_named_uint("SKIPPED: target liquidity, units", available);
            vm.skip(true);
        }
    }
}
