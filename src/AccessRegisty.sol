// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title AccessRegistry
/// @notice Central access control registry managing protocol roles and permissions
/// @dev Implements role-based access control using OpenZeppelin's AccessControl
contract AccessRegistry is AccessControl {
    /// @dev Role identifier for admin users
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @dev Role identifier for multisig signers
    bytes32 public constant MULTISIG_SIGNER_ROLE = keccak256("MULTISIG_SIGNER_ROLE");
    /// @dev Role identifier for whitelisted borrowers
    bytes32 public constant WHITELISTED_BORROWER_ROLE = keccak256("WHITELISTED_BORROWER_ROLE");
    /// @dev Role identifier for protocol-level operations
    bytes32 public constant PROTOCOL_LEVEL_ROLE = keccak256("PROTOCOL_LEVEL_ROLE");

    /// @notice Constructor to initialize the access registry with initial admin
    /// @param admin Address of the initial admin
    constructor(address admin) {
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(MULTISIG_SIGNER_ROLE, admin);
        _grantRole(WHITELISTED_BORROWER_ROLE, admin);
        _grantRole(PROTOCOL_LEVEL_ROLE, admin);

        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(MULTISIG_SIGNER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(WHITELISTED_BORROWER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PROTOCOL_LEVEL_ROLE, ADMIN_ROLE);
    }

    /// @notice Set the admin role for a specific role
    /// @dev Only callable by admins
    /// @param role The role to update admin for
    /// @param adminRole The new admin role
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external onlyRole(ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }
}
