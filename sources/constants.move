/// Constants definition module
/// Defines core constants used by the Olend platform
module olend::constants;

// ===== Protocol Constants =====

/// Current protocol version
const CURRENT_VERSION: u64 = 1;

/// Maximum daily withdrawal limit (in base units)
const MAX_DAILY_WITHDRAWAL_LIMIT: u64 = 1_000_000_000_000; // 1M tokens

/// Default user level
const DEFAULT_USER_LEVEL: u8 = 1;

/// Maximum user level
const MAX_USER_LEVEL: u8 = 10;

/// Seconds per day
const SECONDS_PER_DAY: u64 = 86400;

// ===== Security Constants =====

/// Maximum operations per time window (rate limiting)
const MAX_OPERATIONS_PER_WINDOW: u64 = 100;

/// Time window duration in milliseconds (5 minutes)
const RATE_LIMIT_WINDOW_MS: u64 = 300000;

/// Maximum suspicious activities before account restriction
const MAX_SUSPICIOUS_ACTIVITIES: u64 = 10;

/// Cooldown period after suspicious activity (1 hour in milliseconds)
const SUSPICIOUS_ACTIVITY_COOLDOWN_MS: u64 = 3600000;

// ===== Allowance Type Constants =====

/// Lending allowance type
const ALLOWANCE_TYPE_LENDING: u8 = 1;

/// Borrowing allowance type
const ALLOWANCE_TYPE_BORROWING: u8 = 2;

/// Trading allowance type
const ALLOWANCE_TYPE_TRADING: u8 = 3;

/// Withdrawal allowance type
const ALLOWANCE_TYPE_WITHDRAWAL: u8 = 4;

// ===== Oracle Constants =====

/// Maximum price age in seconds (30 minutes)
const MAX_PRICE_AGE_SECONDS: u64 = 1800;

/// Minimum confidence threshold in basis points (1% = 100 bps)
const MIN_CONFIDENCE_THRESHOLD_BPS: u64 = 100;

/// Maximum number of supported price feeds
const MAX_PRICE_FEEDS: u64 = 100;

/// Basis points denominator (10000 = 100%)
const BASIS_POINTS_DENOMINATOR: u64 = 10000;

/// Oracle price precision (8 decimal places)
const ORACLE_PRICE_PRECISION: u8 = 8;

/// Liquidation threshold in basis points (80% = 8000 bps)
const DEFAULT_LIQUIDATION_THRESHOLD_BPS: u64 = 8000;

/// Health factor precision (2 decimal places)
const HEALTH_FACTOR_PRECISION: u64 = 100;

/// Minimum health factor for borrowing (1.25 = 125)
const MIN_HEALTH_FACTOR: u64 = 125;

// ===== Public Access Functions =====

/// Get current protocol version
public fun current_version(): u64 { CURRENT_VERSION }

/// Get maximum daily withdrawal limit
public fun max_daily_withdrawal_limit(): u64 { MAX_DAILY_WITHDRAWAL_LIMIT }

/// Get default user level
public fun default_user_level(): u8 { DEFAULT_USER_LEVEL }

/// Get maximum user level
public fun max_user_level(): u8 { MAX_USER_LEVEL }

/// Get seconds per day
public fun seconds_per_day(): u64 { SECONDS_PER_DAY }

/// Get lending allowance type
public fun allowance_type_lending(): u8 { ALLOWANCE_TYPE_LENDING }

/// Get borrowing allowance type
public fun allowance_type_borrowing(): u8 { ALLOWANCE_TYPE_BORROWING }

/// Get trading allowance type
public fun allowance_type_trading(): u8 { ALLOWANCE_TYPE_TRADING }

/// Get withdrawal allowance type
public fun allowance_type_withdrawal(): u8 { ALLOWANCE_TYPE_WITHDRAWAL }

/// Get maximum operations per window
public fun max_operations_per_window(): u64 { MAX_OPERATIONS_PER_WINDOW }

/// Get rate limit window duration
public fun rate_limit_window_ms(): u64 { RATE_LIMIT_WINDOW_MS }

/// Get maximum suspicious activities
public fun max_suspicious_activities(): u64 { MAX_SUSPICIOUS_ACTIVITIES }

/// Get suspicious activity cooldown period
public fun suspicious_activity_cooldown_ms(): u64 { SUSPICIOUS_ACTIVITY_COOLDOWN_MS }

/// Get maximum price age in seconds
public fun max_price_age_seconds(): u64 { MAX_PRICE_AGE_SECONDS }

/// Get minimum confidence threshold in basis points
public fun min_confidence_threshold_bps(): u64 { MIN_CONFIDENCE_THRESHOLD_BPS }

/// Get maximum number of price feeds
public fun max_price_feeds(): u64 { MAX_PRICE_FEEDS }

/// Get basis points denominator
public fun basis_points_denominator(): u64 { BASIS_POINTS_DENOMINATOR }

/// Get oracle price precision
public fun oracle_price_precision(): u8 { ORACLE_PRICE_PRECISION }

/// Get default liquidation threshold in basis points
public fun default_liquidation_threshold_bps(): u64 { DEFAULT_LIQUIDATION_THRESHOLD_BPS }

/// Get health factor precision
public fun health_factor_precision(): u64 { HEALTH_FACTOR_PRECISION }

/// Get minimum health factor
public fun min_health_factor(): u64 { MIN_HEALTH_FACTOR }