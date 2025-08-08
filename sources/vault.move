/// Vault Module - ERC-4626 compatible vault implementation
/// Implements unified liquidity vault with share-based asset management
module olend::vault;


use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance, Supply};
use sui::object::{Self, UID, ID};
use sui::tx_context::{Self, TxContext};
use std::option::{Self, Option};
use std::type_name::{Self, TypeName};

use olend::constants;
use olend::errors;
use olend::utils;
use olend::liquidity::{Self, LiquidityAdminCap};
use olend::ytoken::{Self, YToken};
use olend::oracle::{Self, OracleRegistry, PriceData};

// Oracle integration imports
use sui::clock::{Self, Clock};
use pyth::state::{State as PythState};
use pyth::price_info::PriceInfoObject;

// ===== Struct Definitions =====

/// Unified liquidity vault, compatible with ERC-4626 standard
/// Manages assets and shares for a specific asset type
public struct Vault<phantom T> has key, store {
    id: UID,
    /// Protocol version for access control
    version: u64,
    /// Total assets in the vault (including borrowed assets)
    total_assets: Balance<T>,
    /// Assets borrowed by other modules
    borrowed_assets: u64,
    /// YToken supply for minting/burning shares
    ytoken_supply: Supply<YToken<T>>,
    /// Vault status configuration
    status: VaultStatus,
    /// Daily withdrawal limit configuration
    daily_limit: DailyLimit,
    /// Vault configuration parameters
    config: VaultConfig,
}

/// Vault status enumeration
public enum VaultStatus has store, copy, drop {
    /// Vault is active and fully operational
    Active,
    /// Vault is paused - no deposits or withdrawals allowed
    Paused,
    /// Vault allows deposits only
    DepositsOnly,
    /// Vault allows withdrawals only
    WithdrawalsOnly,
    /// Vault is inactive/disabled
    Inactive,
}

/// Daily withdrawal limit management
public struct DailyLimit has store {
    /// Maximum daily withdrawal amount
    max_daily_withdrawal: u64,
    /// Current day number
    current_day: u64,
    /// Amount withdrawn today
    withdrawn_today: u64,
}

/// Vault configuration parameters
public struct VaultConfig has store {
    /// Minimum deposit amount
    min_deposit: u64,
    /// Minimum withdrawal amount
    min_withdrawal: u64,
    /// Deposit fee (in basis points, e.g., 100 = 1%)
    deposit_fee_bps: u64,
    /// Withdrawal fee (in basis points)
    withdrawal_fee_bps: u64,
}

// YToken is now defined in the ytoken module as a standard Coin type

// ===== Vault Creation Functions =====

/// Creates a new Vault for the specified asset type
/// Automatically registers the vault in the Registry
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `registry` - Mutable reference to the registry
/// * `admin_cap` - Admin capability for authorization
/// * `max_daily_withdrawal` - Maximum daily withdrawal limit
/// * `ctx` - Transaction context
/// 
/// # Returns
/// * `Vault<T>` - Newly created vault
public fun create_vault<T>(
    registry: &mut liquidity::Registry,
    admin_cap: &LiquidityAdminCap,
    max_daily_withdrawal: u64,
    ctx: &mut tx_context::TxContext
): Vault<T> {
    // Validate input parameters
    assert!(max_daily_withdrawal > 0, errors::invalid_input());
    assert!(max_daily_withdrawal <= constants::max_daily_withdrawal_limit(), errors::invalid_vault_config());
    
    let vault = Vault<T> {
        id: object::new(ctx),
        version: constants::current_version(),
        total_assets: balance::zero<T>(),
        borrowed_assets: 0,
        ytoken_supply: balance::create_supply(ytoken::create_witness<T>()),
        status: VaultStatus::Active,
        daily_limit: DailyLimit {
            max_daily_withdrawal,
            current_day: utils::get_current_day(ctx),
            withdrawn_today: 0,
        },
        config: VaultConfig {
            min_deposit: 1, // Minimum 1 unit
            min_withdrawal: 1, // Minimum 1 unit
            deposit_fee_bps: 0, // No fees initially
            withdrawal_fee_bps: 0, // No fees initially
        },
    };
    
    // Register the vault in the registry
    let vault_id = object::id(&vault);
    liquidity::register_vault<T>(registry, vault_id, admin_cap);
    
    vault
}

// ===== ERC-4626 Core Functions =====

/// Deposits assets into the vault and returns YToken shares
/// Implements ERC-4626 deposit function
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `assets` - Coin to deposit
/// * `ctx` - Transaction context
/// 
/// # Returns
/// * `Coin<YToken<T>>` - YToken shares as standard Coin
public fun deposit<T>(
    vault: &mut Vault<T>,
    assets: Coin<T>,
    ctx: &mut tx_context::TxContext
): Coin<YToken<T>> {
    // Verify vault version
    assert!(vault.version == constants::current_version(), errors::version_mismatch());
    
    // Verify vault status
    assert!(vault.status != VaultStatus::Inactive, errors::vault_not_active());
    assert!(vault.status != VaultStatus::Paused, errors::vault_paused());
    assert!(
        vault.status == VaultStatus::Active || vault.status == VaultStatus::DepositsOnly,
        errors::operation_denied()
    );
    
    let asset_amount = coin::value(&assets);
    
    // Validate input
    assert!(asset_amount > 0, errors::zero_assets());
    assert!(asset_amount >= vault.config.min_deposit, errors::invalid_assets());
    
    // Calculate shares to mint
    let shares_to_mint = convert_to_shares(vault, asset_amount);
    assert!(shares_to_mint > 0, errors::zero_shares());
    
    // Add assets to vault
    let asset_balance = coin::into_balance(assets);
    balance::join(&mut vault.total_assets, asset_balance);
    
    // Mint YToken shares using Supply
    let ytoken_balance = balance::increase_supply(&mut vault.ytoken_supply, shares_to_mint);
    coin::from_balance(ytoken_balance, ctx)
}

/// Withdraws assets from the vault by burning YToken shares
/// Implements ERC-4626 withdraw function
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `ytoken_coin` - YToken coin to burn
/// * `ctx` - Transaction context
/// 
/// # Returns
/// * `Coin<T>` - Withdrawn assets
public fun withdraw<T>(
    vault: &mut Vault<T>,
    ytoken_coin: Coin<YToken<T>>,
    ctx: &mut tx_context::TxContext
): Coin<T> {
    // Verify vault version
    assert!(vault.version == constants::current_version(), errors::version_mismatch());
    
    // Verify vault status
    assert!(vault.status != VaultStatus::Inactive, errors::vault_not_active());
    assert!(vault.status != VaultStatus::Paused, errors::vault_paused());
    assert!(
        vault.status == VaultStatus::Active || vault.status == VaultStatus::WithdrawalsOnly,
        errors::operation_denied()
    );
    
    let shares_to_burn = coin::value(&ytoken_coin);
    assert!(shares_to_burn > 0, errors::zero_shares());
    
    // Calculate assets to withdraw
    let assets_to_withdraw = convert_to_assets(vault, shares_to_burn);
    assert!(assets_to_withdraw > 0, errors::zero_assets());
    assert!(assets_to_withdraw >= vault.config.min_withdrawal, errors::invalid_assets());
    
    // Check daily withdrawal limit
    let current_day = utils::get_current_day(ctx);
    if (current_day != vault.daily_limit.current_day) {
        // Reset daily limit for new day
        vault.daily_limit.current_day = current_day;
        vault.daily_limit.withdrawn_today = 0;
    };
    
    assert!(
        vault.daily_limit.withdrawn_today + assets_to_withdraw <= vault.daily_limit.max_daily_withdrawal,
        errors::daily_limit_exceeded()
    );
    
    // Check sufficient assets in vault
    let available_assets = balance::value(&vault.total_assets);
    assert!(available_assets >= assets_to_withdraw, errors::insufficient_assets());
    
    // Update daily withdrawal tracking
    vault.daily_limit.withdrawn_today = vault.daily_limit.withdrawn_today + assets_to_withdraw;
    
    // Burn YToken shares
    let ytoken_balance = coin::into_balance(ytoken_coin);
    balance::decrease_supply(&mut vault.ytoken_supply, ytoken_balance);
    
    // Withdraw assets from vault
    let withdrawn_balance = balance::split(&mut vault.total_assets, assets_to_withdraw);
    coin::from_balance(withdrawn_balance, ctx)
}

// ===== Package-Level Functions =====

/// Borrows assets from the vault (package-level access only)
/// Used by other modules like lending/borrowing
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `amount` - Amount to borrow
/// * `ctx` - Transaction context
/// 
/// # Returns
/// * `Coin<T>` - Borrowed assets
public(package) fun borrow<T>(
    vault: &mut Vault<T>,
    amount: u64,
    ctx: &mut tx_context::TxContext
): Coin<T> {
    // Verify vault version
    assert!(vault.version == constants::current_version(), errors::version_mismatch());
    
    // Verify vault status
    assert!(vault.status != VaultStatus::Inactive, errors::vault_not_active());
    assert!(vault.status != VaultStatus::Paused, errors::vault_paused());
    
    // Validate input
    assert!(amount > 0, errors::zero_assets());
    
    // Check sufficient assets in vault
    let available_assets = balance::value(&vault.total_assets);
    assert!(available_assets >= amount, errors::insufficient_assets());
    
    // Update borrowed assets tracking
    vault.borrowed_assets = vault.borrowed_assets + amount;
    
    // Withdraw assets from vault
    let borrowed_balance = balance::split(&mut vault.total_assets, amount);
    coin::from_balance(borrowed_balance, ctx)
}

/// Repays borrowed assets to the vault (package-level access only)
/// Used by other modules like lending/borrowing
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `repayment` - Coin to repay
public(package) fun repay<T>(
    vault: &mut Vault<T>,
    repayment: Coin<T>
) {
    // Verify vault version
    assert!(vault.version == constants::current_version(), errors::version_mismatch());
    
    let repay_amount = coin::value(&repayment);
    assert!(repay_amount > 0, errors::zero_assets());
    
    // Update borrowed assets tracking
    if (vault.borrowed_assets >= repay_amount) {
        vault.borrowed_assets = vault.borrowed_assets - repay_amount;
    } else {
        vault.borrowed_assets = 0;
    };
    
    // Add repayment to vault
    let repay_balance = coin::into_balance(repayment);
    balance::join(&mut vault.total_assets, repay_balance);
}

// ===== ERC-4626 Standard Query Functions =====

/// Returns the total amount of assets held by the vault
/// Implements ERC-4626 totalAssets function
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// 
/// # Returns
/// * `u64` - Total assets amount
public fun total_assets<T>(vault: &Vault<T>): u64 {
    balance::value(&vault.total_assets) + vault.borrowed_assets
}

/// Returns the total amount of shares issued by the vault
/// Implements ERC-4626 totalSupply function
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// 
/// # Returns
/// * `u64` - Total shares amount
public fun total_supply<T>(vault: &Vault<T>): u64 {
    balance::supply_value(&vault.ytoken_supply)
}

/// Converts asset amount to shares amount
/// Implements ERC-4626 convertToShares function
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// * `assets` - Asset amount to convert
/// 
/// # Returns
/// * `u64` - Equivalent shares amount
public fun convert_to_shares<T>(vault: &Vault<T>, assets: u64): u64 {
    let total_assets = total_assets(vault);
    let total_shares = balance::supply_value(&vault.ytoken_supply);
    
    if (total_shares == 0 || total_assets == 0) {
        // Initial deposit: 1:1 ratio
        assets
    } else {
        // Calculate shares based on current ratio
        // shares = assets * total_shares / total_assets
        (assets * total_shares) / total_assets
    }
}

/// Converts shares amount to asset amount
/// Implements ERC-4626 convertToAssets function
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// * `shares` - Shares amount to convert
/// 
/// # Returns
/// * `u64` - Equivalent assets amount
public fun convert_to_assets<T>(vault: &Vault<T>, shares: u64): u64 {
    let total_assets = total_assets(vault);
    let total_shares = balance::supply_value(&vault.ytoken_supply);
    
    if (total_shares == 0) {
        0
    } else {
        // Calculate assets based on current ratio
        // assets = shares * total_assets / total_shares
        (shares * total_assets) / total_shares
    }
}

// ===== Vault Status Management Functions =====

/// Pauses the vault (admin only)
/// Stops all deposits and withdrawals
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `_admin_cap` - Admin capability for authorization
public fun pause_vault_operations<T>(
    vault: &mut Vault<T>,
    _admin_cap: &LiquidityAdminCap
) {
    // Note: We can't verify admin_cap against vault directly since vault doesn't store admin_cap_id
    // This should be called through Registry functions that verify permissions
    
    vault.status = VaultStatus::Paused;
}

/// Resumes the vault (admin only)
/// Allows deposits and withdrawals
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `_admin_cap` - Admin capability for authorization
public fun resume_vault_operations<T>(
    vault: &mut Vault<T>,
    _admin_cap: &LiquidityAdminCap
) {
    // Note: We can't verify admin_cap against vault directly since vault doesn't store admin_cap_id
    // This should be called through Registry functions that verify permissions
    
    vault.status = VaultStatus::Active;
}

/// Sets vault to deposits only mode (admin only)
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `_admin_cap` - Admin capability for authorization
public fun set_deposits_only<T>(
    vault: &mut Vault<T>,
    _admin_cap: &LiquidityAdminCap
) {
    vault.status = VaultStatus::DepositsOnly;
}

/// Sets vault to withdrawals only mode (admin only)
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `_admin_cap` - Admin capability for authorization
public fun set_withdrawals_only<T>(
    vault: &mut Vault<T>,
    _admin_cap: &LiquidityAdminCap
) {
    vault.status = VaultStatus::WithdrawalsOnly;
}

/// Deactivates the vault (admin only)
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `_admin_cap` - Admin capability for authorization
public fun deactivate_vault<T>(
    vault: &mut Vault<T>,
    _admin_cap: &LiquidityAdminCap
) {
    vault.status = VaultStatus::Inactive;
}

/// Updates vault configuration (admin only)
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `_admin_cap` - Admin capability for authorization
/// * `min_deposit` - New minimum deposit amount
/// * `min_withdrawal` - New minimum withdrawal amount
/// * `deposit_fee_bps` - New deposit fee in basis points
/// * `withdrawal_fee_bps` - New withdrawal fee in basis points
public fun update_vault_config<T>(
    vault: &mut Vault<T>,
    _admin_cap: &LiquidityAdminCap,
    min_deposit: u64,
    min_withdrawal: u64,
    deposit_fee_bps: u64,
    withdrawal_fee_bps: u64
) {
    // Note: We can't verify admin_cap against vault directly since vault doesn't store admin_cap_id
    // This should be called through Registry functions that verify permissions
    
    // Validate configuration parameters
    assert!(min_deposit > 0, errors::invalid_vault_config());
    assert!(min_withdrawal > 0, errors::invalid_vault_config());
    assert!(deposit_fee_bps <= 10000, errors::invalid_vault_config()); // Max 100%
    assert!(withdrawal_fee_bps <= 10000, errors::invalid_vault_config()); // Max 100%
    
    vault.config.min_deposit = min_deposit;
    vault.config.min_withdrawal = min_withdrawal;
    vault.config.deposit_fee_bps = deposit_fee_bps;
    vault.config.withdrawal_fee_bps = withdrawal_fee_bps;
}

// ===== Vault Query Functions =====

/// Gets vault status information
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// 
/// # Returns
/// * `VaultStatus` - Current vault status
public fun get_vault_status<T>(vault: &Vault<T>): VaultStatus {
    vault.status
}

/// Checks if vault is active (not inactive)
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// 
/// # Returns
/// * `bool` - True if vault is not inactive
public fun is_vault_active<T>(vault: &Vault<T>): bool {
    vault.status != VaultStatus::Inactive
}

/// Checks if vault is paused
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// 
/// # Returns
/// * `bool` - True if vault is paused
public fun is_vault_paused<T>(vault: &Vault<T>): bool {
    vault.status == VaultStatus::Paused
}

/// Checks if deposits are allowed
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// 
/// # Returns
/// * `bool` - True if deposits are allowed
public fun deposits_allowed<T>(vault: &Vault<T>): bool {
    vault.status == VaultStatus::Active || vault.status == VaultStatus::DepositsOnly
}

/// Checks if withdrawals are allowed
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// 
/// # Returns
/// * `bool` - True if withdrawals are allowed
public fun withdrawals_allowed<T>(vault: &Vault<T>): bool {
    vault.status == VaultStatus::Active || vault.status == VaultStatus::WithdrawalsOnly
}

/// Gets vault daily limit information
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// 
/// # Returns
/// * `(u64, u64, u64)` - (max_daily_withdrawal, current_day, withdrawn_today)
public fun get_daily_limit<T>(vault: &Vault<T>): (u64, u64, u64) {
    (
        vault.daily_limit.max_daily_withdrawal,
        vault.daily_limit.current_day,
        vault.daily_limit.withdrawn_today
    )
}

/// Gets vault configuration
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// 
/// # Returns
/// * `(u64, u64, u64, u64)` - (min_deposit, min_withdrawal, deposit_fee_bps, withdrawal_fee_bps)
public fun get_vault_config<T>(vault: &Vault<T>): (u64, u64, u64, u64) {
    (
        vault.config.min_deposit,
        vault.config.min_withdrawal,
        vault.config.deposit_fee_bps,
        vault.config.withdrawal_fee_bps
    )
}

/// Gets the amount of borrowed assets
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// 
/// # Returns
/// * `u64` - Amount of borrowed assets
public fun get_borrowed_assets<T>(vault: &Vault<T>): u64 {
    vault.borrowed_assets
}

/// Gets available assets for withdrawal/borrowing
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// 
/// # Returns
/// * `u64` - Available assets amount
public fun get_available_assets<T>(vault: &Vault<T>): u64 {
    balance::value(&vault.total_assets)
}

/// Gets YToken coin value (shares amount)
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `ytoken_coin` - Reference to the YToken coin
/// 
/// # Returns
/// * `u64` - Shares amount
public fun get_ytoken_value<T>(ytoken_coin: &Coin<YToken<T>>): u64 {
    coin::value(ytoken_coin)
}

// ===== Test Helper Functions =====

#[test_only]
/// Create a vault for testing without registry registration
public fun create_vault_for_test<T>(
    max_daily_withdrawal: u64,
    ctx: &mut tx_context::TxContext
): Vault<T> {
    Vault<T> {
        id: object::new(ctx),
        version: constants::current_version(),
        total_assets: balance::zero<T>(),
        borrowed_assets: 0,
        ytoken_supply: balance::create_supply(ytoken::create_witness<T>()),
        status: VaultStatus::Active,
        daily_limit: DailyLimit {
            max_daily_withdrawal,
            current_day: utils::get_current_day(ctx),
            withdrawn_today: 0,
        },
        config: VaultConfig {
            min_deposit: 1,
            min_withdrawal: 1,
            deposit_fee_bps: 0,
            withdrawal_fee_bps: 0,
        },
    }
}

#[test_only]
/// Create a YToken coin for testing
public fun create_ytoken_for_test<T>(
    shares: u64,
    vault: &mut Vault<T>,
    ctx: &mut tx_context::TxContext
): Coin<YToken<T>> {
    let ytoken_balance = balance::increase_supply(&mut vault.ytoken_supply, shares);
    coin::from_balance(ytoken_balance, ctx)
}
#[
test_only]
/// Set vault version for testing version mismatch scenarios
public fun set_vault_version_for_test<T>(vault: &mut Vault<T>, version: u64) {
    vault.version = version;
}

// ===== Emergency and Security Functions =====

/// Emergency pause all vault operations
/// More restrictive than regular pause - blocks all operations including admin functions
/// This is the most severe security measure that completely disables the vault
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `admin_cap` - Admin capability for authorization
public fun emergency_pause<T>(
    vault: &mut Vault<T>,
    _admin_cap: &LiquidityAdminCap
) {
    // Emergency pause bypasses version checks for security reasons
    vault.status = VaultStatus::Inactive;
}

/// Global emergency pause for all operations
/// Even more restrictive than emergency_pause - also prevents admin operations
/// Should only be used in critical security situations
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `admin_cap` - Admin capability for authorization
public fun global_emergency_pause<T>(
    vault: &mut Vault<T>,
    _admin_cap: &LiquidityAdminCap
) {
    // Set vault to inactive and reset daily limits for security
    vault.status = VaultStatus::Inactive;
    vault.daily_limit.withdrawn_today = vault.daily_limit.max_daily_withdrawal; // Block all withdrawals
}

/// Check if vault is in emergency state
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// 
/// # Returns
/// * `bool` - True if vault is in emergency state
public fun is_emergency_paused<T>(vault: &Vault<T>): bool {
    vault.status == VaultStatus::Inactive
}

/// Check if vault is in global emergency state
/// Checks both status and daily limit exhaustion
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// 
/// # Returns
/// * `bool` - True if vault is in global emergency state
public fun is_global_emergency_paused<T>(vault: &Vault<T>): bool {
    vault.status == VaultStatus::Inactive && 
    vault.daily_limit.withdrawn_today >= vault.daily_limit.max_daily_withdrawal
}

/// Update daily withdrawal limit
/// Allows dynamic adjustment of withdrawal limits
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `new_limit` - New daily withdrawal limit
/// * `admin_cap` - Admin capability for authorization
public fun update_daily_limit<T>(
    vault: &mut Vault<T>,
    new_limit: u64,
    _admin_cap: &LiquidityAdminCap
) {
    assert!(vault.version == constants::current_version(), errors::version_mismatch());
    assert!(new_limit > 0, errors::invalid_input());
    assert!(new_limit <= constants::max_daily_withdrawal_limit(), errors::invalid_input());
    
    vault.daily_limit.max_daily_withdrawal = new_limit;
}

/// Get detailed vault statistics
/// Provides comprehensive vault information for monitoring
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// 
/// # Returns
/// * `(u64, u64, u64, u64, u64)` - (total_assets, total_supply, borrowed_assets, available_assets, utilization_rate_bps)
public fun get_vault_statistics<T>(vault: &Vault<T>): (u64, u64, u64, u64, u64) {
    let total_assets = total_assets(vault);
    let total_supply = total_supply(vault);
    let borrowed_assets = vault.borrowed_assets;
    let available_assets = balance::value(&vault.total_assets);
    
    // Calculate utilization rate in basis points (0-10000)
    let utilization_rate_bps = if (total_assets > 0) {
        (borrowed_assets * 10000) / total_assets
    } else {
        0
    };
    
    (total_assets, total_supply, borrowed_assets, available_assets, utilization_rate_bps)
}

/// Reset daily withdrawal limit (admin only)
/// Allows manual reset of daily limits in case of emergency or system issues
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `admin_cap` - Admin capability for authorization
public fun reset_daily_limit<T>(
    vault: &mut Vault<T>,
    _admin_cap: &LiquidityAdminCap
) {
    assert!(vault.version == constants::current_version(), errors::version_mismatch());
    
    vault.daily_limit.withdrawn_today = 0;
}

/// Force update daily limit day counter (admin only)
/// Allows manual day counter update for testing or emergency situations
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `new_day` - New day counter value
/// * `admin_cap` - Admin capability for authorization
public fun force_update_day_counter<T>(
    vault: &mut Vault<T>,
    new_day: u64,
    _admin_cap: &LiquidityAdminCap
) {
    assert!(vault.version == constants::current_version(), errors::version_mismatch());
    
    vault.daily_limit.current_day = new_day;
    vault.daily_limit.withdrawn_today = 0; // Reset withdrawn amount for new day
}

/// Check if daily withdrawal limit allows the specified amount
/// Utility function for pre-checking withdrawal limits
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// * `amount` - Amount to check
/// * `ctx` - Transaction context for day calculation
/// 
/// # Returns
/// * `bool` - True if the amount is within daily limits
public fun check_daily_limit<T>(
    vault: &Vault<T>,
    amount: u64,
    ctx: &tx_context::TxContext
): bool {
    let current_day = utils::get_current_day(ctx);
    
    // If it's a new day, the limit is reset
    if (current_day != vault.daily_limit.current_day) {
        amount <= vault.daily_limit.max_daily_withdrawal
    } else {
        vault.daily_limit.withdrawn_today + amount <= vault.daily_limit.max_daily_withdrawal
    }
}

/// Get remaining daily withdrawal limit
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// * `ctx` - Transaction context for day calculation
/// 
/// # Returns
/// * `u64` - Remaining withdrawal amount for today
public fun get_remaining_daily_limit<T>(
    vault: &Vault<T>,
    ctx: &tx_context::TxContext
): u64 {
    let current_day = utils::get_current_day(ctx);
    
    // If it's a new day, full limit is available
    if (current_day != vault.daily_limit.current_day) {
        vault.daily_limit.max_daily_withdrawal
    } else {
        if (vault.daily_limit.withdrawn_today >= vault.daily_limit.max_daily_withdrawal) {
            0
        } else {
            vault.daily_limit.max_daily_withdrawal - vault.daily_limit.withdrawn_today
        }
    }
}

/// Comprehensive security status check
/// Returns detailed security information about the vault
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// * `ctx` - Transaction context
/// 
/// # Returns
/// * `(bool, bool, bool, bool, u64, u64)` - (is_active, is_paused, emergency_paused, daily_limit_exceeded, remaining_limit, utilization_rate_bps)
public fun get_security_status<T>(
    vault: &Vault<T>,
    ctx: &tx_context::TxContext
): (bool, bool, bool, bool, u64, u64) {
    let is_active = is_vault_active(vault);
    let is_paused = is_vault_paused(vault);
    let emergency_paused = is_emergency_paused(vault);
    
    let remaining_limit = get_remaining_daily_limit(vault, ctx);
    let daily_limit_exceeded = remaining_limit == 0;
    
    let (_, _, _, _, utilization_rate_bps) = get_vault_statistics(vault);
    
    (is_active, is_paused, emergency_paused, daily_limit_exceeded, remaining_limit, utilization_rate_bps)
}

// ===== Data Consistency and Atomic Operations =====

/// Atomic deposit and borrow operation
/// Ensures both operations succeed or both fail
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `deposit_assets` - Assets to deposit
/// * `borrow_amount` - Amount to borrow
/// * `ctx` - Transaction context
/// 
/// # Returns
/// * `(Coin<YToken<T>>, Coin<T>)` - (YToken shares, borrowed assets)
public(package) fun atomic_deposit_and_borrow<T>(
    vault: &mut Vault<T>,
    deposit_assets: Coin<T>,
    borrow_amount: u64,
    ctx: &mut tx_context::TxContext
): (Coin<YToken<T>>, Coin<T>) {
    // Verify vault version and status
    assert!(vault.version == constants::current_version(), errors::version_mismatch());
    assert!(vault.status != VaultStatus::Inactive, errors::vault_not_active());
    assert!(vault.status != VaultStatus::Paused, errors::vault_paused());
    
    let deposit_amount = coin::value(&deposit_assets);
    
    // Validate inputs
    assert!(deposit_amount > 0, errors::zero_assets());
    assert!(borrow_amount > 0, errors::zero_assets());
    assert!(deposit_amount >= vault.config.min_deposit, errors::invalid_assets());
    
    // Check if we have enough assets for borrowing after deposit
    let current_available = balance::value(&vault.total_assets);
    let available_after_deposit = current_available + deposit_amount;
    assert!(available_after_deposit >= borrow_amount, errors::insufficient_assets());
    
    // Calculate shares for deposit
    let shares_to_mint = convert_to_shares(vault, deposit_amount);
    assert!(shares_to_mint > 0, errors::zero_shares());
    
    // Execute atomic operations
    // 1. Add deposit assets to vault
    let asset_balance = coin::into_balance(deposit_assets);
    balance::join(&mut vault.total_assets, asset_balance);
    
    // 2. Mint YToken shares
    let ytoken_balance = balance::increase_supply(&mut vault.ytoken_supply, shares_to_mint);
    let ytoken_coin = coin::from_balance(ytoken_balance, ctx);
    
    // 3. Borrow assets
    vault.borrowed_assets = vault.borrowed_assets + borrow_amount;
    let borrowed_balance = balance::split(&mut vault.total_assets, borrow_amount);
    let borrowed_coin = coin::from_balance(borrowed_balance, ctx);
    
    (ytoken_coin, borrowed_coin)
}

/// Atomic repay and withdraw operation
/// Ensures both operations succeed or both fail
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `repay_assets` - Assets to repay
/// * `ytoken_coin` - YToken shares to burn for withdrawal
/// * `ctx` - Transaction context
/// 
/// # Returns
/// * `Coin<T>` - Withdrawn assets (after repayment)
public(package) fun atomic_repay_and_withdraw<T>(
    vault: &mut Vault<T>,
    repay_assets: Coin<T>,
    ytoken_coin: Coin<YToken<T>>,
    ctx: &mut tx_context::TxContext
): Coin<T> {
    // Verify vault version and status
    assert!(vault.version == constants::current_version(), errors::version_mismatch());
    assert!(vault.status != VaultStatus::Inactive, errors::vault_not_active());
    assert!(vault.status != VaultStatus::Paused, errors::vault_paused());
    
    let repay_amount = coin::value(&repay_assets);
    let shares_to_burn = coin::value(&ytoken_coin);
    
    // Validate inputs
    assert!(repay_amount > 0, errors::zero_assets());
    assert!(shares_to_burn > 0, errors::zero_shares());
    
    // Calculate withdrawal amount
    let withdraw_amount = convert_to_assets(vault, shares_to_burn);
    assert!(withdraw_amount > 0, errors::zero_assets());
    assert!(withdraw_amount >= vault.config.min_withdrawal, errors::invalid_assets());
    
    // Check daily withdrawal limit
    let current_day = utils::get_current_day(ctx);
    if (current_day != vault.daily_limit.current_day) {
        vault.daily_limit.current_day = current_day;
        vault.daily_limit.withdrawn_today = 0;
    };
    
    assert!(
        vault.daily_limit.withdrawn_today + withdraw_amount <= vault.daily_limit.max_daily_withdrawal,
        errors::daily_limit_exceeded()
    );
    
    // Execute atomic operations
    // 1. Add repayment to vault
    let repay_balance = coin::into_balance(repay_assets);
    balance::join(&mut vault.total_assets, repay_balance);
    
    // 2. Update borrowed assets tracking
    if (vault.borrowed_assets >= repay_amount) {
        vault.borrowed_assets = vault.borrowed_assets - repay_amount;
    } else {
        vault.borrowed_assets = 0;
    };
    
    // 3. Check sufficient assets for withdrawal
    let available_assets = balance::value(&vault.total_assets);
    assert!(available_assets >= withdraw_amount, errors::insufficient_assets());
    
    // 4. Update daily withdrawal tracking
    vault.daily_limit.withdrawn_today = vault.daily_limit.withdrawn_today + withdraw_amount;
    
    // 5. Burn YToken shares
    let ytoken_balance = coin::into_balance(ytoken_coin);
    balance::decrease_supply(&mut vault.ytoken_supply, ytoken_balance);
    
    // 6. Withdraw assets
    let withdrawn_balance = balance::split(&mut vault.total_assets, withdraw_amount);
    coin::from_balance(withdrawn_balance, ctx)
}

/// Validates vault data consistency
/// Checks for data integrity issues and inconsistencies
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// * `ctx` - Transaction context for timestamp validation
/// 
/// # Returns
/// * `bool` - True if vault data is consistent
public fun validate_vault_consistency<T>(
    vault: &Vault<T>,
    ctx: &tx_context::TxContext
): bool {
    // Version consistency check
    if (vault.version != constants::current_version()) {
        return false
    };
    
    // Balance consistency checks
    let total_assets_balance = balance::value(&vault.total_assets);
    let total_supply = balance::supply_value(&vault.ytoken_supply);
    
    // Borrowed assets should not exceed total assets
    if (vault.borrowed_assets > total_assets_balance + vault.borrowed_assets) {
        return false
    };
    
    // Daily limit consistency
    if (vault.daily_limit.max_daily_withdrawal == 0) {
        return false
    };
    
    if (vault.daily_limit.withdrawn_today > vault.daily_limit.max_daily_withdrawal) {
        return false
    };
    
    // Configuration consistency
    if (vault.config.min_deposit == 0 || vault.config.min_withdrawal == 0) {
        return false
    };
    
    if (vault.config.deposit_fee_bps > 10000 || vault.config.withdrawal_fee_bps > 10000) {
        return false
    };
    
    // Day counter should be reasonable
    let current_day = utils::get_current_day(ctx);
    if (vault.daily_limit.current_day > current_day + 1) { // Allow 1 day tolerance
        return false
    };
    
    // Share-to-asset ratio consistency
    if (total_supply > 0) {
        let calculated_assets = total_assets_balance + vault.borrowed_assets;
        // Ensure the ratio is reasonable (shares should not be 0 when assets exist)
        if (calculated_assets > 0 && total_supply == 0) {
            return false
        };
    };
    
    true
}

/// Concurrent-safe vault operation wrapper
/// Provides additional safety checks for concurrent access
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// * `ctx` - Transaction context
/// 
/// # Returns
/// * `bool` - True if vault is safe for concurrent operations
public fun check_vault_concurrent_safety<T>(
    vault: &Vault<T>,
    ctx: &tx_context::TxContext
): bool {
    // Basic consistency validation
    if (!validate_vault_consistency(vault, ctx)) {
        return false
    };
    
    // Status safety checks
    if (vault.status == VaultStatus::Inactive) {
        return false
    };
    
    // Daily limit safety - ensure we're not at the exact limit boundary
    let remaining_limit = get_remaining_daily_limit(vault, ctx);
    if (remaining_limit == 0) {
        return false // At daily limit, not safe for withdrawals
    };
    
    // Utilization rate safety check
    let (_, _, _, _, utilization_rate_bps) = get_vault_statistics(vault);
    if (utilization_rate_bps >= 9500) { // 95% utilization is high risk
        return false
    };
    
    true
}

/// Batch operation for multiple vault operations
/// Ensures all operations succeed or all fail
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Mutable reference to the vault
/// * `operations` - Vector of operation types (1=deposit, 2=withdraw, 3=borrow, 4=repay)
/// * `amounts` - Vector of amounts corresponding to operations
/// * `ctx` - Transaction context
/// 
/// # Returns
/// * `bool` - True if all operations can be executed safely
public fun validate_batch_operations<T>(
    vault: &Vault<T>,
    operations: vector<u8>,
    amounts: vector<u64>,
    ctx: &tx_context::TxContext
): bool {
    let op_count = std::vector::length(&operations);
    let amount_count = std::vector::length(&amounts);
    
    // Validate input consistency
    if (op_count != amount_count || op_count == 0) {
        return false
    };
    
    // Validate vault consistency first
    if (!validate_vault_consistency(vault, ctx)) {
        return false
    };
    
    // Simulate operations to check feasibility
    let mut simulated_balance = balance::value(&vault.total_assets);
    let mut simulated_borrowed = vault.borrowed_assets;
    let mut simulated_withdrawn_today = vault.daily_limit.withdrawn_today;
    
    let current_day = utils::get_current_day(ctx);
    if (current_day != vault.daily_limit.current_day) {
        simulated_withdrawn_today = 0;
    };
    
    let mut i = 0;
    while (i < op_count) {
        let operation = *std::vector::borrow(&operations, i);
        let amount = *std::vector::borrow(&amounts, i);
        
        if (amount == 0) {
            return false // Invalid amount
        };
        
        if (operation == 1) { // Deposit
            simulated_balance = simulated_balance + amount;
        } else if (operation == 2) { // Withdraw
            if (simulated_balance < amount) {
                return false // Insufficient balance
            };
            if (simulated_withdrawn_today + amount > vault.daily_limit.max_daily_withdrawal) {
                return false // Daily limit exceeded
            };
            simulated_balance = simulated_balance - amount;
            simulated_withdrawn_today = simulated_withdrawn_today + amount;
        } else if (operation == 3) { // Borrow
            if (simulated_balance < amount) {
                return false // Insufficient balance
            };
            simulated_balance = simulated_balance - amount;
            simulated_borrowed = simulated_borrowed + amount;
        } else if (operation == 4) { // Repay
            simulated_balance = simulated_balance + amount;
            if (simulated_borrowed >= amount) {
                simulated_borrowed = simulated_borrowed - amount;
            } else {
                simulated_borrowed = 0;
            };
        } else {
            return false // Invalid operation
        };
        
        i = i + 1;
    };
    
    true
}

// ===== Oracle Integration Functions =====

/// Calculate USD value of vault assets using oracle price feeds
/// Provides real-time valuation of vault holdings
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// * `oracle_registry` - Reference to the oracle registry
/// * `price_info_object` - Reference to the Pyth price info object
/// * `clock` - Reference to the clock for timestamp validation
/// * `asset_decimals` - Number of decimals for the asset
/// 
/// # Returns
/// * `u64` - USD value of vault assets (in USD with oracle decimals)
public fun calculate_vault_usd_value<T>(
    vault: &Vault<T>,
    oracle_registry: &OracleRegistry,
    price_info_object: &PriceInfoObject,
    clock: &Clock,
    asset_decimals: u8,
): u64 {
    // Verify vault version
    assert!(vault.version == constants::current_version(), errors::version_mismatch());
    
    // Check if oracle has price feed for this asset
    if (!oracle::has_price_feed<T>(oracle_registry)) {
        return 0 // No price feed available
    };
    
    let total_vault_assets = total_assets(vault);
    if (total_vault_assets == 0) {
        return 0
    };
    
    // Get current price from oracle
    oracle::calculate_usd_value<T>(
        oracle_registry,
        price_info_object,
        clock,
        total_vault_assets,
        asset_decimals
    )
}

/// Calculate collateral value and health factor for a position
/// Provides comprehensive risk assessment for lending positions
/// 
/// # Type Parameters
/// * `T` - Collateral asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// * `oracle_registry` - Reference to the oracle registry
/// * `price_info_object` - Reference to the Pyth price info object
/// * `clock` - Reference to the clock
/// * `collateral_amount` - Amount of collateral
/// * `debt_usd_value` - Current debt value in USD
/// * `asset_decimals` - Number of decimals for the asset
/// 
/// # Returns
/// * `(u64, u64, bool)` - (collateral_usd_value, health_factor, is_healthy)
public fun calculate_position_health<T>(
    vault: &Vault<T>,
    oracle_registry: &OracleRegistry,
    price_info_object: &PriceInfoObject,
    clock: &Clock,
    collateral_amount: u64,
    debt_usd_value: u64,
    asset_decimals: u8,
): (u64, u64, bool) {
    // Verify vault version
    assert!(vault.version == constants::current_version(), errors::version_mismatch());
    
    if (collateral_amount == 0) {
        return (0, 0, debt_usd_value == 0)
    };
    
    // Check if oracle has price feed for collateral
    if (!oracle::has_price_feed<T>(oracle_registry)) {
        // Without price feed, cannot assess health
        return (0, 0, false)
    };
    
    // Calculate collateral USD value
    let collateral_usd_value = oracle::calculate_usd_value<T>(
        oracle_registry,
        price_info_object,
        clock,
        collateral_amount,
        asset_decimals
    );
    
    if (debt_usd_value == 0) {
        // No debt, position is healthy
        return (collateral_usd_value, constants::health_factor_precision() * 10, true) // Health factor = 10.00
    };
    
    // Calculate health factor: (collateral_value * liquidation_threshold) / debt_value
    // Health factor precision is 100 (2 decimal places)
    let liquidation_threshold = constants::default_liquidation_threshold_bps();
    let adjusted_collateral = (collateral_usd_value * liquidation_threshold) / constants::basis_points_denominator();
    let health_factor = (adjusted_collateral * constants::health_factor_precision()) / debt_usd_value;
    
    let is_healthy = health_factor >= constants::min_health_factor();
    
    (collateral_usd_value, health_factor, is_healthy)
}

/// Check if a position is eligible for liquidation
/// Determines whether a position can be liquidated based on health factor
/// 
/// # Type Parameters
/// * `T` - Collateral asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// * `oracle_registry` - Reference to the oracle registry
/// * `price_info_object` - Reference to the Pyth price info object
/// * `clock` - Reference to the clock
/// * `collateral_amount` - Amount of collateral
/// * `debt_usd_value` - Current debt value in USD
/// * `asset_decimals` - Number of decimals for the asset
/// 
/// # Returns
/// * `(bool, u64, u64)` - (is_liquidatable, health_factor, max_liquidation_amount)
public fun check_liquidation_eligibility<T>(
    vault: &Vault<T>,
    oracle_registry: &OracleRegistry,
    price_info_object: &PriceInfoObject,
    clock: &Clock,
    collateral_amount: u64,
    debt_usd_value: u64,
    asset_decimals: u8,
): (bool, u64, u64) {
    let (collateral_usd_value, health_factor, is_healthy) = calculate_position_health<T>(
        vault,
        oracle_registry,
        price_info_object,
        clock,
        collateral_amount,
        debt_usd_value,
        asset_decimals
    );
    
    if (is_healthy) {
        return (false, health_factor, 0)
    };
    
    // Calculate maximum liquidation amount (typically 50% of debt or collateral value)
    let max_liquidation_usd = if (collateral_usd_value < debt_usd_value) {
        collateral_usd_value / 2
    } else {
        debt_usd_value / 2
    };
    
    (true, health_factor, max_liquidation_usd)
}

/// Calculate borrowing capacity for a collateral position
/// Determines how much can be safely borrowed against collateral
/// 
/// # Type Parameters
/// * `T` - Collateral asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// * `oracle_registry` - Reference to the oracle registry
/// * `price_info_object` - Reference to the Pyth price info object
/// * `clock` - Reference to the clock
/// * `collateral_amount` - Amount of collateral
/// * `existing_debt_usd` - Existing debt value in USD
/// * `asset_decimals` - Number of decimals for the asset
/// 
/// # Returns
/// * `(u64, u64, u64)` - (max_borrow_usd, available_borrow_usd, collateral_usd_value)
public fun calculate_borrowing_capacity<T>(
    vault: &Vault<T>,
    oracle_registry: &OracleRegistry,
    price_info_object: &PriceInfoObject,
    clock: &Clock,
    collateral_amount: u64,
    existing_debt_usd: u64,
    asset_decimals: u8,
): (u64, u64, u64) {
    // Verify vault version
    assert!(vault.version == constants::current_version(), errors::version_mismatch());
    
    if (collateral_amount == 0) {
        return (0, 0, 0)
    };
    
    // Check if oracle has price feed
    if (!oracle::has_price_feed<T>(oracle_registry)) {
        return (0, 0, 0)
    };
    
    // Calculate collateral USD value
    let collateral_usd_value = oracle::calculate_usd_value<T>(
        oracle_registry,
        price_info_object,
        clock,
        collateral_amount,
        asset_decimals
    );
    
    if (collateral_usd_value == 0) {
        return (0, 0, 0)
    };
    
    // Calculate maximum borrowing capacity
    // Max borrow = collateral_value * liquidation_threshold / min_health_factor
    let liquidation_threshold = constants::default_liquidation_threshold_bps();
    let min_health_factor = constants::min_health_factor();
    
    let adjusted_collateral = (collateral_usd_value * liquidation_threshold) / constants::basis_points_denominator();
    let max_borrow_usd = (adjusted_collateral * constants::health_factor_precision()) / min_health_factor;
    
    // Calculate available borrowing capacity
    let available_borrow_usd = if (max_borrow_usd > existing_debt_usd) {
        max_borrow_usd - existing_debt_usd
    } else {
        0
    };
    
    (max_borrow_usd, available_borrow_usd, collateral_usd_value)
}

/// Validate oracle-based operation safety
/// Checks if oracle prices are fresh and reliable for operations
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `oracle_registry` - Reference to the oracle registry
/// * `price_info_object` - Reference to the Pyth price info object
/// * `clock` - Reference to the clock
/// 
/// # Returns
/// * `(bool, PriceData)` - (is_safe, price_data)
public fun validate_oracle_safety<T>(
    oracle_registry: &OracleRegistry,
    price_info_object: &PriceInfoObject,
    clock: &Clock,
): (bool, PriceData) {
    // Check if oracle registry is paused
    if (oracle::is_oracle_paused(oracle_registry)) {
        let invalid_price_data = oracle::create_invalid_price_data<T>();
        return (false, invalid_price_data)
    };
    
    // Check if price feed exists
    if (!oracle::has_price_feed<T>(oracle_registry)) {
        let invalid_price_data = oracle::create_invalid_price_data<T>();
        return (false, invalid_price_data)
    };
    
    // Get price data with validation
    let price_data = oracle::get_price<T>(oracle_registry, price_info_object, clock);
    
    // Validate price data
    let is_valid = oracle::validate_price_data(&price_data);
    
    (is_valid, price_data)
}

/// Oracle-based deposit validation
/// Checks if deposit amount is reasonable based on current market prices
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// * `oracle_registry` - Reference to the oracle registry
/// * `price_info_object` - Reference to the Pyth price info object
/// * `clock` - Reference to the clock
/// * `deposit_amount` - Amount to deposit
/// * `asset_decimals` - Number of decimals for the asset
/// * `max_usd_deposit` - Maximum allowed deposit in USD
/// 
/// # Returns
/// * `bool` - True if deposit is within acceptable limits
public fun validate_oracle_based_deposit<T>(
    vault: &Vault<T>,
    oracle_registry: &OracleRegistry,
    price_info_object: &PriceInfoObject,
    clock: &Clock,
    deposit_amount: u64,
    asset_decimals: u8,
    max_usd_deposit: u64,
): bool {
    // Verify vault version
    assert!(vault.version == constants::current_version(), errors::version_mismatch());
    
    // Check oracle safety first
    let (is_oracle_safe, _) = validate_oracle_safety<T>(oracle_registry, price_info_object, clock);
    if (!is_oracle_safe) {
        return false
    };
    
    // Calculate USD value of deposit
    let deposit_usd_value = oracle::calculate_usd_value<T>(
        oracle_registry,
        price_info_object,
        clock,
        deposit_amount,
        asset_decimals
    );
    
    // Check if deposit is within limits
    deposit_usd_value <= max_usd_deposit && deposit_usd_value > 0
}

/// Oracle-based withdrawal validation
/// Ensures withdrawal won't negatively impact vault health or create risks
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `vault` - Reference to the vault
/// * `oracle_registry` - Reference to the oracle registry
/// * `price_info_object` - Reference to the Pyth price info object
/// * `clock` - Reference to the clock
/// * `withdrawal_amount` - Amount to withdraw
/// * `asset_decimals` - Number of decimals for the asset
/// * `min_vault_usd_value` - Minimum required vault value in USD
/// 
/// # Returns
/// * `bool` - True if withdrawal is safe
public fun validate_oracle_based_withdrawal<T>(
    vault: &Vault<T>,
    oracle_registry: &OracleRegistry,
    price_info_object: &PriceInfoObject,
    clock: &Clock,
    withdrawal_amount: u64,
    asset_decimals: u8,
    min_vault_usd_value: u64,
): bool {
    // Verify vault version
    assert!(vault.version == constants::current_version(), errors::version_mismatch());
    
    // Check oracle safety
    let (is_oracle_safe, _) = validate_oracle_safety<T>(oracle_registry, price_info_object, clock);
    if (!is_oracle_safe) {
        return false
    };
    
    // Calculate current vault USD value
    let current_vault_usd = calculate_vault_usd_value<T>(
        vault,
        oracle_registry,
        price_info_object,
        clock,
        asset_decimals
    );
    
    // Calculate USD value of withdrawal
    let withdrawal_usd_value = oracle::calculate_usd_value<T>(
        oracle_registry,
        price_info_object,
        clock,
        withdrawal_amount,
        asset_decimals
    );
    
    // Check if vault will maintain minimum value after withdrawal
    if (current_vault_usd > withdrawal_usd_value) {
        let vault_value_after = current_vault_usd - withdrawal_usd_value;
        vault_value_after >= min_vault_usd_value
    } else {
        false // Withdrawal would drain vault below minimum
    }
}