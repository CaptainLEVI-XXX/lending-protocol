// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

abstract contract LendingVaultStorage {
    struct TokenInfo {
        address asset;
        string name;
        string symbol;
    }

    struct LendingVaultInfo {
        mapping(address => uint256) borrowVaultAllocations;
        uint256 totalAllocated;
    }

    error InvalidAddress();
    error InsufficientLiquidity();
    error InvalidAmount();
    error NotSupported();

    // Events
    event FundsAllocated(address indexed borrowVault, uint256 amount);
    event FundsReturned(address indexed borrowVault, uint256 principal, uint256 interest);
    event InterestAccrued(uint256 amount);

    bytes32 public constant ASSET_INFO_STORAGE = keccak256("qiro.asset.info.storage");
    bytes32 public constant LENDING_VAULT_INFO_STORAGE = keccak256("qiro.lending.vault.info.storage");

    function tokenInfo() internal pure returns (TokenInfo storage _tokenInfo) {
        bytes32 position = ASSET_INFO_STORAGE;
        assembly {
            _tokenInfo.slot := position
        }
    }

    function lendingVaultInfo() internal pure returns (LendingVaultInfo storage _lendingVaultInfo) {
        bytes32 position = LENDING_VAULT_INFO_STORAGE;
        assembly {
            _lendingVaultInfo.slot := position
        }
    }
}
