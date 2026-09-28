// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MorphoYieldVault} from "../src/MorphoYieldVault.sol";

/// @dev The four access gates of a Morpho Vault V2, and whether a setter is abdicated for good.
///      Any gate set can lock this vault's exits, except `sendAssetsGate` (deposits only).
interface IMorphoVaultV2Gates {
    function receiveSharesGate() external view returns (address);
    function sendSharesGate() external view returns (address);
    function receiveAssetsGate() external view returns (address);
    function sendAssetsGate() external view returns (address);
    function abdicated(bytes4 selector) external view returns (bool);
}

/// @notice Deploys the USDC instance of MorphoYieldVault, and the EURC one when
///         EURC_MORPHO_TARGET is set, on Arc testnet or Arc mainnet, from the same bytecode.
///         The broadcasting account is a deployment key: it holds no role, the three roles are
///         set by the constructor. On mainnet, deposits are reserved to the owner, both targets
///         are pinned, and their exit gates must be abdicated so that no curator can ever lock
///         the vault's exits after a deposit.
///
///         EXPECTED_CHAIN_ID=5042 OWNER=0x… GUARDIAN=0x… RECOVERY=0x… \
///         USDC_MORPHO_TARGET=0x… EURC_MORPHO_TARGET=0x… \
///         arc-forge script script/Deploy.s.sol --rpc-url arc_mainnet \
///             --account <deployer keystore> --sender <deployer> --broadcast
///
///         Run it once without --broadcast first: the simulation prints every parameter and the
///         vault addresses. Arc Foundry is required: the simulation touches the USDC precompile.
contract Deploy is Script {
    uint256 internal constant ARC_MAINNET = 5042;
    uint256 internal constant ARC_TESTNET = 5042002;
    /// @dev Same address on both networks: the native gas balance exposed as an ERC-20.
    IERC20 internal constant USDC = IERC20(0x3600000000000000000000000000000000000000);
    IERC20 internal constant EURC_MAINNET = IERC20(0xbEf5f6d51CB62b58e6A8f77868681825C6fe21c1);
    IERC20 internal constant EURC_TESTNET = IERC20(0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a);
    /// @dev Mainnet targets, pinned by address: several test vaults share these names. Exit gates
    ///      abdicated and no gate set, checked on chain on 2026-09-28.
    address internal constant GALAXY_USDC = 0x8E357432CC12ff425c36432F312968aEb16112AF;
    address internal constant GALAXY_EURC = 0x389abDf4355e0cF4f19298179991705a98f21c18;

    error UnsupportedChain(uint256 chainId);
    error WrongChain(uint256 expected, uint256 actual);
    error TargetNotPinned(address target, address expected);
    error TargetGated(address target, address gate);
    error ExitGateNotAbdicated(address target, bytes4 setter);
    error DeployerHoldsRole(address deployer);
    error MissingEurcTarget();
    error DeployerNotSet();

    /// @dev Everything the deployment depends on. `run()` reads it from the environment; tests
    ///      call `deploy` directly, since environment variables are shared by parallel tests.
    struct Config {
        uint256 expectedChainId;
        address owner;
        address guardian;
        address recovery;
        IERC4626 usdcTarget;
        IERC4626 eurcTarget;
    }

    function run() external returns (MorphoYieldVault usdcVault, MorphoYieldVault eurcVault) {
        return deploy(
            Config({
                expectedChainId: vm.envUint("EXPECTED_CHAIN_ID"),
                owner: vm.envAddress("OWNER"),
                guardian: vm.envAddress("GUARDIAN"),
                recovery: vm.envAddress("RECOVERY"),
                usdcTarget: IERC4626(vm.envAddress("USDC_MORPHO_TARGET")),
                eurcTarget: IERC4626(vm.envOr("EURC_MORPHO_TARGET", address(0)))
            })
        );
    }

    function deploy(Config memory c)
        public
        returns (MorphoYieldVault usdcVault, MorphoYieldVault eurcVault)
    {
        if (block.chainid != c.expectedChainId) {
            revert WrongChain(c.expectedChainId, block.chainid);
        }
        bool mainnet = block.chainid == ARC_MAINNET;
        if (!mainnet && block.chainid != ARC_TESTNET) revert UnsupportedChain(block.chainid);
        if (msg.sender == c.owner || msg.sender == c.guardian || msg.sender == c.recovery) {
            revert DeployerHoldsRole(msg.sender);
        }
        if (mainnet && address(c.eurcTarget) == address(0)) revert MissingEurcTarget();
        // Without --sender, forge simulates from its default caller: the predicted addresses and
        // the role check would be meaningless.
        if (mainnet && msg.sender == DEFAULT_SENDER) revert DeployerNotSet();

        _requireSafeTarget(c.usdcTarget, mainnet, GALAXY_USDC);
        if (address(c.eurcTarget) != address(0)) {
            _requireSafeTarget(c.eurcTarget, mainnet, GALAXY_EURC);
        }

        IERC20 eurc = mainnet ? EURC_MAINNET : EURC_TESTNET;
        _log(c, mainnet, eurc);

        vm.startBroadcast();
        usdcVault = new MorphoYieldVault(
            USDC,
            "ForYield Arc USDC",
            "fyUSDC",
            c.owner,
            c.guardian,
            c.recovery,
            mainnet,
            c.usdcTarget
        );
        if (address(c.eurcTarget) != address(0)) {
            eurcVault = new MorphoYieldVault(
                eurc,
                "ForYield Arc EURC",
                "fyEURC",
                c.owner,
                c.guardian,
                c.recovery,
                mainnet,
                c.eurcTarget
            );
        }
        vm.stopBroadcast();
    }

    /// @dev No gate may be set. On mainnet the target must also be the pinned one, and the three
    ///      gates that can block an exit must be abdicated: a gate set after a deposit would lock
    ///      every exit, `forceDeallocate` included.
    function _requireSafeTarget(IERC4626 target, bool mainnet, address pinned) internal view {
        IMorphoVaultV2Gates gates = IMorphoVaultV2Gates(address(target));
        address[4] memory set = [
            gates.receiveSharesGate(),
            gates.sendSharesGate(),
            gates.receiveAssetsGate(),
            gates.sendAssetsGate()
        ];
        for (uint256 i; i < set.length; ++i) {
            if (set[i] != address(0)) revert TargetGated(address(target), set[i]);
        }
        if (!mainnet) return;
        if (address(target) != pinned) revert TargetNotPinned(address(target), pinned);
        bytes4[3] memory exitSetters = [
            bytes4(keccak256("setReceiveSharesGate(address)")),
            bytes4(keccak256("setSendSharesGate(address)")),
            bytes4(keccak256("setReceiveAssetsGate(address)"))
        ];
        for (uint256 i; i < exitSetters.length; ++i) {
            if (!gates.abdicated(exitSetters[i])) {
                revert ExitGateNotAbdicated(address(target), exitSetters[i]);
            }
        }
    }

    /// @dev Everything a reviewer needs before the broadcast, and the constructor arguments the
    ///      source verification asks for.
    function _log(Config memory c, bool mainnet, IERC20 eurc) internal view {
        console.log("chain id           ", block.chainid);
        console.log("deployer (no role) ", msg.sender);
        console.log("owner              ", c.owner);
        console.log("guardian           ", c.guardian);
        console.log("recovery           ", c.recovery);
        console.log("owner-only deposits", mainnet);
        console.log("USDC target        ", address(c.usdcTarget));
        console.log("USDC constructor args");
        console.logBytes(
            abi.encode(
                USDC,
                "ForYield Arc USDC",
                "fyUSDC",
                c.owner,
                c.guardian,
                c.recovery,
                mainnet,
                c.usdcTarget
            )
        );
        if (address(c.eurcTarget) == address(0)) return;
        console.log("EURC target        ", address(c.eurcTarget));
        console.log("EURC constructor args");
        console.logBytes(
            abi.encode(
                eurc,
                "ForYield Arc EURC",
                "fyEURC",
                c.owner,
                c.guardian,
                c.recovery,
                mainnet,
                c.eurcTarget
            )
        );
    }
}
