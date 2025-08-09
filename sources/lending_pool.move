/// Lending Pool Module - Lending pool management system
/// Implements LendingPool for asset lending with interest earning
module olend::lending_pool;

use std::type_name::{Self, TypeName};
use sui::table::{Self, Table};
use sui::coin::{Self, Coin};
use sui::clock::{Self, Clock};
use sui::event;

use olend::constants;
use olend::errors;
use olend::vault::{Self, Vault};
use olend::ytoken::{YToken};
use olend::account::{Self, Account, AccountCap};

// ===== Struct Definitions =====

/// Global lending pool registry - Shared Object for managing all lending pools
public struct LendingPoolRegistry has key {
    id: UID,
    /// Protocol version for access control
    version: u64,
    /// Mapping from pool ID to pool object ID
    pools: Table<ID, ID>,
    /// Mapping from asset type to list of pool IDs
    asset_pools: Table<TypeName, vector<ID>>,
    /// Pool counter for generating unique pool IDs
    pool_counter: u64,
    /// Admin capability ID for permission control
    admin_cap_id: ID,
}

/// Lending pool - Shared Object for business logic, does not hold assets
/// Assets are managed by the corresponding Vault<T>
public struct LendingPool<phantom T> has key {
    id: UID,
    /// Protocol version for access control
    version: u64,
    /// Unique pool ID
    pool_id: u64,
    /// Pool name for identification
    name: vector<u8>,
    /// Pool description
    description: vector<u8>,
    /// Interest rate model type (0: dynamic, 1: fixed)
    interest_model: u8,
    /// Base interest rate (in basis points, e.g., 500 = 5%)
    base_rate: u64,
    /// Interest rate slope for dynamic model (in basis points)
    rate_slope: u64,
    /// Fixed interest rate for fixed model (in basis points)
    fixed_rate: u64,
    /// Recorded total deposits for statistics and rate calculation
    total_deposits: u64,
    /// Recorded total borrowed amount for utilization calculation
    total_borrowed: u64,
    /// Liquidity reserve ratio (in basis points, e.g., 1000 = 10%)
    reserve_ratio: u64,
    /// Platform fee rate (in basis points, e.g., 1000 = 10%)
    platform_fee_rate: u64,
    /// Maximum single deposit limit
    max_deposit_limit: u64,
    /// Daily withdrawal limit
    daily_withdraw_limit: u64,
    /// Pool configuration
    config: PoolConfig,
    /// Pool statistics
    stats: PoolStats,
    /// Pool status
    status: PoolStatus,
}

/// Pool configuration parameters
public struct PoolConfig has store, copy, drop {
    /// Minimum deposit amount
    min_deposit: u64,
    /// Minimum withdrawal amount
    min_withdrawal: u64,
    /// Enable/disable deposits
    deposits_enabled: bool,
    /// Enable/disable withdrawals
    withdrawals_enabled: bool,
    /// Enable/disable interest accrual
    interest_enabled: bool,
    /// Auto-compound interest
    auto_compound: bool,
}

/// Pool statistics for monitoring and analytics
public struct PoolStats has store, copy, drop {
    /// Total number of depositors
    total_depositors: u64,
    /// Total interest paid out
    total_interest_paid: u64,
    /// Total platform fees collected
    total_fees_collected: u64,
    /// Pool creation timestamp
    created_at: u64,
    /// Last interest update timestamp
    last_interest_update: u64,
    /// Current annual percentage yield (APY) in basis points
    current_apy: u64,
}

/// Pool status enumeration
public enum PoolStatus has store, copy, drop {
    /// Pool is active and fully operational
    Active,
    /// Pool is paused - no new operations allowed
    Paused,
    /// Pool allows deposits only
    DepositsOnly,
    /// Pool allows withdrawals only
    WithdrawalsOnly,
    /// Pool is inactive/disabled
    Inactive,
}

/// Lending pool admin capability
public struct LendingPoolAdminCap has key, store {
    id: UID,
}

/// User deposit position tracking
public struct DepositPosition has key, store {
    id: UID,
    /// Position ID for tracking
    position_id: ID,
    /// Depositor account ID
    depositor_account: ID,
    /// Pool ID this position belongs to
    pool_id: u64,
    /// YToken shares held
    shares: u64,
    /// Initial deposit amount (for statistics)
    initial_deposit: u64,
    /// Deposit timestamp
    deposited_at: u64,
    /// Last interest claim timestamp
    last_claim_at: u64,
    /// Position status
    status: u8, // 0: active, 1: withdrawn
}

// ===== Events =====

/// Deposit event
public struct DepositEvent has copy, drop {
    pool_id: u64,
    depositor: address,
    asset_amount: u64,
    shares_minted: u64,
    timestamp: u64,
}

/// Withdrawal event
public struct WithdrawalEvent has copy, drop {
    pool_id: u64,
    withdrawer: address,
    shares_burned: u64,
    asset_amount: u64,
    timestamp: u64,
}

/// Interest accrual event
public struct InterestAccrualEvent has copy, drop {
    pool_id: u64,
    interest_rate: u64,
    interest_amount: u64,
    timestamp: u64,
}

/// Pool status change event
public struct PoolStatusChangeEvent has copy, drop {
    pool_id: u64,
    old_status: u8,
    new_status: u8,
    timestamp: u64,
}

// ===== Error Constants =====

/// Pool is paused
const EPoolPaused: u64 = 3002;

/// Insufficient deposit amount
const EInsufficientDeposit: u64 = 3003;

/// Insufficient withdrawal amount
const EInsufficientWithdrawal: u64 = 3004;

/// Invalid pool configuration
const EInvalidPoolConfig: u64 = 3006;

/// Deposits not allowed
const EDepositsNotAllowed: u64 = 3007;

/// Withdrawals not allowed
const EWithdrawalsNotAllowed: u64 = 3008;

/// Deposit limit exceeded
const EDepositLimitExceeded: u64 = 3009;

/// Daily withdrawal limit exceeded
const EDailyWithdrawLimitExceeded: u64 = 3010;

// ===== Interest Model Constants =====

/// Dynamic interest rate model
const INTEREST_MODEL_DYNAMIC: u8 = 0;

/// Fixed interest rate model
const INTEREST_MODEL_FIXED: u8 = 1;

/// Basis points denominator (10000 = 100%)
const BASIS_POINTS: u64 = 10000;

/// Seconds per year for APY calculation
const SECONDS_PER_YEAR: u64 = 31536000;

// ===== Creation and Initialization Functions =====

/// Initialize the lending pool system
/// Creates a shared LendingPoolRegistry and returns admin capability
public fun initialize_lending_pools(ctx: &mut TxContext): LendingPoolAdminCap {
    let admin_cap = LendingPoolAdminCap {
        id: object::new(ctx),
    };
    
    let admin_cap_id = object::id(&admin_cap);
    
    let registry = LendingPoolRegistry {
        id: object::new(ctx),
        version: constants::current_version(),
        pools: table::new(ctx),
        asset_pools: table::new(ctx),
        pool_counter: 0,
        admin_cap_id,
    };
    
    transfer::share_object(registry);
    admin_cap
}

/// Create a new lending pool
/// Creates a LendingPool<T> as a Shared Object and registers it in the registry
public fun create_lending_pool<T>(
    registry: &mut LendingPoolRegistry,
    admin_cap: &LendingPoolAdminCap,
    name: vector<u8>,
    description: vector<u8>,
    interest_model: u8,
    base_rate: u64,
    rate_slope: u64,
    fixed_rate: u64,
    max_deposit_limit: u64,
    daily_withdraw_limit: u64,
    clock: &Clock,
    ctx: &mut TxContext
): ID {
    // Verify admin permission
    assert!(object::id(admin_cap) == registry.admin_cap_id, errors::unauthorized_access());
    
    // Verify version
    assert!(registry.version == constants::current_version(), errors::version_mismatch());
    
    // Validate parameters
    assert!(!vector::is_empty(&name), EInvalidPoolConfig);
    assert!(interest_model <= INTEREST_MODEL_FIXED, EInvalidPoolConfig);
    assert!(base_rate <= BASIS_POINTS, EInvalidPoolConfig);
    assert!(rate_slope <= BASIS_POINTS, EInvalidPoolConfig);
    assert!(fixed_rate <= BASIS_POINTS, EInvalidPoolConfig);
    assert!(max_deposit_limit > 0, EInvalidPoolConfig);
    assert!(daily_withdraw_limit > 0, EInvalidPoolConfig);
    
    // Generate unique pool ID
    registry.pool_counter = registry.pool_counter + 1;
    let pool_id = registry.pool_counter;
    
    let current_time = clock::timestamp_ms(clock) / 1000;
    
    // Create pool configuration
    let config = PoolConfig {
        min_deposit: 1, // Minimum 1 unit
        min_withdrawal: 1, // Minimum 1 unit
        deposits_enabled: true,
        withdrawals_enabled: true,
        interest_enabled: true,
        auto_compound: true,
    };
    
    // Create pool statistics
    let stats = PoolStats {
        total_depositors: 0,
        total_interest_paid: 0,
        total_fees_collected: 0,
        created_at: current_time,
        last_interest_update: current_time,
        current_apy: base_rate, // Initial APY equals base rate
    };
    
    // Create lending pool
    let pool = LendingPool<T> {
        id: object::new(ctx),
        version: constants::current_version(),
        pool_id,
        name,
        description,
        interest_model,
        base_rate,
        rate_slope,
        fixed_rate,
        total_deposits: 0,
        total_borrowed: 0,
        reserve_ratio: 1000, // 10% default reserve
        platform_fee_rate: 1000, // 10% default platform fee
        max_deposit_limit,
        daily_withdraw_limit,
        config,
        stats,
        status: PoolStatus::Active,
    };
    
    let pool_object_id = object::id(&pool);
    
    // Register pool in registry
    table::add(&mut registry.pools, pool_object_id, pool_object_id);
    
    // Add to asset type mapping
    let asset_type = type_name::get<T>();
    if (table::contains(&registry.asset_pools, asset_type)) {
        let pool_list = table::borrow_mut(&mut registry.asset_pools, asset_type);
        vector::push_back(pool_list, pool_object_id);
    } else {
        let mut new_pool_list = vector::empty<ID>();
        vector::push_back(&mut new_pool_list, pool_object_id);
        table::add(&mut registry.asset_pools, asset_type, new_pool_list);
    };
    
    // Share the pool as a Shared Object
    transfer::share_object(pool);
    
    pool_object_id
}

// ===== Core Lending Functions =====

/// Deposit assets into the lending pool
/// User provides assets and receives YToken shares from the Vault
#[allow(lint(self_transfer))]
public fun deposit<T>(
    pool: &mut LendingPool<T>,
    vault: &mut Vault<T>,
    account: &mut Account,
    account_cap: &AccountCap,
    asset: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext
): Coin<YToken<T>> {
    // Verify pool version
    assert!(pool.version == constants::current_version(), errors::version_mismatch());
    
    // Verify pool status allows deposits
    assert!(pool.status != PoolStatus::Inactive, EPoolPaused);
    assert!(pool.status != PoolStatus::Paused, EPoolPaused);
    assert!(
        pool.status == PoolStatus::Active || pool.status == PoolStatus::DepositsOnly,
        EDepositsNotAllowed
    );
    
    // Verify pool configuration
    assert!(pool.config.deposits_enabled, EDepositsNotAllowed);
    
    // Verify user identity through account system
    assert!(account::verify_account_cap(account, account_cap), errors::account_cap_mismatch());
    
    let asset_amount = coin::value(&asset);
    
    // Validate deposit amount
    assert!(asset_amount > 0, errors::zero_assets());
    assert!(asset_amount >= pool.config.min_deposit, EInsufficientDeposit);
    assert!(asset_amount <= pool.max_deposit_limit, EDepositLimitExceeded);
    
    // Update interest before deposit to ensure accurate share calculation
    update_pool_interest(pool, clock);
    
    // Deposit assets into vault and get YToken shares (package-level call)
    let ytoken_coin = vault::deposit(vault, asset, ctx);
    let shares_minted = coin::value(&ytoken_coin);
    
    // Update pool statistics
    pool.total_deposits = pool.total_deposits + asset_amount;
    pool.stats.total_depositors = pool.stats.total_depositors + 1;
    
    // Update user account activity and points
    account::update_user_activity_for_module(account, account_cap, ctx);
    
    // Calculate deposit points based on amount (1 point per 1000 units)
    let deposit_points = asset_amount / 1000;
    if (deposit_points > 0) {
        account::add_user_points_for_module(account, account_cap, deposit_points);
    };
    
    // Create deposit position for tracking
    let position_uid = object::new(ctx);
    let position_id = object::uid_to_inner(&position_uid);
    let position = DepositPosition {
        id: position_uid,
        position_id,
        depositor_account: object::id(account),
        pool_id: pool.pool_id,
        shares: shares_minted,
        initial_deposit: asset_amount,
        deposited_at: clock::timestamp_ms(clock) / 1000,
        last_claim_at: clock::timestamp_ms(clock) / 1000,
        status: 0, // Active
    };
    
    // Add position to user account
    account::add_position(account, account_cap, position_id);
    
    // Transfer position to user
    transfer::public_transfer(position, tx_context::sender(ctx));
    
    // Emit deposit event
    event::emit(DepositEvent {
        pool_id: pool.pool_id,
        depositor: tx_context::sender(ctx),
        asset_amount,
        shares_minted,
        timestamp: clock::timestamp_ms(clock) / 1000,
    });
    
    ytoken_coin
}

/// Withdraw assets from the lending pool
/// User burns YToken shares and receives underlying assets from the Vault
public fun withdraw<T>(
    pool: &mut LendingPool<T>,
    vault: &mut Vault<T>,
    account: &mut Account,
    account_cap: &AccountCap,
    ytoken_coin: Coin<YToken<T>>,
    clock: &Clock,
    ctx: &mut TxContext
): Coin<T> {
    // Verify pool version
    assert!(pool.version == constants::current_version(), errors::version_mismatch());
    
    // Verify pool status allows withdrawals
    assert!(pool.status != PoolStatus::Inactive, EPoolPaused);
    assert!(pool.status != PoolStatus::Paused, EPoolPaused);
    assert!(
        pool.status == PoolStatus::Active || pool.status == PoolStatus::WithdrawalsOnly,
        EWithdrawalsNotAllowed
    );
    
    // Verify pool configuration
    assert!(pool.config.withdrawals_enabled, EWithdrawalsNotAllowed);
    
    // Verify user identity through account system
    assert!(account::verify_account_cap(account, account_cap), errors::account_cap_mismatch());
    
    let shares_to_burn = coin::value(&ytoken_coin);
    
    // Validate withdrawal amount
    assert!(shares_to_burn > 0, errors::zero_shares());
    
    // Update interest before withdrawal to ensure accurate asset calculation
    update_pool_interest(pool, clock);
    
    // Calculate asset amount to withdraw based on current vault exchange rate
    let asset_amount = vault::convert_to_assets(vault, shares_to_burn);
    assert!(asset_amount >= pool.config.min_withdrawal, EInsufficientWithdrawal);
    
    // Check daily withdrawal limit
    // Note: This is a simplified check. In production, you'd track per-user daily limits
    assert!(asset_amount <= pool.daily_withdraw_limit, EDailyWithdrawLimitExceeded);
    
    // Withdraw assets from vault (package-level call)
    let withdrawn_asset = vault::withdraw(vault, ytoken_coin, ctx);
    let actual_withdrawn = coin::value(&withdrawn_asset);
    
    // Update pool statistics
    if (pool.total_deposits >= actual_withdrawn) {
        pool.total_deposits = pool.total_deposits - actual_withdrawn;
    } else {
        pool.total_deposits = 0;
    };
    
    // Update user account activity and points
    account::update_user_activity_for_module(account, account_cap, ctx);
    
    // Calculate withdrawal points (smaller than deposit points)
    let withdrawal_points = actual_withdrawn / 2000; // 1 point per 2000 units
    if (withdrawal_points > 0) {
        account::add_user_points_for_module(account, account_cap, withdrawal_points);
    };
    
    // Emit withdrawal event
    event::emit(WithdrawalEvent {
        pool_id: pool.pool_id,
        withdrawer: tx_context::sender(ctx),
        shares_burned: shares_to_burn,
        asset_amount: actual_withdrawn,
        timestamp: clock::timestamp_ms(clock) / 1000,
    });
    
    withdrawn_asset
}

// ===== Interest Rate Management =====

/// Update pool interest based on utilization and time elapsed
/// This function calculates and applies interest accrual
public fun update_pool_interest<T>(
    pool: &mut LendingPool<T>,
    clock: &Clock,
) {
    if (!pool.config.interest_enabled) {
        return
    };
    
    let current_time = clock::timestamp_ms(clock) / 1000;
    let time_elapsed = current_time - pool.stats.last_interest_update;
    
    // Skip if less than 1 second has passed
    if (time_elapsed == 0) {
        return
    };
    
    // Calculate current interest rate based on model
    let current_rate = calculate_current_interest_rate(pool);
    
    // Calculate interest amount for the elapsed time
    let interest_amount = if (pool.total_deposits > 0) {
        // Annual rate to per-second rate: rate / SECONDS_PER_YEAR
        // Interest = principal * rate * time
        (pool.total_deposits * current_rate * time_elapsed) / (BASIS_POINTS * SECONDS_PER_YEAR)
    } else {
        0
    };
    
    if (interest_amount > 0) {
        // Update pool statistics
        pool.stats.total_interest_paid = pool.stats.total_interest_paid + interest_amount;
        pool.stats.current_apy = current_rate;
        
        // Emit interest accrual event
        event::emit(InterestAccrualEvent {
            pool_id: pool.pool_id,
            interest_rate: current_rate,
            interest_amount,
            timestamp: current_time,
        });
    };
    
    pool.stats.last_interest_update = current_time;
}

/// Calculate current interest rate based on pool's interest model
fun calculate_current_interest_rate<T>(pool: &LendingPool<T>): u64 {
    match (pool.interest_model) {
        INTEREST_MODEL_DYNAMIC => {
            // Dynamic rate: base_rate + utilization_rate * rate_slope
            let utilization_rate = if (pool.total_deposits > 0) {
                (pool.total_borrowed * BASIS_POINTS) / pool.total_deposits
            } else {
                0
            };
            
            pool.base_rate + ((utilization_rate * pool.rate_slope) / BASIS_POINTS)
        },
        INTEREST_MODEL_FIXED => {
            // Fixed rate model
            pool.fixed_rate
        },
        _ => {
            // Default to base rate for unknown models
            pool.base_rate
        }
    }
}

// ===== Pool Management Functions =====

/// Pause pool operations
public fun pause_pool<T>(
    pool: &mut LendingPool<T>,
    admin_cap: &LendingPoolAdminCap,
    clock: &Clock,
) {
    // Verify admin permission (simplified - in production, verify through registry)
    let _ = admin_cap;
    
    // Update interest before pausing
    update_pool_interest(pool, clock);
    
    let old_status = match (pool.status) {
        PoolStatus::Active => 0,
        PoolStatus::Paused => 1,
        PoolStatus::DepositsOnly => 2,
        PoolStatus::WithdrawalsOnly => 3,
        PoolStatus::Inactive => 4,
    };
    
    pool.status = PoolStatus::Paused;
    
    // Emit status change event
    event::emit(PoolStatusChangeEvent {
        pool_id: pool.pool_id,
        old_status,
        new_status: 1, // Paused
        timestamp: clock::timestamp_ms(clock) / 1000,
    });
}

/// Resume pool operations
public fun resume_pool<T>(
    pool: &mut LendingPool<T>,
    admin_cap: &LendingPoolAdminCap,
    clock: &Clock,
) {
    // Verify admin permission (simplified - in production, verify through registry)
    let _ = admin_cap;
    
    let old_status = match (pool.status) {
        PoolStatus::Active => 0,
        PoolStatus::Paused => 1,
        PoolStatus::DepositsOnly => 2,
        PoolStatus::WithdrawalsOnly => 3,
        PoolStatus::Inactive => 4,
    };
    
    pool.status = PoolStatus::Active;
    
    // Emit status change event
    event::emit(PoolStatusChangeEvent {
        pool_id: pool.pool_id,
        old_status,
        new_status: 0, // Active
        timestamp: clock::timestamp_ms(clock) / 1000,
    });
}

/// Update pool configuration
public fun update_pool_config<T>(
    pool: &mut LendingPool<T>,
    admin_cap: &LendingPoolAdminCap,
    new_config: PoolConfig,
) {
    // Verify admin permission (simplified - in production, verify through registry)
    let _ = admin_cap;
    
    // Verify version
    assert!(pool.version == constants::current_version(), errors::version_mismatch());
    
    pool.config = new_config;
}

/// Update interest rate parameters
public fun update_interest_rates<T>(
    pool: &mut LendingPool<T>,
    admin_cap: &LendingPoolAdminCap,
    base_rate: u64,
    rate_slope: u64,
    fixed_rate: u64,
    clock: &Clock,
) {
    // Verify admin permission (simplified - in production, verify through registry)
    let _ = admin_cap;
    
    // Verify version
    assert!(pool.version == constants::current_version(), errors::version_mismatch());
    
    // Validate rates
    assert!(base_rate <= BASIS_POINTS, EInvalidPoolConfig);
    assert!(rate_slope <= BASIS_POINTS, EInvalidPoolConfig);
    assert!(fixed_rate <= BASIS_POINTS, EInvalidPoolConfig);
    
    // Update interest before changing rates
    update_pool_interest(pool, clock);
    
    pool.base_rate = base_rate;
    pool.rate_slope = rate_slope;
    pool.fixed_rate = fixed_rate;
}

// ===== Query Functions =====

/// Get pool information
public fun get_pool_info<T>(pool: &LendingPool<T>): (u64, vector<u8>, u8, u64, u64, u64) {
    (
        pool.pool_id,
        pool.name,
        pool.interest_model,
        pool.base_rate,
        pool.rate_slope,
        pool.fixed_rate
    )
}

/// Get pool statistics
public fun get_pool_stats<T>(pool: &LendingPool<T>): (u64, u64, u64, u64, u64, u64) {
    (
        pool.total_deposits,
        pool.total_borrowed,
        pool.stats.total_depositors,
        pool.stats.total_interest_paid,
        pool.stats.total_fees_collected,
        pool.stats.current_apy
    )
}

/// Get pool status
public fun get_pool_status<T>(pool: &LendingPool<T>): u8 {
    match (pool.status) {
        PoolStatus::Active => 0,
        PoolStatus::Paused => 1,
        PoolStatus::DepositsOnly => 2,
        PoolStatus::WithdrawalsOnly => 3,
        PoolStatus::Inactive => 4,
    }
}

/// Get pool configuration
public fun get_pool_config<T>(pool: &LendingPool<T>): PoolConfig {
    pool.config
}

/// Calculate current utilization rate
public fun get_utilization_rate<T>(pool: &LendingPool<T>): u64 {
    if (pool.total_deposits > 0) {
        (pool.total_borrowed * BASIS_POINTS) / pool.total_deposits
    } else {
        0
    }
}

/// Get current interest rate
public fun get_current_interest_rate<T>(pool: &LendingPool<T>): u64 {
    calculate_current_interest_rate(pool)
}

/// Check if deposits are allowed
public fun deposits_allowed<T>(pool: &LendingPool<T>): bool {
    pool.config.deposits_enabled &&
    (pool.status == PoolStatus::Active || pool.status == PoolStatus::DepositsOnly)
}

/// Check if withdrawals are allowed
public fun withdrawals_allowed<T>(pool: &LendingPool<T>): bool {
    pool.config.withdrawals_enabled &&
    (pool.status == PoolStatus::Active || pool.status == PoolStatus::WithdrawalsOnly)
}

// ===== Registry Query Functions =====

/// Get pools for a specific asset type
public fun get_pools_for_asset<T>(registry: &LendingPoolRegistry): vector<ID> {
    let asset_type = type_name::get<T>();
    if (table::contains(&registry.asset_pools, asset_type)) {
        *table::borrow(&registry.asset_pools, asset_type)
    } else {
        vector::empty<ID>()
    }
}

/// Check if pool exists in registry
public fun pool_exists(registry: &LendingPoolRegistry, pool_id: ID): bool {
    table::contains(&registry.pools, pool_id)
}

/// Get total number of pools
public fun get_total_pools(registry: &LendingPoolRegistry): u64 {
    registry.pool_counter
}

/// Get registry version
public fun get_registry_version(registry: &LendingPoolRegistry): u64 {
    registry.version
}

// ===== Test Helper Functions =====

#[test_only]
/// Create a lending pool for testing without registry
public fun create_pool_for_test<T>(
    pool_id: u64,
    name: vector<u8>,
    interest_model: u8,
    base_rate: u64,
    ctx: &mut TxContext
): LendingPool<T> {
    let config = PoolConfig {
        min_deposit: 1,
        min_withdrawal: 1,
        deposits_enabled: true,
        withdrawals_enabled: true,
        interest_enabled: true,
        auto_compound: true,
    };
    
    let stats = PoolStats {
        total_depositors: 0,
        total_interest_paid: 0,
        total_fees_collected: 0,
        created_at: 0,
        last_interest_update: 0,
        current_apy: base_rate,
    };
    
    LendingPool<T> {
        id: object::new(ctx),
        version: constants::current_version(),
        pool_id,
        name,
        description: b"Test pool",
        interest_model,
        base_rate,
        rate_slope: 1000, // 10%
        fixed_rate: base_rate,
        total_deposits: 0,
        total_borrowed: 0,
        reserve_ratio: 1000, // 10%
        platform_fee_rate: 1000, // 10%
        max_deposit_limit: 1_000_000_000,
        daily_withdraw_limit: 100_000_000,
        config,
        stats,
        status: PoolStatus::Active,
    }
}

#[test_only]
/// Initialize registry for testing
public fun init_registry_for_test(ctx: &mut TxContext): (LendingPoolRegistry, LendingPoolAdminCap) {
    let admin_cap = LendingPoolAdminCap {
        id: object::new(ctx),
    };
    
    let admin_cap_id = object::id(&admin_cap);
    
    let registry = LendingPoolRegistry {
        id: object::new(ctx),
        version: constants::current_version(),
        pools: table::new(ctx),
        asset_pools: table::new(ctx),
        pool_counter: 0,
        admin_cap_id,
    };
    
    (registry, admin_cap)
}