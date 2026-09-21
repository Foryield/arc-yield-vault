// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YieldVault} from "../../src/YieldVault.sol";

/// @notice Concrete YieldVault with no venue: assets stay idle. Exercises the base contract alone.
contract IdleYieldVault is YieldVault {
    constructor(IERC20 asset_, address owner_, address guardian_, address recovery_)
        YieldVault(asset_, "Idle Yield Vault", "iyv", owner_, guardian_, recovery_)
    {}
}
