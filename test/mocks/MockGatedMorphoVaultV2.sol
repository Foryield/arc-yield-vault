// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockMorphoVaultV2} from "./MockMorphoVaultV2.sol";

/// @notice Morpho Vault V2 target that also exposes the four access gates and the abdication
///         flags the deployment script reads. Abdication is open by default, as on a fresh vault.
contract MockGatedMorphoVaultV2 is MockMorphoVaultV2 {
    address public receiveSharesGate;
    address public sendSharesGate;
    address public receiveAssetsGate;
    address public sendAssetsGate;
    mapping(bytes4 => bool) public abdicated;

    constructor(IERC20 asset_) MockMorphoVaultV2(asset_) {}

    function setReceiveSharesGate(address gate) external {
        receiveSharesGate = gate;
    }

    function setSendSharesGate(address gate) external {
        sendSharesGate = gate;
    }

    function setReceiveAssetsGate(address gate) external {
        receiveAssetsGate = gate;
    }

    function setSendAssetsGate(address gate) external {
        sendAssetsGate = gate;
    }

    function setAbdicated(bytes4 selector, bool value) external {
        abdicated[selector] = value;
    }

    /// @dev Abdicates the three setters that could block an exit, as Galaxy did on Arc mainnet.
    function abdicateExitGates() external {
        abdicated[this.setReceiveSharesGate.selector] = true;
        abdicated[this.setSendSharesGate.selector] = true;
        abdicated[this.setReceiveAssetsGate.selector] = true;
    }
}
