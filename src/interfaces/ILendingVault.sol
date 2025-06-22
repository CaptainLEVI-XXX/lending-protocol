// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title ILendingVault
/// @notice Interface for the LendingVault contract
/// @dev ERC-4626 compliant vault for deposits and withdrawals
interface ILendingVault {
    /// @notice Get the underlying asset address
    /// @return The asset address
    function asset() external view returns (address);

    /// @notice Get the total assets managed by the vault
    /// @return The total assets
    function totalAssets() external view returns (uint256);

    /// @notice Get the available liquidity for lending
    /// @return The available liquidity
    function availableLiquidity() external view returns (uint256);

    /// @notice Allocate funds to a borrow vault
    /// @param amount Amount to allocate
    /// @return success Whether the allocation was successful
    function allocateFunds(uint256 amount) external returns (bool);

    /// @notice Return funds from a borrow vault
    /// @param principal Principal amount being returned
    /// @param interest Interest amount being paid
    function returnFunds(uint256 principal, uint256 interest) external;

    /// @notice Authorize a borrow vault to request funds
    /// @param borrowVault The borrow vault address
    function authorizeBorrowVault(address borrowVault) external;

    /// @notice Convert assets to shares
    /// @param assets Amount of assets
    /// @return The number of shares
    function convertToShares(uint256 assets) external view returns (uint256);

    /// @notice Convert shares to assets
    /// @param shares Number of shares
    /// @return The amount of assets
    function convertToAssets(uint256 shares) external view returns (uint256);

    /// @notice Preview deposit amount
    /// @param assets Amount of assets
    /// @return The number of shares that would be minted
    function previewDeposit(uint256 assets) external view returns (uint256);

    /// @notice Deposit assets into the vault
    /// @param assets Amount of assets
    /// @param receiver The receiver of the shares
    /// @return shares The number of shares minted
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @notice Withdraw assets from the vault
    /// @param assets Amount of assets
    /// @param receiver The receiver of the assets
    /// @param owner The owner of the shares
    /// @return asset The amount of assets withdrawn
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 asset);
}
