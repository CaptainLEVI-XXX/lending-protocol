// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract AccessRegistry is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MULTISIG_SIGNER_ROLE = keccak256("MULTISIG_SIGNER_ROLE");
    bytes32 public constant WHITELISTED_BORROWER_ROLE = keccak256("WHITELISTED_BORROWER_ROLE");

    constructor(address admin) {
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(MULTISIG_SIGNER_ROLE, admin);
        _grantRole(WHITELISTED_BORROWER_ROLE, admin);

        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(MULTISIG_SIGNER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(WHITELISTED_BORROWER_ROLE, ADMIN_ROLE);
    }

    function setRoleAdmin(bytes32 role, bytes32 adminRole) external onlyRole(ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }
}