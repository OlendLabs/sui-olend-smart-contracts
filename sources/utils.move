/// Utility functions module
/// Provides common utility functions and data structures used by the Olend platform
module olend::utils;

use olend::constants;
use sui::tx_context::TxContext;

// ===== Helper Structures =====

/// Version information structure
public struct VersionInfo has store, copy, drop {
    major: u8,
    minor: u8,
    patch: u8,
}

/// Timestamp helper structure
public struct Timestamp has store, copy, drop {
    seconds: u64,
}

// ===== Utility Functions =====

/// Create version information
public fun create_version_info(major: u8, minor: u8, patch: u8): VersionInfo {
    VersionInfo { major, minor, patch }
}

/// Get current timestamp
public fun current_timestamp(ctx: &TxContext): Timestamp {
    Timestamp { seconds: tx_context::epoch_timestamp_ms(ctx) / 1000 }
}

/// Calculate days difference between two timestamps
public fun days_difference(timestamp1: &Timestamp, timestamp2: &Timestamp): u64 {
    let diff = if (timestamp1.seconds > timestamp2.seconds) {
        timestamp1.seconds - timestamp2.seconds
    } else {
        timestamp2.seconds - timestamp1.seconds
    };
    diff / constants::seconds_per_day()
}

/// Check version compatibility
public fun is_version_compatible(current: u64, required: u64): bool {
    current >= required
}

/// Validate user level
public fun is_valid_user_level(level: u8): bool {
    level >= constants::default_user_level() && level <= constants::max_user_level()
}

/// Validate allowance type
public fun is_valid_allowance_type(allowance_type: u8): bool {
    allowance_type == constants::allowance_type_lending() ||
    allowance_type == constants::allowance_type_borrowing() ||
    allowance_type == constants::allowance_type_trading() ||
    allowance_type == constants::allowance_type_withdrawal()
}

/// Get current day number based on timestamp
public fun get_current_day(ctx: &TxContext): u64 {
    let timestamp = current_timestamp(ctx);
    timestamp.seconds / constants::seconds_per_day()
}

/// Calculate power of 10 (10^n)
public fun pow(base: u64, exp: u8): u64 {
    let mut result = 1;
    let mut i = 0;
    while (i < exp) {
        result = result * base;
        i = i + 1;
    };
    result
}

/// Verify version compatibility - throws error if incompatible
public fun verify_version(current: u64) {
    assert!(current == constants::current_version(), 1006); // EVersionMismatch
}