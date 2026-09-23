// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MorphoYieldVault} from "../src/MorphoYieldVault.sol";

/// @notice Deploys the USDC and EURC instances of MorphoYieldVault on Arc testnet, from the same
///         bytecode. The broadcasting account must be OWNER.
///
///         OWNER=0x… GUARDIAN=0x… RECOVERY=0x… USDC_MORPHO_TARGET=0x… EURC_MORPHO_TARGET=0x… \
///         arc-forge script script/Deploy.s.sol --rpc-url arc_testnet --account arc-admin \
///             --broadcast --verify --verifier blockscout \
///             --verifier-url https://explorer.testnet.arc.io/api/
///
///         Arc Foundry is required: the simulation touches the USDC precompile.
contract Deploy is Script {
    uint256 internal constant ARC_TESTNET = 5042002;
    IERC20 internal constant USDC = IERC20(0x3600000000000000000000000000000000000000);
    IERC20 internal constant EURC = IERC20(0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a);

    function run() external returns (MorphoYieldVault usdcVault, MorphoYieldVault eurcVault) {
        require(block.chainid == ARC_TESTNET, "Deploy: Arc testnet only");
        address owner = vm.envAddress("OWNER");
        address guardian = vm.envAddress("GUARDIAN");
        address recovery = vm.envAddress("RECOVERY");
        IERC4626 usdcTarget = IERC4626(vm.envAddress("USDC_MORPHO_TARGET"));
        IERC4626 eurcTarget = IERC4626(vm.envAddress("EURC_MORPHO_TARGET"));

        vm.startBroadcast(owner);
        usdcVault = new MorphoYieldVault(
            USDC, "ForYield Arc USDC", "fyUSDC", owner, guardian, recovery, false, usdcTarget
        );
        eurcVault = new MorphoYieldVault(
            EURC, "ForYield Arc EURC", "fyEURC", owner, guardian, recovery, false, eurcTarget
        );
        vm.stopBroadcast();
    }
}
