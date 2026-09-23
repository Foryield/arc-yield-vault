// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MorphoYieldVault} from "../src/MorphoYieldVault.sol";

/// @dev The four access gates of a Morpho Vault V2. Any of them set can lock this vault's exits.
interface IMorphoVaultV2Gates {
    function receiveSharesGate() external view returns (address);
    function sendSharesGate() external view returns (address);
    function receiveAssetsGate() external view returns (address);
    function sendAssetsGate() external view returns (address);
}

/// @notice Deploys the USDC instance of MorphoYieldVault, and the EURC one when
///         EURC_MORPHO_TARGET is set, on Arc testnet or Arc mainnet, from the same bytecode.
///         The broadcasting account is a deployment key: it holds no role, the three roles are
///         set by the constructor. On mainnet, deposits are reserved to the owner.
///
///         OWNER=0x… GUARDIAN=0x… RECOVERY=0x… USDC_MORPHO_TARGET=0x… [EURC_MORPHO_TARGET=0x…] \
///         arc-forge script script/Deploy.s.sol --rpc-url arc --account <deployer keystore> \
///             --sender <deployer> --broadcast
///
///         Arc Foundry is required: the simulation touches the USDC precompile.
contract Deploy is Script {
    uint256 internal constant ARC_MAINNET = 5042;
    uint256 internal constant ARC_TESTNET = 5042002;
    /// @dev Same address on both networks: the native gas balance exposed as an ERC-20.
    IERC20 internal constant USDC = IERC20(0x3600000000000000000000000000000000000000);
    IERC20 internal constant EURC_MAINNET = IERC20(0xbEf5f6d51CB62b58e6A8f77868681825C6fe21c1);
    IERC20 internal constant EURC_TESTNET = IERC20(0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a);

    error UnsupportedChain(uint256 chainId);
    error TargetGated(address target, address gate);

    function run() external returns (MorphoYieldVault usdcVault, MorphoYieldVault eurcVault) {
        bool mainnet = block.chainid == ARC_MAINNET;
        if (!mainnet && block.chainid != ARC_TESTNET) revert UnsupportedChain(block.chainid);
        address owner = vm.envAddress("OWNER");
        address guardian = vm.envAddress("GUARDIAN");
        address recovery = vm.envAddress("RECOVERY");
        IERC4626 usdcTarget = IERC4626(vm.envAddress("USDC_MORPHO_TARGET"));
        IERC4626 eurcTarget = IERC4626(vm.envOr("EURC_MORPHO_TARGET", address(0)));

        _requireUngated(usdcTarget);
        if (address(eurcTarget) != address(0)) _requireUngated(eurcTarget);

        vm.startBroadcast();
        usdcVault = new MorphoYieldVault(
            USDC, "ForYield Arc USDC", "fyUSDC", owner, guardian, recovery, mainnet, usdcTarget
        );
        if (address(eurcTarget) != address(0)) {
            eurcVault = new MorphoYieldVault(
                mainnet ? EURC_MAINNET : EURC_TESTNET,
                "ForYield Arc EURC",
                "fyEURC",
                owner,
                guardian,
                recovery,
                mainnet,
                eurcTarget
            );
        }
        vm.stopBroadcast();
    }

    /// @dev A gate set on the target would lock every exit; refuse to deploy against one.
    function _requireUngated(IERC4626 target) internal view {
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
    }
}
