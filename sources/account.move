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
    id: sui::object::UID,
    /// Protocol version for access control
    version: u64,
    /// Mapping from user address to their Account ID
    accounts: Table<address, sui::object::ID>,
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

/// User main account
/// Stores user basic information and position ID list
public struct Account has key {
    id: sui::object::UID,
    /// Protocol version for access control
    version: u64,
    /// Account owner address
    owner: address,
    /// User level (1-10)
    level: u8,
    /// User points for rewards and benefits
    points: u64,
    /// List of position IDs (does not store position details)
    position_ids: vector<sui::object::ID>,

    /// Account status information
    status: AccountStatus,
}

/// Account capability (non-transferable)
/// Used for permission verification and account operations
public struct AccountCap has key {
    id: sui::object::UID,
    /// Corresponding Account ID
    account_id: sui::object::ID,
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
fun create_account_registry(ctx: &mut sui::tx_context::TxContext): AccountRegistry {
    let registry = AccountRegistry {
        id: sui::object::new(ctx),
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
fun init(ctx: &mut sui::tx_context::TxContext) {
    let registry = create_account_registry(ctx);
    sui::transfer::share_object(registry);
}

#[test_only]
/// Initialize AccountRegistry for testing purposes
/// Calls the standard init function to create and share AccountRegistry
/// Test scenarios should use take_shared to get the AccountRegistry object
/// 
/// # Arguments
/// * `ctx` - Transaction context
public fun init_for_testing(ctx: &mut sui::tx_context::TxContext) {
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
    ctx: &mut sui::tx_context::TxContext
): (Account, AccountCap) {
    // Verify version
    assert!(registry.version == constants::current_version(), errors::version_mismatch());
    
    // Check if account already exists
    assert!(!table::contains(&registry.accounts, user), errors::account_already_exists());
    
    // Create account status
    let current_time = sui::tx_context::epoch_timestamp_ms(ctx);
    let status = AccountStatus {
        created_at: current_time,
        last_activity: current_time,
    };
    
    // Create account
    let account = Account {
        id: sui::object::new(ctx),
        version: constants::current_version(),
        owner: user,
        level: constants::default_user_level(),
        points: 0,
        position_ids: std::vector::empty<sui::object::ID>(),

        status,
    };
    
    let account_id = sui::object::id(&account);
    
    // Create account capability
    let account_cap = AccountCap {
        id: sui::object::new(ctx),
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
    ctx: &mut sui::tx_context::TxContext
) {
    let (account, account_cap) = create_account(registry, user, ctx);
    sui::transfer::transfer(account, user);
    sui::transfer::transfer(account_cap, user);
}

/// Finds user account by address
/// 
/// # Arguments
/// * `registry` - Reference to the account registry
/// * `user` - User address to look up
/// 
/// # Returns
/// * `Option<ID>` - Account ID if found, or None
public fun get_account(registry: &AccountRegistry, user: address): std::option::Option<sui::object::ID> {
    if (table::contains(&registry.accounts, user)) {
        std::option::some(*table::borrow(&registry.accounts, user))
    } else {
        std::option::none<sui::object::ID>()
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
    sui::object::id(account) == cap.account_id && account.owner == cap.owner
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
    position_id: sui::object::ID
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
    position_id: sui::object::ID
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
/// * `points_delta` - Points to add (can be negative for deduction)
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

/// Updates account activity timestamp
/// 
/// # Arguments
/// * `account` - Mutable reference to the account
/// * `cap` - Reference to the account capability for authorization
/// * `ctx` - Transaction context for timestamp
public fun update_activity(
    account: &mut Account,
    cap: &AccountCap,
    ctx: &sui::tx_context::TxContext
) {
    // Verify permission
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    
    // Verify version
    assert!(account.version == constants::current_version(), errors::version_mismatch());
    
    // Update last activity timestamp
    account.status.last_activity = sui::tx_context::epoch_timestamp_ms(ctx);
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
public fun get_position_ids(account: &Account): vector<sui::object::ID> {
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
    if (registered_id != sui::object::id(account)) {
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
    ctx: &sui::tx_context::TxContext
) {
    assert!(verify_account_cap(account, cap), errors::account_cap_mismatch());
    account.status.last_activity = sui::tx_context::epoch_timestamp_ms(ctx);
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
public fun get_account_id_from_cap(cap: &AccountCap): sui::object::ID {
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

// ===== Test Helper Functions =====

#[test_only]
/// Test helper to create account without registry checks
public fun create_account_for_test(
    user: address,
    ctx: &mut sui::tx_context::TxContext
): (Account, AccountCap) {
    let current_time = sui::tx_context::epoch_timestamp_ms(ctx);
    let status = AccountStatus {
        created_at: current_time,
        last_activity: current_time,
    };
    
    let account = Account {
        id: sui::object::new(ctx),
        version: constants::current_version(),
        owner: user,
        level: constants::default_user_level(),
        points: 0,
        position_ids: std::vector::empty<sui::object::ID>(),

        status,
    };
    
    let account_id = sui::object::id(&account);
    
    let account_cap = AccountCap {
        id: sui::object::new(ctx),
        account_id,
        owner: user,
    };
    
    (account, account_cap)
}