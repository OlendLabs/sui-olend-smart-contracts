# Olend DeFi Lending Platform

Olend is a decentralized lending platform built on Sui Network, developed using Sui Move smart contract language.

## Features

- **Unified Liquidity Management**: Efficient asset management through Registry and Vault architecture
- **Hierarchical Account System**: Complete permission management supporting main accounts and sub-accounts
- **Efficient Liquidation Mechanism**: Tick-based batch liquidation with low liquidation penalties and high loan-to-value ratios
- **ERC-4626 Compatibility**: Vault design compatible with ERC-4626 standard
- **Single Active Vault Policy**: Each asset type can only have one active vault to ensure consistency and security

## Project Structure

```
olend/
├── Move.toml                    # Move project configuration
├── sources/                     # Source code directory
│   ├── errors.move             # Error code definitions
│   ├── constants.move          # Constants definitions
│   ├── utils.move              # Utility functions
│   └── liquidity.move          # Liquidity management module
├── tests/                      # Test directory
│   ├── test_helpers.move       # Test helper functions
│   ├── basic_tests.move        # Basic functionality tests
│   ├── test_registry.move      # Registry module tests
│   └── test_init.move          # Initialization tests
└── .kiro/                      # Kiro IDE configuration
    └── specs/                  # Feature specifications
        └── olend-defi-platform/
            ├── requirements.md  # Requirements document
            ├── design.md       # Design document
            └── tasks.md        # Implementation tasks
```

## Core Modules

### 1. Liquidity Module
The liquidity management system provides unified asset management through a registry-vault architecture.

#### Key Components:
- **Registry**: Global asset vault registry supporting single active vault per asset type
- **Vault<T>**: ERC-4626 compatible unified liquidity vault
- **YToken<T>**: Share certificates representing user shares in specific vaults
- **AdminCap**: Administrative capability for permission control

#### Key Features:
- **Single Active Vault**: Each asset type can only have one active vault at a time
- **Vault State Management**: Support for pausing/resuming vaults
- **Default Vault Selection**: Automatic default vault assignment for new vaults
- **Version Control**: Protocol version management for upgrades

### 2. Error Handling System
Comprehensive error code system with categorized error types:
- **Liquidity Module Errors** (1000-1999): Vault operations, permissions, state management
- **Account Module Errors** (2000-2999): Account operations, allowances, permissions
- **General Errors** (9000-9999): System-wide errors

### 3. Constants and Utilities
- **Protocol Constants**: Version control, limits, and configuration values
- **Utility Functions**: Version compatibility, validation, and helper functions
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

# Run all tests
sui move test

# Run specific test module
sui move test test_registry

# Run specific test function
sui move test test_create_registry

# Check test coverage
sui move test --coverage

# Publish to testnet
sui client publish --gas-budget 100000000
```

## Project Status

### ✅ Completed
- [x] Project foundation and structure setup
- [x] Error code definition module (`errors.move`)
- [x] Constants definition module (`constants.move`) 
- [x] Utility functions module (`utils.move`)
- [x] Test helper functions (`test_helpers.move`)
- [x] Basic functionality tests (`basic_tests.move`)
- [x] **Registry System Implementation** (`liquidity.move`)
  - [x] Global asset vault registry
  - [x] Multi-vault management with single active vault policy
  - [x] Vault state management (active/paused)
  - [x] Administrative permission control
  - [x] Version control system
- [x] **Comprehensive Test Suite**
  - [x] Registry creation and initialization tests
  - [x] Vault registration and management tests
  - [x] Permission verification tests
  - [x] Error handling and edge case tests
  - [x] 17 test cases with 100% pass rate

### 🚧 In Progress
- [ ] Vault<T> core structure and ERC-4626 compatible interface implementation
- [ ] YToken<T> share certificate system
- [ ] Account Module implementation

### 📋 Planned
- [ ] Advanced liquidity management features
- [ ] Account hierarchy and permission system
- [ ] Integration tests
- [ ] Performance optimization
- [ ] Security audit
- [ ] Documentation enhancement

## Architecture Highlights

### Registry-Vault Architecture
- **Centralized Registry**: Single source of truth for all asset vaults
- **Single Active Vault Policy**: Ensures consistency and reduces complexity
- **State Management**: Comprehensive vault lifecycle management
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