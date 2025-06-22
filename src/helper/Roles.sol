// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAccessRegistry} from "../interfaces/IAccessRegistry.sol";
import {CustomRevert} from "../libraries/CustomRevert.sol";

abstract contract Roles {
    using CustomRevert for bytes4;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MULTISIG_SIGNER_ROLE = keccak256("MULTISIG_SIGNER_ROLE");
    bytes32 public constant WHITELISTED_BORROWER_ROLE = keccak256("WHITELISTED_BORROWER_ROLE");
    bytes32 public constant PROTOCOL_LEVEL_ROLE = keccak256("PROTOCOL_LEVEL_ROLE");

    IAccessRegistry internal accessRegistry;

    error NotAuthorized();

    constructor(address _accessRegistry) {
        accessRegistry = IAccessRegistry(_accessRegistry);
    }

    modifier onlyAdmin() {
        if (!accessRegistry.hasRole(ADMIN_ROLE, msg.sender)) NotAuthorized.selector.revertWith();
        _;
    }

    modifier onlyWhitelistedBorrower() {
        if (!accessRegistry.hasRole(WHITELISTED_BORROWER_ROLE, msg.sender)) NotAuthorized.selector.revertWith();
        _;
    }

    modifier onlyMultisigSigner() {
        if (!accessRegistry.hasRole(MULTISIG_SIGNER_ROLE, msg.sender)) NotAuthorized.selector.revertWith();
        _;
    }

    modifier onlyProtocolLevel() {
        if (!accessRegistry.hasRole(PROTOCOL_LEVEL_ROLE, msg.sender)) NotAuthorized.selector.revertWith();
        _;
    }
}
