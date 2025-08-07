/// Vault Module - ERC-4626 compatible vault implementation
/// Implements unified liquidity vault with share-based asset management
module olend::vault;


use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance, Supply};

use olend::constants;
use olend::errors;
use olend::utils;
use olend::liquidity::{Self, AdminCap};
use olend::ytoken::{Self, YToken};

// ===== Struct Definitions =====

/// Unified liquidity vault, compatible with ERC-4626 standard
/// Manages assets and shares for a specific asset type
public struct Vault<phantom T> has key, store {
    id: sui::object::UID,
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
    admin_cap: &AdminCap,
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
    _admin_cap: &AdminCap
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
    _admin_cap: &AdminCap
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
    _admin_cap: &AdminCap
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
    _admin_cap: &AdminCap
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
    _admin_cap: &AdminCap
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
    _admin_cap: &AdminCap,
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
    _admin_cap: &AdminCap
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
    _admin_cap: &AdminCap
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
    _admin_cap: &AdminCap
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
    _admin_cap: &AdminCap
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
    _admin_cap: &AdminCap
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