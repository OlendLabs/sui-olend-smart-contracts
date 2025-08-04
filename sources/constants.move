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

// ===== Allowance Type Constants =====

/// Lending allowance type
const ALLOWANCE_TYPE_LENDING: u8 = 1;

/// Borrowing allowance type
const ALLOWANCE_TYPE_BORROWING: u8 = 2;

/// Trading allowance type
const ALLOWANCE_TYPE_TRADING: u8 = 3;

/// Withdrawal allowance type
const ALLOWANCE_TYPE_WITHDRAWAL: u8 = 4;

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