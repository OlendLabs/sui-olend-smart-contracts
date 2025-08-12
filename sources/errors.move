/// Error code definition module
/// Defines error code constants used by all modules in the Olend platform
module olend::errors;

// ===== Liquidity Module Error Codes (1000-1999) =====

/// Vault is paused
const EVaultPaused: u64 = 1001;

/// Vault not found
const EVaultNotFound: u64 = 1002;

/// Insufficient assets
const EInsufficientAssets: u64 = 1003;

/// Daily limit exceeded
const EDailyLimitExceeded: u64 = 1004;

/// Invalid shares amount
const EInvalidShares: u64 = 1005;

/// Version mismatch
const EVersionMismatch: u64 = 1006;

/// Unauthorized access
const EUnauthorizedAccess: u64 = 1007;

/// Vault not active
const EVaultNotActive: u64 = 1008;

/// Invalid assets amount
const EInvalidAssets: u64 = 1009;

/// Invalid vault configuration
const EInvalidVaultConfig: u64 = 1010;

/// Zero shares operation
const EZeroShares: u64 = 1011;

/// Zero assets operation
const EZeroAssets: u64 = 1012;

/// Vault already exists for this asset type
const EVaultAlreadyExists: u64 = 1013;

/// Data consistency check failed
const EDataInconsistency: u64 = 1014;

/// Concurrent access violation
const EConcurrentAccessViolation: u64 = 1015;

/// Atomic operation failed
const EAtomicOperationFailed: u64 = 1016;

// ===== Account Module Error Codes (2000-2099) =====

/// Account not found
const EAccountNotFound: u64 = 2001;

/// Account suspended
const EAccountSuspended: u64 = 2002;

/// Insufficient allowance
const EInsufficientAllowance: u64 = 2003;

/// Unauthorized operation
const EUnauthorizedOperation: u64 = 2004;

// Sub-account functionality removed

/// Allowance expired
const EAllowanceExpired: u64 = 2006;

/// Account capability mismatch
const EAccountCapMismatch: u64 = 2007;

/// Account already exists
const EAccountAlreadyExists: u64 = 2008;

/// Invalid account status
const EInvalidAccountStatus: u64 = 2009;

// Sub-account functionality removed

/// Position ID not found
const EPositionIdNotFound: u64 = 2011;

/// Invalid allowance type
const EInvalidAllowanceType: u64 = 2012;

/// Rate limit exceeded
const EAccountRateLimitExceeded: u64 = 2013;

/// Replay attack detected
const EReplayAttackDetected: u64 = 2014;

/// Suspicious activity detected
const ESuspiciousActivityDetected: u64 = 2015;

/// Account temporarily restricted
const EAccountRestricted: u64 = 2016;

// ===== Oracle Module Error Codes (2050-2099) =====

/// Price feed not configured for asset type
const EPriceFeedNotFound: u64 = 2050;

/// Price data is stale (too old)
const EPriceDataStale: u64 = 2051;

/// Price confidence too low
const EPriceConfidenceTooLow: u64 = 2052;

/// Price manipulation detected (Oracle module)
const EOraclePriceManipulationDetected: u64 = 2053;

/// Invalid price feed ID
const EInvalidPriceFeedId: u64 = 2054;

/// Oracle in emergency mode
const EOracleEmergencyMode: u64 = 2055;

/// Price validation failed
const EPriceValidationFailed: u64 = 2056;

/// Unauthorized oracle access
const EUnauthorizedOracleAccess: u64 = 2057;

/// Invalid oracle configuration
const EInvalidOracleConfig: u64 = 2058;

/// Price cache miss
const EPriceCacheMiss: u64 = 2059;

// ===== Security Error Codes (5000-5999) =====

/// Oracle price is stale (timestamp too old)
const EOraclePriceStale: u64 = 5001;

/// Oracle confidence level too low
const EOracleConfidenceLow: u64 = 5002;

/// Price manipulation detected
const EPriceManipulationDetected: u64 = 5003;

/// Circuit breaker is active
const ECircuitBreakerActive: u64 = 5004;

/// Reentrancy attack detected
const EReentrancyDetected: u64 = 5005;

/// Flash loan attack detected
const EFlashLoanAttack: u64 = 5006;

/// Mathematical overflow detected
const EMathOverflow: u64 = 5007;

/// Mathematical underflow detected
const EMathUnderflow: u64 = 5008;

/// Access denied - insufficient permissions
const EAccessDenied: u64 = 5009;

/// Operation is time-delayed
const EOperationDelayed: u64 = 5010;

/// Multi-signature required for operation
const EMultisigRequired: u64 = 5011;

/// Emergency pause is active
const EEmergencyPauseActive: u64 = 5012;

/// Position is too new for operation
const EPositionTooNew: u64 = 5013;

/// Rate limit exceeded
const ERateLimitExceeded: u64 = 5014;

/// Suspicious activity pattern detected
const ESuspiciousActivity: u64 = 5015;

/// Division by zero attempted
const EDivisionByZero: u64 = 5016;

/// Invalid security configuration
const EInvalidSecurityConfig: u64 = 5017;

/// Security module not initialized
const ESecurityNotInitialized: u64 = 5018;

/// Invalid role assignment
const EInvalidRole: u64 = 5019;

/// Operation timeout exceeded
const EOperationTimeout: u64 = 5020;

// ===== General Error Codes (9000-9999) =====

/// Invalid input parameter
const EInvalidInput: u64 = 9001;

/// Operation denied
const EOperationDenied: u64 = 9002;

/// System under maintenance
const ESystemMaintenance: u64 = 9003;

/// Internal error
const EInternalError: u64 = 9004;

// ===== Public Access Functions =====
// Since constants are module-internal, provide public functions to access error codes

/// Get Vault-related error codes
public fun vault_paused(): u64 { EVaultPaused }
public fun vault_not_found(): u64 { EVaultNotFound }
public fun insufficient_assets(): u64 { EInsufficientAssets }
public fun daily_limit_exceeded(): u64 { EDailyLimitExceeded }
public fun invalid_shares(): u64 { EInvalidShares }
public fun version_mismatch(): u64 { EVersionMismatch }
public fun unauthorized_access(): u64 { EUnauthorizedAccess }
public fun vault_not_active(): u64 { EVaultNotActive }
public fun invalid_assets(): u64 { EInvalidAssets }
public fun invalid_vault_config(): u64 { EInvalidVaultConfig }
public fun zero_shares(): u64 { EZeroShares }
public fun zero_assets(): u64 { EZeroAssets }
public fun vault_already_exists(): u64 { EVaultAlreadyExists }
public fun data_inconsistency(): u64 { EDataInconsistency }
public fun concurrent_access_violation(): u64 { EConcurrentAccessViolation }
public fun atomic_operation_failed(): u64 { EAtomicOperationFailed }

/// Get Account-related error codes
public fun account_not_found(): u64 { EAccountNotFound }
public fun account_suspended(): u64 { EAccountSuspended }
public fun insufficient_allowance(): u64 { EInsufficientAllowance }
public fun unauthorized_operation(): u64 { EUnauthorizedOperation }
// Sub-account functionality removed
public fun allowance_expired(): u64 { EAllowanceExpired }
public fun account_cap_mismatch(): u64 { EAccountCapMismatch }
public fun account_already_exists(): u64 { EAccountAlreadyExists }
public fun invalid_account_status(): u64 { EInvalidAccountStatus }
// Sub-account functionality removed
public fun position_id_not_found(): u64 { EPositionIdNotFound }
public fun invalid_allowance_type(): u64 { EInvalidAllowanceType }
public fun account_rate_limit_exceeded(): u64 { EAccountRateLimitExceeded }
public fun replay_attack_detected(): u64 { EReplayAttackDetected }
public fun suspicious_activity_detected(): u64 { ESuspiciousActivityDetected }
public fun account_restricted(): u64 { EAccountRestricted }

/// Get Oracle-related error codes
public fun price_feed_not_found(): u64 { EPriceFeedNotFound }
public fun price_data_stale(): u64 { EPriceDataStale }
public fun price_confidence_too_low(): u64 { EPriceConfidenceTooLow }
public fun oracle_price_manipulation_detected(): u64 { EOraclePriceManipulationDetected }
public fun invalid_price_feed_id(): u64 { EInvalidPriceFeedId }
public fun oracle_emergency_mode(): u64 { EOracleEmergencyMode }
public fun price_validation_failed(): u64 { EPriceValidationFailed }
public fun unauthorized_oracle_access(): u64 { EUnauthorizedOracleAccess }
public fun invalid_oracle_config(): u64 { EInvalidOracleConfig }
public fun price_cache_miss(): u64 { EPriceCacheMiss }

// ===== Borrowing Pool Module Error Codes (4000-4099) =====

/// Pool is paused
const EBorrowingPoolPaused: u64 = 4001;

/// Insufficient collateral
const EInsufficientCollateral: u64 = 4002;

/// Insufficient borrow amount
const EInsufficientBorrow: u64 = 4003;

/// Position not found
const EPositionNotFound: u64 = 4004;

/// Invalid pool configuration
const EInvalidBorrowingPoolConfig: u64 = 4005;

/// Borrowing not allowed
const EBorrowingNotAllowed: u64 = 4006;

/// Repayment not allowed
const ERepaymentNotAllowed: u64 = 4007;

/// Liquidation not allowed
const ELiquidationNotAllowed: u64 = 4008;

/// Borrow limit exceeded
const EBorrowLimitExceeded: u64 = 4009;

/// Collateral ratio too high (unsafe)
const ECollateralRatioTooHigh: u64 = 4010;

/// Position not liquidatable
const EPositionNotLiquidatable: u64 = 4011;

/// Invalid liquidation amount
const EInvalidLiquidationAmount: u64 = 4012;

/// Get Borrowing Pool-related error codes
public fun borrowing_pool_paused(): u64 { EBorrowingPoolPaused }
public fun insufficient_collateral(): u64 { EInsufficientCollateral }
public fun insufficient_borrow(): u64 { EInsufficientBorrow }
public fun position_not_found(): u64 { EPositionNotFound }
public fun invalid_borrowing_pool_config(): u64 { EInvalidBorrowingPoolConfig }
public fun borrowing_not_allowed(): u64 { EBorrowingNotAllowed }
public fun repayment_not_allowed(): u64 { ERepaymentNotAllowed }
public fun liquidation_not_allowed(): u64 { ELiquidationNotAllowed }
public fun borrow_limit_exceeded(): u64 { EBorrowLimitExceeded }
public fun collateral_ratio_too_high(): u64 { ECollateralRatioTooHigh }
public fun position_not_liquidatable(): u64 { EPositionNotLiquidatable }
public fun invalid_liquidation_amount(): u64 { EInvalidLiquidationAmount }

/// Get Security-related error codes
public fun oracle_price_stale(): u64 { EOraclePriceStale }
public fun oracle_confidence_low(): u64 { EOracleConfidenceLow }
public fun price_manipulation_detected(): u64 { EPriceManipulationDetected }
public fun circuit_breaker_active(): u64 { ECircuitBreakerActive }
public fun reentrancy_detected(): u64 { EReentrancyDetected }
public fun flash_loan_attack(): u64 { EFlashLoanAttack }
public fun math_overflow(): u64 { EMathOverflow }
public fun math_underflow(): u64 { EMathUnderflow }
public fun access_denied(): u64 { EAccessDenied }
public fun operation_delayed(): u64 { EOperationDelayed }
public fun multisig_required(): u64 { EMultisigRequired }
public fun emergency_pause_active(): u64 { EEmergencyPauseActive }
public fun position_too_new(): u64 { EPositionTooNew }
public fun rate_limit_exceeded(): u64 { ERateLimitExceeded }
public fun suspicious_activity(): u64 { ESuspiciousActivity }
public fun division_by_zero(): u64 { EDivisionByZero }
public fun invalid_security_config(): u64 { EInvalidSecurityConfig }
public fun security_not_initialized(): u64 { ESecurityNotInitialized }
public fun invalid_role(): u64 { EInvalidRole }
public fun operation_timeout(): u64 { EOperationTimeout }

/// Get general error codes
public fun invalid_input(): u64 { EInvalidInput }
public fun operation_denied(): u64 { EOperationDenied }
public fun system_maintenance(): u64 { ESystemMaintenance }
public fun internal_error(): u64 { EInternalError }