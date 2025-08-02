# Decentralized Lending Protocol

A modular, upgradeable lending protocol implementing ERC-4626 vaults with amortized loans and multisig controls.

## 📋 Table of Contents

- [Architecture Overview](#architecture-overview)
- [Key Components](#key-components)
- [Design Decisions](#design-decisions)
- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [Development Guide](#development-guide)
- [Testing](#testing)
- [Deliverables](#deliverables)
- [Tools & Libraries](#tools--libraries)

## Architecture Overview

```
┌─────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   Router    │────▶│  Lending Vault   │     │  Borrow Vault    │
│  (Entry)    │     │  (UUPS Proxy)    │◀───▶│  (UUPS Proxy)    │
└──────┬──────┘     └──────────────────┘     └──────────────────┘
       │                      │                         │
       └──────────────────────┴─────────────────────────┘
                              │
                    ┌─────────▼──────────┐
                    │  Access Registry   │
                    │  (Role Management) │
                    └────────────────────┘
```

## Key Components

### 🔐 AccessRegistry
- **Purpose**: Centralized role management system
- **Features**:
  - Grant, revoke, and check roles for any address
  - Stores all protocol roles (Admin, Multisig, Whitelisted Borrowers)
  - Single source of truth for permissions

### 🚪 Router
- **Purpose**: Single entry point for all user interactions
- **Key Features**:
  - Uses advanced `Lock` mechanism (similar to Uniswap V4) with `tstore`/`tload` for 90% gas savings over traditional reentrancy guards
  - Manages vault registry for multiple assets (USDT, USDC, etc.)
  - Enforces role-based access control via AccessRegistry
  - Restricts direct vault access - only Router can call main vault operations

### 💰 LendingVault (ERC-4626)
- **Purpose**: Manages deposits and share distribution
- **Key Functions**:
  - `deposit/withdraw`: Standard ERC-4626 operations (Router-only)
  - `allocateFunds`: Lends assets to Borrow Vault
  - `returnFunds`: Receives repayments (principal + interest)
- **Features**: UUPS upgradeable for future enhancements

### 📊 BorrowVault
- **Purpose**: Handles loan lifecycle and amortization logic
- **Key Functions**:
  - `requestBorrow`: Whitelisted borrowers request loans
  - `approveBorrow`: Multisig signers approve requests (2/N required)
  - `executeBorrow`: Anyone can execute approved loans
  - `makePayment`: Monthly payments (anyone can pay on behalf)
  - `payoffLoan`: Early payoff option
- **Features**: Fixed-rate amortized loans with predictable payments

## Design Decisions

### 1. Modular Vault Separation

**Why separate Lending and Borrowing vaults?**

✅ **Single Responsibility**: Each vault has one clear purpose
- Lending Vault → Deposits, withdrawals, share accounting
- Borrow Vault → Loans, repayments, debt tracking

✅ **Risk Isolation**: Bugs in borrowing logic don't directly affect depositor funds

✅ **Independent Scaling**: Optimize each vault for its use case
- Lending: Many small transactions
- Borrowing: Fewer, larger operations

✅ **Compliance**: Handle different regulatory requirements independently

### 2. UUPS Upgradeable Pattern

**Benefits:**
- ⚡ **Gas Efficient**: More efficient than transparent proxy
- 🔄 **Future-Proof**: Fix bugs and add features without migration
- 💾 **Preserves State**: User balances remain intact during upgrades
- 🎯 **Selective Upgrades**: Upgrade one vault without touching others

### 3. Router Pattern

**Advantages:**
- 👤 **Better UX**: One address, one token approval
- ⚛️ **Atomic Operations**: Bundle multiple actions in one transaction
- 🔍 **Upgrade Transparency**: Users always interact with same address
- 🔗 **Cross-Vault Operations**: Coordinate between vaults seamlessly

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) - Smart contract development framework
- [Node.js](https://nodejs.org/) v16+ - Development tooling
- [Git](https://git-scm.com/) - Version control

### Installation

```bash
# Clone the repository
git clone https://github.com/CaptainLEVI-XXX/lending-protocol.git
cd lending-protoco

# Install Foundry (if not already installed)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install project dependencies
forge install
```

### Build

```bash
forge build
```

## Project Structure

```
src/
├── AccessRegisty.sol         # Role-based access control
├── Router.sol                # Main entry point for users
├── LendingVault.sol          # ERC-4626 deposit vault
├── BorrowVault.sol         # Amortized loan logic
├── helper/
│   └── Roles.sol            # Role definitions and modifiers
├── interfaces/
│   ├── IAccessRegistry.sol  # Access registry interface
│   ├── IBorrowVault.sol     # Borrow vault interface
│   └── ILendingVault.sol    # Lending vault interface
├── libraries/
│   ├── CustomRevert.sol     # Gas-efficient error handling
│   └── Lock.sol             # Reentrancy protection
└── storage/
    ├── BorrowVault.sol      # Storage layout for upgrades
    └── LendingVault.sol     # Storage layout for upgrades

test/
├── Test.t.sol               # Comprehensive test suite
└── mock/
    └── ERC20.sol           # Mock token for testing
```

## Development Guide

### Running Tests

```bash
# Run all tests with verbosity
forge test -vvv

# Run specific test
forge test --match-test testFullLoanLifecycle -vvv

# Run with gas reporting
forge test --gas-report

# Run with coverage
forge coverage
```

### Key Test Scenarios

1. **Deposit Flow**: Test share minting and value tracking
2. **Loan Lifecycle**: Request → Approve → Execute → Repay
3. **Share Appreciation**: Verify yield distribution via share value increase
4. **Edge Cases**: Insufficient liquidity, unauthorized access, etc.

## Testing

The test suite (`test/Test.t.sol`) demonstrates:

- ✅ Token deposits and share issuance
- ✅ Borrower whitelisting and loan approval flow
- ✅ Loan disbursement with multisig controls
- ✅ Monthly payment tracking (principal vs interest)
- ✅ Share value appreciation from interest payments
- ✅ Early loan payoff functionality

## Deliverables

### 1. Smart Contracts ✅
- `LendingVault.sol` - ERC-4626 compliant deposit vault
- `BorrowVault.sol` - Amortized loan management
- `Router.sol` - User interaction layer
- `AccessRegisty.sol` - Role-based permissions

### 2. Test Suite ✅
- `test/Test.t.sol` - Comprehensive test coverage including:
  - Deposit and withdrawal flows
  - Loan lifecycle (request → approval → repayment)
  - Share value appreciation tracking
  - Edge cases and security tests


## Tools & Libraries

| Library              | Purpose                           | Why Chosen |
|----------------------|-----------------------------------|------------|
| **Solady**           | Gas-optimized implementations     | Superior gas efficiency vs OpenZeppelin |
| **OpenZeppelin**     | Security standards                | Industry-standard, audited contracts |
| **Foundry**          | Development framework             | Fast testing, built-in fuzzing, great DX |
| **Custom Libraries** | Specialized needs                 | `Lock` for efficient reentrancy, `CustomRevert` for gas savings |

## Limitations & Assumptions

- **Fixed monthly periods**: 30-day cycles for simplicity
- **Single asset per vault**: Multi-asset support requires separate deployments
