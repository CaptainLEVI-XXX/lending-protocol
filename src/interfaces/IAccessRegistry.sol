// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ===== IAccessRegistry.sol =====
interface IAccessRegistry {
    function ADMIN_ROLE() external view returns (bytes32);
    function MULTISIG_SIGNER_ROLE() external view returns (bytes32);
    function WHITELISTED_BORROWER_ROLE() external view returns (bytes32);

    function hasRole(bytes32 role, address account) external view returns (bool);
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
}
