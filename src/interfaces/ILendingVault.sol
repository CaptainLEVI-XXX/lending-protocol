// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ===== ILendingVault.sol =====
interface ILendingVault {
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function availableLiquidity() external view returns (uint256);
    function allocateFunds(uint256 amount) external returns (bool);
    function returnFunds(uint256 principal, uint256 interest) external;
    function authorizeBorrowVault(address borrowVault) external;
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 asset);
}
