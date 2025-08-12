/// Borrowing Pool Module - Borrowing pool management system
/// Implements BorrowingPool for asset borrowing with collateral management
module olend::borrowing_pool;

use std::type_name::{Self, TypeName};
use sui::table::{Self, Table};
use sui::coin::{Self, Coin};
use sui::clock::{Self, Clock};
use sui::event;
use sui::balance;

use olend::constants;
use olend::errors;
use olend::vault::{Self, Vault};
use olend::ytoken::{YToken};
use olend::account::{Self, Account, AccountCap};
use olend::oracle::{Self, PriceOracle};
use olend::safe_math;

// ===== Struct Definitions =====

/// Global borrowing pool registry - Shared Object for managing all borrowing pools
public struct BorrowingPoolRegistry has key {
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

/// Borrowing pool - Shared Object for business logic, does not hold assets
/// Assets are managed by the corresponding Vault<T>
public struct BorrowingPool<phantom T> has key {
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
    /// Risk premium for borrowing (in basis points)
    risk_premium: u64,
    /// Fixed interest rate for fixed model (in basis points)
    fixed_rate: u64,
    /// Initial collateral ratio threshold (in basis points, e.g., 8000 = 80%)
    initial_ltv: u64,
    /// Warning collateral ratio threshold (in basis points, e.g., 9000 = 90%)
    warning_ltv: u64,
    /// Liquidation collateral ratio threshold (in basis points, e.g., 9500 = 95%)
    liquidation_ltv: u64,
    /// Recorded total borrowed amount for statistics and rate calculation
    total_borrowed: u64,
    /// Number of active positions
    active_positions: u64,
    /// Tick liquidation configuration
    tick_config: TickLiquidationConfig,
    /// High collateral ratio configuration
    high_collateral_config: HighCollateralConfig,
    /// Risk monitoring configuration
    risk_monitoring_config: RiskMonitoringConfig,
    /// Maximum single borrow limit
    max_borrow_limit: u64,
    /// Optional admin cap id for permission verification
    admin_cap_id_opt: option::Option<ID>,
    /// Pool configuration
    config: BorrowingPoolConfig,
    /// Pool statistics
    stats: BorrowingPoolStats,
    /// Pool status
    status: BorrowingPoolStatus,
}

/// Tick liquidation configuration
public struct TickLiquidationConfig has store, copy, drop {
    /// Tick size (collateral ratio interval in basis points)
    tick_size: u64,
    /// Liquidation penalty rate (in basis points)
    liquidation_penalty: u64,
    /// Liquidation reward rate (in basis points)
    liquidation_reward: u64,
    /// Maximum liquidation ratio per operation (in basis points)
    max_liquidation_ratio: u64,
}

/// High collateral ratio configuration for different asset types
public struct HighCollateralConfig has store, copy, drop {
    /// Maximum LTV for BTC (in basis points, e.g., 9700 = 97%)
    btc_max_ltv: u64,
    /// Maximum LTV for ETH (in basis points, e.g., 9500 = 95%)
    eth_max_ltv: u64,
    /// Maximum LTV for other assets (in basis points, e.g., 9000 = 90%)
    default_max_ltv: u64,
    /// User level bonus LTV (in basis points, e.g., 200 = 2% for diamond users)
    level_bonus_ltv: u64,
    /// Enable dynamic LTV adjustment based on market conditions
    dynamic_ltv_enabled: bool,
}

/// Risk monitoring configuration
public struct RiskMonitoringConfig has store, copy, drop {
    /// Price change threshold for risk alerts (in basis points)
    price_change_threshold: u64,
    /// Monitoring interval in seconds
    monitoring_interval: u64,
    /// Auto-liquidation enabled
    auto_liquidation_enabled: bool,
    /// Risk alert enabled
    risk_alert_enabled: bool,
}

/// Borrowing pool configuration parameters
public struct BorrowingPoolConfig has store, copy, drop {
    /// Minimum borrow amount
    min_borrow: u64,
    /// Minimum collateral amount
    min_collateral: u64,
    /// Enable/disable borrowing
    borrowing_enabled: bool,
    /// Enable/disable repayment
    repayment_enabled: bool,
    /// Enable/disable liquidation
    liquidation_enabled: bool,
    /// Auto-compound interest
    auto_compound: bool,
}

/// Borrowing pool statistics for monitoring and analytics
public struct BorrowingPoolStats has store, copy, drop {
    /// Total number of borrowers
    total_borrowers: u64,
    /// Total interest paid
    total_interest_paid: u64,
    /// Total liquidations performed
    total_liquidations: u64,
    /// Total liquidation penalties collected
    total_liquidation_penalties: u64,
    /// Pool creation timestamp
    created_at: u64,
    /// Last interest update timestamp
    last_interest_update: u64,
    /// Current annual percentage rate (APR) in basis points
    current_apr: u64,
}

/// Borrowing pool status enumeration
public enum BorrowingPoolStatus has store, copy, drop {
    /// Pool is active and fully operational
    Active,
    /// Pool is paused - no new operations allowed
    Paused,
    /// Pool allows borrowing only
    BorrowingOnly,
    /// Pool allows repayment only
    RepaymentOnly,
    /// Pool is inactive/disabled
    Inactive,
}

/// Borrowing pool admin capability
public struct BorrowingPoolAdminCap has key, store {
    id: UID,
}

/// Borrow position tracking individual borrowing positions
public struct BorrowPosition has key, store {
    id: UID,
    /// Position ID for tracking
    position_id: ID,
    /// Borrower account ID
    borrower_account: ID,
    /// Pool ID this position belongs to
    pool_id: u64,
    /// Collateral holder object id (shared object)
    collateral_holder_id: ID,
    /// Collateral vault id used for shares<->assets conversion checks
    collateral_vault_id: ID,
    /// Collateral amount (for single collateral type initially)
    collateral_amount: u64,
    /// Collateral type name for tracking
    collateral_type: TypeName,
    /// Borrowed amount
    borrowed_amount: u64,
    /// Accrued interest
    accrued_interest: u64,
    /// Position creation timestamp
    created_at: u64,
    /// Last interest update timestamp
    last_updated: u64,
    /// Borrowing term type (0: indefinite, 1: fixed term)
    term_type: u8,
    /// Maturity time for fixed term borrowing
    maturity_time: option::Option<u64>,
    /// Position status (0: active, 1: liquidatable, 2: liquidated, 3: closed)
    status: u8,
}

/// Collateral holder for storing YToken collateral
/// This is a separate object that holds the actual collateral tokens
public struct CollateralHolder<phantom C> has key, store {
    id: UID,
    /// Position ID this collateral belongs to
    position_id: ID,
    /// YToken collateral balance (stored inside shared object)
    collateral: balance::Balance<YToken<C>>,
}

// ===== Events =====

/// Borrow event
public struct BorrowEvent has copy, drop {
    pool_id: u64,
    borrower: address,
    collateral_amount: u64,
    borrowed_amount: u64,
    position_id: ID,
    timestamp: u64,
}

/// Repay event
public struct RepayEvent has copy, drop {
    pool_id: u64,
    borrower: address,
    repay_amount: u64,
    position_id: ID,
    timestamp: u64,
}

// LiquidationEvent removed (unused)

/// Interest accrual event
public struct InterestAccrualEvent has copy, drop {
    pool_id: u64,
    interest_rate: u64,
    total_interest: u64,
    timestamp: u64,
}

// PoolStatusChangeEvent removed (unused)

/// High collateral ratio warning event
public struct HighCollateralWarningEvent has copy, drop {
    pool_id: u64,
    position_id: ID,
    borrower: address,
    current_ltv: u64,
    warning_ltv: u64,
    timestamp: u64,
}

/// Collateral ratio update event
public struct CollateralRatioUpdateEvent has copy, drop {
    pool_id: u64,
    position_id: ID,
    borrower: address,
    old_ltv: u64,
    new_ltv: u64,
    timestamp: u64,
}

/// Risk monitoring alert event
public struct RiskMonitoringAlertEvent has copy, drop {
    pool_id: u64,
    alert_type: u8, // 0: price change, 1: high ltv, 2: liquidation risk
    position_id: option::Option<ID>,
    details: vector<u8>,
    timestamp: u64,
}

// ===== Error Constants =====

/// Pool is paused
const EPoolPaused: u64 = 4001;

/// Insufficient collateral
const EInsufficientCollateral: u64 = 4002;

/// Insufficient borrow amount
const EInsufficientBorrow: u64 = 4003;

/// Position not found
const EPositionNotFound: u64 = 4004;

/// Invalid pool configuration
const EInvalidPoolConfig: u64 = 4005;

/// Borrowing not allowed
const EBorrowingNotAllowed: u64 = 4006;

/// Repayment not allowed
const ERepaymentNotAllowed: u64 = 4007;

// Removed ELiquidationNotAllowed (unused)

/// Borrow limit exceeded
const EBorrowLimitExceeded: u64 = 4009;

/// Collateral ratio too high (unsafe)
const ECollateralRatioTooHigh: u64 = 4010;

/// Position is overdue
const EPositionOverdue: u64 = 4011;

/// Invalid term configuration
const EInvalidTerm: u64 = 4012;

// Removed liquidation-related error codes (unused)

// ===== Interest Model Constants =====

/// Dynamic interest rate model
const INTEREST_MODEL_DYNAMIC: u8 = 0;

/// Fixed interest rate model
const INTEREST_MODEL_FIXED: u8 = 1;

/// Basis points denominator (10000 = 100%)
const BASIS_POINTS: u64 = 10000;

/// Seconds per year for APR calculation
const SECONDS_PER_YEAR: u64 = 31536000;

/// Arithmetic overflow error
const EArithmeticOverflow: u64 = 4013;

/// Invalid vault exchange rate
const EInvalidExchangeRate: u64 = 4014;

/// Position status constants
const POSITION_STATUS_ACTIVE: u8 = 0;
const POSITION_STATUS_CLOSED: u8 = 3;

/// Term type constants
const TERM_TYPE_INDEFINITE: u8 = 0;
const TERM_TYPE_FIXED: u8 = 1;

/// Maximum reasonable exchange rate (10x) to prevent manipulation
const MAX_REASONABLE_EXCHANGE_RATE: u64 = 10_0000_0000; // 10.0 with 8 decimal places

/// Minimum reasonable exchange rate (0.1x) to prevent manipulation  
const MIN_REASONABLE_EXCHANGE_RATE: u64 = 10000000; // 0.1 with 8 decimal places

/// Grace period for overdue positions (7 days in seconds)
const OVERDUE_GRACE_PERIOD: u64 = 604800;

/// Overdue penalty rate (in basis points, e.g., 500 = 5% annual)
const OVERDUE_PENALTY_RATE: u64 = 500;

// ===== Helper Functions =====

/// Calculate 10^n for price scaling
fun pow10(n: u8): u64 {
    let mut result = 1;
    let mut i = 0;
    while (i < n) {
        result = result * 10;
        i = i + 1;
    };
    result
}

/// Validate vault exchange rate to prevent manipulation
/// Checks that the exchange rate is within reasonable bounds
fun validate_vault_exchange_rate<C>(vault: &Vault<C>, collateral_amount: u64): u64 {
    // Get vault statistics for exchange rate calculation
    let total_assets = vault::total_assets(vault);
    let total_shares = vault::total_supply(vault);
    
    // Avoid division by zero
    if (total_shares == 0) {
        return 0
    };
    
    // Calculate exchange rate: assets per share (scaled by 8 decimal places)
    let exchange_rate = if (total_assets > 0) {
        safe_math::safe_mul_div(total_assets, 100000000, total_shares) // Scale by 10^8 for precision
    } else {
        100000000 // 1.0 when no assets
    };
    
    // Validate exchange rate is within reasonable bounds
    assert!(exchange_rate >= MIN_REASONABLE_EXCHANGE_RATE, EInvalidExchangeRate);
    assert!(exchange_rate <= MAX_REASONABLE_EXCHANGE_RATE, EInvalidExchangeRate);
    
    // Convert collateral shares to assets using validated rate
    let collateral_assets = vault::convert_to_assets(vault, collateral_amount);
    
    // Additional sanity check: conversion should be consistent with rate
    let expected_assets = safe_math::safe_mul_div(collateral_amount, exchange_rate, 100000000);
    let rate_tolerance = safe_math::safe_div(expected_assets, 100); // 1% tolerance
    assert!(
        collateral_assets >= safe_math::safe_sub(expected_assets, rate_tolerance) && 
        collateral_assets <= safe_math::safe_add(expected_assets, rate_tolerance),
        EInvalidExchangeRate
    );
    
    collateral_assets
}

// ===== Creation and Initialization Functions =====

/// Creates a new BorrowingPoolRegistry and its admin capability (not shared)
/// Returns both so that callers can decide whether to publish or transfer
fun create_registry(ctx: &mut TxContext): (BorrowingPoolRegistry, BorrowingPoolAdminCap) {
    let admin_cap = BorrowingPoolAdminCap {
        id: object::new(ctx),
    };
    let admin_cap_id = object::id(&admin_cap);

    let registry = BorrowingPoolRegistry {
        id: object::new(ctx),
        version: constants::current_version(),
        pools: table::new(ctx),
        asset_pools: table::new(ctx),
        pool_counter: 0,
        admin_cap_id,
    };

    (registry, admin_cap)
}

/// Module initialization function
/// Creates and shares the BorrowingPoolRegistry, and transfers admin cap to sender
fun init(ctx: &mut TxContext) {
    let (registry, admin_cap) = create_registry(ctx);
    transfer::share_object(registry);
    transfer::transfer(admin_cap, tx_context::sender(ctx));
}

#[test_only]
/// Initialize BorrowingPoolRegistry for testing
/// Shares the registry and transfers admin cap to the test sender
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

/// Create a new borrowing pool
/// Creates a BorrowingPool<T> as a Shared Object and registers it in the registry
public fun create_borrowing_pool<T>(
    registry: &mut BorrowingPoolRegistry,
    admin_cap: &BorrowingPoolAdminCap,
    name: vector<u8>,
    description: vector<u8>,
    interest_model: u8,
    base_rate: u64,
    rate_slope: u64,
    risk_premium: u64,
    fixed_rate: u64,
    initial_ltv: u64,
    warning_ltv: u64,
    liquidation_ltv: u64,
    max_borrow_limit: u64,
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
    assert!(risk_premium <= BASIS_POINTS, EInvalidPoolConfig);
    assert!(fixed_rate <= BASIS_POINTS, EInvalidPoolConfig);
    assert!(initial_ltv < warning_ltv, EInvalidPoolConfig);
    assert!(warning_ltv < liquidation_ltv, EInvalidPoolConfig);
    assert!(liquidation_ltv <= BASIS_POINTS, EInvalidPoolConfig);
    assert!(max_borrow_limit > 0, EInvalidPoolConfig);
    
    // Generate unique pool ID
    registry.pool_counter = registry.pool_counter + 1;
    let pool_id = registry.pool_counter;
    
    let current_time = safe_math::safe_div(clock::timestamp_ms(clock), 1000);
    
    // Create tick liquidation configuration
    let tick_config = TickLiquidationConfig {
        tick_size: 50, // 0.5% tick size
        liquidation_penalty: 10, // 0.1% penalty
        liquidation_reward: 5, // 0.05% reward
        max_liquidation_ratio: 1000, // 10% max liquidation per operation
    };
    
    // Create high collateral configuration
    let high_collateral_config = HighCollateralConfig {
        btc_max_ltv: 9700, // 97% for BTC
        eth_max_ltv: 9500, // 95% for ETH
        default_max_ltv: 9000, // 90% for other assets
        level_bonus_ltv: 200, // 2% bonus for high-level users
        dynamic_ltv_enabled: true,
    };
    
    // Create risk monitoring configuration
    let risk_monitoring_config = RiskMonitoringConfig {
        price_change_threshold: 500, // 5% price change threshold
        monitoring_interval: 300, // 5 minutes
        auto_liquidation_enabled: true,
        risk_alert_enabled: true,
    };
    
    // Create pool configuration
    let config = BorrowingPoolConfig {
        min_borrow: 1, // Minimum 1 unit
        min_collateral: 1, // Minimum 1 unit
        borrowing_enabled: true,
        repayment_enabled: true,
        liquidation_enabled: true,
        auto_compound: true,
    };
    
    // Create pool statistics
    let stats = BorrowingPoolStats {
        total_borrowers: 0,
        total_interest_paid: 0,
        total_liquidations: 0,
        total_liquidation_penalties: 0,
        created_at: current_time,
        last_interest_update: current_time,
        current_apr: base_rate + risk_premium, // Initial APR
    };
    
    // Create borrowing pool
    let pool = BorrowingPool<T> {
        id: object::new(ctx),
        version: constants::current_version(),
        pool_id,
        name,
        description,
        interest_model,
        base_rate,
        rate_slope,
        risk_premium,
        fixed_rate,
        initial_ltv,
        warning_ltv,
        liquidation_ltv,
        total_borrowed: 0,
        active_positions: 0,
        tick_config,
        high_collateral_config,
        risk_monitoring_config,
        max_borrow_limit,
        admin_cap_id_opt: option::some(object::id(admin_cap)),
        config,
        stats,
        status: BorrowingPoolStatus::Active,
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

// ===== High Collateral Ratio Management Functions =====

/// Calculate the maximum LTV for a specific asset type and user level
public fun calculate_max_ltv_for_asset<T, C>(
    pool: &BorrowingPool<T>,
    account: &Account,
) : u64 {
    let base_max_ltv = get_asset_max_ltv<T, C>(pool);
    
    // Apply user level bonus if enabled
    if (pool.high_collateral_config.dynamic_ltv_enabled) {
        let user_level = account::get_level(account);
        let level_bonus = calculate_level_bonus_ltv(user_level, pool.high_collateral_config.level_bonus_ltv);
        safe_math::safe_add(base_max_ltv, level_bonus)
    } else {
        base_max_ltv
    }
}

/// Get the base maximum LTV for a specific asset type
fun get_asset_max_ltv<T, C>(pool: &BorrowingPool<T>): u64 {
    let asset_type = type_name::get<C>();
    let asset_name_bytes = std::ascii::into_bytes(type_name::into_string(asset_type));
    
    // Check if it's BTC
    if (vector::length(&asset_name_bytes) >= 3) {
        let btc_check = b"BTC";
        if (contains_substring(&asset_name_bytes, &btc_check)) {
            return pool.high_collateral_config.btc_max_ltv
        };
    };
    
    // Check if it's ETH
    if (vector::length(&asset_name_bytes) >= 3) {
        let eth_check = b"ETH";
        if (contains_substring(&asset_name_bytes, &eth_check)) {
            return pool.high_collateral_config.eth_max_ltv
        };
    };
    
    // Default for other assets
    pool.high_collateral_config.default_max_ltv
}

/// Calculate level bonus LTV based on user level
fun calculate_level_bonus_ltv(user_level: u8, max_bonus: u64): u64 {
    // Level 0-2: No bonus
    // Level 3-4: 50% of max bonus (1% if max is 2%)
    // Level 5+: Full bonus (2% if max is 2%)
    if (user_level >= 5) {
        max_bonus
    } else if (user_level >= 3) {
        max_bonus / 2
    } else {
        0
    }
}

/// Check if a substring exists in a vector<u8>
fun contains_substring(haystack: &vector<u8>, needle: &vector<u8>): bool {
    let haystack_len = vector::length(haystack);
    let needle_len = vector::length(needle);
    
    if (needle_len > haystack_len) {
        return false
    };
    
    let mut i = 0;
    while (i <= haystack_len - needle_len) {
        let mut j = 0;
        let mut found = true;
        
        while (j < needle_len) {
            if (*vector::borrow(haystack, i + j) != *vector::borrow(needle, j)) {
                found = false;
                break
            };
            j = j + 1;
        };
        
        if (found) {
            return true
        };
        i = i + 1;
    };
    
    false
}

/// Calculate current collateral ratio for a position
public fun calculate_position_ltv<T, C>(
    _pool: &BorrowingPool<T>,
    position: &BorrowPosition,
    collateral_vault: &Vault<C>,
    oracle: &PriceOracle,
    clock: &Clock,
): u64 {
    // Get current prices
    let borrow_asset_price_info = oracle::get_price<T>(oracle, clock);
    let collateral_asset_price_info = oracle::get_price<C>(oracle, clock);
    
    // Verify price data is valid and fresh
    assert!(oracle::price_info_is_valid(&borrow_asset_price_info), errors::price_validation_failed());
    assert!(oracle::price_info_is_valid(&collateral_asset_price_info), errors::price_validation_failed());
    
    let now = safe_math::safe_div(clock::timestamp_ms(clock), 1000);
    let borrow_price_time = oracle::price_info_timestamp(&borrow_asset_price_info);
    let collateral_price_time = oracle::price_info_timestamp(&collateral_asset_price_info);
    assert!(safe_math::safe_sub(now, borrow_price_time) <= constants::default_max_price_delay(), errors::price_validation_failed());
    assert!(safe_math::safe_sub(now, collateral_price_time) <= constants::default_max_price_delay(), errors::price_validation_failed());
    
    let borrow_asset_price_raw = oracle::price_info_price(&borrow_asset_price_info);
    let collateral_asset_price_raw = oracle::price_info_price(&collateral_asset_price_info);
    let borrow_conf = oracle::price_info_confidence(&borrow_asset_price_info);
    let collateral_conf = oracle::price_info_confidence(&collateral_asset_price_info);
    
    // Apply conservative discount using confidence interval
    let borrow_asset_price = if (borrow_asset_price_raw > borrow_conf) { borrow_asset_price_raw - borrow_conf } else { 0 };
    let collateral_asset_price = if (collateral_asset_price_raw > collateral_conf) { collateral_asset_price_raw - collateral_conf } else { 0 };
    assert!(borrow_asset_price > 0 && collateral_asset_price > 0, errors::price_validation_failed());
    
    // Convert YToken shares to underlying asset amount with exchange rate validation
    let collateral_assets = validate_vault_exchange_rate(collateral_vault, position.collateral_amount);
    assert!(collateral_assets > 0, EInsufficientCollateral);
    
    // Calculate total debt (principal + accrued interest) with overflow protection
    let total_debt = safe_math::safe_add(position.borrowed_amount, position.accrued_interest);
    
    // Price scale based on oracle price precision
    let price_scale: u64 = pow10(constants::price_decimal_precision());
    
    // Calculate values in USD with overflow protection
    let collateral_value_usd = safe_math::safe_mul_div(collateral_assets, collateral_asset_price, price_scale);
    let debt_value_usd = safe_math::safe_mul_div(total_debt, borrow_asset_price, price_scale);
    
    // Avoid division by zero
    assert!(collateral_value_usd > 0, EInsufficientCollateral);
    
    // Calculate LTV: debt_value / collateral_value * 100% with overflow protection
    safe_math::safe_mul_div(debt_value_usd, BASIS_POINTS, collateral_value_usd)
}

/// Monitor position risk and emit warnings if necessary
public fun monitor_position_risk<T, C>(
    pool: &BorrowingPool<T>,
    position: &BorrowPosition,
    collateral_vault: &Vault<C>,
    oracle: &PriceOracle,
    clock: &Clock,
) {
    if (!pool.risk_monitoring_config.risk_alert_enabled) {
        return
    };
    
    let current_ltv = calculate_position_ltv<T, C>(pool, position, collateral_vault, oracle, clock);
    let timestamp = safe_math::safe_div(clock::timestamp_ms(clock), 1000);
    
    // Check if position is approaching warning threshold
    if (current_ltv >= pool.warning_ltv && current_ltv < pool.liquidation_ltv) {
        event::emit(HighCollateralWarningEvent {
            pool_id: pool.pool_id,
            position_id: position.position_id,
            borrower: object::id_to_address(&position.borrower_account),
            current_ltv,
            warning_ltv: pool.warning_ltv,
            timestamp,
        });
    };
    
    // Check if position is at liquidation risk
    if (current_ltv >= pool.liquidation_ltv) {
        event::emit(RiskMonitoringAlertEvent {
            pool_id: pool.pool_id,
            alert_type: 2, // liquidation risk
            position_id: option::some(position.position_id),
            details: b"Position at liquidation risk",
            timestamp,
        });
    };
}

/// Update position LTV and emit events if significant change
public fun update_position_ltv_tracking<T, C>(
    pool: &BorrowingPool<T>,
    position: &mut BorrowPosition,
    collateral_vault: &Vault<C>,
    oracle: &PriceOracle,
    clock: &Clock,
) {
    let old_ltv = if (position.borrowed_amount > 0) {
        // Calculate old LTV based on stored values (approximation)
        let old_debt = position.borrowed_amount + position.accrued_interest;
        let collateral_assets = vault::convert_to_assets(collateral_vault, position.collateral_amount);
        if (collateral_assets > 0) {
            safe_math::safe_mul_div(old_debt, BASIS_POINTS, collateral_assets) // Simplified calculation
        } else {
            0
        }
    } else {
        0
    };
    
    let new_ltv = calculate_position_ltv<T, C>(pool, position, collateral_vault, oracle, clock);
    
    // Emit event if LTV changed significantly (more than 1%)
    if (new_ltv > old_ltv + 100 || old_ltv > new_ltv + 100) {
        event::emit(CollateralRatioUpdateEvent {
            pool_id: pool.pool_id,
            position_id: position.position_id,
            borrower: object::id_to_address(&position.borrower_account),
            old_ltv,
            new_ltv,
            timestamp: safe_math::safe_div(clock::timestamp_ms(clock), 1000),
        });
    };
    
    // Monitor risk
    monitor_position_risk<T, C>(pool, position, collateral_vault, oracle, clock);
}

// ===== Core Borrowing Functions =====

/// Borrow assets from the pool using YToken collateral
/// Creates a new borrow position or updates existing one
public fun borrow<T, C>(
    pool: &mut BorrowingPool<T>,
    borrow_vault: &mut Vault<T>,
    collateral_vault: &mut Vault<C>,
    account: &mut Account,
    account_cap: &AccountCap,
    collateral: Coin<YToken<C>>,
    borrow_amount: u64,
    oracle: &PriceOracle,
    clock: &Clock,
    ctx: &mut TxContext
): (Coin<T>, BorrowPosition) {
    // Verify pool version
    assert!(pool.version == constants::current_version(), errors::version_mismatch());
    
    // Verify pool status allows borrowing
    assert!(pool.status != BorrowingPoolStatus::Inactive, EPoolPaused);
    assert!(pool.status != BorrowingPoolStatus::Paused, EPoolPaused);
    assert!(
        pool.status == BorrowingPoolStatus::Active || pool.status == BorrowingPoolStatus::BorrowingOnly,
        EBorrowingNotAllowed
    );
    
    // Verify pool configuration
    assert!(pool.config.borrowing_enabled, EBorrowingNotAllowed);
    
    // Verify user identity through account system
    assert!(account::verify_account_cap(account, account_cap), errors::account_cap_mismatch());
    // Ensure collateral vault is active for valid conversion
    assert!(vault::is_vault_active(collateral_vault), errors::invalid_assets());
    
    // Collateral in shares (YToken amount)
    let collateral_amount = coin::value(&collateral);
    
    // Validate input amounts
    assert!(borrow_amount > 0, errors::zero_assets());
    assert!(borrow_amount >= pool.config.min_borrow, EInsufficientBorrow);
    assert!(borrow_amount <= pool.max_borrow_limit, EBorrowLimitExceeded);
    assert!(collateral_amount > 0, errors::zero_assets());
    assert!(collateral_amount >= pool.config.min_collateral, EInsufficientCollateral);
    
    // Update interest before borrowing
    update_pool_interest(pool, clock);
    
    // Get asset prices from oracle
    let borrow_asset_price_info = oracle::get_price<T>(oracle, clock);
    let collateral_asset_price_info = oracle::get_price<C>(oracle, clock);
    
    // Verify price data is valid
    assert!(oracle::price_info_is_valid(&borrow_asset_price_info), errors::price_validation_failed());
    assert!(oracle::price_info_is_valid(&collateral_asset_price_info), errors::price_validation_failed());
    
    // Freshness check using default max delay to avoid stale data
    let now = safe_math::safe_div(clock::timestamp_ms(clock), 1000);
    let borrow_price_time = oracle::price_info_timestamp(&borrow_asset_price_info);
    let collateral_price_time = oracle::price_info_timestamp(&collateral_asset_price_info);
    assert!(safe_math::safe_sub(now, borrow_price_time) <= constants::default_max_price_delay(), errors::price_validation_failed());
    assert!(safe_math::safe_sub(now, collateral_price_time) <= constants::default_max_price_delay(), errors::price_validation_failed());
    
    let borrow_asset_price_raw = oracle::price_info_price(&borrow_asset_price_info);
    let collateral_asset_price_raw = oracle::price_info_price(&collateral_asset_price_info);
    let borrow_conf = oracle::price_info_confidence(&borrow_asset_price_info);
    let collateral_conf = oracle::price_info_confidence(&collateral_asset_price_info);
    
    // Apply conservative discount using confidence interval
    let borrow_asset_price = if (borrow_asset_price_raw > borrow_conf) { borrow_asset_price_raw - borrow_conf } else { 0 };
    let collateral_asset_price = if (collateral_asset_price_raw > collateral_conf) { collateral_asset_price_raw - collateral_conf } else { 0 };
    assert!(borrow_asset_price > 0 && collateral_asset_price > 0, errors::price_validation_failed());
    
    // Convert YToken shares to underlying asset amount with exchange rate validation
    let collateral_assets = validate_vault_exchange_rate(collateral_vault, collateral_amount);
    // Ensure conversion yielded non-zero assets to avoid division by zero and false safety
    assert!(collateral_assets > 0, EInsufficientCollateral);
    
    // Price scale based on oracle price precision
    let price_scale: u64 = pow10(constants::price_decimal_precision());
    
    // Calculate collateral value and borrow value in USD using safe order to reduce overflow risk
    let collateral_value_usd = safe_math::safe_mul_div(collateral_assets, collateral_asset_price, price_scale);
    let borrow_value_usd = safe_math::safe_mul_div(borrow_amount, borrow_asset_price, price_scale);
    // Avoid division by zero in LTV calculation
    assert!(collateral_value_usd > 0, EInsufficientCollateral);
    
    // Calculate collateral ratio (LTV) with overflow protection
    let collateral_ratio = safe_math::safe_mul_div(borrow_value_usd, BASIS_POINTS, collateral_value_usd);
    
    // Calculate maximum allowed LTV for this asset type and user level
    let max_allowed_ltv = calculate_max_ltv_for_asset<T, C>(pool, account);
    
    // Verify collateral ratio is within safe limits (use the higher of initial_ltv or max_allowed_ltv)
    let effective_max_ltv = if (max_allowed_ltv > pool.initial_ltv) { max_allowed_ltv } else { pool.initial_ltv };
    assert!(collateral_ratio <= effective_max_ltv, ECollateralRatioTooHigh);
    
    // Borrow assets from vault (package-level call)
    let borrowed_asset = vault::borrow(borrow_vault, borrow_amount, ctx);
    
    // Create borrow position first (to bind collateral holder)
    let position_uid = object::new(ctx);
    let position_id = object::uid_to_inner(&position_uid);
    
    // Move collateral coin into a balance stored in a shared holder object
    let collateral_balance = coin::into_balance(collateral);
    let collateral_holder = CollateralHolder<C> {
        id: object::new(ctx),
        position_id,
        collateral: collateral_balance,
    };
    let collateral_holder_id = object::id(&collateral_holder);
    
    // Share the collateral holder as a shared object managed by protocol
    transfer::share_object(collateral_holder);
    
    // Create borrow position with reference to the collateral holder id
    let position = BorrowPosition {
        id: position_uid,
        position_id,
        borrower_account: object::id(account),
        pool_id: pool.pool_id,
        collateral_holder_id: collateral_holder_id,
        collateral_vault_id: object::id(collateral_vault),
        collateral_amount,
        collateral_type: type_name::get<C>(),
        borrowed_amount: borrow_amount,
        accrued_interest: 0,
        created_at: safe_math::safe_div(clock::timestamp_ms(clock), 1000),
        last_updated: safe_math::safe_div(clock::timestamp_ms(clock), 1000),
        term_type: TERM_TYPE_INDEFINITE,
        maturity_time: option::none(),
        status: POSITION_STATUS_ACTIVE,
    };
    
    // Update pool statistics with overflow protection
    pool.total_borrowed = safe_math::safe_add(pool.total_borrowed, borrow_amount);
    pool.active_positions = safe_math::safe_add(pool.active_positions, 1);
    pool.stats.total_borrowers = safe_math::safe_add(pool.stats.total_borrowers, 1);
    
    // Update user account activity and points
    account::update_user_activity_for_module(account, account_cap, ctx);
    
    // Calculate borrowing points based on amount and user level with safe division
    let base_borrow_points = safe_math::safe_div(borrow_amount, 1000); // 1 point per 1000 units
    let user_level = account::get_level(account);
    let level_bonus_points = calculate_level_bonus_points(user_level, base_borrow_points);
    let total_borrow_points = safe_math::safe_add(base_borrow_points, level_bonus_points);
    
    if (total_borrow_points > 0) {
        account::add_user_points_for_module(account, account_cap, total_borrow_points);
    };
    
    // Add position to user account
    account::add_position(account, account_cap, position_id);
    
    // Emit borrow event
    event::emit(BorrowEvent {
        pool_id: pool.pool_id,
        borrower: tx_context::sender(ctx),
        collateral_amount,
        borrowed_amount: borrow_amount,
        position_id,
        timestamp: safe_math::safe_div(clock::timestamp_ms(clock), 1000),
    });
    
    (borrowed_asset, position)
}

/// Borrow assets with fixed term (definite period)
/// Creates a new fixed-term borrow position
public fun borrow_fixed_term<T, C>(
    pool: &mut BorrowingPool<T>,
    borrow_vault: &mut Vault<T>,
    collateral_vault: &mut Vault<C>,
    account: &mut Account,
    account_cap: &AccountCap,
    collateral: Coin<YToken<C>>,
    borrow_amount: u64,
    term_days: u64, // Borrowing term in days
    oracle: &PriceOracle,
    clock: &Clock,
    ctx: &mut TxContext
): (Coin<T>, BorrowPosition) {
    // Validate term days (minimum 1 day, maximum 365 days)
    assert!(term_days >= 1 && term_days <= 365, EInvalidPoolConfig);
    
    // Call the regular borrow function first
    let (borrowed_asset, mut position) = borrow<T, C>(
        pool, borrow_vault, collateral_vault, account, account_cap,
        collateral, borrow_amount, oracle, clock, ctx
    );
    
    // Update position to fixed term
    let current_time = safe_math::safe_div(clock::timestamp_ms(clock), 1000);
    let maturity_time = safe_math::safe_add(current_time, safe_math::safe_mul(term_days, 86400)); // Convert days to seconds
    
    position.term_type = TERM_TYPE_FIXED;
    position.maturity_time = option::some(maturity_time);
    
    (borrowed_asset, position)
}

/// Claim collateral after the position is fully repaid (status == CLOSED)
/// Caller must be the original borrower and must provide the correct collateral holder
public fun claim_collateral<C>(
    account: &mut Account,
    account_cap: &AccountCap,
    position: &mut BorrowPosition,
    collateral_holder: &mut CollateralHolder<C>,
    collateral_vault: &Vault<C>,
    ctx: &mut TxContext
): Coin<YToken<C>> {
    // Verify caller identity
    assert!(account::verify_account_cap(account, account_cap), errors::account_cap_mismatch());
    // Position ownership and status checks
    assert!(position.borrower_account == object::id(account), errors::unauthorized_operation());
    assert!(position.status == POSITION_STATUS_CLOSED, errors::unauthorized_operation());
    // Ensure the provided holder matches the position
    assert!(position.collateral_holder_id == object::id(collateral_holder), errors::unauthorized_operation());
    // Ensure the provided vault matches the one used at borrow time
    assert!(position.collateral_vault_id == object::id(collateral_vault), errors::unauthorized_operation());
    // Ensure type matches stored collateral type
    assert!(position.collateral_type == type_name::get<C>(), errors::unauthorized_operation());

    // Withdraw entire collateral balance and return as Coin back to caller
    let shares = balance::value(&collateral_holder.collateral);
    // Ensure shares equal to originally locked shares
    assert!(shares == position.collateral_amount, errors::invalid_assets());
    let withdraw_balance = balance::split(&mut collateral_holder.collateral, shares);
    let collateral_coin = coin::from_balance(withdraw_balance, ctx);
    collateral_coin
}

/// Convenience function: repay full debt and immediately claim original YToken collateral
/// Requires providing the concrete collateral type and holder
public fun repay_and_claim<T, C>(
    pool: &mut BorrowingPool<T>,
    vault: &mut Vault<T>,
    account: &mut Account,
    account_cap: &AccountCap,
    position: &mut BorrowPosition,
    collateral_holder: &mut CollateralHolder<C>,
    collateral_vault: &Vault<C>,
    repay_asset: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<YToken<C>> {
    let closed = repay<T>(pool, vault, account, account_cap, position, repay_asset, clock, ctx);
    assert!(closed, errors::operation_denied());
    claim_collateral<C>(account, account_cap, position, collateral_holder, collateral_vault, ctx)
}

/// Repay borrowed assets and retrieve collateral
/// Supports partial and full repayment
public fun repay<T>(
    pool: &mut BorrowingPool<T>,
    vault: &mut Vault<T>,
    account: &mut Account,
    account_cap: &AccountCap,
    position: &mut BorrowPosition,
    repay_asset: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext
): bool {
    // Verify pool version
    assert!(pool.version == constants::current_version(), errors::version_mismatch());
    
    // Verify pool status allows repayment
    assert!(pool.status != BorrowingPoolStatus::Inactive, EPoolPaused);
    assert!(pool.status != BorrowingPoolStatus::Paused, EPoolPaused);
    assert!(
        pool.status == BorrowingPoolStatus::Active || pool.status == BorrowingPoolStatus::RepaymentOnly,
        ERepaymentNotAllowed
    );
    
    // Verify pool configuration
    assert!(pool.config.repayment_enabled, ERepaymentNotAllowed);
    
    // Verify user identity and position ownership
    assert!(account::verify_account_cap(account, account_cap), errors::account_cap_mismatch());
    assert!(position.borrower_account == object::id(account), errors::unauthorized_operation());
    assert!(position.pool_id == pool.pool_id, EPositionNotFound);
    assert!(position.status == POSITION_STATUS_ACTIVE, EPositionNotFound);
    
    let repay_amount = coin::value(&repay_asset);
    assert!(repay_amount > 0, errors::zero_assets());
    
    // Update interest before repayment
    update_pool_interest(pool, clock);
    update_position_interest_with_level_discount(position, pool, account, clock);
    
    // Apply overdue penalty and deduct credit points if position is overdue
    apply_overdue_penalty_with_account(position, account, account_cap, clock);
    
    // Snapshot amounts before mutation
    let original_principal = position.borrowed_amount;
    let original_interest = position.accrued_interest;
    // Calculate total debt (principal + accrued interest) with overflow protection
    let total_debt = safe_math::safe_add(original_principal, original_interest);
    
    // Determine actual repayment amount (cannot exceed total debt)
    let actual_repay_amount = if (repay_amount >= total_debt) {
        total_debt
    } else {
        repay_amount
    };
    
    // Split repayment coin if necessary with safe subtraction
    let (actual_repay_coin, remaining_coin) = if (repay_amount > actual_repay_amount) {
        let mut repay_coin = repay_asset;
        let remaining_amount = safe_math::safe_sub(repay_amount, actual_repay_amount);
        let remaining = coin::split(&mut repay_coin, remaining_amount, ctx);
        (repay_coin, remaining)
    } else {
        (repay_asset, coin::zero<T>(ctx))
    };
    
    // Repay to vault (package-level call)
    vault::repay(vault, actual_repay_coin);
    
    // Update position debt
    if (actual_repay_amount >= total_debt) {
        // Full repayment - close position
        position.borrowed_amount = 0;
        position.accrued_interest = 0;
        position.status = POSITION_STATUS_CLOSED;
        
        // Update pool statistics with safe subtraction
        pool.active_positions = safe_math::safe_sub(pool.active_positions, 1);
        
        // Remove position from user account
        account::remove_position(account, account_cap, position.position_id);
    } else {
        // Partial repayment - update debt
        if (actual_repay_amount >= position.accrued_interest) {
            // Repay interest first, then principal
            let principal_repay = actual_repay_amount - position.accrued_interest;
            position.accrued_interest = 0;
            position.borrowed_amount = position.borrowed_amount - principal_repay;
        } else {
            // Only repay part of interest
            position.accrued_interest = position.accrued_interest - actual_repay_amount;
        };
    };
    
    // Update pool statistics: subtract only principal portion repaid
    let principal_repaid_for_pool = if (actual_repay_amount > original_interest) {
        let repay_principal_part = actual_repay_amount - original_interest;
        if (repay_principal_part > original_principal) { original_principal } else { repay_principal_part }
    } else { 0 };
    if (pool.total_borrowed >= principal_repaid_for_pool) {
        pool.total_borrowed = pool.total_borrowed - principal_repaid_for_pool;
    } else {
        pool.total_borrowed = 0;
    };
    
    position.last_updated = safe_math::safe_div(clock::timestamp_ms(clock), 1000);
    
    // Update user account activity and points
    account::update_user_activity_for_module(account, account_cap, ctx);
    
    // Calculate repayment points (credit points for good behavior)
    let base_repay_points = actual_repay_amount / 500; // 1 point per 500 units (better than borrowing)
    
    // Add level bonus for repayment points
    let user_level = account::get_level(account);
    let level_bonus_repay_points = calculate_level_bonus_points(user_level, base_repay_points);
    
    // Add bonus credit points for early repayment
    let early_repay_bonus = calculate_early_repayment_bonus(position, clock);
    
    // Add on-time repayment bonus (extra points for not being overdue)
    let on_time_bonus = if (!is_position_overdue(position, clock)) {
        base_repay_points / 10 // 10% bonus for on-time repayment
    } else {
        0
    };
    
    let total_credit_points = base_repay_points + level_bonus_repay_points + early_repay_bonus + on_time_bonus;
    
    if (total_credit_points > 0) {
        account::add_user_points_for_module(account, account_cap, total_credit_points);
    };
    
    // Transfer remaining coin back to user if any
    if (coin::value(&remaining_coin) > 0) {
        transfer::public_transfer(remaining_coin, tx_context::sender(ctx));
    } else {
        coin::destroy_zero(remaining_coin);
    };
    
    // Emit repay event
    event::emit(RepayEvent {
        pool_id: pool.pool_id,
        borrower: tx_context::sender(ctx),
        repay_amount: actual_repay_amount,
        position_id: position.position_id,
        timestamp: safe_math::safe_div(clock::timestamp_ms(clock), 1000),
    });
    
    // Return true if position is fully closed
    position.status == POSITION_STATUS_CLOSED
}

// ===== High Collateral Ratio Configuration Management =====

/// Update high collateral configuration (admin only)
public fun update_high_collateral_config<T>(
    pool: &mut BorrowingPool<T>,
    admin_cap: &BorrowingPoolAdminCap,
    btc_max_ltv: u64,
    eth_max_ltv: u64,
    default_max_ltv: u64,
    level_bonus_ltv: u64,
    dynamic_ltv_enabled: bool,
) {
    // Verify admin permission
    assert!(
        pool.admin_cap_id_opt == option::some(object::id(admin_cap)),
        errors::unauthorized_access()
    );
    
    // Validate parameters
    assert!(btc_max_ltv <= BASIS_POINTS, EInvalidPoolConfig);
    assert!(eth_max_ltv <= BASIS_POINTS, EInvalidPoolConfig);
    assert!(default_max_ltv <= BASIS_POINTS, EInvalidPoolConfig);
    assert!(level_bonus_ltv <= 500, EInvalidPoolConfig); // Max 5% bonus
    
    // Update configuration
    pool.high_collateral_config.btc_max_ltv = btc_max_ltv;
    pool.high_collateral_config.eth_max_ltv = eth_max_ltv;
    pool.high_collateral_config.default_max_ltv = default_max_ltv;
    pool.high_collateral_config.level_bonus_ltv = level_bonus_ltv;
    pool.high_collateral_config.dynamic_ltv_enabled = dynamic_ltv_enabled;
}

/// Update risk monitoring configuration (admin only)
public fun update_risk_monitoring_config<T>(
    pool: &mut BorrowingPool<T>,
    admin_cap: &BorrowingPoolAdminCap,
    price_change_threshold: u64,
    monitoring_interval: u64,
    auto_liquidation_enabled: bool,
    risk_alert_enabled: bool,
) {
    // Verify admin permission
    assert!(
        pool.admin_cap_id_opt == option::some(object::id(admin_cap)),
        errors::unauthorized_access()
    );
    
    // Validate parameters
    assert!(price_change_threshold <= 5000, EInvalidPoolConfig); // Max 50% threshold
    assert!(monitoring_interval >= 60, EInvalidPoolConfig); // Min 1 minute
    
    // Update configuration
    pool.risk_monitoring_config.price_change_threshold = price_change_threshold;
    pool.risk_monitoring_config.monitoring_interval = monitoring_interval;
    pool.risk_monitoring_config.auto_liquidation_enabled = auto_liquidation_enabled;
    pool.risk_monitoring_config.risk_alert_enabled = risk_alert_enabled;
}

/// Get high collateral configuration for a pool
public fun get_high_collateral_config<T>(pool: &BorrowingPool<T>): (u64, u64, u64, u64, bool) {
    (
        pool.high_collateral_config.btc_max_ltv,
        pool.high_collateral_config.eth_max_ltv,
        pool.high_collateral_config.default_max_ltv,
        pool.high_collateral_config.level_bonus_ltv,
        pool.high_collateral_config.dynamic_ltv_enabled,
    )
}

/// Get risk monitoring configuration for a pool
public fun get_risk_monitoring_config<T>(pool: &BorrowingPool<T>): (u64, u64, bool, bool) {
    (
        pool.risk_monitoring_config.price_change_threshold,
        pool.risk_monitoring_config.monitoring_interval,
        pool.risk_monitoring_config.auto_liquidation_enabled,
        pool.risk_monitoring_config.risk_alert_enabled,
    )
}

// ===== Interest Rate Management =====

/// Update pool interest based on utilization and time elapsed
public fun update_pool_interest<T>(
    pool: &mut BorrowingPool<T>,
    clock: &Clock,
) {
    if (!pool.config.auto_compound) {
        return
    };
    
    let current_time = safe_math::safe_div(clock::timestamp_ms(clock), 1000);
    let time_elapsed = safe_math::safe_sub(current_time, pool.stats.last_interest_update);
    
    // Skip if less than 1 second has passed
    if (time_elapsed == 0) {
        return
    };
    
    // Calculate current interest rate based on model
    let current_rate = calculate_current_interest_rate(pool);
    
    // Calculate interest amount for the elapsed time with SafeMath overflow protection
    let interest_amount = if (pool.total_borrowed > 0) {
        let denominator = safe_math::safe_mul(BASIS_POINTS, SECONDS_PER_YEAR);
        
        // Use SafeMath for compound interest calculation
        safe_math::calculate_compound_interest_safe(
            pool.total_borrowed,
            current_rate,
            time_elapsed,
            denominator
        ) - pool.total_borrowed // Subtract principal to get just the interest
    } else {
        0
    };
    
    if (interest_amount > 0) {
        // Update pool statistics with overflow protection
        pool.stats.total_interest_paid = safe_math::safe_add(pool.stats.total_interest_paid, interest_amount);
        pool.stats.current_apr = current_rate;
        
        // Emit interest accrual event
        event::emit(InterestAccrualEvent {
            pool_id: pool.pool_id,
            interest_rate: current_rate,
            total_interest: interest_amount,
            timestamp: current_time,
        });
    };
    
    pool.stats.last_interest_update = current_time;
}

/// Update interest for a specific position with user level discount
fun update_position_interest_with_level_discount<T>(
    position: &mut BorrowPosition,
    pool: &BorrowingPool<T>,
    account: &Account,
    clock: &Clock,
) {
    let current_time = safe_math::safe_div(clock::timestamp_ms(clock), 1000);
    let time_elapsed = safe_math::safe_sub(current_time, position.last_updated);
    
    if (time_elapsed == 0 || position.borrowed_amount == 0) {
        return
    };
    
    // Calculate interest rate with user level discount
    let current_rate = calculate_interest_rate_with_level_discount(pool, account);
    
    // Calculate interest for this position with SafeMath overflow protection
    let denominator = safe_math::safe_mul(BASIS_POINTS, SECONDS_PER_YEAR);
    
    let position_interest = safe_math::safe_mul_div(
        safe_math::safe_mul(position.borrowed_amount, current_rate),
        time_elapsed,
        denominator
    );
    
    position.accrued_interest = safe_math::safe_add(position.accrued_interest, position_interest);
    position.last_updated = current_time;
}


/// Calculate current interest rate based on pool's interest model
fun calculate_current_interest_rate<T>(pool: &BorrowingPool<T>): u64 {
    match (pool.interest_model) {
        INTEREST_MODEL_DYNAMIC => {
            // Dynamic rate: base_rate + risk_premium + utilization_based_adjustment
            // Note: For borrowing pools, we don't have total_deposits, so we use a simplified model
            safe_math::safe_add(pool.base_rate, pool.risk_premium)
        },
        INTEREST_MODEL_FIXED => {
            // Fixed rate model
            pool.fixed_rate
        },
        _ => {
            // Default to base rate + risk premium for unknown models
            pool.base_rate + pool.risk_premium
        }
    }
}

/// Calculate interest rate with user level discount applied
/// VIP users get 0.1%-0.5% discount based on their level
public fun calculate_interest_rate_with_level_discount<T>(
    pool: &BorrowingPool<T>,
    account: &Account
): u64 {
    let base_rate = calculate_current_interest_rate(pool);
    let user_level = account::get_level(account);
    
    // Calculate level-based discount
    let discount = calculate_level_interest_discount(user_level);
    
    // Apply discount (ensure rate doesn't go below 0)
    if (base_rate > discount) {
        base_rate - discount
    } else {
        0
    }
}

/// Calculate interest rate discount based on user level
/// Level 1-2: No discount
/// Level 3-4: 0.1% discount (10 basis points)
/// Level 5-6: 0.2% discount (20 basis points)
/// Level 7-8: 0.3% discount (30 basis points)
/// Level 9-10: 0.5% discount (50 basis points)
fun calculate_level_interest_discount(user_level: u8): u64 {
    if (user_level >= 9) {
        50 // 0.5% discount for diamond users (level 9-10)
    } else if (user_level >= 7) {
        30 // 0.3% discount for platinum users (level 7-8)
    } else if (user_level >= 5) {
        20 // 0.2% discount for gold users (level 5-6)
    } else if (user_level >= 3) {
        10 // 0.1% discount for silver users (level 3-4)
    } else {
        0  // No discount for bronze users (level 1-2)
    }
}

/// Calculate bonus credit points for early repayment
/// Rewards users who repay before significant interest accrues
fun calculate_early_repayment_bonus(position: &BorrowPosition, clock: &Clock): u64 {
    let current_time = safe_math::safe_div(clock::timestamp_ms(clock), 1000);
    let position_age = safe_math::safe_sub(current_time, position.created_at);
    
    // Early repayment bonus based on how quickly the loan is repaid
    // Within 1 day: 50% bonus
    // Within 1 week: 25% bonus  
    // Within 1 month: 10% bonus
    // After 1 month: No bonus
    let bonus_multiplier = if (position_age <= 86400) { // 1 day
        50 // 50% bonus
    } else if (position_age <= 604800) { // 1 week
        25 // 25% bonus
    } else if (position_age <= 2592000) { // 1 month
        10 // 10% bonus
    } else {
        0 // No bonus
    };
    
    // Base bonus points based on borrowed amount
    let base_bonus = position.borrowed_amount / 2000; // 1 bonus point per 2000 units
    
    // Apply multiplier
    safe_math::safe_mul_div(base_bonus, bonus_multiplier, 100)
}

/// Calculate credit points penalty for overdue positions
/// Penalizes users who fail to repay on time
fun calculate_overdue_points_penalty(position: &BorrowPosition, clock: &Clock): u64 {
    if (!is_position_overdue(position, clock)) {
        return 0
    };
    
    let maturity_time = *option::borrow(&position.maturity_time);
    let current_time = safe_math::safe_div(clock::timestamp_ms(clock), 1000);
    let overdue_days = safe_math::safe_div(safe_math::safe_sub(current_time, maturity_time), 86400); // Convert to days
    
    if (overdue_days == 0) {
        return 0
    };
    
    // Calculate penalty points based on borrowed amount and overdue duration
    // Base penalty: 1 point per 500 units borrowed (same rate as repayment reward)
    let base_penalty = position.borrowed_amount / 500;
    
    // Escalating penalty based on overdue duration
    // 1-3 days: 1x penalty
    // 4-7 days: 2x penalty (still in grace period)
    // 8-14 days: 3x penalty
    // 15+ days: 5x penalty
    let penalty_multiplier = if (overdue_days <= 3) {
        1 // 1x penalty for short overdue
    } else if (overdue_days <= 7) {
        2 // 2x penalty within grace period
    } else if (overdue_days <= 14) {
        3 // 3x penalty after grace period
    } else {
        5 // 5x penalty for long overdue
    };
    
    safe_math::safe_mul(base_penalty, penalty_multiplier)
}

/// Calculate bonus points based on user level
/// Higher level users get more points for the same activities
fun calculate_level_bonus_points(user_level: u8, base_points: u64): u64 {
    // Level 0-2: No bonus
    // Level 3-4: 10% bonus
    // Level 5-6: 20% bonus
    // Level 7-8: 30% bonus
    // Level 9-10: 50% bonus (diamond users)
    let bonus_percentage = if (user_level >= 9) {
        50 // 50% bonus for diamond users (level 9-10)
    } else if (user_level >= 7) {
        30 // 30% bonus for platinum users (level 7-8)
    } else if (user_level >= 5) {
        20 // 20% bonus for gold users (level 5-6)
    } else if (user_level >= 3) {
        10 // 10% bonus for silver users (level 3-4)
    } else {
        0  // No bonus for bronze users (level 1-2)
    };
    
    safe_math::safe_mul_div(base_points, bonus_percentage, 100)
}

// ===== Term and Maturity Management Functions =====

/// Check if a position is overdue
public fun is_position_overdue(position: &BorrowPosition, clock: &Clock): bool {
    if (position.term_type == TERM_TYPE_INDEFINITE) {
        return false // Indefinite positions never expire
    };
    
    if (option::is_none(&position.maturity_time)) {
        return false // No maturity time set
    };
    
    let maturity_time = *option::borrow(&position.maturity_time);
    let current_time = safe_math::safe_div(clock::timestamp_ms(clock), 1000);
    
    current_time > maturity_time
}

/// Check if a position is in grace period (overdue but within grace period)
public fun is_position_in_grace_period(position: &BorrowPosition, clock: &Clock): bool {
    if (!is_position_overdue(position, clock)) {
        return false
    };
    
    let maturity_time = *option::borrow(&position.maturity_time);
    let current_time = safe_math::safe_div(clock::timestamp_ms(clock), 1000);
    
    safe_math::safe_sub(current_time, maturity_time) <= OVERDUE_GRACE_PERIOD
}

/// Calculate overdue penalty for a position
public fun calculate_overdue_penalty(position: &BorrowPosition, clock: &Clock): u64 {
    if (!is_position_overdue(position, clock)) {
        return 0
    };
    
    let maturity_time = *option::borrow(&position.maturity_time);
    let current_time = safe_math::safe_div(clock::timestamp_ms(clock), 1000);
    let overdue_days = safe_math::safe_div(safe_math::safe_sub(current_time, maturity_time), 86400); // Convert to days
    
    if (overdue_days == 0) {
        return 0
    };
    
    // Calculate penalty: principal * penalty_rate * overdue_days / 365
    let principal = position.borrowed_amount;
    let annual_penalty = safe_math::safe_mul_div(principal, OVERDUE_PENALTY_RATE, BASIS_POINTS);
    safe_math::safe_mul_div(annual_penalty, overdue_days, 365)
}

/// Update position with overdue penalty and deduct credit points
fun apply_overdue_penalty(position: &mut BorrowPosition, clock: &Clock) {
    if (!is_position_overdue(position, clock)) {
        return
    };
    
    let penalty = calculate_overdue_penalty(position, clock);
    if (penalty > 0) {
        position.accrued_interest = safe_math::safe_add(position.accrued_interest, penalty);
        position.last_updated = safe_math::safe_div(clock::timestamp_ms(clock), 1000);
    };
}

/// Apply overdue penalty and deduct credit points from user account
/// This is a separate function that requires account access for point deduction
fun apply_overdue_penalty_with_account(
    position: &mut BorrowPosition, 
    account: &mut Account,
    account_cap: &AccountCap,
    clock: &Clock
) {
    if (!is_position_overdue(position, clock)) {
        return
    };
    
    let penalty = calculate_overdue_penalty(position, clock);
    if (penalty > 0) {
        position.accrued_interest = safe_math::safe_add(position.accrued_interest, penalty);
        position.last_updated = safe_math::safe_div(clock::timestamp_ms(clock), 1000);
        
        // Calculate credit points to deduct based on overdue severity
        let overdue_points_penalty = calculate_overdue_points_penalty(position, clock);
        if (overdue_points_penalty > 0) {
            account::deduct_points(account, account_cap, overdue_points_penalty);
        };
    };
}

/// Get position maturity information
public fun get_position_maturity_info(position: &BorrowPosition): (u8, option::Option<u64>) {
    (position.term_type, position.maturity_time)
}

/// Get days until maturity (returns 0 if indefinite or already overdue)
public fun get_days_until_maturity(position: &BorrowPosition, clock: &Clock): u64 {
    if (position.term_type == TERM_TYPE_INDEFINITE) {
        return 0 // Indefinite positions never expire
    };
    
    if (option::is_none(&position.maturity_time)) {
        return 0 // No maturity time set
    };
    
    let maturity_time = *option::borrow(&position.maturity_time);
    let current_time = safe_math::safe_div(clock::timestamp_ms(clock), 1000);
    
    if (current_time >= maturity_time) {
        return 0 // Already overdue
    };
    
    (maturity_time - current_time) / 86400 // Convert to days
}

/// Check if early repayment is allowed for fixed-term positions
public fun is_early_repayment_allowed(position: &BorrowPosition, clock: &Clock): bool {
    if (position.term_type == TERM_TYPE_INDEFINITE) {
        return true // Indefinite positions can always be repaid
    };
    
    // Fixed-term positions can be repaid early, but may incur penalties
    // For now, we allow early repayment but give bonus points for it
    true
}

/// Calculate the total amount due for a position (principal + interest + penalties)
public fun calculate_total_amount_due(position: &BorrowPosition, clock: &Clock): u64 {
    let principal = position.borrowed_amount;
    let interest = position.accrued_interest;
    let penalty = calculate_overdue_penalty(position, clock);
    
    principal + interest + penalty
}

// ===== Query Functions =====

/// Get pool information
public fun get_pool_info<T>(pool: &BorrowingPool<T>): (u64, vector<u8>, u8, u64, u64, u64, u64, u64, u64) {
    (
        pool.pool_id,
        pool.name,
        pool.interest_model,
        pool.base_rate,
        pool.rate_slope,
        pool.risk_premium,
        pool.initial_ltv,
        pool.warning_ltv,
        pool.liquidation_ltv
    )
}

/// Get pool statistics
public fun get_pool_stats<T>(pool: &BorrowingPool<T>): (u64, u64, u64, u64, u64, u64) {
    (
        pool.total_borrowed,
        pool.active_positions,
        pool.stats.total_borrowers,
        pool.stats.total_interest_paid,
        pool.stats.total_liquidations,
        pool.stats.current_apr
    )
}

/// Get pool status
public fun get_pool_status<T>(pool: &BorrowingPool<T>): u8 {
    match (pool.status) {
        BorrowingPoolStatus::Active => 0,
        BorrowingPoolStatus::Paused => 1,
        BorrowingPoolStatus::BorrowingOnly => 2,
        BorrowingPoolStatus::RepaymentOnly => 3,
        BorrowingPoolStatus::Inactive => 4,
    }
}

/// Get position information
public fun get_position_info(position: &BorrowPosition): (ID, u64, u64, u64, u64, u8) {
    (
        position.position_id,
        position.pool_id,
        position.borrowed_amount,
        position.accrued_interest,
        position.created_at,
        position.status
    )
}

/// Check if borrowing is allowed
public fun borrowing_allowed<T>(pool: &BorrowingPool<T>): bool {
    pool.config.borrowing_enabled &&
    (pool.status == BorrowingPoolStatus::Active || pool.status == BorrowingPoolStatus::BorrowingOnly)
}

/// Check if repayment is allowed
public fun repayment_allowed<T>(pool: &BorrowingPool<T>): bool {
    pool.config.repayment_enabled &&
    (pool.status == BorrowingPoolStatus::Active || pool.status == BorrowingPoolStatus::RepaymentOnly)
}

/// Get position term information for display
public fun get_position_term_info(position: &BorrowPosition, clock: &Clock): (u8, option::Option<u64>, u64, bool, u64) {
    let term_type = position.term_type;
    let maturity_time = position.maturity_time;
    let days_until_maturity = get_days_until_maturity(position, clock);
    let is_overdue = is_position_overdue(position, clock);
    let overdue_penalty = calculate_overdue_penalty(position, clock);
    
    (term_type, maturity_time, days_until_maturity, is_overdue, overdue_penalty)
}

/// Get position financial summary
public fun get_position_financial_summary(position: &BorrowPosition, clock: &Clock): (u64, u64, u64, u64) {
    let principal = position.borrowed_amount;
    let interest = position.accrued_interest;
    let penalty = calculate_overdue_penalty(position, clock);
    let total_due = calculate_total_amount_due(position, clock);
    
    (principal, interest, penalty, total_due)
}

/// Calculate potential points for borrowing a specific amount
/// Helps users understand point rewards before borrowing
public fun calculate_potential_borrow_points(borrow_amount: u64, user_level: u8): u64 {
    let base_points = borrow_amount / 1000; // 1 point per 1000 units
    let level_bonus = calculate_level_bonus_points(user_level, base_points);
    base_points + level_bonus
}

/// Calculate potential points for repaying a specific amount
/// Helps users understand point rewards before repaying
public fun calculate_potential_repay_points(
    position: &BorrowPosition, 
    repay_amount: u64, 
    user_level: u8, 
    clock: &Clock
): u64 {
    let base_points = repay_amount / 500; // 1 point per 500 units
    let level_bonus = calculate_level_bonus_points(user_level, base_points);
    let early_bonus = calculate_early_repayment_bonus(position, clock);
    let on_time_bonus = if (!is_position_overdue(position, clock)) {
        base_points / 10 // 10% bonus for on-time repayment
    } else {
        0
    };
    
    base_points + level_bonus + early_bonus + on_time_bonus
}

/// Calculate potential point penalty for overdue position
/// Helps users understand the cost of being overdue
public fun calculate_potential_overdue_penalty_points(position: &BorrowPosition, clock: &Clock): u64 {
    calculate_overdue_points_penalty(position, clock)
}

// ===== Utility Functions =====

#[test_only]
/// Create a test position for testing purposes
public fun create_test_position(
    position_id: u64,
    borrower: address,
    pool_id: u64,
    borrowed_amount: u64,
    accrued_interest: u64,
    term_type: u8,
    maturity_time: option::Option<u64>,
    status: u8,
): BorrowPosition {
    BorrowPosition {
        id: object::new(&mut tx_context::dummy()),
        position_id: object::id_from_address(borrower),
        borrower_account: object::id_from_address(borrower),
        pool_id,
        collateral_holder_id: object::id_from_address(borrower),
        collateral_vault_id: object::id_from_address(borrower),
        collateral_amount: 1000,
        collateral_type: type_name::get<sui::sui::SUI>(),
        borrowed_amount,
        accrued_interest,
        created_at: 0,
        last_updated: 0,
        term_type,
        maturity_time,
        status,
    }
}

/// Get the collateral holder object id stored in a position
public fun get_collateral_holder_id(position: &BorrowPosition): ID {
    position.collateral_holder_id
}

// ===== Registry Query Functions =====

/// Get pools for a specific asset type
public fun get_pools_for_asset<T>(registry: &BorrowingPoolRegistry): vector<ID> {
    let asset_type = type_name::get<T>();
    if (table::contains(&registry.asset_pools, asset_type)) {
        *table::borrow(&registry.asset_pools, asset_type)
    } else {
        vector::empty<ID>()
    }
}

/// Check if pool exists in registry
public fun pool_exists(registry: &BorrowingPoolRegistry, pool_id: ID): bool {
    table::contains(&registry.pools, pool_id)
}

/// Get total number of pools
public fun get_total_pools(registry: &BorrowingPoolRegistry): u64 {
    registry.pool_counter
}

/// Get registry version
public fun get_registry_version(registry: &BorrowingPoolRegistry): u64 {
    registry.version
}

// ===== Test Helper Functions =====

#[test_only]
/// Create a borrowing pool for testing without registry
public fun create_pool_for_test<T>(
    pool_id: u64,
    name: vector<u8>,
    interest_model: u8,
    base_rate: u64,
    initial_ltv: u64,
    warning_ltv: u64,
    liquidation_ltv: u64,
    ctx: &mut TxContext
): BorrowingPool<T> {
    let tick_config = TickLiquidationConfig {
        tick_size: 50,
        liquidation_penalty: 10,
        liquidation_reward: 5,
        max_liquidation_ratio: 1000,
    };
    
    let config = BorrowingPoolConfig {
        min_borrow: 1,
        min_collateral: 1,
        borrowing_enabled: true,
        repayment_enabled: true,
        liquidation_enabled: true,
        auto_compound: true,
    };
    
    let stats = BorrowingPoolStats {
        total_borrowers: 0,
        total_interest_paid: 0,
        total_liquidations: 0,
        total_liquidation_penalties: 0,
        created_at: 0,
        last_interest_update: 0,
        current_apr: base_rate,
    };
    
    let high_collateral_config = HighCollateralConfig {
        btc_max_ltv: 9700, // 97% for BTC
        eth_max_ltv: 9500, // 95% for ETH
        default_max_ltv: 9000, // 90% for other assets
        level_bonus_ltv: 200, // 2% bonus for high-level users
        dynamic_ltv_enabled: true,
    };
    
    let risk_monitoring_config = RiskMonitoringConfig {
        price_change_threshold: 500, // 5% price change threshold
        monitoring_interval: 300, // 5 minutes
        auto_liquidation_enabled: true,
        risk_alert_enabled: true,
    };

    BorrowingPool<T> {
        id: object::new(ctx),
        version: constants::current_version(),
        pool_id,
        name,
        description: b"Test pool",
        interest_model,
        base_rate,
        rate_slope: 1000, // 10%
        risk_premium: 200, // 2%
        fixed_rate: base_rate,
        initial_ltv,
        warning_ltv,
        liquidation_ltv,
        total_borrowed: 0,
        active_positions: 0,
        tick_config,
        high_collateral_config,
        risk_monitoring_config,
        max_borrow_limit: 1_000_000_000,
        admin_cap_id_opt: option::none<ID>(),
        config,
        stats,
        status: BorrowingPoolStatus::Active,
    }
}

#[test_only]
/// Initialize registry for testing
public fun init_registry_for_test(ctx: &mut TxContext): (BorrowingPoolRegistry, BorrowingPoolAdminCap) {
    let admin_cap = BorrowingPoolAdminCap {
        id: object::new(ctx),
    };
    
    let admin_cap_id = object::id(&admin_cap);
    
    let registry = BorrowingPoolRegistry {
        id: object::new(ctx),
        version: constants::current_version(),
        pools: table::new(ctx),
        asset_pools: table::new(ctx),
        pool_counter: 0,
        admin_cap_id,
    };
    
    (registry, admin_cap)
}

#[test_only]
/// Create admin cap for testing
public fun create_admin_cap_for_test(ctx: &mut TxContext): BorrowingPoolAdminCap {
    BorrowingPoolAdminCap {
        id: object::new(ctx),
    }
}

#[test_only]
/// Create a test position for testing
public fun create_position_for_test(
    _position_id: u64,
    borrower: address,
    pool_id: u64,
    collateral_amount: u64,
    borrowed_amount: u64,
    accrued_interest: u64,
    ctx: &mut TxContext
): BorrowPosition {
    let position_uid = object::new(ctx);
    let position_id_inner = object::uid_to_inner(&position_uid);
    
    BorrowPosition {
        id: position_uid,
        position_id: position_id_inner,
        borrower_account: object::id_from_address(borrower),
        pool_id,
        collateral_holder_id: object::id_from_address(@0x0), // dummy
        collateral_vault_id: object::id_from_address(@0x0), // dummy
        collateral_amount,
        collateral_type: type_name::get<u64>(), // dummy type
        borrowed_amount,
        accrued_interest,
        created_at: 0,
        last_updated: 0,
        term_type: TERM_TYPE_INDEFINITE,
        maturity_time: option::none(),
        status: POSITION_STATUS_ACTIVE,
    }
}

#[test_only]
/// Create a borrowing pool for testing with admin cap
public fun create_pool_with_admin_for_test<T>(
    pool_id: u64,
    name: vector<u8>,
    interest_model: u8,
    base_rate: u64,
    initial_ltv: u64,
    warning_ltv: u64,
    liquidation_ltv: u64,
    admin_cap: &BorrowingPoolAdminCap,
    ctx: &mut TxContext
): BorrowingPool<T> {
    let tick_config = TickLiquidationConfig {
        tick_size: 50,
        liquidation_penalty: 10,
        liquidation_reward: 5,
        max_liquidation_ratio: 1000,
    };
    
    let high_collateral_config = HighCollateralConfig {
        btc_max_ltv: 9700, // 97% for BTC
        eth_max_ltv: 9500, // 95% for ETH
        default_max_ltv: 9000, // 90% for other assets
        level_bonus_ltv: 200, // 2% bonus for high-level users
        dynamic_ltv_enabled: true,
    };
    
    let risk_monitoring_config = RiskMonitoringConfig {
        price_change_threshold: 500, // 5% price change threshold
        monitoring_interval: 300, // 5 minutes
        auto_liquidation_enabled: true,
        risk_alert_enabled: true,
    };
    
    let config = BorrowingPoolConfig {
        min_borrow: 1,
        min_collateral: 1,
        borrowing_enabled: true,
        repayment_enabled: true,
        liquidation_enabled: true,
        auto_compound: true,
    };
    
    let stats = BorrowingPoolStats {
        total_borrowers: 0,
        total_interest_paid: 0,
        total_liquidations: 0,
        total_liquidation_penalties: 0,
        created_at: 0,
        last_interest_update: 0,
        current_apr: base_rate,
    };
    
    BorrowingPool<T> {
        id: object::new(ctx),
        version: constants::current_version(),
        pool_id,
        name,
        description: b"Test pool with admin",
        interest_model,
        base_rate,
        rate_slope: 1000, // 10%
        risk_premium: 200, // 2%
        fixed_rate: base_rate,
        initial_ltv,
        warning_ltv,
        liquidation_ltv,
        total_borrowed: 0,
        active_positions: 0,
        tick_config,
        high_collateral_config,
        risk_monitoring_config,
        max_borrow_limit: 1_000_000_000,
        admin_cap_id_opt: option::some(object::id(admin_cap)),
        config,
        stats,
        status: BorrowingPoolStatus::Active,
    }
}
#[
test_only]
/// Set position created_at time for testing purposes
public fun set_position_created_at_for_test(position: &mut BorrowPosition, created_at: u64) {
    position.created_at = created_at;
}