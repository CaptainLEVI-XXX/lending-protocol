// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.19;

// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "./interfaces/IAccessRegistry.sol";
// import "./interfaces/ILendingVault.sol";
// import {CustomRevert} from "./libraries/CustomRevert.sol";
// import {Roles} from "./helper/Roles.sol";

// /**
//  * @title BorrowVault
//  * @dev Debt token (dToken) implementation for borrowing
//  * @notice Mints debt tokens to represent borrowed amounts with accruing interest
//  */
// contract BorrowVault is ERC20, ReentrancyGuard {
//     using SafeERC20 for IERC20;
//     using CustomRevert for bytes4;

//     // Constants
//     uint256 public constant SECONDS_PER_YEAR = 365 days;
//     uint256 public constant BASIS_POINTS = 10000;
//     uint256 public constant RAY = 1e27; // Ray precision for interest calculations

//     // Immutables
//     IAccessRegistry public immutable accessRegistry;
//     ILendingVault public immutable lendingVault;
//     IERC20 public immutable asset;

//     // Interest rate model parameters
//     uint256 public baseRate = 200; // 2% base rate
//     uint256 public rateSlope = 800; // 8% slope
//     uint256 public optimalUtilization = 8000; // 80% optimal utilization

//     // Borrowing parameters
//     uint256 public maxBorrowAmount = 1000000e6; // 1M USDC default
//     uint256 public minBorrowAmount = 1000e6; // 1K USDC default

//     // Interest accrual state
//     uint256 public lastUpdateTimestamp;
//     uint256 public borrowIndex; // Cumulative interest index (in RAY)

//     // Borrowing requests
//     struct BorrowRequest {
//         address borrower;
//         uint256 amount;
//         uint256 approvals;
//         mapping(address => bool) hasApproved;
//         bool executed;
//     }

//     mapping(uint256 => BorrowRequest) public borrowRequests;
//     uint256 public nextRequestId;
//     uint256 public requiredApprovals = 2;

//     // User debt tracking (principal only, interest calculated via index)
//     mapping(address => uint256) public userBorrowIndex; // Index at which user borrowed
//     mapping(address => uint256) public principalBorrowAmount; // Principal borrowed

//     // Global state
//     uint256 public totalBorrowedPrincipal;

//     //error
//     error InvalidAmount();
//     error DebtTokenAreNotTransferable();
//     error DebtTokenAreNotApprovable();
//     error AlreadyExecuted();
//     error AlreadyApproved();
//     error InsufficientApprovals();
//     error InsufficientFunds();
//     error NoDebt();
//     error HasOutstandingDebt();
//     error NotAdmin();
//     error NotMultisig();
//     error NotWhitelisted();
//     error InvalidAddress();

//     // Events
//     event BorrowRequested(uint256 indexed requestId, address indexed borrower, uint256 amount);
//     event BorrowApproved(uint256 indexed requestId, address indexed approver);
//     event Borrowed(address indexed borrower, uint256 amount, uint256 debtMinted);
//     event Repaid(address indexed borrower, uint256 amount, uint256 debtBurned);
//     event InterestAccrued(uint256 newIndex, uint256 totalDebt);
//     event ParameterUpdated(string parameter, uint256 value);

//     modifier onlyAdmin() {
//         if (!accessRegistry.hasRole(ADMIN_ROLE, msg.sender)) NotAdmin.selector.revertWith();
//         _;
//     }

//     modifier onlyMultisig() {
//         if (!accessRegistry.hasRole(MULTISIG_SIGNER_ROLE, msg.sender)) NotMultisig.selector.revertWith();
//         _;
//     }

//     modifier onlyWhitelistedBorrower() {
//         if (!accessRegistry.hasRole(WHITELISTED_BORROWER_ROLE, msg.sender)) NotWhitelisted.selector.revertWith();
//         _;
//     }

//     modifier onlyProtocolLevel() {
//         if (!accessRegistry.hasRole(PROTOCOL_LEVEL_ROLE, msg.sender)) NotAuthorized.selector.revertWith();
//         _;
//     }

//     /**
//      * @dev Constructor
//      * @param _name Debt token name
//      * @param _symbol Debt token symbol
//      * @param _accessRegistry Access control registry
//      * @param _lendingVault Associated lending vault
//      * @param _asset Underlying asset
//      */
//     constructor(
//         string memory _name,
//         string memory _symbol,
//         address _accessRegistry,
//         address _lendingVault,
//         address _asset
//     ) ERC20(_name, _symbol) {
//         if (_accessRegistry == address(0)) InvalidAddress.selector.revertWith();
//         if (_lendingVault == address(0)) InvalidAddress.selector.revertWith();
//         if (_asset == address(0)) InvalidAddress.selector.revertWith();

//         accessRegistry = IAccessRegistry(_accessRegistry);
//         lendingVault = ILendingVault(_lendingVault);
//         asset = IERC20(_asset);

//         lastUpdateTimestamp = block.timestamp;
//         borrowIndex = RAY; // Start at 1.0
//     }

//     // === CONFIGURATION ===

//     function updateParameter(string calldata parameter, uint256 value) external onlyAdmin {
//         if (keccak256(bytes(parameter)) == keccak256("requiredApprovals")) {
//             if (value == 0) InvalidAmount.selector.revertWith();
//             requiredApprovals = value;
//         } else if (keccak256(bytes(parameter)) == keccak256("baseRate")) {
//             if (value >= BASIS_POINTS) InvalidAmount.selector.revertWith();
//             baseRate = value;
//         } else if (keccak256(bytes(parameter)) == keccak256("rateSlope")) {
//             if (value >= BASIS_POINTS) InvalidAmount.selector.revertWith();
//             rateSlope = value;
//         } else if (keccak256(bytes(parameter)) == keccak256("optimalUtilization")) {
//             if (value >= BASIS_POINTS) InvalidAmount.selector.revertWith();
//             optimalUtilization = value;
//         } else {
//             revert("Unknown parameter");
//         }

//         emit ParameterUpdated(parameter, value);
//     }

//     // === INTEREST ACCRUAL ===

//     /**
//      * @dev Accrue interest and update borrow index
//      */
//     function accrueInterest() public {
//         uint256 currentTimestamp = block.timestamp;
//         if (currentTimestamp == lastUpdateTimestamp) return;

//         uint256 totalDebt = totalDebt();
//         if (totalDebt == 0) {
//             lastUpdateTimestamp = currentTimestamp;
//             return;
//         }

//         uint256 borrowRate = calculateBorrowRate();
//         uint256 timeElapsed = currentTimestamp - lastUpdateTimestamp;

//         // Calculate interest multiplier: (1 + rate * time)
//         uint256 interestMultiplier = RAY + (borrowRate * timeElapsed / SECONDS_PER_YEAR);

//         // Update borrow index
//         borrowIndex = borrowIndex * interestMultiplier / RAY;
//         lastUpdateTimestamp = currentTimestamp;

//         emit InterestAccrued(borrowIndex, totalDebt);
//     }

//     /**
//      * @dev Calculate current borrow rate based on utilization
//      * @return Annual borrow rate in RAY
//      */
//     function calculateBorrowRate() public view returns (uint256) {
//         uint256 utilization = getUtilizationRate();

//         if (utilization <= optimalUtilization) {
//             // Below optimal: rate = base + (utilization / optimal) * slope
//             return baseRate * RAY / BASIS_POINTS + (utilization * rateSlope * RAY) / (optimalUtilization * BASIS_POINTS);
//         } else {
//             // Above optimal: steeper slope
//             uint256 excessUtilization = utilization - optimalUtilization;
//             uint256 excessRate =
//                 (excessUtilization * rateSlope * 2 * RAY) / ((BASIS_POINTS - optimalUtilization) * BASIS_POINTS);

//             return baseRate * RAY / BASIS_POINTS + rateSlope * RAY / BASIS_POINTS + excessRate;
//         }
//     }

//     /**
//      * @dev Get current utilization rate
//      * @return Utilization in basis points
//      */
//     function getUtilizationRate() public view returns (uint256) {
//         uint256 totalLiquidity = lendingVault.totalAssets();
//         if (totalLiquidity == 0) return 0;

//         uint256 borrowed = totalDebt();
//         return borrowed * BASIS_POINTS / totalLiquidity;
//     }

//     // === BORROWING ===

//     /**
//      * @dev Request to borrow funds
//      * @param amount Amount to borrow
//      * @return requestId Request ID
//      */
//     function requestBorrow(uint256 amount, address caller)
//         external
//         onlyProtocolLevel
//         returns (uint256 requestId)
//     {
//         if (balanceOf(caller) != 0) HasOutstandingDebt.selector.revertWith();

//         requestId = nextRequestId++;

//         BorrowRequest storage request = borrowRequests[requestId];
//         request.borrower = caller;
//         request.amount = amount;

//         emit BorrowRequested(requestId, caller, amount);
//     }

//     /**
//      * @dev Approve a borrow request
//      * @param requestId Request to approve
//      */
//     function approveBorrow(uint256 requestId) external onlyMultisig {
//         BorrowRequest storage request = borrowRequests[requestId];
//         if (request.borrower == address(0)) InvalidRequest.selector.revertWith();
//         if (request.executed) AlreadyExecuted.selector.revertWith();
//         if (request.hasApproved[msg.sender]) AlreadyApproved.selector.revertWith();

//         request.hasApproved[msg.sender] = true;
//         request.approvals++;

//         emit BorrowApproved(requestId, msg.sender);
//     }

//     /**
//      * @dev Execute approved borrow request
//      * @param requestId Request to execute
//      */
//     function executeBorrow(uint256 requestId) external nonReentrant {
//         BorrowRequest storage request = borrowRequests[requestId];
//         if (request.executed) AlreadyExecuted.selector.revertWith();
//         if (request.approvals < requiredApprovals) InsufficientApprovals.selector.revertWith();

//         request.executed = true;

//         // Accrue interest before borrowing
//         accrueInterest();

//         // Request funds from lending vault
//         bool success = lendingVault.allocateFunds(request.amount);
//         if (!success) InsufficientFunds.selector.revertWith();

//         // Record borrowing
//         userBorrowIndex[request.borrower] = borrowIndex;
//         principalBorrowAmount[request.borrower] = request.amount;
//         totalBorrowedPrincipal += request.amount;

//         // Mint debt tokens (1:1 with borrowed amount at inception)
//         _mint(request.borrower, request.amount);

//         // Transfer funds to borrower
//         asset.safeTransfer(request.borrower, request.amount);

//         emit Borrowed(request.borrower, request.amount, request.amount);
//     }

//     // === REPAYMENT ===

//     /**
//      * @dev Repay borrowed amount
//      * @param amount Amount to repay (in underlying asset)
//      */
//     function repay(uint256 amount, address caller) external onlyProtocolLevel {
//         if (balanceOf(caller) == 0) NoDebt.selector.revertWith();

//         // Accrue interest before repayment
//         accrueInterest();

//         // Calculate current debt
//         uint256 currentDebt = getDebtAmount(caller);
//         uint256 repayAmount = amount > currentDebt ? currentDebt : amount;

//         // Transfer payment from user
//         asset.safeTransferFrom(msg.sender, address(this), repayAmount);

//         // Calculate how much debt tokens to burn
//         uint256 debtTokensToBurn = _calculateDebtTokensToBurn(caller, repayAmount);

//         // Update principal tracking
//         if (repayAmount >= currentDebt) {
//             // Full repayment
//             totalBorrowedPrincipal -= principalBorrowAmount[caller];
//             principalBorrowAmount[caller] = 0;
//             userBorrowIndex[caller] = 0;
//         } else {
//             // Partial repayment - reduce principal proportionally
//             uint256 principalRepaid = principalBorrowAmount[caller] * repayAmount / currentDebt;
//             principalBorrowAmount[caller] -= principalRepaid;
//             totalBorrowedPrincipal -= principalRepaid;
//         }

//         // Burn debt tokens
//         _burn(caller, debtTokensToBurn);

//         // Calculate interest portion
//         uint256 interestPortion =
//             repayAmount > principalBorrowAmount[caller] ? repayAmount - principalBorrowAmount[caller] : 0;
//         uint256 principalPortion = repayAmount - interestPortion;

//         // Return funds to lending vault
//         asset.approve(address(lendingVault), repayAmount);
//         lendingVault.returnFunds(principalPortion, interestPortion);

//         emit Repaid(caller, repayAmount, debtTokensToBurn);
//     }

//     /**
//      * @dev Calculate debt tokens to burn for a repayment
//      */
//     function _calculateDebtTokensToBurn(address user, uint256 repayAmount) internal view returns (uint256) {
//         uint256 currentDebt = getDebtAmount(user);
//         uint256 debtTokens = balanceOf(user);

//         if (repayAmount >= currentDebt) {
//             return debtTokens;
//         }

//         // Proportional burn
//         return debtTokens * repayAmount / currentDebt;
//     }

//     // === VIEW FUNCTIONS ===

//     /**
//      * @dev Get current debt amount for a user
//      * @param user User address
//      * @return Current debt including interest
//      */
//     function getDebtAmount(address user) public view returns (uint256) {
//         if (principalBorrowAmount[user] == 0) return 0;

//         // Apply interest from user's borrow index to current index
//         uint256 currentIndex = _getCurrentBorrowIndex();
//         return principalBorrowAmount[user] * currentIndex / userBorrowIndex[user];
//     }

//     /**
//      * @dev Get current borrow index with pending interest
//      */
//     function _getCurrentBorrowIndex() internal view returns (uint256) {
//         uint256 currentTimestamp = block.timestamp;
//         if (currentTimestamp == lastUpdateTimestamp || totalDebt() == 0) {
//             return borrowIndex;
//         }

//         uint256 borrowRate = calculateBorrowRate();
//         uint256 timeElapsed = currentTimestamp - lastUpdateTimestamp;
//         uint256 interestMultiplier = RAY + (borrowRate * timeElapsed / SECONDS_PER_YEAR);

//         return borrowIndex * interestMultiplier / RAY;
//     }

//     /**
//      * @dev Get total debt across all users
//      */
//     function totalDebt() public view returns (uint256) {
//         if (totalBorrowedPrincipal == 0) return 0;

//         uint256 currentIndex = _getCurrentBorrowIndex();
//         return totalBorrowedPrincipal * currentIndex / RAY;
//     }

//     /**
//      * @dev Get vault statistics
//      */
//     function getVaultStats()
//         external
//         view
//         returns (
//             uint256 totalBorrowed,
//             uint256 totalDebtAmount,
//             uint256 utilizationRate,
//             uint256 borrowRate,
//             uint256 debtTokenSupply
//         )
//     {
//         totalBorrowed = totalBorrowedPrincipal;
//         totalDebtAmount = totalDebt();
//         utilizationRate = getUtilizationRate();
//         borrowRate = calculateBorrowRate() * BASIS_POINTS / RAY; // Convert to basis points
//         debtTokenSupply = totalSupply();
//     }

//     /**
//      * @dev Override transfer to prevent debt token transfers
//      */
//     function transfer(address, uint256) public pure override returns (bool) {
//         DebtTokenAreNotTransferable.selector.revertWith();
//     }

//     /**
//      * @dev Override transferFrom to prevent debt token transfers
//      */
//     function transferFrom(address, address, uint256) public pure override returns (bool) {
//         DebtTokenAreNotTransferable.selector.revertWith();
//     }

//     function approve(address, uint256) public pure override returns (bool) {
//         DebtTokenAreNotApprovable.selector.revertWith();
//     }

//     /**
//      * @dev Get user's borrow information
//      */
//     function getUserBorrowInfo(address user)
//         external
//         view
//         returns (uint256 principal, uint256 currentDebt, uint256 debtTokens, uint256 borrowRate)
//     {
//         principal = principalBorrowAmount[user];
//         currentDebt = getDebtAmount(user);
//         debtTokens = balanceOf(user);
//         borrowRate = calculateBorrowRate() * BASIS_POINTS / RAY;
//     }
// }
