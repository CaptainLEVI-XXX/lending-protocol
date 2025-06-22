// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title IBorrowVault
/// @notice Interface for the BorrowVault contract
/// @dev Manages borrowing functionality with amortized loans
interface IBorrowVault {
    /// @notice Get the underlying asset address
    /// @return The asset address
    function asset() external view returns (address);

    /// @notice Get the associated lending vault address
    /// @return The lending vault address
    function lendingVault() external view returns (address);

    /// @notice Get the debt amount for a specific user
    /// @param user The user address
    /// @return The debt amount
    function getDebtAmount(address user) external view returns (uint256);

    /// @notice Get the total debt amount across all users
    /// @return The total debt amount
    function totalDebt() external view returns (uint256);

    /// @notice Get vault statistics
    /// @return totalBorrowed Total amount borrowed
    /// @return totalDebtAmount Total debt amount
    /// @return utilizationRate Current utilization rate
    /// @return borrowRate Current borrow rate
    /// @return debtTokenSupply Total debt token supply
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

    /// @notice Get user-specific borrow information
    /// @param user The user address
    /// @return principal Original principal amount
    /// @return currentDebt Current debt amount
    /// @return debtTokens Number of debt tokens
    /// @return borrowRate Current borrow rate
    function getUserBorrowInfo(address user)
        external
        view
        returns (uint256 principal, uint256 currentDebt, uint256 debtTokens, uint256 borrowRate);

    /// @notice Request a new borrow
    /// @param amount Amount to borrow
    /// @param duration Duration in months
    /// @param caller The calling address
    /// @return requestId The request ID
    function requestBorrow(uint256 amount, uint256 duration, address caller) external returns (uint256 requestId);

    /// @notice Repay a loan
    /// @param amount Amount to repay
    /// @param caller The calling address
    function repay(uint256 amount, address caller) external;

    /// @notice Get loan details for a borrower
    /// @param borrower The borrower address
    /// @return principal Original principal amount
    /// @return remainingPrincipal Remaining principal
    /// @return apr Annual percentage rate
    /// @return monthlyPayment Monthly payment amount
    /// @return nextPaymentDue Timestamp of next payment due
    /// @return paymentsRemaining Number of payments remaining
    /// @return active Whether the loan is active
    function getLoanDetails(address borrower)
        external
        view
        returns (
            uint256 principal,
            uint256 remainingPrincipal,
            uint256 apr,
            uint256 monthlyPayment,
            uint256 nextPaymentDue,
            uint256 paymentsRemaining,
            bool active
        );

    /// @notice Make a loan payment
    /// @param borrower The borrower address
    function makePayment(address borrower) external;

    /// @notice Pay off an entire loan
    /// @param borrower The borrower address
    function payoffLoan(address borrower) external;

    /// @notice Get the amount needed to pay off a loan
    /// @param borrower The borrower address
    /// @return The payoff amount
    function getPayoffAmount(address borrower) external view returns (uint256);
}
