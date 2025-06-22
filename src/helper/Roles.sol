// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAccessRegistry} from "../interfaces/IAccessRegistry.sol";
import {CustomRevert} from "../libraries/CustomRevert.sol";

/// @title Roles
/// @notice Base contract for role-based access control
/// @dev Provides modifiers for role-based access control using AccessRegistry
abstract contract Roles {
    using CustomRevert for bytes4;

    /// @dev Role identifier for admin users
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @dev Role identifier for multisig signers
    bytes32 public constant MULTISIG_SIGNER_ROLE = keccak256("MULTISIG_SIGNER_ROLE");
    /// @dev Role identifier for whitelisted borrowers
    bytes32 public constant WHITELISTED_BORROWER_ROLE = keccak256("WHITELISTED_BORROWER_ROLE");
    /// @dev Role identifier for protocol-level operations
    bytes32 public constant PROTOCOL_LEVEL_ROLE = keccak256("PROTOCOL_LEVEL_ROLE");

    /// @dev Access registry instance
    IAccessRegistry internal accessRegistry;

    /// @dev Custom error for unauthorized access
    error NotAuthorized();

    /// @notice Constructor to initialize the access registry
    /// @param _accessRegistry Address of the access registry
    constructor(address _accessRegistry) {
        accessRegistry = IAccessRegistry(_accessRegistry);
    }

    /// @dev Modifier to restrict access to admin role
    modifier onlyAdmin() {
        if (!accessRegistry.hasRole(ADMIN_ROLE, msg.sender)) NotAuthorized.selector.revertWith();
        _;
    }

    /// @dev Modifier to restrict access to whitelisted borrowers
    modifier onlyWhitelistedBorrower() {
        if (!accessRegistry.hasRole(WHITELISTED_BORROWER_ROLE, msg.sender)) NotAuthorized.selector.revertWith();
        _;
    }

    /// @dev Modifier to restrict access to multisig signers
    modifier onlyMultisigSigner() {
        if (!accessRegistry.hasRole(MULTISIG_SIGNER_ROLE, msg.sender)) NotAuthorized.selector.revertWith();
        _;
    }

    /// @dev Modifier to restrict access to protocol-level operations
    modifier onlyProtocolLevel() {
        if (!accessRegistry.hasRole(PROTOCOL_LEVEL_ROLE, msg.sender)) NotAuthorized.selector.revertWith();
        _;
    }
}
