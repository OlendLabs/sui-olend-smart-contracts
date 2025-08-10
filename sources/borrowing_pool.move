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

/// Liquidation event
public struct LiquidationEvent has copy, drop {
    pool_id: u64,
    liquidator: address,
    borrower: address,
    position_id: ID,
    collateral_liquidated: u64,
    debt_repaid: u64,
    penalty_amount: u64,
    timestamp: u64,
}

/// Interest accrual event
public struct InterestAccrualEvent has copy, drop {
    pool_id: u64,
    interest_rate: u64,
    total_interest: u64,
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

// ===== Interest Model Constants =====

/// Dynamic interest rate model
const INTEREST_MODEL_DYNAMIC: u8 = 0;

/// Fixed interest rate model
const INTEREST_MODEL_FIXED: u8 = 1;

/// Basis points denominator (10000 = 100%)
const BASIS_POINTS: u64 = 10000;

/// Seconds per year for APR calculation
const SECONDS_PER_YEAR: u64 = 31536000;

/// Position status constants
const POSITION_STATUS_ACTIVE: u8 = 0;
const POSITION_STATUS_LIQUIDATABLE: u8 = 1;
const POSITION_STATUS_LIQUIDATED: u8 = 2;
const POSITION_STATUS_CLOSED: u8 = 3;

/// Term type constants
const TERM_TYPE_INDEFINITE: u8 = 0;
const TERM_TYPE_FIXED: u8 = 1;

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
    
    let current_time = clock::timestamp_ms(clock) / 1000;
    
    // Create tick liquidation configuration
    let tick_config = TickLiquidationConfig {
        tick_size: 50, // 0.5% tick size
        liquidation_penalty: 10, // 0.1% penalty
        liquidation_reward: 5, // 0.05% reward
        max_liquidation_ratio: 1000, // 10% max liquidation per operation
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

// ===== Core Borrowing Functions =====

/// Borrow assets from the pool using YToken collateral
/// Creates a new borrow position or updates existing one
#[allow(lint(self_transfer))]
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
    let now = clock::timestamp_ms(clock) / 1000;
    let borrow_price_time = oracle::price_info_timestamp(&borrow_asset_price_info);
    let collateral_price_time = oracle::price_info_timestamp(&collateral_asset_price_info);
    assert!(now - borrow_price_time <= constants::default_max_price_delay(), errors::price_validation_failed());
    assert!(now - collateral_price_time <= constants::default_max_price_delay(), errors::price_validation_failed());
    
    let borrow_asset_price_raw = oracle::price_info_price(&borrow_asset_price_info);
    let collateral_asset_price_raw = oracle::price_info_price(&collateral_asset_price_info);
    let borrow_conf = oracle::price_info_confidence(&borrow_asset_price_info);
    let collateral_conf = oracle::price_info_confidence(&collateral_asset_price_info);
    
    // Apply conservative discount using confidence interval
    let borrow_asset_price = if (borrow_asset_price_raw > borrow_conf) { borrow_asset_price_raw - borrow_conf } else { 0 };
    let collateral_asset_price = if (collateral_asset_price_raw > collateral_conf) { collateral_asset_price_raw - collateral_conf } else { 0 };
    assert!(borrow_asset_price > 0 && collateral_asset_price > 0, errors::price_validation_failed());
    
    // Convert YToken shares to underlying asset amount using the vault's current ratio
    let collateral_assets = vault::convert_to_assets(collateral_vault, collateral_amount);
    // Ensure conversion yielded non-zero assets to avoid division by zero and false safety
    assert!(collateral_assets > 0, EInsufficientCollateral);
    
    // Price scale based on oracle price precision
    let price_scale: u64 = pow10(constants::price_decimal_precision());
    
    // Calculate collateral value and borrow value in USD using safe order to reduce overflow risk
    let collateral_value_usd = (collateral_assets * collateral_asset_price) / price_scale;
    let borrow_value_usd = (borrow_amount * borrow_asset_price) / price_scale;
    // Avoid division by zero in LTV calculation
    assert!(collateral_value_usd > 0, EInsufficientCollateral);
    
    // Calculate collateral ratio (LTV)
    let collateral_ratio = (borrow_value_usd * BASIS_POINTS) / collateral_value_usd;
    
    // Verify collateral ratio is within safe limits
    assert!(collateral_ratio <= pool.initial_ltv, ECollateralRatioTooHigh);
    
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
        created_at: clock::timestamp_ms(clock) / 1000,
        last_updated: clock::timestamp_ms(clock) / 1000,
        term_type: TERM_TYPE_INDEFINITE,
        maturity_time: option::none(),
        status: POSITION_STATUS_ACTIVE,
    };
    
    // Update pool statistics
    pool.total_borrowed = pool.total_borrowed + borrow_amount;
    pool.active_positions = pool.active_positions + 1;
    pool.stats.total_borrowers = pool.stats.total_borrowers + 1;
    
    // Update user account activity and points
    account::update_user_activity_for_module(account, account_cap, ctx);
    
    // Calculate borrow points based on amount (1 point per 1000 units)
    let borrow_points = borrow_amount / 1000;
    if (borrow_points > 0) {
        account::add_user_points_for_module(account, account_cap, borrow_points);
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
        timestamp: clock::timestamp_ms(clock) / 1000,
    });
    
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
#[allow(lint(self_transfer))]
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
    update_position_interest(position, pool, clock);
    
    // Snapshot amounts before mutation
    let original_principal = position.borrowed_amount;
    let original_interest = position.accrued_interest;
    // Calculate total debt (principal + accrued interest)
    let total_debt = original_principal + original_interest;
    
    // Determine actual repayment amount (cannot exceed total debt)
    let actual_repay_amount = if (repay_amount >= total_debt) {
        total_debt
    } else {
        repay_amount
    };
    
    // Split repayment coin if necessary
    let (actual_repay_coin, remaining_coin) = if (repay_amount > actual_repay_amount) {
        let mut repay_coin = repay_asset;
        let remaining = coin::split(&mut repay_coin, repay_amount - actual_repay_amount, ctx);
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
        
        // Update pool statistics
        pool.active_positions = pool.active_positions - 1;
        
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
    
    position.last_updated = clock::timestamp_ms(clock) / 1000;
    
    // Update user account activity and points
    account::update_user_activity_for_module(account, account_cap, ctx);
    
    // Calculate repayment points (credit points for good behavior)
    let repay_points = actual_repay_amount / 500; // 1 point per 500 units (better than borrowing)
    if (repay_points > 0) {
        account::add_user_points_for_module(account, account_cap, repay_points);
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
        timestamp: clock::timestamp_ms(clock) / 1000,
    });
    
    // Return true if position is fully closed
    position.status == POSITION_STATUS_CLOSED
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
    
    let current_time = clock::timestamp_ms(clock) / 1000;
    let time_elapsed = current_time - pool.stats.last_interest_update;
    
    // Skip if less than 1 second has passed
    if (time_elapsed == 0) {
        return
    };
    
    // Calculate current interest rate based on model
    let current_rate = calculate_current_interest_rate(pool);
    
    // Calculate interest amount for the elapsed time
    let interest_amount = if (pool.total_borrowed > 0) {
        // Annual rate to per-second rate: rate / SECONDS_PER_YEAR
        // Interest = principal * rate * time
        (pool.total_borrowed * current_rate * time_elapsed) / (BASIS_POINTS * SECONDS_PER_YEAR)
    } else {
        0
    };
    
    if (interest_amount > 0) {
        // Update pool statistics
        pool.stats.total_interest_paid = pool.stats.total_interest_paid + interest_amount;
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

/// Update interest for a specific position
fun update_position_interest<T>(
    position: &mut BorrowPosition,
    pool: &BorrowingPool<T>,
    clock: &Clock,
) {
    let current_time = clock::timestamp_ms(clock) / 1000;
    let time_elapsed = current_time - position.last_updated;
    
    if (time_elapsed == 0 || position.borrowed_amount == 0) {
        return
    };
    
    // Calculate current interest rate
    let current_rate = calculate_current_interest_rate(pool);
    
    // Calculate interest for this position
    let position_interest = (position.borrowed_amount * current_rate * time_elapsed) / (BASIS_POINTS * SECONDS_PER_YEAR);
    
    position.accrued_interest = position.accrued_interest + position_interest;
    position.last_updated = current_time;
}

/// Calculate current interest rate based on pool's interest model
fun calculate_current_interest_rate<T>(pool: &BorrowingPool<T>): u64 {
    match (pool.interest_model) {
        INTEREST_MODEL_DYNAMIC => {
            // Dynamic rate: base_rate + risk_premium + utilization_based_adjustment
            // Note: For borrowing pools, we don't have total_deposits, so we use a simplified model
            pool.base_rate + pool.risk_premium
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

// ===== Utility Functions =====

/// Compute 10^exp for small exp (u8) to derive price scale dynamically
fun pow10(exp: u8): u64 {
    let mut i: u8 = 0;
    let mut result: u64 = 1;
    while (i < exp) {
        result = result * 10;
        i = i + 1;
    };
    result
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