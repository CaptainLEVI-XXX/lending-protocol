// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {AccessRegistry} from "@qiro/AccessRegisty.sol";
import {LendingVault} from "@qiro/LendingVault.sol";
import {BorrowVault} from "@qiro/BorrowVaultII.sol";
import {MockERC20} from "./mock/ERC20.sol";
import {VaultRouter} from "@qiro/Router.sol";
import {BorrowVaultStorage} from "@qiro/storage/BorrowVault.sol";
import {LendingVaultStorage} from "@qiro/storage/LendingVault.sol";
import {ILendingVault} from "@qiro/interfaces/ILendingVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/Proxy/ERC1967/ERC1967Proxy.sol";

contract VaultRouterTest is Test {
    // Contracts
    AccessRegistry public accessRegistry;
    VaultRouter public router;
    LendingVault public lendingVault;
    BorrowVault public borrowVault;
    MockERC20 public usdc;

    // Actors
    address public admin = makeAddr("admin");
    address public feeRecipient = makeAddr("feeRecipient");
    address public signer1 = makeAddr("signer1");
    address public signer2 = makeAddr("signer2");
    address public depositor1 = makeAddr("depositor1");
    address public depositor2 = makeAddr("depositor2");
    address public borrower1 = makeAddr("borrower1");
    address public borrower2 = makeAddr("borrower2");
    address public nonWhitelistedUser = makeAddr("nonWhitelistedUser");

    // Role constants
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MULTISIG_SIGNER_ROLE = keccak256("MULTISIG_SIGNER_ROLE");
    bytes32 public constant WHITELISTED_BORROWER_ROLE = keccak256("WHITELISTED_BORROWER_ROLE");
    bytes32 public constant PROTOCOL_LEVEL_ROLE = keccak256("PROTOCOL_LEVEL_ROLE");

    // Test constants
    uint256 public constant INITIAL_BALANCE = 1_000_000e6; // 1M USDC
    uint256 public constant DEPOSIT_AMOUNT = 50_000e6; // 50k USDC
    uint256 public constant BORROW_AMOUNT = 10_000e6; // 10k USDC
    uint256 public constant LOAN_DURATION = 12; // 12 months

    // Events to test
    event BorrowRequested(uint256 indexed requestId, address indexed borrower, uint256 amount, uint256 duration);
    event BorrowApproved(uint256 indexed requestId, address indexed approver);
    event LoanDisbursed(
        address indexed borrower, uint256 principal, uint256 apr, uint256 monthlyPayment, uint256 duration
    );
    event PaymentMade(address indexed borrower, uint256 principalPaid, uint256 interestPaid, uint256 paymentsRemaining);
    event LoanPaidOff(address indexed borrower);

    function setUp() public {
        // Deploy contracts
        usdc = new MockERC20();

        // Deploy core contracts
        vm.startPrank(admin);
        accessRegistry = new AccessRegistry(admin);
        router = new VaultRouter(address(accessRegistry));
        _setUpLendingVault();
        _setUpBorrowVault();
        vm.stopPrank();

        _setupRoles();
        _setupVaults();
        _fundAccounts();
    }

    function _setUpLendingVault() internal {
        lendingVault = new LendingVault();

        bytes memory data = abi.encodeWithSelector(
            LendingVault.initializeLendingVault.selector,
            LendingVaultStorage.TokenInfo(address(usdc), "Lending USDC", "lUSDC"),
            address(accessRegistry)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(lendingVault), data);

        lendingVault = LendingVault(address(proxy));
    }

    function _setUpBorrowVault() internal {
        borrowVault = new BorrowVault();

        bytes memory data = abi.encodeWithSelector(
            BorrowVault.initializeBorrowVault.selector,
            BorrowVaultStorage.AssetInfo("Debt USDC", "dUSDC", address(usdc), ILendingVault(address(lendingVault))),
            address(accessRegistry)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(borrowVault), data);

        borrowVault = BorrowVault(address(proxy));
    }

    function _setupRoles() internal {
        vm.startPrank(admin);

        // Grant admin roles
        accessRegistry.grantRole(ADMIN_ROLE, admin);

        // Grant multisig signer roles
        accessRegistry.grantRole(MULTISIG_SIGNER_ROLE, signer1);
        accessRegistry.grantRole(MULTISIG_SIGNER_ROLE, signer2);

        // Grant whitelisted borrower roles
        accessRegistry.grantRole(WHITELISTED_BORROWER_ROLE, borrower1);
        accessRegistry.grantRole(WHITELISTED_BORROWER_ROLE, borrower2);

        // Grant protocol level roles
        accessRegistry.grantRole(PROTOCOL_LEVEL_ROLE, address(router));
        accessRegistry.grantRole(PROTOCOL_LEVEL_ROLE, address(lendingVault));
        accessRegistry.grantRole(PROTOCOL_LEVEL_ROLE, address(borrowVault));

        vm.stopPrank();
    }

    function _setupVaults() internal {
        vm.startPrank(admin);

        // Configure lending vault in router
        VaultRouter.LendingVaultInfo memory lendingInfo = VaultRouter.LendingVaultInfo({
            vaultAddress: address(lendingVault),
            minDepositAmount: 100e6, // Min 100 USDC
            maxDepositAmount: 1_000_000e6, // Max 1M USDC
            isPaused: false
        });
        router.setLendingVault(address(usdc), lendingInfo);

        // Configure borrow vault in router
        VaultRouter.BorrowVaultInfo memory borrowInfo = VaultRouter.BorrowVaultInfo({
            vaultAddress: address(borrowVault),
            minLoanAmount: 1_000e6, // Min 1k USDC
            maxLoanAmount: 100_000e6, // Max 100k USDC
            maxLoanDuration: 36, // Max 36 months
            minLoanDuration: 6, // Min 6 months
            isPaused: false
        });
        router.setBorrowVault(address(usdc), borrowInfo);

        vm.stopPrank();
    }

    function _fundAccounts() internal {
        // Fund depositors
        usdc.mint(depositor1, INITIAL_BALANCE);
        usdc.mint(depositor2, INITIAL_BALANCE);

        // Fund borrowers with some USDC for payments
        usdc.mint(borrower1, 50_000e6);
        usdc.mint(borrower2, 50_000e6);
    }

    // ============================================
    // DEPOSIT TESTS
    // ============================================

    function testDepositSuccess() public {
        vm.startPrank(depositor1);

        // Approve router
        usdc.approve(address(router), DEPOSIT_AMOUNT);

        // Get balance before
        uint256 balanceBefore = usdc.balanceOf(depositor1);

        // Deposit
        uint256 shares = router.deposit(address(usdc), DEPOSIT_AMOUNT, depositor1);

        // Verify
        assertEq(shares, DEPOSIT_AMOUNT, "Should receive 1:1 shares initially");
        assertEq(usdc.balanceOf(depositor1), balanceBefore - DEPOSIT_AMOUNT, "USDC should be transferred");
        assertEq(lendingVault.balanceOf(depositor1), shares, "Should receive vault shares");

        vm.stopPrank();
    }

    // ============================================
    // WITHDRAW TESTS
    // ============================================

    function testWithdrawSuccess() public {
        // First deposit
        vm.startPrank(depositor1);
        usdc.approve(address(router), DEPOSIT_AMOUNT);
        uint256 shares = router.deposit(address(usdc), DEPOSIT_AMOUNT, depositor1);

        assertEq(lendingVault.balanceOf(depositor1), shares);

        // Then withdraw half
        uint256 withdrawAmount = DEPOSIT_AMOUNT / 2;
        uint256 balanceBefore = usdc.balanceOf(depositor1);

        uint256 assets = router.withdraw(address(usdc), withdrawAmount, depositor1, depositor1);

        console.log("assets", assets);

        // Verify
        assertEq(assets, withdrawAmount, "Should receive requested assets");
        assertEq(usdc.balanceOf(depositor1), balanceBefore + withdrawAmount, "USDC should be received");
        assertEq(lendingVault.balanceOf(depositor1), DEPOSIT_AMOUNT - withdrawAmount, "Shares should be burned");

        vm.stopPrank();
    }

    // ============================================
    // BORROW REQUEST TESTS
    // ============================================

    function testBorrowRequestSuccess() public {
        // First, fund the lending vault
        vm.startPrank(depositor1);
        usdc.approve(address(router), DEPOSIT_AMOUNT);
        router.deposit(address(usdc), DEPOSIT_AMOUNT, depositor1);
        vm.stopPrank();

        // Request borrow
        vm.startPrank(borrower1);

        vm.expectEmit(false, true, false, true);
        emit BorrowRequested(0, borrower1, BORROW_AMOUNT, LOAN_DURATION);

        uint256 requestId = router.requestBorrow(address(usdc), BORROW_AMOUNT, LOAN_DURATION);
        assertEq(requestId, 0, "First request should have ID 0");

        vm.stopPrank();
    }

    function testBorrowRequestNotWhitelisted() public {
        vm.startPrank(nonWhitelistedUser);

        vm.expectRevert();
        router.requestBorrow(address(usdc), BORROW_AMOUNT, LOAN_DURATION);

        vm.stopPrank();
    }

    // // ============================================
    // // FULL LOAN LIFECYCLE TEST
    // // ============================================

    function testFullLoanLifecycle() public {
        // 1. Deposit funds to lending vault
        vm.startPrank(depositor1);
        usdc.approve(address(router), DEPOSIT_AMOUNT);
        router.deposit(address(usdc), DEPOSIT_AMOUNT, depositor1);
        vm.stopPrank();

        // 2. Request borrow
        vm.startPrank(borrower1);
        uint256 requestId = router.requestBorrow(address(usdc), BORROW_AMOUNT, LOAN_DURATION);
        vm.stopPrank();

        // 3. Approve borrow (multisig)
        vm.prank(signer1);
        borrowVault.approveBorrow(requestId);

        vm.prank(signer2);
        borrowVault.approveBorrow(requestId);

        // 4. Execute borrow
        uint256 borrowerBalanceBefore = usdc.balanceOf(borrower1);

        vm.expectEmit(true, false, false, false);
        emit LoanDisbursed(borrower1, BORROW_AMOUNT, 800, 0, LOAN_DURATION); // 8% APR

        borrowVault.executeBorrow(requestId);

        // Verify loan disbursement
        assertEq(usdc.balanceOf(borrower1), borrowerBalanceBefore + BORROW_AMOUNT, "Borrower should receive funds");
        assertGt(borrowVault.balanceOf(borrower1), 0, "Borrower should have debt tokens");

        // 5. Make first payment
        vm.warp(block.timestamp + 30 days); // Move forward 1 month

        // Get payment details
        (uint256 paymentAmount,,,) = borrowVault.getNextPaymentDetails(borrower1);

        vm.startPrank(borrower1);
        usdc.approve(address(router), paymentAmount);

        vm.expectEmit(true, false, false, false);
        emit PaymentMade(borrower1, 0, 0, 11); // Will have 11 payments remaining

        router.makePayment(address(usdc), borrower1);
        vm.stopPrank();

        // Verify payment
        (, uint256 remainingPrincipal,,,, uint256 paymentsRemaining,) = borrowVault.getLoanDetails(borrower1);
        assertLt(remainingPrincipal, BORROW_AMOUNT, "Principal should decrease");
        assertEq(paymentsRemaining, 11, "Should have 11 payments remaining");

        // 6. Pay off loan early
        vm.warp(block.timestamp + 30 days); // Move forward another month

        uint256 payoffAmount = borrowVault.getPayoffAmount(borrower1);

        vm.startPrank(borrower1);
        usdc.approve(address(router), payoffAmount);

        vm.expectEmit(true, false, false, false);
        emit LoanPaidOff(borrower1);

        router.payoffLoan(address(usdc), borrower1);
        vm.stopPrank();

        // Verify loan is paid off
        (,,,,,, bool active) = borrowVault.getLoanDetails(borrower1);
        assertFalse(active, "Loan should be inactive");
        assertEq(borrowVault.balanceOf(borrower1), 0, "All debt tokens should be burned");
    }

    // ============================================
    // PAYMENT TESTS
    // ============================================

    function testMakePaymentNotDue() public {
        // Setup loan first
        _setupLoan();

        // Try to pay immediately (too early)
        vm.startPrank(borrower1);
        (uint256 paymentAmount,,,) = borrowVault.getNextPaymentDetails(borrower1);
        usdc.approve(address(router), paymentAmount);

        vm.expectRevert();
        router.makePayment(address(usdc), borrower1);

        vm.stopPrank();
    }

    function testMakePaymentNoActiveLoan() public {
        vm.startPrank(borrower1);

        vm.expectRevert();
        router.makePayment(address(usdc), borrower1);

        vm.stopPrank();
    }

    function testPayoffLoanNoActiveLoan() public {
        vm.startPrank(borrower1);

        vm.expectRevert();
        router.payoffLoan(address(usdc), borrower1);

        vm.stopPrank();
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    function _setupLoan() internal returns (uint256 requestId) {
        // Deposit funds
        vm.startPrank(depositor1);
        usdc.approve(address(router), DEPOSIT_AMOUNT);
        router.deposit(address(usdc), DEPOSIT_AMOUNT, depositor1);
        vm.stopPrank();

        // Request borrow
        vm.prank(borrower1);
        requestId = router.requestBorrow(address(usdc), BORROW_AMOUNT, LOAN_DURATION);

        // Approve
        vm.prank(signer1);
        borrowVault.approveBorrow(requestId);
        vm.prank(signer2);
        borrowVault.approveBorrow(requestId);

        // Execute
        borrowVault.executeBorrow(requestId);
    }

    // ============================================
    // FUZZ TESTS
    // ============================================

    function testFuzzDeposit(uint256 amount) public {
        // Bound the amount to valid range
        amount = bound(amount, 100e6, 100_000e6 - 1e6);

        // Fund depositorq
        usdc.mint(depositor1, amount);

        vm.startPrank(depositor1);
        usdc.approve(address(router), amount);

        uint256 shares = router.deposit(address(usdc), amount, depositor1);

        // In initial state, shares should equal assets 1:1
        assertEq(shares, amount, "Initial deposit should be 1:1");
        assertEq(lendingVault.balanceOf(depositor1), shares, "Should receive correct shares");

        vm.stopPrank();
    }

    function testFuzzBorrowRequest(uint256 amount, uint256 duration) public {
        // Bound inputs
        amount = bound(amount, 1_000e6, 100_000e6); // Within min/max loan
        duration = bound(duration, 6, 36); // 6-36 months

        // Setup lending vault with funds
        usdc.mint(depositor1, 200_000e6);
        vm.startPrank(depositor1);
        usdc.approve(address(router), 200_000e6);
        router.deposit(address(usdc), 200_000e6, depositor1);
        vm.stopPrank();

        // Request borrow
        vm.prank(borrower1);
        uint256 requestId = router.requestBorrow(address(usdc), amount, duration);

        // Verify request was created
        // (address borrower, uint256 reqAmount, uint256 reqDuration,,,) = borrowVault.borrowRequests(requestId);
        // assertEq(borrower, borrower1, "Borrower should match");
        // assertEq(reqAmount, amount, "Amount should match");
        // assertEq(reqDuration, duration, "Duration should match");
    }

    // ============================================
    // INTEGRATION TESTS
    // ============================================

    function testMultipleBorrowersAndDepositors() public {
        // Multiple depositors
        vm.startPrank(depositor1);
        usdc.approve(address(router), 30_000e6);
        router.deposit(address(usdc), 30_000e6, depositor1);
        vm.stopPrank();

        vm.startPrank(depositor2);
        usdc.approve(address(router), 20_000e6);
        router.deposit(address(usdc), 20_000e6, depositor2);
        vm.stopPrank();

        // Total TVL should be 50k
        assertEq(lendingVault.totalAssets(), 50_000e6, "Total assets should be sum of deposits");

        // Multiple borrowers
        vm.prank(borrower1);
        uint256 request1 = router.requestBorrow(address(usdc), 10_000e6, 12);

        vm.prank(borrower2);
        uint256 request2 = router.requestBorrow(address(usdc), 5_000e6, 6);

        // Approve both
        vm.prank(signer1);
        borrowVault.approveBorrow(request1);
        vm.prank(signer2);
        borrowVault.approveBorrow(request1);

        vm.prank(signer1);
        borrowVault.approveBorrow(request2);
        vm.prank(signer2);
        borrowVault.approveBorrow(request2);

        // Execute both
        borrowVault.executeBorrow(request1);
        borrowVault.executeBorrow(request2);

        // Verify both loans are active
        (,,,,,, bool active1) = borrowVault.getLoanDetails(borrower1);
        (,,,,,, bool active2) = borrowVault.getLoanDetails(borrower2);
        assertTrue(active1, "Borrower 1 loan should be active");
        assertTrue(active2, "Borrower 2 loan should be active");

        // Verify vault liquidity
        assertEq(lendingVault.availableLiquidity(), 35_000e6, "Should have 35k USDC remaining");
    }

    // ============================================
    // EDGE CASE TESTS
    // ============================================

    function testExistingLoanPreventsNewBorrow() public {
        _setupLoan(); // Setup first loan

        // Try to request another loan while first is active
        vm.prank(borrower1);
        vm.expectRevert();
        router.requestBorrow(address(usdc), 5_000e6, 6);
    }

    function testInsufficientLiquidityPreventsLoan() public {
        // Deposit small amount
        vm.startPrank(depositor1);
        usdc.approve(address(router), 5_000e6);
        router.deposit(address(usdc), 5_000e6, depositor1);
        vm.stopPrank();

        // Request larger loan
        vm.prank(borrower1);
        uint256 requestId = router.requestBorrow(address(usdc), 10_000e6, 12);

        // Approve
        vm.prank(signer1);
        borrowVault.approveBorrow(requestId);
        vm.prank(signer2);
        borrowVault.approveBorrow(requestId);

        // Execute should fail due to insufficient liquidity
        vm.expectRevert();
        borrowVault.executeBorrow(requestId);
    }
}
