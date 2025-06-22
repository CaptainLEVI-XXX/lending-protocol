// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ILendingVault} from "@qiro/interfaces/ILendingVault.sol";


abstract contract BorrowVaultStorage {

    struct AssetInfo{
        string name;
        string symbol;
        address asset;
        ILendingVault lendingVault;
    }

       // Loan structure for amortized loans
    struct Loan {
        uint256 principal; // Original loan amount
        uint256 remainingPrincipal; // Outstanding principal
        uint256 apr; // Annual percentage rate in basis points
        uint256 monthlyPayment; // Fixed monthly payment amount
        uint256 loanDuration; // Loan duration in months
        uint256 startTime; // Loan start timestamp
        uint256 nextPaymentDue; // Next payment due date
        uint256 paymentsRemaining; // Number of payments remaining
        bool active; // Loan status
    }

    // Payment tracking
    struct PaymentRecord {
        uint256 timestamp;
        uint256 principalPaid;
        uint256 interestPaid;
        uint256 totalPaid;
    }

    // Borrowing requests
    struct BorrowRequest {
        address borrower;
        uint256 amount;
        uint256 duration; // in months
        uint256 approvals;
        mapping(address => bool) hasApproved;
        bool executed;
    }

    struct BorrowRequestInfo{
        mapping(uint256 => BorrowRequest) borrowRequests;
    }

    struct LoanInfo{
        mapping(address => Loan) loans;
        uint256 nextRequestId;
        uint256 totalOutstandingPrincipal;
        uint256 totalInterestCollected;
    }

    struct PaymentHistoryInfo{
        mapping(address => PaymentRecord[]) paymentHistory;
    }

    // Errors
    error InvalidAmount();
    error DebtTokenAreNotTransferable();
    error DebtTokenAreNotApprovable();
    error AlreadyExecuted();
    error AlreadyApproved();
    error InsufficientApprovals();
    error InsufficientFunds();
    error NoActiveLoan();
    error HasOutstandingLoan();
    error InvalidAddress();
    error InvalidDuration();
    error PaymentTooEarly();
    error PaymentExceedsDebt();
    error InvalidRequest();

    // Events
    event BorrowRequested(uint256 indexed requestId, address indexed borrower, uint256 amount, uint256 duration);
    event BorrowApproved(uint256 indexed requestId, address indexed approver);
    event LoanDisbursed(
        address indexed borrower, uint256 principal, uint256 apr, uint256 monthlyPayment, uint256 duration
    );
    event PaymentMade(address indexed borrower, uint256 principalPaid, uint256 interestPaid, uint256 paymentsRemaining);
    event LoanPaidOff(address indexed borrower);
    event ParameterUpdated(string parameter, uint256 value);


    bytes32 public constant ASSET_INFO_STORAGE = keccak256("qiro.asset.info.storage");
    bytes32 public constant BORROW_REQUEST_INFO_STORAGE = keccak256("qiro.borrow.request.info.storage");
    bytes32 public constant LOAN_INFO_STORAGE = keccak256("qiro.loan.info.storage");
    bytes32 public constant PAYMENT_HISTORY_INFO_STORAGE = keccak256("qiro.payment.history.info.storage");
    bytes32 public constant STATE_VARIABLES_STORAGE = keccak256("qiro.state.variables.storage");



    function assetInfo() internal pure returns (AssetInfo storage _assetInfo) {
        bytes32 position = ASSET_INFO_STORAGE;
        assembly{
            _assetInfo.slot := position
        }
    }

    function borrowRequestInfo() internal pure returns (BorrowRequestInfo storage _borrowRequestInfo) {
        bytes32 position = BORROW_REQUEST_INFO_STORAGE;
        assembly{
            _borrowRequestInfo.slot := position
        }
    }

    function loanInfo() internal pure returns (LoanInfo storage _loanInfo) {
        bytes32 position = LOAN_INFO_STORAGE;
        assembly{
            _loanInfo.slot := position
        }
    }

    function paymentHistoryInfo() internal pure returns (PaymentHistoryInfo storage _paymentHistoryInfo) {
        bytes32 position = PAYMENT_HISTORY_INFO_STORAGE;
        assembly{
            _paymentHistoryInfo.slot := position
        }
    }

    
}