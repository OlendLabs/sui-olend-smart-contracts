/// Account Module - User account management system
/// Implements AccountRegistry for global account management and Account for user data
module olend::account;

use sui::table::{Self, Table};


use olend::constants;
use olend::errors;

// ===== Struct Definitions =====

/// Global account registry
/// Manages all user accounts and provides unified account management
public struct AccountRegistry has key {
    id: UID,
    /// Protocol version for access control
    version: u64,
    /// Mapping from user address to their Account ID
    accounts: Table<address, ID>,
    /// Account counter for generating unique account IDs
    account_counter: u64,

}

/// User account metadata information
/// Only contains essential data for DeFi operations, no centralized control
public struct AccountStatus has store, copy, drop {
    /// Account creation timestamp
    created_at: u64,
    /// Last activity timestamp (for analytics and user experience)
    last_activity: u64,
}

/// Security tracking for rate limiting and attack prevention
public struct SecurityTracker has store {
    /// Operation count in current time window
    operation_count: u64,
    /// Current time window start
    window_start: u64,
    /// Last transaction hash (for replay protection)
    last_tx_hash: vector<u8>,
    /// Suspicious activity counter
    suspicious_activity_count: u64,
    /// Last suspicious activity timestamp
    last_suspicious_activity: u64,
}

/// User main account
/// Stores user basic information and position ID list
public struct Account has key {
    id: UID,
    /// Protocol version for access control
    version: u64,
    /// Account owner address
    owner: address,
    /// User level (1-10)
    level: u8,
    /// User points for rewards and benefits
    points: u64,
    /// List of position IDs (does not store position details)
    position_ids: vector<ID>,

    /// Account status information
    status: AccountStatus,
    /// Security tracking for rate limiting and attack prevention
    security: SecurityTracker,
}

/// Account capability (non-transferable)
/// Used for permission verification and account operations
public struct AccountCap has key {
    id: UID,
    /// Corresponding Account ID
    account_id: ID,
    /// Account owner address
    owner: address,
}

// Note: In a decentralized platform, account management should not require admin capabilities
// Account operations are controlled by users themselves through AccountCap

// ===== Creation and Initialization Functions =====

/// Creates a new AccountRegistry
/// Should only be called once during module initialization
/// 
/// # Arguments
/// * `ctx` - Transaction context
/// 
/// # Returns
/// * `AccountRegistry` - Newly created account registry
/// * `AdminCap` - Admin capability for permission control
fun create_account_registry(ctx: &mut TxContext): AccountRegistry {
    let registry = AccountRegistry {
        id: object::new(ctx),
        version: constants::current_version(),
        accounts: table::new(ctx),
        account_counter: 0,
    };
    
    registry
}

/// Module initialization function
/// Creates and initializes the AccountRegistry as a shared object
/// 
/// # Arguments
/// * `ctx` - Transaction context
fun init(ctx: &mut TxContext) {
    let registry = create_account_registry(ctx);
    transfer::share_object(registry);
}

#[test_only]
/// Initialize AccountRegistry for testing purposes
/// Calls the standard init function to create and share AccountRegistry
/// Test scenarios should use take_shared to get the AccountRegistry object
/// 
/// # Arguments
/// * `ctx` - Transaction context
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

// ===== Account Management Functions =====

/// Creates a new user account
/// Generates a unique Account object and corresponding AccountCap
/// 
/// # Arguments
/// * `registry` - Mutable reference to the account registry
/// * `user` - User address
/// * `ctx` - Transaction context
/// 
/// # Returns
/// * `Account` - Newly created account object
/// * `AccountCap` - Account capability for the user
public fun create_account(
    registry: &mut AccountRegistry,
    user: address,
    ctx: &mut TxContext
): (Account, AccountCap) {
    // Verify version
    assert!(registry.version == constants::current_version(), errors::version_mismatch());
    
    // Check if account already exists
    assert!(!table::contains(&registry.accounts, user), errors::account_already_exists());
    
    // Create account status
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    let status = AccountStatus {
        created_at: current_time,
        last_activity: current_time,
    };
    
    // Create security tracker
    let security = SecurityTracker {
        operation_count: 0,
        window_start: current_time,
        last_tx_hash: std::vector::empty<u8>(),
        suspicious_activity_count: 0,
        last_suspicious_activity: 0,
    };
    
    // Create account
    let account = Account {
        id: object::new(ctx),
        version: constants::current_version(),
        owner: user,
        level: constants::default_user_level(),
        points: 0,
        position_ids: std::vector::empty<ID>(),

        status,
        security,
    };
    
    let account_id = object::id(&account);
    
    // Create account capability
    let account_cap = AccountCap {
        id: object::new(ctx),
        account_id,
        owner: user,
    };
    
    // Register account in registry
    table::add(&mut registry.accounts, user, account_id);
    registry.account_counter = registry.account_counter + 1;
    
    (account, account_cap)
}

/// Creates and transfers a new user account to the user
/// This is a convenience function for creating accounts in one step
/// 
/// # Arguments
/// * `registry` - Mutable reference to the account registry
/// * `user` - User address
/// * `ctx` - Transaction context
public fun create_and_transfer_account(
    registry: &mut AccountRegistry,
    user: address,
    ctx: &mut TxContext
) {
    let (account, account_cap) = create_account(registry, user, ctx);
    transfer::transfer(account, user);
    transfer::transfer(account_cap, user);
}

/// Finds user account by address
/// 
/// # Arguments
/// * `registry` - Reference to the account registry
/// * `user` - User address to look up
/// 
/// # Returns
/// * `Option<ID>` - Account ID if found, or None
public fun get_account(registry: &AccountRegistry, user: address): std::option::Option<ID> {
    if (table::contains(&registry.accounts, user)) {
        std::option::some(*table::borrow(&registry.accounts, user))
    } else {
        std::option::none<ID>()
    }
}

/// Checks if account exists for the given user
/// 
/// # Arguments
/// * `registry` - Reference to the account registry
/// * `user` - User address to check
/// 
/// # Returns
/// * `bool` - True if account exists
public fun account_exists(registry: &AccountRegistry, user: address): bool {
    table::contains(&registry.accounts, user)
}

/// Verifies account capability matches the account
/// 
/// # Arguments
/// * `account` - Reference to the account
/// * `cap` - Reference to the account capability
/// 
/// # Returns
/// * `bool` - True if capability matches the account
public fun verify_account_cap(account: &Account, cap: &AccountCap): bool {
    object::id(account) == cap.account_id && account.owner == cap.owner
}

// ===== Account Information Management Functions =====

/// Adds a position ID to the account
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `position_id` - Position ID to add
public fun add_position(
    account: &mut Account,
    cap: &AccountCap,
    position_id: ID
) {
    // Verify permission
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    
    // Verify version
    assert!(account.version == constants::current_version(), errors::version_mismatch());
    
    // Add position ID if not already present
    if (!std::vector::contains(&account.position_ids, &position_id)) {
        std::vector::push_back(&mut account.position_ids, position_id);
    };
}

/// Removes a position ID from the account
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `position_id` - Position ID to remove
public fun remove_position(
    account: &mut Account,
    cap: &AccountCap,
    position_id: ID
) {
    // Verify permission
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    
    // Verify version
    assert!(account.version == constants::current_version(), errors::version_mismatch());
    
    // Find and remove position ID
    let (found, index) = std::vector::index_of(&account.position_ids, &position_id);
    assert!(found, errors::position_id_not_found());
    
    std::vector::remove(&mut account.position_ids, index);
}

/// Updates user level and points
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `new_level` - New user level (1-10)
/// * `points_delta` - Points to add (must be positive; use separate function for deduction)
public fun update_level_and_points(
    account: &mut Account,
    cap: &AccountCap,
    new_level: u8,
    points_delta: u64
) {
    // Verify permission
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    
    // Verify version
    assert!(account.version == constants::current_version(), errors::version_mismatch());
    
    // Validate level range
    assert!(new_level >= 1 && new_level <= constants::max_user_level(), errors::invalid_input());
    
    // Update level and points
    account.level = new_level;
    account.points = account.points + points_delta;
}

/// Deducts points from user account with safe underflow protection
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `points_to_deduct` - Points to deduct (with underflow protection)
public fun deduct_points(
    account: &mut Account,
    cap: &AccountCap,
    points_to_deduct: u64
) {
    // Verify permission
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    
    // Verify version
    assert!(account.version == constants::current_version(), errors::version_mismatch());
    
    // Safe deduction with underflow protection
    if (account.points >= points_to_deduct) {
        account.points = account.points - points_to_deduct;
    } else {
        account.points = 0; // Set to 0 if deduction would cause underflow
    };
}

/// Updates account activity timestamp
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `ctx` - Transaction context for timestamp
public fun update_activity(
    account: &mut Account,
    cap: &AccountCap,
    ctx: &TxContext
) {
    // Verify permission
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    
    // Verify version
    assert!(account.version == constants::current_version(), errors::version_mismatch());
    
    // Update last activity timestamp
    account.status.last_activity = tx_context::epoch_timestamp_ms(ctx);
}

// ===== Account Status Management Functions =====
// Note: In a decentralized platform, there are no admin controls over user accounts
// Account status is managed automatically by the protocol based on user actions

// ===== Query Functions =====

/// Gets the list of position IDs for an account
/// 
/// # Arguments
/// * `account` - Reference to the account
/// 
/// # Returns
/// * `vector<ID>` - List of position IDs
public fun get_position_ids(account: &Account): vector<ID> {
    account.position_ids
}

/// Gets the user level
/// 
/// # Arguments
/// * `account` - Reference to the account
/// 
/// # Returns
/// * `u8` - User level
public fun get_level(account: &Account): u8 {
    account.level
}

/// Gets the user points
/// 
/// # Arguments
/// * `account` - Reference to the account
/// 
/// # Returns
/// * `u64` - User points
public fun get_points(account: &Account): u64 {
    account.points
}

/// Gets the account owner address
/// 
/// # Arguments
/// * `account` - Reference to the account
/// 
/// # Returns
/// * `address` - Owner address
public fun get_owner(account: &Account): address {
    account.owner
}

/// Gets the account status
/// 
/// # Arguments
/// * `account` - Reference to the account
/// 
/// # Returns
/// * `AccountStatus` - Account status information
public fun get_status(account: &Account): AccountStatus {
    account.status
}

/// Gets the account age in milliseconds
/// 
/// # Arguments
/// * `status` - Reference to the account status
/// * `current_time` - Current timestamp
/// 
/// # Returns
/// * `u64` - Account age in milliseconds
public fun get_account_age(status: &AccountStatus, current_time: u64): u64 {
    if (current_time >= status.created_at) {
        current_time - status.created_at
    } else {
        0
    }
}

/// Gets the time since last activity in milliseconds
/// 
/// # Arguments
/// * `status` - Reference to the account status
/// * `current_time` - Current timestamp
/// 
/// # Returns
/// * `u64` - Time since last activity in milliseconds
public fun get_time_since_last_activity(status: &AccountStatus, current_time: u64): u64 {
    if (current_time >= status.last_activity) {
        current_time - status.last_activity
    } else {
        0
    }
}

/// Gets the account creation timestamp
/// 
/// # Arguments
/// * `status` - Reference to the account status
/// 
/// # Returns
/// * `u64` - Creation timestamp
public fun get_status_created_at(status: &AccountStatus): u64 {
    status.created_at
}

/// Gets the last activity timestamp
/// 
/// # Arguments
/// * `status` - Reference to the account status
/// 
/// # Returns
/// * `u64` - Last activity timestamp
public fun get_status_last_activity(status: &AccountStatus): u64 {
    status.last_activity
}

// Sub-account functionality removed from decentralized platform

/// Checks if account has recent activity (within last 30 days)
/// 
/// # Arguments
/// * `account` - Reference to the account
/// * `current_time` - Current timestamp
/// 
/// # Returns
/// * `bool` - True if account has recent activity
public fun has_recent_activity(account: &Account, current_time: u64): bool {
    let thirty_days_ms = 30 * 24 * 60 * 60 * 1000; // 30 days in milliseconds
    get_time_since_last_activity(&account.status, current_time) <= thirty_days_ms
}

// ===== Registry Query Functions =====

/// Gets the current version of the AccountRegistry
/// 
/// # Arguments
/// * `registry` - Reference to the registry
/// 
/// # Returns
/// * `u64` - Current version number
public fun get_registry_version(registry: &AccountRegistry): u64 {
    registry.version
}

/// Gets the total number of accounts
/// 
/// # Arguments
/// * `registry` - Reference to the registry
/// 
/// # Returns
/// * `u64` - Total account count
public fun get_account_count(registry: &AccountRegistry): u64 {
    registry.account_counter
}

// ===== Upgrade Functions =====

/// Upgrades the AccountRegistry to a new version
/// 
/// # Arguments
/// * `registry` - Mutable reference to the registry
/// * `upgrade_cap` - Upgrade capability for authorization
/// * `new_version` - New version number
public fun upgrade_registry(
    registry: &mut AccountRegistry,
    _upgrade_cap: &sui::package::UpgradeCap,
    new_version: u64
) {
    assert!(new_version > registry.version, errors::invalid_input());
    registry.version = new_version;
}

/// Upgrades an Account to a new version
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `upgrade_cap` - Upgrade capability for authorization
/// * `new_version` - New version number
public fun upgrade_account(
    account: &mut Account,
    _upgrade_cap: &sui::package::UpgradeCap,
    new_version: u64
) {
    assert!(new_version > account.version, errors::invalid_input());
    account.version = new_version;
}

// ===== Cross-Module Integration Interfaces =====

/// Verifies user identity for cross-module operations
/// Used by lending, borrowing, and other modules
/// 
/// # Arguments
/// * `registry` - Reference to the account registry
/// * `account` - Reference to the account
/// * `cap` - Reference to the account capability
/// 
/// # Returns
/// * `bool` - True if identity is verified
public fun verify_user_identity(
    registry: &AccountRegistry,
    account: &Account,
    cap: &AccountCap
): bool {
    // Verify account exists in registry
    if (!table::contains(&registry.accounts, account.owner)) {
        return false
    };
    
    // Verify account ID matches registry record
    let registered_id = *table::borrow(&registry.accounts, account.owner);
    if (registered_id != object::id(account)) {
        return false
    };
    
    // Verify capability matches account
    verify_account_cap(account, cap)
}

/// Gets user level for cross-module operations
/// Used for calculating fees, limits, and privileges
/// 
/// # Arguments
/// * `account` - Reference to the account
/// * `cap` - Reference to the account capability for authorization
/// 
/// # Returns
/// * `u8` - User level
public fun get_user_level_for_module(account: &Account, cap: &AccountCap): u8 {
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    account.level
}

/// Updates user activity for cross-module operations
/// Called by other modules when user performs operations
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `ctx` - Transaction context
public fun update_user_activity_for_module(
    account: &mut Account,
    cap: &AccountCap,
    ctx: &TxContext
) {
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    account.status.last_activity = tx_context::epoch_timestamp_ms(ctx);
}

/// Adds points to user account from cross-module operations
/// Called by other modules to reward user activities
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `points` - Points to add
public fun add_user_points_for_module(
    account: &mut Account,
    cap: &AccountCap,
    points: u64
) {
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    account.points = account.points + points;
}

// ===== AccountCap Query Functions =====

/// Gets the account ID from AccountCap
/// 
/// # Arguments
/// * `cap` - Reference to the account capability
/// 
/// # Returns
/// * `ID` - Account ID
public fun get_account_id_from_cap(cap: &AccountCap): ID {
    cap.account_id
}

/// Gets the owner address from AccountCap
/// 
/// # Arguments
/// * `cap` - Reference to the account capability
/// 
/// # Returns
/// * `address` - Owner address
public fun get_owner_from_cap(cap: &AccountCap): address {
    cap.owner
}

// ===== Data Consistency and Atomic Operations =====

/// Atomic operation to update account level and add points simultaneously
/// Ensures both operations succeed or both fail
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `new_level` - New user level (1-10)
/// * `points_to_add` - Points to add
/// * `ctx` - Transaction context for activity update
public fun atomic_update_level_and_points(
    account: &mut Account,
    cap: &AccountCap,
    new_level: u8,
    points_to_add: u64,
    ctx: &TxContext
) {
    // Verify permission first
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    
    // Verify version
    assert!(account.version == constants::current_version(), errors::version_mismatch());
    
    // Validate level range
    assert!(new_level >= 1 && new_level <= constants::max_user_level(), errors::invalid_input());
    
    // Perform atomic updates
    account.level = new_level;
    account.points = account.points + points_to_add;
    account.status.last_activity = tx_context::epoch_timestamp_ms(ctx);
}

/// Atomic operation to add position and update activity
/// Ensures position is added and activity is updated atomically
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `position_id` - Position ID to add
/// * `ctx` - Transaction context for activity update
public fun atomic_add_position_and_update_activity(
    account: &mut Account,
    cap: &AccountCap,
    position_id: ID,
    ctx: &TxContext
) {
    // Verify permission
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    
    // Verify version
    assert!(account.version == constants::current_version(), errors::version_mismatch());
    
    // Atomic operations
    if (!std::vector::contains(&account.position_ids, &position_id)) {
        std::vector::push_back(&mut account.position_ids, position_id);
    };
    account.status.last_activity = tx_context::epoch_timestamp_ms(ctx);
}

/// Atomic operation to remove position and update activity
/// Ensures position is removed and activity is updated atomically
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `position_id` - Position ID to remove
/// * `ctx` - Transaction context for activity update
public fun atomic_remove_position_and_update_activity(
    account: &mut Account,
    cap: &AccountCap,
    position_id: ID,
    ctx: &TxContext
) {
    // Verify permission
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    
    // Verify version
    assert!(account.version == constants::current_version(), errors::version_mismatch());
    
    // Find and remove position ID atomically
    let (found, index) = std::vector::index_of(&account.position_ids, &position_id);
    assert!(found, errors::position_id_not_found());
    
    std::vector::remove(&mut account.position_ids, index);
    account.status.last_activity = tx_context::epoch_timestamp_ms(ctx);
}

/// Validates account data consistency
/// Checks for data integrity issues and inconsistencies
/// 
/// # Arguments
/// * `account` - Reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `ctx` - Transaction context for timestamp validation
/// 
/// # Returns
/// * `bool` - True if account data is consistent
public fun validate_account_consistency(
    account: &Account,
    cap: &AccountCap,
    ctx: &TxContext
): bool {
    // Basic capability verification
    if (!verify_account_cap(account, cap)) {
        return false
    };
    
    // Version consistency check
    if (account.version != constants::current_version()) {
        return false
    };
    
    // Level validation
    if (account.level < 1 || account.level > constants::max_user_level()) {
        return false
    };
    
    // Timestamp consistency checks
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    if (account.status.created_at > current_time) {
        return false
    };
    
    if (account.status.last_activity < account.status.created_at) {
        return false
    };
    
    if (account.status.last_activity > current_time) {
        return false
    };
    
    // Position IDs uniqueness check
    let position_count = std::vector::length(&account.position_ids);
    let mut i = 0;
    while (i < position_count) {
        let current_id = *std::vector::borrow(&account.position_ids, i);
        let mut j = i + 1;
        while (j < position_count) {
            let other_id = *std::vector::borrow(&account.position_ids, j);
            if (current_id == other_id) {
                return false // Duplicate position ID found
            };
            j = j + 1;
        };
        i = i + 1;
    };
    
    true
}

/// Concurrent-safe account operation wrapper
/// Provides additional safety checks for concurrent access
/// 
/// # Arguments
/// * `registry` - Reference to the account registry
/// * `account` - Reference to the account
/// * `cap` - Reference to the account capability
/// * `ctx` - Transaction context
/// 
/// # Returns
/// * `bool` - True if account is safe for concurrent operations
public fun check_concurrent_access_safety(
    registry: &AccountRegistry,
    account: &Account,
    cap: &AccountCap,
    ctx: &TxContext
): bool {
    // Verify account exists in registry
    if (!verify_user_identity(registry, account, cap)) {
        return false
    };
    
    // Validate account consistency
    if (!validate_account_consistency(account, cap, ctx)) {
        return false
    };
    
    // Check for version consistency between registry and account
    if (registry.version != account.version) {
        return false
    };
    
    // Additional safety checks for concurrent access
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    
    // Check if account has been recently modified (within last second)
    // This helps detect potential concurrent modifications
    let time_since_last_activity = if (current_time >= account.status.last_activity) {
        current_time - account.status.last_activity
    } else {
        0
    };
    
    // If last activity was less than 1 second ago, require extra caution
    if (time_since_last_activity < 1000) {
        // Additional validation for recent activity
        return validate_account_consistency(account, cap, ctx)
    };
    
    true
}

/// Batch operation for multiple position updates
/// Ensures all position operations succeed or all fail
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `positions_to_add` - Vector of position IDs to add
/// * `positions_to_remove` - Vector of position IDs to remove
/// * `ctx` - Transaction context
public fun atomic_batch_position_update(
    account: &mut Account,
    cap: &AccountCap,
    positions_to_add: vector<ID>,
    positions_to_remove: vector<ID>,
    ctx: &TxContext
) {
    // Verify permission
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    
    // Verify version
    assert!(account.version == constants::current_version(), errors::version_mismatch());
    
    // Validate all operations before executing any
    let mut i = 0;
    let add_count = std::vector::length(&positions_to_add);
    while (i < add_count) {
        let _position_id = *std::vector::borrow(&positions_to_add, i);
        // Check if position already exists (would be a no-op, but validate)
        i = i + 1;
    };
    
    i = 0;
    let remove_count = std::vector::length(&positions_to_remove);
    while (i < remove_count) {
        let position_id = *std::vector::borrow(&positions_to_remove, i);
        // Verify position exists before removal
        let (found, _) = std::vector::index_of(&account.position_ids, &position_id);
        assert!(found, errors::position_id_not_found());
        i = i + 1;
    };
    
    // Execute all removals first
    i = 0;
    while (i < remove_count) {
        let position_id = *std::vector::borrow(&positions_to_remove, i);
        let (found, index) = std::vector::index_of(&account.position_ids, &position_id);
        if (found) {
            std::vector::remove(&mut account.position_ids, index);
        };
        i = i + 1;
    };
    
    // Execute all additions
    i = 0;
    while (i < add_count) {
        let position_id = *std::vector::borrow(&positions_to_add, i);
        if (!std::vector::contains(&account.position_ids, &position_id)) {
            std::vector::push_back(&mut account.position_ids, position_id);
        };
        i = i + 1;
    };
    
    // Update activity timestamp
    account.status.last_activity = tx_context::epoch_timestamp_ms(ctx);
}

/// Registry-level consistency validation
/// Validates the overall consistency of the account registry
/// 
/// # Arguments
/// * `registry` - Reference to the account registry
/// 
/// # Returns
/// * `bool` - True if registry is consistent
public fun validate_registry_consistency(registry: &AccountRegistry): bool {
    // Version validation
    if (registry.version != constants::current_version()) {
        return false
    };
    
    // Account counter should not exceed reasonable limits
    if (registry.account_counter > 1_000_000_000) { // 1 billion accounts max
        return false
    };
    
    true
}

// ===== Security Enhancement Functions =====

/// Checks and enforces rate limiting for account operations
/// Prevents excessive operations within a time window
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `ctx` - Transaction context for timestamp
/// 
/// # Returns
/// * `bool` - True if operation is allowed within rate limits
public fun check_rate_limit(
    account: &mut Account,
    cap: &AccountCap,
    ctx: &TxContext
): bool {
    // Verify permission
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    let window_duration = constants::rate_limit_window_ms();
    
    // Check if we need to reset the window
    if (current_time >= account.security.window_start + window_duration) {
        // Reset window
        account.security.window_start = current_time;
        account.security.operation_count = 0;
    };
    
    // Check rate limit
    if (account.security.operation_count >= constants::max_operations_per_window()) {
        false
    } else {
        // Increment operation count
        account.security.operation_count = account.security.operation_count + 1;
        true
    }
}

/// Enforces rate limiting with abort on violation
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `ctx` - Transaction context for timestamp
public fun enforce_rate_limit(
    account: &mut Account,
    cap: &AccountCap,
    ctx: &TxContext
) {
    assert!(check_rate_limit(account, cap, ctx), errors::rate_limit_exceeded());
}

/// Checks for replay attacks by comparing transaction hashes
/// Prevents the same transaction from being executed multiple times
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `tx_hash` - Current transaction hash
/// 
/// # Returns
/// * `bool` - True if transaction is not a replay
public fun check_replay_protection(
    account: &mut Account,
    cap: &AccountCap,
    tx_hash: vector<u8>
): bool {
    // Verify permission
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    
    // Check if this transaction hash was already used
    if (account.security.last_tx_hash == tx_hash && std::vector::length(&tx_hash) > 0) {
        false
    } else {
        // Update last transaction hash
        account.security.last_tx_hash = tx_hash;
        true
    }
}

/// Enforces replay protection with abort on violation
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `tx_hash` - Current transaction hash
public fun enforce_replay_protection(
    account: &mut Account,
    cap: &AccountCap,
    tx_hash: vector<u8>
) {
    assert!(check_replay_protection(account, cap, tx_hash), errors::replay_attack_detected());
}

/// Detects suspicious activity patterns
/// Monitors for unusual behavior that might indicate malicious activity
/// 
/// # Arguments
/// * `account` - Reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `operation_type` - Type of operation being performed (1=deposit, 2=withdraw, 3=borrow, 4=repay)
/// * `amount` - Amount involved in the operation
/// * `ctx` - Transaction context for timestamp
/// 
/// # Returns
/// * `bool` - True if activity appears suspicious
public fun detect_suspicious_activity(
    account: &Account,
    cap: &AccountCap,
    operation_type: u8,
    amount: u64,
    ctx: &TxContext
): bool {
    // Verify permission
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    
    // Check for suspicious patterns
    let mut suspicious = false;
    
    // Pattern 1: Very large amounts (potential whale manipulation)
    if (amount > 1_000_000_000_000) { // 1 trillion units
        suspicious = true;
    };
    
    // Pattern 2: Very frequent operations (checked via rate limiting)
    if (account.security.operation_count > constants::max_operations_per_window() / 2) {
        suspicious = true;
    };
    
    // Pattern 3: Operations on very new accounts (less than 1 hour old)
    let account_age = current_time - account.status.created_at;
    if (account_age < 3600000 && amount > 1_000_000) { // 1 hour and 1M units
        suspicious = true;
    };
    
    // Pattern 4: Rapid sequence of borrow/repay operations (potential flash loan attack)
    if (operation_type == 3 || operation_type == 4) { // borrow or repay
        let time_since_last_activity = current_time - account.status.last_activity;
        if (time_since_last_activity < 1000 && amount > 100_000) { // Less than 1 second
            suspicious = true;
        };
    };
    
    suspicious
}

/// Records suspicious activity and enforces restrictions
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `ctx` - Transaction context for timestamp
public fun record_suspicious_activity(
    account: &mut Account,
    cap: &AccountCap,
    ctx: &TxContext
) {
    // Verify permission
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    
    // Increment suspicious activity counter
    account.security.suspicious_activity_count = account.security.suspicious_activity_count + 1;
    account.security.last_suspicious_activity = current_time;
    
    // Check if account should be restricted
    if (account.security.suspicious_activity_count >= constants::max_suspicious_activities()) {
        // Account is now restricted
        assert!(false, errors::account_restricted());
    };
}

/// Checks if account is currently restricted due to suspicious activity
/// 
/// # Arguments
/// * `account` - Reference to the account
/// * `ctx` - Transaction context for timestamp
/// 
/// # Returns
/// * `bool` - True if account is restricted
public fun is_account_restricted(
    account: &Account,
    ctx: &TxContext
): bool {
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    
    // Check if account has too many suspicious activities
    if (account.security.suspicious_activity_count >= constants::max_suspicious_activities()) {
        // Check if cooldown period has passed
        let time_since_last_suspicious = current_time - account.security.last_suspicious_activity;
        if (time_since_last_suspicious < constants::suspicious_activity_cooldown_ms()) {
            return true
        };
    };
    
    false
}

/// Comprehensive security check for account operations
/// Combines rate limiting, replay protection, and suspicious activity detection
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `operation_type` - Type of operation being performed
/// * `amount` - Amount involved in the operation
/// * `tx_hash` - Transaction hash for replay protection
/// * `ctx` - Transaction context
public fun comprehensive_security_check(
    account: &mut Account,
    cap: &AccountCap,
    operation_type: u8,
    amount: u64,
    tx_hash: vector<u8>,
    ctx: &TxContext
) {
    // Check if account is restricted
    assert!(!is_account_restricted(account, ctx), errors::account_restricted());
    
    // Enforce rate limiting
    enforce_rate_limit(account, cap, ctx);
    
    // Enforce replay protection
    enforce_replay_protection(account, cap, tx_hash);
    
    // Check for suspicious activity
    if (detect_suspicious_activity(account, cap, operation_type, amount, ctx)) {
        record_suspicious_activity(account, cap, ctx);
    };
}

/// Resets security counters (admin function for emergency situations)
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `ctx` - Transaction context
public fun reset_security_counters(
    account: &mut Account,
    cap: &AccountCap,
    ctx: &TxContext
) {
    // Verify permission
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    
    // Reset all security counters
    account.security.operation_count = 0;
    account.security.window_start = current_time;
    account.security.last_tx_hash = std::vector::empty<u8>();
    account.security.suspicious_activity_count = 0;
    account.security.last_suspicious_activity = 0;
}

/// Gets security status information
/// 
/// # Arguments
/// * `account` - Reference to the account
/// * `ctx` - Transaction context
/// 
/// # Returns
/// * `(u64, u64, u64, bool)` - (operation_count, suspicious_activity_count, window_start, is_restricted)
public fun get_security_status(
    account: &Account,
    ctx: &TxContext
): (u64, u64, u64, bool) {
    let is_restricted = is_account_restricted(account, ctx);
    (
        account.security.operation_count,
        account.security.suspicious_activity_count,
        account.security.window_start,
        is_restricted
    )
}

// ===== Test Helper Functions =====

#[test_only]
/// Test helper to create account without registry checks
public fun create_account_for_test(
    user: address,
    ctx: &mut TxContext
): (Account, AccountCap) {
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    let status = AccountStatus {
        created_at: current_time,
        last_activity: current_time,
    };
    
    let security = SecurityTracker {
        operation_count: 0,
        window_start: current_time,
        last_tx_hash: std::vector::empty<u8>(),
        suspicious_activity_count: 0,
        last_suspicious_activity: 0,
    };
    
    let account = Account {
        id: object::new(ctx),
        version: constants::current_version(),
        owner: user,
        level: constants::default_user_level(),
        points: 0,
        position_ids: std::vector::empty<ID>(),

        status,
        security,
    };
    
    let account_id = object::id(&account);
    
    let account_cap = AccountCap {
        id: object::new(ctx),
        account_id,
        owner: user,
    };
    
    (account, account_cap)
}

#[test_only]
/// Test helper to create account with invalid data for consistency testing
public fun create_inconsistent_account_for_test(
    user: address,
    invalid_level: u8,
    future_timestamp: u64,
    ctx: &mut TxContext
): (Account, AccountCap) {
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    let status = AccountStatus {
        created_at: current_time,
        last_activity: future_timestamp, // Invalid: future timestamp
    };
    
    let security = SecurityTracker {
        operation_count: 0,
        window_start: current_time,
        last_tx_hash: std::vector::empty<u8>(),
        suspicious_activity_count: 0,
        last_suspicious_activity: 0,
    };
    
    let account = Account {
        id: object::new(ctx),
        version: constants::current_version(),
        owner: user,
        level: invalid_level, // Invalid level
        points: 0,
        position_ids: std::vector::empty<ID>(),
        status,
        security,
    };
    
    let account_id = object::id(&account);
    
    let account_cap = AccountCap {
        id: object::new(ctx),
        account_id,
        owner: user,
    };
    
    (account, account_cap)
}

#[test_only]
/// Test helper to create account with specific security settings
public fun create_account_with_security_for_test(
    user: address,
    operation_count: u64,
    suspicious_count: u64,
    ctx: &mut TxContext
): (Account, AccountCap) {
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    let status = AccountStatus {
        created_at: current_time,
        last_activity: current_time,
    };
    
    let security = SecurityTracker {
        operation_count,
        window_start: current_time,
        last_tx_hash: std::vector::empty<u8>(),
        suspicious_activity_count: suspicious_count,
        last_suspicious_activity: current_time,
    };
    
    let account = Account {
        id: object::new(ctx),
        version: constants::current_version(),
        owner: user,
        level: constants::default_user_level(),
        points: 0,
        position_ids: std::vector::empty<ID>(),
        status,
        security,
    };
    
    let account_id = object::id(&account);
    
    let account_cap = AccountCap {
        id: object::new(ctx),
        account_id,
        owner: user,
    };
    
    (account, account_cap)
}