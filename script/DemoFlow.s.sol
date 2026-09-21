// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MorphoYieldVault} from "../src/MorphoYieldVault.sol";

/// @notice Demonstration flow on one vault, signed by a depositor distinct from the owner:
///         exact approval, deposit (supplied to Morpho in the same transaction), then redemption
///         of half the shares. Every transaction hash lands in broadcast/.
///
///         DEPOSITOR=0x… VAULT=0x… AMOUNT=5000000 \
///         arc-forge script script/DemoFlow.s.sol --rpc-url arc_testnet --account arc-depositor \
///             --broadcast
contract DemoFlow is Script {
    uint256 internal constant ARC_TESTNET = 5042002;

    function run() external {
        require(block.chainid == ARC_TESTNET, "DemoFlow: Arc testnet only");
        address depositor = vm.envAddress("DEPOSITOR");
        MorphoYieldVault vault = MorphoYieldVault(vm.envAddress("VAULT"));
        uint256 amount = vm.envUint("AMOUNT");
        IERC20 asset = IERC20(vault.asset());

        vm.startBroadcast(depositor);
        require(asset.approve(address(vault), amount), "DemoFlow: approve failed");
        uint256 shares = vault.deposit(amount, depositor);
        vault.redeem(shares / 2, depositor, depositor);
        vm.stopBroadcast();

        require(asset.allowance(address(vault), address(vault.MORPHO_VAULT())) == 0, "allowance");
        require(asset.allowance(depositor, address(vault)) == 0, "depositor allowance");
    }
}
