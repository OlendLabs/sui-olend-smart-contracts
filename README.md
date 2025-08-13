# Olend DeFi Lending Platform

Olend is a decentralized lending platform built on Sui Network, developed using Sui Move smart contract language.

## Features

### ✅ Implemented Core Features
- **Unified Liquidity Management**: Complete Registry-Vault architecture with Shared Object design
- **ERC-4626 Compatibility**: Full standard compliance with deposit/withdraw/convert functions
- **Advanced Fee System**: Configurable deposit and withdrawal fees (0-100%)
- **Comprehensive Account System**: User accounts with points, levels, and position tracking
- **Daily Withdrawal Limits**: Automatic reset and configurable limits
- **Multi-Status Vault Management**: Active, Paused, DepositsOnly, WithdrawalsOnly, Inactive modes
- **Package-Level Security**: Critical functions restricted to package access only
- **Emergency Controls**: Multi-level emergency pause mechanisms
- **Single Vault Policy**: One shared vault per asset type for maximum efficiency

### 🚧 Planned DeFi Features
- **Oracle Integration**: Pyth Network price feeds for accurate asset pricing
- **High LTV Lending**: Support for up to 97% loan-to-value ratios
- **Tick-Based Liquidation**: Efficient batch liquidation with low penalties (0.1%+)
- **Multi-Asset Collateral**: Support for diverse collateral types
- **Revenue Sharing**: 70% revenue return to users
- **Governance System**: Decentralized parameter management

## Project Structure

```
olend/
├── Move.toml                    # Move project configuration
├── sources/                     # Source code directory
│   ├── errors.move             # Error code definitions
│   ├── constants.move          # Constants definitions
│   ├── utils.move              # Utility functions
│   ├── liquidity.move          # Liquidity management module
│   ├── vault.move              # ERC-4626 compatible vault implementation
│   ├── ytoken.move             # Share token implementation
│   ├── account.move            # Account management system
│   ├── oracle.move             # Pyth Network oracle integration
│   ├── lending_pool.move       # Lending pool management
│   └── borrowing_pool.move     # Borrowing pool with points integration
├── tests/                      # Test directory
│   ├── test_helpers.move       # Test helper functions
│   ├── basic_tests.move        # Basic functionality tests
│   ├── test_init.move          # Initialization tests
│   ├── test_registry.move      # Registry module tests
│   ├── test_vault.move         # Vault module tests
│   ├── test_account.move       # Account module tests
│   ├── test_oracle.move        # Oracle integration tests
│   ├── test_lending_pool.move  # Lending pool tests
│   ├── test_borrowing_pool.move # Borrowing pool and points tests
│   ├── test_package_interface.move # Package interface tests
│   └── test_data_consistency.move  # Data consistency tests
└── .kiro/                      # Kiro IDE configuration
    └── specs/                  # Feature specifications
        └── olend-defi-platform/
            ├── requirements.md  # Requirements document
            ├── design.md       # Design document
            └── tasks.md        # Implementation tasks
```

## Core Modules

### 1. Vault System (`vault.move`)
ERC-4626 compatible unified liquidity vault implementation with advanced features.

#### Key Components:
- **Vault<T>**: Shared Object for unified liquidity management
- **VaultStatus**: Comprehensive status management (Active, Paused, DepositsOnly, WithdrawalsOnly, Inactive)
- **VaultConfig**: Configurable parameters including fees and limits
- **Daily Limits**: Withdrawal limit management with automatic reset

#### Key Features:
- **ERC-4626 Compatibility**: Standard deposit/withdraw/convert functions
- **Fee System**: Configurable deposit and withdrawal fees (0-100%)
- **Shared Object Architecture**: Each asset type has one shared Vault<T>
- **Package-Level Security**: Critical functions restricted to package access
- **Emergency Controls**: Multiple levels of emergency pause functionality

### 2. Account System (`account.move`)
Comprehensive user account management with points and level system.

#### Key Components:
- **AccountRegistry**: Global account management
- **Account**: User account with points, levels, and position tracking
- **AccountCap**: Non-transferable account capability for security

#### Key Features:
- **Points System**: Multiple point types (deposit, borrow, credit points)
- **Level System**: User levels with associated benefits
- **Position Tracking**: Track user positions across the platform
- **Safe Point Deduction**: Underflow protection for point operations

### 3. YToken System (`ytoken.move`)
Simple and secure share token implementation.

#### Key Components:
- **YToken<T>**: Phantom type for share representation
- **Witness Pattern**: Secure token creation restricted to package

#### Key Features:
- **Package-Only Creation**: Prevents external token minting
- **Type Safety**: Phantom type ensures type safety
- **Minimal Design**: Optimized for performance

### 4. Liquidity Registry (`liquidity.move`)
Global registry for vault management and discovery.

#### Key Components:
- **Registry**: Global asset vault registry
- **VaultInfo**: Vault metadata and status tracking
- **LiquidityAdminCap**: Administrative capability

#### Key Features:
- **Single Vault Policy**: One vault per asset type
- **Vault Discovery**: Efficient vault lookup and management
- **State Management**: Vault lifecycle management
- **Version Control**: Protocol upgrade safety

### 6. Oracle Integration System (`oracle.move`)
Pyth Network price feed integration for accurate asset pricing.

#### Key Components:
- **PriceOracle**: Shared Object for price data management
- **PriceInfo**: Price data with confidence intervals and timestamps
- **Multi-Asset Support**: BTC, ETH, SUI, USDC, USDT price feeds

#### Key Features:
- **Real-Time Pricing**: Live price feeds from Pyth Network
- **Price Validation**: Confidence interval and freshness checks
- **8-Decimal Precision**: Standardized price formatting
- **Safety Mechanisms**: Price manipulation protection

### 7. Lending Pool System (`lending_pool.move`)
ERC-4626 compatible lending pools with advanced features.

#### Key Components:
- **LendingPool<T>**: Asset-specific lending pools
- **LendingPoolRegistry**: Global pool management
- **Interest Rate Models**: Dynamic and fixed rate support

#### Key Features:
- **Unified Liquidity**: Integration with Vault system
- **Points Integration**: Deposit rewards and level bonuses
- **Multiple Rate Models**: Flexible interest rate strategies
- **Liquidity Management**: Real-time utilization tracking

### 8. Borrowing Pool System (`borrowing_pool.move`)
High-LTV borrowing with comprehensive user incentive system.

#### Key Components:
- **BorrowingPool<T>**: Asset-specific borrowing pools
- **BorrowPosition**: Individual borrowing position tracking
- **CollateralHolder<C>**: Secure collateral management

#### Key Features:
- **High LTV Support**: Up to 97% for BTC, 95% for ETH
- **Points Integration**: Comprehensive reward system
  - Borrowing points: 1 point per 1000 units
  - Credit points: 1 point per 500 units repaid
  - Early repayment bonuses: Up to 50% bonus
- **Level-Based Benefits**:
  - Interest rate discounts: 0.1%-0.5% for VIP users
  - LTV bonuses: Up to 2% extra for diamond users
- **Real-Time Monitoring**: Continuous collateral ratio tracking
- **Risk Management**: Multi-threshold liquidation protection

### 9. Error Handling System (`errors.move`)
Comprehensive error code system with categorized error types:
- **Liquidity Module Errors** (1000-1999): Vault operations, permissions, state management
- **Account Module Errors** (2000-2999): Account operations, allowances, permissions
- **Oracle Module Errors** (3000-3999): Price feed operations, validation errors
- **Lending Pool Errors** (4000-4999): Lending operations, rate calculations
- **Borrowing Pool Errors** (5000-5999): Borrowing operations, collateral management
- **General Errors** (9000-9999): System-wide errors

### 10. Constants and Utilities
- **Constants** (`constants.move`): Protocol version, limits, and configuration values
- **Utilities** (`utils.move`): Version compatibility, validation, and helper functions
- **Test Helpers**: Comprehensive testing utilities and mock data

## Development Standards

### Code Style
This project strictly follows the [Move Book Code Quality Checklist](https://move-book.com/guides/code-quality-checklist):

- **Struct Definitions**: All structs must be defined as `public struct` (Move 2024 requirement)
- **Naming Conventions**: 
  - Functions: snake_case
  - Structs: PascalCase
  - Error constants: EPascalCase (e.g., `const ENotAuthorized: u64 = 0;`)
  - Other constants: SCREAMING_SNAKE_CASE
  - Modules: Descriptive names (avoid generic names like `types`)
- **Documentation**: All public functions must have documentation comments in English
- **Error Handling**: Comprehensive error codes with meaningful messages

### Testing Requirements
- Every public function must have corresponding test cases
- Test coverage requirement: 90%+
- Include both normal flow and edge case testing
- Use Sui test framework with proper scenario management

## Build and Test

```bash
# Build project
sui move build

# Run all tests (188 tests, 100% pass rate)

sui move test

# Run specific test modules
sui move test test_vault          # Vault system tests (50+ tests)
sui move test test_account        # Account system tests (30+ tests)
sui move test test_registry       # Registry tests (20+ tests)
sui move test test_oracle         # Oracle integration tests (15+ tests)
sui move test test_lending_pool   # Lending pool tests (25+ tests)
sui move test test_borrowing_pool # Borrowing pool and points tests (27+ tests)

# Run specific test categories
sui move test test_deposit_withdrawal_fees  # Fee system tests
sui move test test_points_deduction        # Points system tests
sui move test test_create_and_share_vault  # Shared object tests

# Check test coverage (90%+ coverage achieved)
sui move test --coverage

# Publish to testnet
sui client publish --gas-budget 100000000
```

### Test Results
- **Total Tests**: 188
- **Pass Rate**: 100%
- **Coverage**: 90%+
- **Test Categories**: 
  - Core functionality tests
  - Security and permission tests
  - Integration tests

  - Points and level system tests
  - Oracle integration tests
  - Borrowing and lending pool tests
                       
  - Edge case and error handling tests

## Project Status

### ✅ Completed (Phase 1: Core Infrastructure)
- [x] **Project Foundation**
  - [x] Error code definition module (`errors.move`)
  - [x] Constants definition module (`constants.move`) 
  - [x] Utility functions module (`utils.move`)
  - [x] Test helper functions (`test_helpers.move`)

- [x] **Vault System Implementation** (`vault.move`)
  - [x] ERC-4626 compatible vault structure
  - [x] Shared Object architecture (Vault<T> as shared object)
  - [x] Comprehensive fee system (deposit/withdrawal fees)
  - [x] Daily withdrawal limits with automatic reset
  - [x] Multiple vault status modes (Active, Paused, DepositsOnly, etc.)
  - [x] Package-level security for critical operations
  - [x] Emergency pause mechanisms
  - [x] Asset consistency validation

- [x] **YToken System Implementation** (`ytoken.move`)
  - [x] Secure share token with phantom types
  - [x] Package-only witness creation
  - [x] Integration with vault system

- [x] **Account System Implementation** (`account.move`)
  - [x] Comprehensive user account management
  - [x] Points system (deposit, borrow, credit points)
  - [x] User level system with benefits
  - [x] Position tracking across platform
  - [x] Safe point deduction with underflow protection
  - [x] Account capability security model

- [x] **Registry System Implementation** (`liquidity.move`)
  - [x] Global asset vault registry
  - [x] Single vault per asset type policy
  - [x] Vault state management and discovery
  - [x] Administrative permission control
  - [x] Version control system

- [x] **Comprehensive Test Suite** (188 tests, 100% pass rate)
  - [x] Vault system tests (deposit, withdraw, fees, limits)
  - [x] Account system tests (points, levels, positions)
  - [x] Registry tests (vault management, permissions)
  - [x] Oracle integration tests (price feeds, validation)
  - [x] Lending pool tests (deposits, interest rates, rewards)
  - [x] Borrowing pool tests (collateral, points, level benefits)
  - [x] Integration tests (cross-module interactions)
  - [x] Security tests (emergency controls, consistency)
  - [x] Edge case and error handling tests

### ✅ Completed (Phase 2: Advanced Features)
- [x] **Oracle Integration System** (`oracle.move`)
  - [x] Pyth Network price feed integration
  - [x] Real-time price data with confidence intervals
  - [x] Multi-asset price support (BTC, ETH, SUI, USDC, USDT)
  - [x] Price validation and safety mechanisms
  - [x] 8-decimal precision price formatting

- [x] **Lending Pool Management System** (`lending_pool.move`)
  - [x] ERC-4626 compatible lending pools
  - [x] Dynamic and fixed interest rate models
  - [x] Liquidity management and utilization tracking
  - [x] User points integration for deposit rewards
  - [x] Level-based interest rate bonuses

- [x] **Borrowing Pool Management System** (`borrowing_pool.move`)
  - [x] High collateral ratio support (up to 97% for BTC, 95% for ETH)
  - [x] Single-asset collateral borrowing (multi-asset planned for future)
  - [x] Real-time collateral ratio monitoring
  - [x] **User Points and Level Integration**:
    - [x] Borrowing points: 1 point per 1000 units borrowed
    - [x] Credit points: 1 point per 500 units repaid (better rate)
    - [x] Early repayment bonuses (up to 50% bonus within 1 day)
    - [x] Level-based interest rate discounts (0.1%-0.5% for VIP users)
    - [x] Level-based LTV bonuses (up to 2% extra for diamond users)

### 🚧 In Progress (Phase 2: Advanced Features)
- [ ] Multi-asset collateral support (planned for future versions)
- [ ] Advanced liquidation system with Tick mechanism

### 📋 Planned (Phase 3: DeFi Features)
- [ ] High-efficiency liquidation system with Tick mechanism
- [ ] DEX integration for liquidity provision
- [ ] Governance and revenue distribution system
- [ ] Advanced risk management features
- [ ] Performance optimization and monitoring
- [ ] Security audit and formal verification

## Architecture Highlights

### Registry-Vault Architecture
- **Centralized Registry**: Single source of truth for all asset vaults
- **Single Vault Policy**: One vault per asset type ensures simplicity and consistency
- **State Management**: Vault lifecycle management with active/inactive states
- **Type Safety**: Full generic type support for different asset types

### Security Features
- **Permission Control**: AdminCap-based authorization system
- **Version Control**: Protocol upgrade safety mechanisms
- **State Validation**: Comprehensive state checks and validations
- **Error Handling**: Detailed error codes for debugging and monitoring

### Testing Strategy
- **Unit Tests**: Individual function testing with comprehensive coverage
- **Integration Tests**: Cross-module interaction testing
- **Edge Case Testing**: Boundary conditions and error scenarios
- **Scenario Testing**: Real-world usage patterns simulation

## Requirements

- **Sui Framework**: mainnet
- **Move Edition**: 2024.beta
- **Minimum Sui Version**: 1.0.0

## Contributing

1. Follow the Move Book code quality guidelines
2. Ensure all tests pass before submitting
3. Add comprehensive test coverage for new features
4. Use English for all code comments and documentation
5. Follow the established naming conventions

## License

MIT License

## Contact

For questions and support, please refer to the project documentation or create an issue in the repository.