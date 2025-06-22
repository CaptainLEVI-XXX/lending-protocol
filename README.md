
## Features

- ERC-4626 compliant lending vaults
- Amortized loan mechanism with fixed monthly payments
- Multi-signature loan approval system
- Upgradeable smart contracts using UUPS pattern
- Role-based access control
- Comprehensive test suite

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (for development and testing)
- [Node.js](https://nodejs.org/) (for development tooling)
- [Git](https://git-scm.com/)

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/CaptainLEVI-XXX/qiro-assignment.git
cd qiro-assignment
```

### 2. Install Dependencies

```bash
# Install Foundry if you haven't already
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install project dependencies
forge install
```

### 3. Configure Environment

Create a `.env` file in the root directory with the following variables:

```env
RPC_URL=your_ethereum_node_url
PRIVATE_KEY=your_private_key
ETHERSCAN_API_KEY=your_etherscan_api_key
```

## Project Structure

```
src/
├── AccessRegisty.sol         # Access control registry
├── BorrowVaultII.sol         # Borrowing vault implementation
├── LendingVault.sol          # Lending vault implementation (ERC-4626)
├── Router.sol                # Main entry point for user interactions
├── helper/
│   └── Roles.sol            # Role management
├── interfaces/
│   └── ILendingVault.sol   # Lending vault interface
├── libraries/
│   └── CustomRevert.sol    # Custom error handling
└── storage/
    ├── BorrowVault.sol      # Borrow vault storage layout
    └── LendingVault.sol     # Lending vault storage layout

test/
├── Test.t.sol              # Main test file
└── mock/
    └── ERC20.sol           # Mock ERC20 token for testing
```

## Development

### Compile Contracts

```bash
forge build
```

### Run Tests

```bash
# Run all tests
forge test -vvv

# Run a specific test
forge test --match-test testFullLoanLifecycle -vvv

# Run tests with gas reporting
forge test --gas-report
```

### Code Formatting

```bash
forge fmt
```

### Gas Optimization

```bash
forge snapshot
```



## Tools and Libraries Used

- [Solady](https://github.com/Vectorized/solady) - Gas optimized Solidity libraries
- [OpenZeppelin](https://openzeppelin.com/) - Secure smart contract development
- [Foundry](https://book.getfoundry.sh/) - Smart contract development framework