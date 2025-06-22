// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccessRegistry} from "./interfaces/IAccessRegistry.sol";
import {ILendingVault} from "./interfaces/ILendingVault.sol";
import {CustomRevert} from "./libraries/CustomRevert.sol";
import {Roles} from "./helper/Roles.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title BorrowVault
 * @dev Debt token (dToken) implementation for amortized borrowing
 * @notice Manages loans with fixed payment schedules and amortization
 */
contract BorrowVault is ERC20, Roles, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using CustomRevert for bytes4;

    // Constants
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant SECONDS_PER_MONTH = 30 days;
    uint256 public constant GRACE_PERIOD = 5 days;

    // Immutables
    ILendingVault public immutable lendingVault;
    IERC20 public immutable asset;

    // Loan parameters
    uint256 public baseAPR = 800; // 8% base APR in basis points
    uint256 public maxLoanDuration = 36; // 36 months max
    uint256 public minLoanDuration = 6; // 6 months min
    uint256 public maxBorrowAmount = 1000000e6; // 1M USDC default
    uint256 public minBorrowAmount = 10000e6; // 10K USDC default

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

    // State variables
    mapping(address => Loan) public loans;
    mapping(address => PaymentRecord[]) public paymentHistory;
    mapping(uint256 => BorrowRequest) public borrowRequests;

    uint256 public nextRequestId;
    uint256 public requiredApprovals = 2;
    uint256 public totalOutstandingPrincipal;
    uint256 public totalInterestCollected;

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
    error NotAdmin();
    error NotMultisig();
    error NotWhitelisted();
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

    /**
     * @dev Constructor
     * @param _name Debt token name
     * @param _symbol Debt token symbol
     * @param _accessRegistry Access control registry
     * @param _lendingVault Associated lending vault
     * @param _asset Underlying asset
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _accessRegistry,
        address _lendingVault,
        address _asset
    ) ERC20(_name, _symbol) Roles(_accessRegistry) {
        if (_accessRegistry == address(0)) InvalidAddress.selector.revertWith();
        if (_lendingVault == address(0)) InvalidAddress.selector.revertWith();
        if (_asset == address(0)) InvalidAddress.selector.revertWith();
        lendingVault = ILendingVault(_lendingVault);
        asset = IERC20(_asset);
    }

    // === CONFIGURATION ===

    function updateParameter(string calldata parameter, uint256 value) external onlyAdmin {
        if (keccak256(bytes(parameter)) == keccak256("requiredApprovals")) {
            if (value == 0) InvalidAmount.selector.revertWith();
            requiredApprovals = value;
        } else if (keccak256(bytes(parameter)) == keccak256("baseAPR")) {
            if (value >= BASIS_POINTS) InvalidAmount.selector.revertWith();
            baseAPR = value;
        } else if (keccak256(bytes(parameter)) == keccak256("maxLoanDuration")) {
            if (value == 0 || value > 60) InvalidDuration.selector.revertWith();
            maxLoanDuration = value;
        } else if (keccak256(bytes(parameter)) == keccak256("minLoanDuration")) {
            if (value == 0 || value > maxLoanDuration) InvalidDuration.selector.revertWith();
            minLoanDuration = value;
        } else {
            revert("Unknown parameter");
        }

        emit ParameterUpdated(parameter, value);
    }

    // === BORROWING ===

    /**
     * @dev Request to borrow funds with specified duration
     * @param amount Amount to borrow
     * @param duration Loan duration in months
     * @return requestId Request ID
     */
    function requestBorrow(uint256 amount, uint256 duration, address caller)
        external
        onlyProtocolLevel
        returns (uint256 requestId)
    {
        // if (duration < minLoanDuration || duration > maxLoanDuration) InvalidDuration.selector.revertWith();
        if (loans[caller].active) HasOutstandingLoan.selector.revertWith();

        requestId = nextRequestId++;

        BorrowRequest storage request = borrowRequests[requestId];
        request.borrower = caller;
        request.amount = amount;
        request.duration = duration;

        emit BorrowRequested(requestId, caller, amount, duration);
    }

    /**
     * @dev Approve a borrow request
     * @param requestId Request to approve
     */
    function approveBorrow(uint256 requestId) external onlyMultisigSigner {
        BorrowRequest storage request = borrowRequests[requestId];
        if (request.borrower == address(0)) InvalidRequest.selector.revertWith();
        if (request.executed) AlreadyExecuted.selector.revertWith();
        if (request.hasApproved[msg.sender]) AlreadyApproved.selector.revertWith();

        request.hasApproved[msg.sender] = true;
        request.approvals++;

        emit BorrowApproved(requestId, msg.sender);
    }

    /**
     * @dev Execute approved borrow request and create amortized loan
     * @param requestId Request to execute
     */
    function executeBorrow(uint256 requestId) external {
        BorrowRequest storage request = borrowRequests[requestId];
        if (request.executed) AlreadyExecuted.selector.revertWith();
        if (request.approvals < requiredApprovals) InsufficientApprovals.selector.revertWith();

        request.executed = true;

        // Request funds from lending vault
        bool success = lendingVault.allocateFunds(request.amount);
        if (!success) InsufficientFunds.selector.revertWith();

        // Calculate loan parameters
        uint256 monthlyRate = baseAPR * 1e18 / BASIS_POINTS / 12;
        uint256 monthlyPayment = calculateMonthlyPayment(request.amount, monthlyRate, request.duration);

        // Create loan
        Loan storage loan = loans[request.borrower];
        loan.principal = request.amount;
        loan.remainingPrincipal = request.amount;
        loan.apr = baseAPR;
        loan.monthlyPayment = monthlyPayment;
        loan.loanDuration = request.duration;
        loan.startTime = block.timestamp;
        loan.nextPaymentDue = block.timestamp + SECONDS_PER_MONTH;
        loan.paymentsRemaining = request.duration;
        loan.active = true;

        // Update global tracking
        totalOutstandingPrincipal += request.amount;

        // Mint debt tokens (1:1 with borrowed amount)
        _mint(request.borrower, request.amount);

        // Transfer funds to borrower
        asset.safeTransfer(request.borrower, request.amount);

        emit LoanDisbursed(request.borrower, request.amount, baseAPR, monthlyPayment, request.duration);
    }

    // === REPAYMENT ===

    /**
     * @dev Make a monthly payment
     */
    function makePayment(address caller) external onlyProtocolLevel {
        Loan storage loan = loans[caller];
        if (!loan.active) NoActiveLoan.selector.revertWith();

        // Check if payment is due (with grace period)
        if (block.timestamp < loan.nextPaymentDue - SECONDS_PER_MONTH + 1 days) {
            PaymentTooEarly.selector.revertWith();
        }

        uint256 paymentAmount = loan.monthlyPayment;

        // For the last payment, adjust to pay exact remaining amount
        if (loan.paymentsRemaining == 1) {
            paymentAmount = calculateFinalPayment(caller);
        }

        // Transfer payment from borrower
        asset.safeTransferFrom(msg.sender, address(this), paymentAmount);

        // Calculate interest and principal portions
        uint256 interestPayment = calculateInterestPayment(loan.remainingPrincipal, loan.apr);
        uint256 principalPayment = paymentAmount - interestPayment;

        // Update loan state
        loan.remainingPrincipal -= principalPayment;
        loan.paymentsRemaining -= 1;
        loan.nextPaymentDue += SECONDS_PER_MONTH;

        // Record payment
        paymentHistory[caller].push(
            PaymentRecord({
                timestamp: block.timestamp,
                principalPaid: principalPayment,
                interestPaid: interestPayment,
                totalPaid: paymentAmount
            })
        );

        // Update global tracking
        totalOutstandingPrincipal -= principalPayment;
        totalInterestCollected += interestPayment;

        // Burn debt tokens proportionally
        uint256 tokensToBurn = balanceOf(caller) * principalPayment / (loan.remainingPrincipal + principalPayment);
        _burn(caller, tokensToBurn);

        // Return funds to lending vault
        asset.approve(address(lendingVault), paymentAmount);
        lendingVault.returnFunds(principalPayment, interestPayment);

        emit PaymentMade(caller, principalPayment, interestPayment, loan.paymentsRemaining);

        // Check if loan is paid off
        if (loan.paymentsRemaining == 0) {
            loan.active = false;
            loan.remainingPrincipal = 0;
            _burn(caller, balanceOf(caller)); // Burn any remaining dust
            emit LoanPaidOff(caller);
        }
    }

    /**
     * @dev Pay off entire loan early
     */
    function payoffLoan(address borrower) external onlyProtocolLevel {
        Loan storage loan = loans[borrower];
        if (!loan.active) NoActiveLoan.selector.revertWith();

        // Calculate total payoff amount (remaining principal + accrued interest)
        uint256 accruedInterest = calculateAccruedInterest(borrower);
        uint256 payoffAmount = loan.remainingPrincipal + accruedInterest;

        // Transfer payment
        asset.safeTransferFrom(msg.sender, address(this), payoffAmount);

        // Record payment
        paymentHistory[borrower].push(
            PaymentRecord({
                timestamp: block.timestamp,
                principalPaid: loan.remainingPrincipal,
                interestPaid: accruedInterest,
                totalPaid: payoffAmount
            })
        );

        // Update global tracking
        totalOutstandingPrincipal -= loan.remainingPrincipal;
        totalInterestCollected += accruedInterest;

        // Return funds to lending vault
        asset.approve(address(lendingVault), payoffAmount);
        lendingVault.returnFunds(loan.remainingPrincipal, accruedInterest);

        // Clear loan
        loan.remainingPrincipal = 0;
        loan.paymentsRemaining = 0;
        loan.active = false;

        // Burn all debt tokens
        _burn(borrower, balanceOf(borrower));

        emit LoanPaidOff(borrower);
    }

    // === CALCULATION FUNCTIONS ===

    /**
     * @dev Calculate fixed monthly payment using amortization formula
     * @param principal Loan principal amount
     * @param monthlyRate Monthly interest rate (scaled by 1e18)
     * @param months Number of months
     * @return Monthly payment amount
     */
    function calculateMonthlyPayment(uint256 principal, uint256 monthlyRate, uint256 months)
        public
        pure
        returns (uint256)
    {
        // PMT = P * [r(1+r)^n] / [(1+r)^n - 1]
        // Where P = principal, r = monthly rate, n = number of payments

        if (monthlyRate == 0) {
            return principal / months;
        }

        // Calculate (1 + r)^n
        uint256 onePlusR = 1e18 + monthlyRate;
        uint256 compoundFactor = 1e18;

        for (uint256 i = 0; i < months; i++) {
            compoundFactor = compoundFactor * onePlusR / 1e18;
        }

        // Calculate payment
        uint256 numerator = principal * monthlyRate * compoundFactor / 1e18;
        uint256 denominator = compoundFactor - 1e18;

        return numerator / denominator;
    }

    /**
     * @dev Calculate interest portion of a payment
     * @param remainingPrincipal Outstanding principal
     * @param apr Annual percentage rate in basis points
     * @return Interest payment amount
     */
    function calculateInterestPayment(uint256 remainingPrincipal, uint256 apr) public pure returns (uint256) {
        // Monthly interest = (Remaining Principal * APR) / 12
        return remainingPrincipal * apr / BASIS_POINTS / 12;
    }

    /**
     * @dev Calculate final payment amount
     * @param borrower Borrower address
     * @return Final payment amount
     */
    function calculateFinalPayment(address borrower) public view returns (uint256) {
        Loan memory loan = loans[borrower];
        uint256 interestPayment = calculateInterestPayment(loan.remainingPrincipal, loan.apr);
        return loan.remainingPrincipal + interestPayment;
    }

    /**
     * @dev Calculate accrued interest for early payoff
     * @param borrower Borrower address
     * @return Accrued interest amount
     */
    function calculateAccruedInterest(address borrower) public view returns (uint256) {
        Loan memory loan = loans[borrower];

        // Calculate days since last payment
        uint256 daysSinceLastPayment;
        if (loan.paymentsRemaining == loan.loanDuration) {
            // No payments made yet
            daysSinceLastPayment = (block.timestamp - loan.startTime) / 1 days;
        } else {
            uint256 lastPaymentTime = loan.nextPaymentDue - SECONDS_PER_MONTH;
            daysSinceLastPayment = (block.timestamp - lastPaymentTime) / 1 days;
        }

        // Daily interest rate
        uint256 dailyRate = loan.apr * 1e18 / BASIS_POINTS / 365;

        // Accrued interest
        return loan.remainingPrincipal * dailyRate * daysSinceLastPayment / 1e18;
    }

    // === VIEW FUNCTIONS ===

    /**
     * @dev Get loan details for a borrower
     */
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
        )
    {
        Loan memory loan = loans[borrower];
        return (
            loan.principal,
            loan.remainingPrincipal,
            loan.apr,
            loan.monthlyPayment,
            loan.nextPaymentDue,
            loan.paymentsRemaining,
            loan.active
        );
    }

    /**
     * @dev Get payment history for a borrower
     */
    function getPaymentHistory(address borrower) external view returns (PaymentRecord[] memory) {
        return paymentHistory[borrower];
    }

    /**
     * @dev Get next payment details
     */
    function getNextPaymentDetails(address borrower)
        external
        view
        returns (uint256 paymentAmount, uint256 principalPortion, uint256 interestPortion, uint256 dueDate)
    {
        Loan memory loan = loans[borrower];
        if (!loan.active) return (0, 0, 0, 0);

        if (loan.paymentsRemaining == 1) {
            paymentAmount = calculateFinalPayment(borrower);
        } else {
            paymentAmount = loan.monthlyPayment;
        }

        interestPortion = calculateInterestPayment(loan.remainingPrincipal, loan.apr);
        principalPortion = paymentAmount - interestPortion;
        dueDate = loan.nextPaymentDue;
    }

    /**
     * @dev Get payoff amount for early repayment
     */
    function getPayoffAmount(address borrower) external view returns (uint256) {
        Loan memory loan = loans[borrower];
        if (!loan.active) return 0;

        uint256 accruedInterest = calculateAccruedInterest(borrower);
        return loan.remainingPrincipal + accruedInterest;
    }

    /**
     * @dev Get vault statistics
     */
    function getVaultStats()
        external
        view
        returns (
            uint256 totalPrincipalOutstanding,
            uint256 totalInterestEarned,
            uint256 averageAPR,
            uint256 activeLoans
        )
    {
        totalPrincipalOutstanding = totalOutstandingPrincipal;
        totalInterestEarned = totalInterestCollected;
        averageAPR = baseAPR; // Could be made dynamic based on risk

        // Count active loans (simplified - in production, maintain a counter)
        // This is a placeholder - you'd want to track this more efficiently
        activeLoans = totalSupply() > 0 ? 1 : 0; // Simplified
    }

    /**
     * @dev Override transfer to prevent debt token transfers
     */
    function transfer(address, uint256) public pure override returns (bool) {
        DebtTokenAreNotTransferable.selector.revertWith();
    }

    /**
     * @dev Override transferFrom to prevent debt token transfers
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        DebtTokenAreNotTransferable.selector.revertWith();
    }

    /**
     * @dev Override approve to prevent debt token approvals
     */
    function approve(address, uint256) public pure override returns (bool) {
        DebtTokenAreNotApprovable.selector.revertWith();
    }

    function _authorizeUpgrade(address) internal override onlyAdmin {}
}
