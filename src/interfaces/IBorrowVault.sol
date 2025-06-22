// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBorrowVault {
    function asset() external view returns (address);
    function lendingVault() external view returns (address);
    function getDebtAmount(address user) external view returns (uint256);
    function totalDebt() external view returns (uint256);
    function getVaultStats()
        external
        view
        returns (
            uint256 totalBorrowed,
            uint256 totalDebtAmount,
            uint256 utilizationRate,
            uint256 borrowRate,
            uint256 debtTokenSupply
        );
    function getUserBorrowInfo(address user)
        external
        view
        returns (uint256 principal, uint256 currentDebt, uint256 debtTokens, uint256 borrowRate);
    function requestBorrow(uint256 amount, address caller) external returns (uint256 requestId);
    function repay(uint256 amount, address caller) external;
}
