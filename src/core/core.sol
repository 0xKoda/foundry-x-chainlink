// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "../gov/vLex.sol";
import {ERC4626, Vault, ERC20} from "../Vault.sol";
import {ICore} from "./ICore.sol";
import {Permissions} from "./Permissions.sol";
import "lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

/// @title Source of truth for AER Protocol
/// @author Fei Protocol
/// @notice maintains roles, access control, Volt, Vcon, and the Vcon treasury
contract Core is ICore, Permissions, Initializable {
    /// @notice the address of the FEI contract
    IVolt public override AER;

    /// @notice the address of the Vcon contract
    IERC20 public override vLex;

    function init() external initializer {
        aer = new AER(address(this));
        /// msg.sender already has the VOLT Minting abilities, so grant them governor as well
        _setupGovernor(msg.sender);
    }

    /// @notice governor only function to set the VCON token
    function setVcon(IERC20 _vcon) external onlyGovernor {
        vLex = _vcon;

        emit VconUpdate(_vcon);
    }
}