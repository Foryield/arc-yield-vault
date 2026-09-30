// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Deploy, IMorphoVaultV2Gates} from "../../script/Deploy.s.sol";
import {YieldVault} from "../../src/YieldVault.sol";
import {MorphoYieldVault} from "../../src/MorphoYieldVault.sol";

/// @dev The curator side of a Morpho Vault V2: changes are submitted, then executed after their
///      timelock unless the setter was abdicated.
interface IMorphoVaultV2Curator {
    function curator() external view returns (address);
    function submit(bytes calldata data) external;
}

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

/// @notice Dress rehearsal of the mainnet deployment and of the owner's own-capital round trip,
///         on a local fork of Arc mainnet, through the real deployment script and against the
///         real Galaxy targets. Nothing is broadcast.
///
///         arc-forge test --isolate --match-path test/fork/DeployMainnet.fork.t.sol \
///             --fork-url https://rpc.mainnet.arc.io
///
///         OWNER, GUARDIAN and RECOVERY may be exported to rehearse with the real role addresses;
///         labelled placeholders are used otherwise. Skipped on any other chain.
contract DeployMainnetForkTest is Test {
    uint256 internal constant ARC_MAINNET = 5042;
    uint256 internal constant AMOUNT = 100e6; // 100 USDC, the own-capital proof
    IERC20 internal constant USDC = IERC20(0x3600000000000000000000000000000000000000);
    IERC20 internal constant EURC = IERC20(0xbEf5f6d51CB62b58e6A8f77868681825C6fe21c1);
    IERC4626 internal constant GALAXY_USDC = IERC4626(0x8E357432CC12ff425c36432F312968aEb16112AF);
    IERC4626 internal constant GALAXY_EURC = IERC4626(0x389abDf4355e0cF4f19298179991705a98f21c18);

    MorphoYieldVault internal usdcVault;
    MorphoYieldVault internal eurcVault;
    address internal owner;
    address internal guardian;
    address internal recovery;
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        if (block.chainid != ARC_MAINNET) vm.skip(true);
        owner = vm.envOr("OWNER", makeAddr("owner"));
        guardian = vm.envOr("GUARDIAN", makeAddr("guardian"));
        recovery = vm.envOr("RECOVERY", makeAddr("recovery"));
        (usdcVault, eurcVault) = new Deploy()
            .deploy(
                Deploy.Config({
                    expectedChainId: ARC_MAINNET,
                    owner: owner,
                    guardian: guardian,
                    recovery: recovery,
                    usdcTarget: GALAXY_USDC,
                    eurcTarget: GALAXY_EURC
                })
            );
        // On Arc the USDC ERC-20 balance is the native balance scaled by 1e12: 101 USDC leaves
        // a margin for gas, as the owner will keep one on mainnet.
        vm.deal(owner, 101e18);
        vm.deal(stranger, 101e18);
    }

    // F1: the script's output, read back as the post-deployment checks will read it.
    function test_fork_deploymentMatchesTheMainnetConfiguration() public view {
        _assertDeployed(usdcVault, USDC, GALAXY_USDC);
        _assertDeployed(eurcVault, EURC, GALAXY_EURC);
        assertEq(usdcVault.maxDeposit(stranger), 0);
        assertEq(usdcVault.maxDeposit(owner), type(uint256).max);
    }

    function _assertDeployed(MorphoYieldVault vault, IERC20 asset, IERC4626 target) internal view {
        assertEq(vault.asset(), address(asset));
        assertEq(address(vault.MORPHO_VAULT()), address(target));
        assertEq(vault.owner(), owner);
        assertEq(vault.pendingOwner(), address(0));
        assertEq(vault.guardian(), guardian);
        assertEq(vault.RECOVERY_ADDRESS(), recovery);
        assertTrue(vault.OWNER_ONLY_DEPOSITS());
        assertEq(vault.decimals(), 12);
        assertFalse(vault.paused());
        assertFalse(vault.terminated());
        assertEq(vault.totalSupply(), 0);
    }

    // F2: the exact sequence the owner will sign, then a full exit.
    function test_fork_ownerRoundTripOfOneHundredUsdc() public {
        _skipUnlessTargetCanPay(GALAXY_USDC, 1e6); // a day of interest on 100 USDC, with margin
        uint256 shares = _ownerDeposit(AMOUNT);
        assertEq(shares, usdcVault.balanceOf(owner));
        assertEq(usdcVault.totalSupply(), shares);
        assertEq(USDC.balanceOf(address(usdcVault)), 0);
        assertEq(USDC.allowance(address(usdcVault), address(GALAXY_USDC)), 0);
        assertEq(USDC.allowance(owner, address(usdcVault)), 0);
        assertGt(GALAXY_USDC.balanceOf(address(usdcVault)), 0);
        assertApproxEqAbs(usdcVault.totalAssets(), AMOUNT, 2);
        assertLe(usdcVault.totalAssets(), AMOUNT);

        vm.warp(block.timestamp + 1 days);
        uint256 before = USDC.balanceOf(owner);
        uint256 toRedeem = usdcVault.maxRedeem(owner);
        assertEq(toRedeem, shares);
        uint256 expected = usdcVault.previewRedeem(toRedeem);
        vm.prank(owner);
        uint256 out = usdcVault.redeem(toRedeem, owner, owner);

        assertEq(out, expected);
        assertGe(out, AMOUNT - 2);
        assertEq(USDC.balanceOf(owner) - before, out);
        assertEq(usdcVault.balanceOf(owner), 0);
        assertEq(usdcVault.totalSupply(), 0);
    }

    function test_fork_ownerExitsWithMaxWithdrawToo() public {
        _ownerDeposit(AMOUNT);
        uint256 assets = usdcVault.maxWithdraw(owner);
        assertGe(assets, AMOUNT - 2);
        vm.prank(owner);
        usdcVault.withdraw(assets, owner, owner);
        assertEq(usdcVault.totalSupply(), 0);
    }

    // F3: the terminal emergency path, against the real Morpho Vault V2.
    function test_fork_guardianEvacuatesToRecovery() public {
        _ownerDeposit(AMOUNT);

        vm.prank(guardian);
        usdcVault.pause();
        assertEq(usdcVault.maxRedeem(owner), 0);
        vm.prank(owner);
        vm.expectRevert(); // ERC4626ExceededMaxRedeem: exits closed while paused
        usdcVault.redeem(1, owner, owner);

        vm.prank(guardian);
        usdcVault.emergencyDeallocate();
        assertEq(GALAXY_USDC.balanceOf(address(usdcVault)), 0);

        uint256 before = USDC.balanceOf(recovery);
        vm.prank(guardian);
        usdcVault.emergencyWithdraw();
        assertGe(USDC.balanceOf(recovery) - before, AMOUNT - 2);
        assertTrue(usdcVault.terminated());

        vm.prank(owner);
        vm.expectRevert(YieldVault.VaultTerminated.selector);
        usdcVault.unpause();
    }

    /// @dev A second deallocation once the position is empty redeems zero Morpho shares; this
    ///      records what the real Vault V2 does with it.
    function test_fork_secondDeallocateOnAnEmptyPosition() public {
        _ownerDeposit(AMOUNT);
        vm.startPrank(guardian);
        usdcVault.emergencyDeallocate();
        usdcVault.emergencyDeallocate();
        vm.stopPrank();
        assertEq(GALAXY_USDC.balanceOf(address(usdcVault)), 0);
    }

    // F4: the non-terminal drill that will be run on the empty mainnet vault.
    function test_fork_pauseByGuardianUnpauseByOwnerThenDeposit() public {
        vm.prank(guardian);
        usdcVault.pause();
        vm.prank(owner);
        usdcVault.unpause();
        assertGt(_ownerDeposit(1e6), 0);
    }

    // F5: nobody but the owner can enter, whatever the receiver.
    function test_fork_strangerCannotEnter() public {
        vm.startPrank(stranger);
        USDC.approve(address(usdcVault), AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, stranger, 1e6, 0)
        );
        usdcVault.deposit(1e6, stranger);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.DepositNotAllowed.selector, stranger));
        usdcVault.deposit(1e6, owner);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxMint.selector, stranger, 1e12, 0)
        );
        usdcVault.mint(1e12, stranger);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.DepositNotAllowed.selector, stranger));
        usdcVault.mint(1e12, owner);
        vm.stopPrank();

        vm.startPrank(owner);
        USDC.approve(address(usdcVault), AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, stranger, 1e6, 0)
        );
        usdcVault.deposit(1e6, stranger);
        vm.stopPrank();
        assertEq(usdcVault.totalSupply(), 0);
    }

    function test_fork_donationBeforeTheFirstDepositCostsTheOwnerAlmostNothing() public {
        vm.prank(stranger);
        USDC.transfer(address(usdcVault), AMOUNT);

        _ownerDeposit(AMOUNT);
        uint256 toRedeem = usdcVault.maxRedeem(owner);
        vm.prank(owner);
        uint256 out = usdcVault.redeem(toRedeem, owner, owner);
        assertGe(out, AMOUNT - 100);
    }

    // F6: the curator state the deployment relies on. Fails loudly if it changes before the
    //     deployment: exit gates abdicated and no gate set, on both targets.
    function test_fork_targetsKeepTheirExitGatesAbdicated() public view {
        _assertTargetSafe(GALAXY_USDC);
        _assertTargetSafe(GALAXY_EURC);
    }

    /// @dev The flags above, proven by behaviour: the curator can still submit an exit gate, but
    ///      executing it reverts `Abdicated()` even after any timelock.
    function test_fork_curatorCannotEverSetAnExitGate() public {
        IERC4626[2] memory targets = [GALAXY_USDC, GALAXY_EURC];
        bytes4[3] memory setters = [
            bytes4(keccak256("setReceiveSharesGate(address)")),
            bytes4(keccak256("setSendSharesGate(address)")),
            bytes4(keccak256("setReceiveAssetsGate(address)"))
        ];
        for (uint256 i; i < targets.length; ++i) {
            IMorphoVaultV2Curator target = IMorphoVaultV2Curator(address(targets[i]));
            for (uint256 j; j < setters.length; ++j) {
                bytes memory data = abi.encodeWithSelector(setters[j], stranger);
                vm.prank(target.curator());
                target.submit(data);
                vm.warp(block.timestamp + 3650 days);
                (bool ok, bytes memory reason) = address(target).call(data);
                assertFalse(ok);
                assertEq(bytes4(reason), bytes4(keccak256("Abdicated()")));
            }
        }
    }

    function _assertTargetSafe(IERC4626 target) internal view {
        IMorphoVaultV2Gates gates = IMorphoVaultV2Gates(address(target));
        assertEq(gates.receiveSharesGate(), address(0));
        assertEq(gates.sendSharesGate(), address(0));
        assertEq(gates.receiveAssetsGate(), address(0));
        assertEq(gates.sendAssetsGate(), address(0));
        assertTrue(gates.abdicated(bytes4(keccak256("setReceiveSharesGate(address)"))));
        assertTrue(gates.abdicated(bytes4(keccak256("setSendSharesGate(address)"))));
        assertTrue(gates.abdicated(bytes4(keccak256("setReceiveAssetsGate(address)"))));
    }

    function _ownerDeposit(uint256 assets) internal returns (uint256 shares) {
        vm.startPrank(owner);
        USDC.approve(address(usdcVault), assets);
        shares = usdcVault.deposit(assets, owner);
        vm.stopPrank();
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
