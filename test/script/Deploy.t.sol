// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {MorphoYieldVault} from "../../src/MorphoYieldVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockGatedMorphoVaultV2} from "../mocks/MockGatedMorphoVaultV2.sol";

/// @notice The deployment script's guards, without a network: the Arc tokens and the pinned
///         mainnet targets are mocks etched at their real addresses.
contract DeployScriptTest is Test {
    uint256 internal constant ARC_MAINNET = 5042;
    uint256 internal constant ARC_TESTNET = 5042002;
    address internal constant USDC = 0x3600000000000000000000000000000000000000;
    address internal constant EURC_MAINNET = 0xbEf5f6d51CB62b58e6A8f77868681825C6fe21c1;
    address internal constant EURC_TESTNET = 0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a;
    address internal constant GALAXY_USDC = 0x8E357432CC12ff425c36432F312968aEb16112AF;
    address internal constant GALAXY_EURC = 0x389abDf4355e0cF4f19298179991705a98f21c18;

    Deploy internal script;
    address internal owner = makeAddr("owner");
    address internal guardian = makeAddr("guardian");
    address internal recovery = makeAddr("recovery");

    function setUp() public {
        script = new Deploy();
        _etchToken(USDC, "USDC");
        _etchToken(EURC_MAINNET, "EURC");
        _etchToken(EURC_TESTNET, "EURC");
        _etchTarget(GALAXY_USDC, USDC);
        _etchTarget(GALAXY_EURC, EURC_MAINNET);
        MockGatedMorphoVaultV2(GALAXY_USDC).abdicateExitGates();
        MockGatedMorphoVaultV2(GALAXY_EURC).abdicateExitGates();
        vm.chainId(ARC_MAINNET);
    }

    function _etchToken(address at, string memory symbol) internal {
        vm.etch(at, address(new MockERC20(symbol, symbol, 6)).code);
    }

    /// @dev The mock's asset is an immutable, so the etched code keeps it.
    function _etchTarget(address at, address asset) internal {
        vm.etch(at, address(new MockGatedMorphoVaultV2(IERC20(asset))).code);
    }

    function _config(uint256 chainId, address usdcTarget, address eurcTarget)
        internal
        view
        returns (Deploy.Config memory)
    {
        return Deploy.Config({
            expectedChainId: chainId,
            owner: owner,
            guardian: guardian,
            recovery: recovery,
            usdcTarget: IERC4626(usdcTarget),
            eurcTarget: IERC4626(eurcTarget)
        });
    }

    function _mainnet() internal view returns (Deploy.Config memory) {
        return _config(ARC_MAINNET, GALAXY_USDC, GALAXY_EURC);
    }

    function test_mainnet_deploysBothVaultsRestrictedToTheOwner() public {
        (MorphoYieldVault usdcVault, MorphoYieldVault eurcVault) = script.deploy(_mainnet());
        _assertVault(usdcVault, USDC, GALAXY_USDC, true);
        _assertVault(eurcVault, EURC_MAINNET, GALAXY_EURC, true);
        assertEq(usdcVault.symbol(), "fyUSDC");
        assertEq(eurcVault.symbol(), "fyEURC");
    }

    function test_testnet_deploysOpenVaultsAndEurcIsOptional() public {
        vm.chainId(ARC_TESTNET);
        MockGatedMorphoVaultV2 target = new MockGatedMorphoVaultV2(IERC20(USDC));
        (MorphoYieldVault usdcVault, MorphoYieldVault eurcVault) =
            script.deploy(_config(ARC_TESTNET, address(target), address(0)));
        _assertVault(usdcVault, USDC, address(target), false);
        assertEq(address(eurcVault), address(0));
    }

    function test_testnet_usesTheTestnetEurc() public {
        vm.chainId(ARC_TESTNET);
        MockGatedMorphoVaultV2 usdcTarget = new MockGatedMorphoVaultV2(IERC20(USDC));
        MockGatedMorphoVaultV2 eurcTarget = new MockGatedMorphoVaultV2(IERC20(EURC_TESTNET));
        (, MorphoYieldVault eurcVault) =
            script.deploy(_config(ARC_TESTNET, address(usdcTarget), address(eurcTarget)));
        _assertVault(eurcVault, EURC_TESTNET, address(eurcTarget), false);
    }

    function _assertVault(MorphoYieldVault vault, address asset, address target, bool ownerOnly)
        internal
        view
    {
        assertEq(vault.asset(), asset);
        assertEq(address(vault.MORPHO_VAULT()), target);
        assertEq(vault.owner(), owner);
        assertEq(vault.pendingOwner(), address(0));
        assertEq(vault.guardian(), guardian);
        assertEq(vault.RECOVERY_ADDRESS(), recovery);
        assertEq(vault.OWNER_ONLY_DEPOSITS(), ownerOnly);
        assertEq(vault.decimals(), 12);
        assertFalse(vault.paused());
        assertEq(vault.totalSupply(), 0);
    }

    function test_revertsWhenTheChainIsNotTheExpectedOne() public {
        vm.expectRevert(
            abi.encodeWithSelector(Deploy.WrongChain.selector, ARC_TESTNET, ARC_MAINNET)
        );
        script.deploy(_config(ARC_TESTNET, GALAXY_USDC, GALAXY_EURC));
    }

    function test_revertsOnAChainOtherThanArc() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(Deploy.UnsupportedChain.selector, 1));
        script.deploy(_config(1, GALAXY_USDC, GALAXY_EURC));
    }

    function test_revertsWhenTheDeployerHoldsARole() public {
        address[3] memory roles = [owner, guardian, recovery];
        for (uint256 i; i < roles.length; ++i) {
            vm.prank(roles[i]);
            vm.expectRevert(abi.encodeWithSelector(Deploy.DeployerHoldsRole.selector, roles[i]));
            script.deploy(_mainnet());
        }
    }

    function test_mainnet_requiresAnExplicitSender() public {
        vm.prank(DEFAULT_SENDER);
        vm.expectRevert(Deploy.DeployerNotSet.selector);
        script.deploy(_mainnet());
    }

    function test_mainnet_requiresTheEurcTarget() public {
        vm.expectRevert(Deploy.MissingEurcTarget.selector);
        script.deploy(_config(ARC_MAINNET, GALAXY_USDC, address(0)));
    }

    function test_mainnet_refusesATargetOtherThanThePinnedOne() public {
        MockGatedMorphoVaultV2 lookalike = new MockGatedMorphoVaultV2(IERC20(USDC));
        lookalike.abdicateExitGates();
        vm.expectRevert(
            abi.encodeWithSelector(Deploy.TargetNotPinned.selector, address(lookalike), GALAXY_USDC)
        );
        script.deploy(_config(ARC_MAINNET, address(lookalike), GALAXY_EURC));

        vm.expectRevert(
            abi.encodeWithSelector(Deploy.TargetNotPinned.selector, GALAXY_USDC, GALAXY_EURC)
        );
        script.deploy(_config(ARC_MAINNET, GALAXY_USDC, GALAXY_USDC));
    }

    function test_mainnet_refusesATargetWhoseExitGatesAreNotAbdicated() public {
        bytes4[3] memory setters = [
            MockGatedMorphoVaultV2.setReceiveSharesGate.selector,
            MockGatedMorphoVaultV2.setSendSharesGate.selector,
            MockGatedMorphoVaultV2.setReceiveAssetsGate.selector
        ];
        MockGatedMorphoVaultV2 target = MockGatedMorphoVaultV2(GALAXY_EURC);
        for (uint256 i; i < setters.length; ++i) {
            target.abdicateExitGates();
            target.setAbdicated(setters[i], false); // exactly one exit gate left open
            vm.expectRevert(
                abi.encodeWithSelector(
                    Deploy.ExitGateNotAbdicated.selector, GALAXY_EURC, setters[i]
                )
            );
            script.deploy(_mainnet());
        }
    }

    function test_refusesATargetWithAnyGateSet() public {
        address gate = makeAddr("gate");
        MockGatedMorphoVaultV2 target = MockGatedMorphoVaultV2(GALAXY_USDC);

        target.setReceiveSharesGate(gate);
        _expectGated(target, gate);
        target.setReceiveSharesGate(address(0));

        target.setSendSharesGate(gate);
        _expectGated(target, gate);
        target.setSendSharesGate(address(0));

        target.setReceiveAssetsGate(gate);
        _expectGated(target, gate);
        target.setReceiveAssetsGate(address(0));

        // Deposits only, but still refused at deployment: nothing could be deposited.
        target.setSendAssetsGate(gate);
        _expectGated(target, gate);
    }

    function _expectGated(MockGatedMorphoVaultV2 target, address gate) internal {
        vm.expectRevert(abi.encodeWithSelector(Deploy.TargetGated.selector, address(target), gate));
        script.deploy(_mainnet());
    }

    function test_testnet_refusesAGatedTargetToo() public {
        vm.chainId(ARC_TESTNET);
        MockGatedMorphoVaultV2 target = new MockGatedMorphoVaultV2(IERC20(USDC));
        target.setSendSharesGate(address(this));
        vm.expectRevert(
            abi.encodeWithSelector(Deploy.TargetGated.selector, address(target), address(this))
        );
        script.deploy(_config(ARC_TESTNET, address(target), address(0)));
    }
}
