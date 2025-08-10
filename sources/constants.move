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

/// Default maximum price delay in seconds (30 seconds - reduced from 5 minutes for security)
const DEFAULT_MAX_PRICE_DELAY: u64 = 30;

/// Default minimum confidence requirement (95%)
const DEFAULT_MIN_CONFIDENCE: u64 = 95;

/// Default cache expiry time in seconds (1 minute)
const DEFAULT_CACHE_EXPIRY: u64 = 60;

/// Default maximum price change percentage in basis points (10%)
const DEFAULT_MAX_PRICE_CHANGE_PCT: u64 = 1000;

/// Price decimal precision (8 decimal places)
const PRICE_DECIMAL_PRECISION: u8 = 8;

/// Maximum confidence level (100%)
const MAX_CONFIDENCE_LEVEL: u64 = 100;

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

/// Get default maximum price delay
public fun default_max_price_delay(): u64 { DEFAULT_MAX_PRICE_DELAY }

/// Get default minimum confidence
public fun default_min_confidence(): u64 { DEFAULT_MIN_CONFIDENCE }

/// Get default cache expiry time
public fun default_cache_expiry(): u64 { DEFAULT_CACHE_EXPIRY }

/// Get default maximum price change percentage
public fun default_max_price_change_pct(): u64 { DEFAULT_MAX_PRICE_CHANGE_PCT }

/// Get price decimal precision
public fun price_decimal_precision(): u8 { PRICE_DECIMAL_PRECISION }

/// Get maximum confidence level
public fun max_confidence_level(): u64 { MAX_CONFIDENCE_LEVEL }