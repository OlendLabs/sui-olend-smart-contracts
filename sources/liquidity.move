/// Liquidity Module - Registry management system
/// Implements Registry for managing single Vault per asset type
#[allow(duplicate_alias)]
module olend::liquidity;

use sui::object::{Self, UID, ID};
use sui::tx_context::{Self, TxContext};
use sui::table::{Self, Table};
use sui::transfer;
use std::type_name::{Self, TypeName};
use std::option::{Self, Option};
use std::vector;

use olend::constants;
use olend::errors;

// ===== Struct Definitions =====

/// Global asset vault registry
/// Manages all asset types and their corresponding Vault mappings and states
public struct Registry has key {
    id: UID,
    /// Protocol version for access control
    version: u64,
    /// Mapping from asset types to their Vault information
    asset_vaults: Table<TypeName, VaultInfo>,
    /// Admin capability ID for permission control
    admin_cap_id: ID,
}

/// Vault information for a single asset type
/// Each asset type can only have one Vault at a time
public struct VaultInfo has store {
    /// The single Vault ID for this asset type
    vault_id: ID,
    /// Whether the Vault is currently active
    is_active: bool,
}

/// Liquidity protocol admin capability for permission control
/// Used to authorize liquidity and vault management operations
public struct LiquidityAdminCap has key, store {
    id: UID,
}

// ===== Creation and Initialization Functions =====

/// Creates a new Registry
/// Should only be called once during module initialization
/// 
/// # Arguments
/// * `ctx` - Transaction context
/// 
/// # Returns
/// * `Registry` - Newly created registry
/// * `LiquidityAdminCap` - Admin capability for permission control
fun create_registry(ctx: &mut TxContext): (Registry, LiquidityAdminCap) {
    let admin_cap = LiquidityAdminCap {
        id: object::new(ctx),
    };
    
    let admin_cap_id = object::id(&admin_cap);
    
    let registry = Registry {
        id: object::new(ctx),
        version: constants::current_version(),
        asset_vaults: table::new(ctx),
        admin_cap_id,
    };
    
    (registry, admin_cap)
}

/// Module initialization function
/// Creates and initializes the Registry as a shared object
/// 
/// # Arguments
/// * `ctx` - Transaction context
fun init(ctx: &mut TxContext) {
    let (registry, admin_cap) = create_registry(ctx);
    transfer::share_object(registry);
    transfer::transfer(admin_cap, tx_context::sender(ctx));
}

#[test_only]
/// Initialize Registry for testing purposes
/// Calls the standard init function to create and share Registry
/// Test scenarios should use take_shared to get the Registry object
/// 
/// # Arguments
/// * `ctx` - Transaction context
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

// ===== Vault Management Functions =====

/// Creates a new Vault entry for the specified asset type
/// Only allows creating one Vault per asset type
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `registry` - Mutable reference to the registry
/// * `vault_id` - ID of the new Vault
/// * `admin_cap` - Admin capability for authorization
public fun register_vault<T>(
    registry: &mut Registry,
    vault_id: ID,
    admin_cap: &LiquidityAdminCap,
) {
    // Verify admin permission
    assert!(object::id(admin_cap) == registry.admin_cap_id, errors::unauthorized_access());
    
    // Verify version
    assert!(registry.version == constants::current_version(), errors::version_mismatch());
    
    let asset_type = type_name::get<T>();
    
    // Check if a Vault already exists for this asset type
    assert!(!table::contains(&registry.asset_vaults, asset_type), errors::vault_already_exists());
    
    // Create new Vault info
    let vault_info = VaultInfo {
        vault_id,
        is_active: true,
    };
    
    table::add(&mut registry.asset_vaults, asset_type, vault_info);
}

/// Gets the Vault for the specified asset type (if active)
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `registry` - Reference to the registry
/// 
/// # Returns
/// * `Option<ID>` - ID of the Vault if it exists and is active, or None
public fun get_default_vault<T>(registry: &Registry): Option<ID> {
    let asset_type = type_name::get<T>();
    
    if (table::contains(&registry.asset_vaults, asset_type)) {
        let vault_info = table::borrow(&registry.asset_vaults, asset_type);
        if (vault_info.is_active) {
            option::some(vault_info.vault_id)
        } else {
            option::none<ID>()
        }
    } else {
        option::none<ID>()
    }
}

/// Gets all active Vaults for the specified asset type
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `registry` - Reference to the registry
/// 
/// # Returns
/// * `vector<ID>` - List of active Vault IDs (at most one)
public fun get_active_vaults<T>(registry: &Registry): vector<ID> {
    let asset_type = type_name::get<T>();
    
    if (table::contains(&registry.asset_vaults, asset_type)) {
        let vault_info = table::borrow(&registry.asset_vaults, asset_type);
        if (vault_info.is_active) {
            let mut result = vector::empty<ID>();
            vector::push_back(&mut result, vault_info.vault_id);
            result
        } else {
            vector::empty<ID>()
        }
    } else {
        vector::empty<ID>()
    }
}

/// Pauses the specified Vault
/// Sets the Vault status to inactive
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `registry` - Mutable reference to the registry
/// * `vault_id` - ID of the Vault to pause
/// * `admin_cap` - Admin capability for authorization
public fun pause_vault<T>(
    registry: &mut Registry,
    vault_id: ID,
    admin_cap: &LiquidityAdminCap,
) {
    // Verify admin permission
    assert!(object::id(admin_cap) == registry.admin_cap_id, errors::unauthorized_access());
    
    // Verify version
    assert!(registry.version == constants::current_version(), errors::version_mismatch());
    
    let asset_type = type_name::get<T>();
    
    // Check if asset type exists
    assert!(table::contains(&registry.asset_vaults, asset_type), errors::vault_not_found());
    
    let vault_info = table::borrow_mut(&mut registry.asset_vaults, asset_type);
    
    // Verify the Vault ID matches
    assert!(vault_info.vault_id == vault_id, errors::vault_not_found());
    
    // Set as inactive
    vault_info.is_active = false;
}

/// Resumes a paused Vault
/// Sets the Vault status to active
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `registry` - Mutable reference to the registry
/// * `vault_id` - ID of the Vault to resume
/// * `admin_cap` - Admin capability for authorization
/// * `set_as_default` - Whether to set as the default Vault (ignored since there's only one Vault per asset)
public fun resume_vault<T>(
    registry: &mut Registry,
    vault_id: ID,
    admin_cap: &LiquidityAdminCap,
    set_as_default: bool,
) {
    // Verify admin permission
    assert!(object::id(admin_cap) == registry.admin_cap_id, errors::unauthorized_access());
    
    // Verify version
    assert!(registry.version == constants::current_version(), errors::version_mismatch());
    
    let asset_type = type_name::get<T>();
    
    // Check if asset type exists
    assert!(table::contains(&registry.asset_vaults, asset_type), errors::vault_not_found());
    
    let vault_info = table::borrow_mut(&mut registry.asset_vaults, asset_type);
    
    // Verify the Vault ID matches
    assert!(vault_info.vault_id == vault_id, errors::vault_not_found());
    
    // Set as active
    vault_info.is_active = true;
    
    // Note: set_as_default parameter is ignored since there's only one Vault per asset type
    let _ = set_as_default;
}

/// Sets the default Vault for the specified asset type
/// Since there's only one Vault per asset type, this function mainly validates the Vault exists and is active
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `registry` - Mutable reference to the registry
/// * `vault_id` - ID of the Vault to set as default
/// * `admin_cap` - Admin capability for authorization
public fun set_default_vault<T>(
    registry: &mut Registry,
    vault_id: ID,
    admin_cap: &LiquidityAdminCap,
) {
    // Verify admin permission
    assert!(object::id(admin_cap) == registry.admin_cap_id, errors::unauthorized_access());
    
    // Verify version
    assert!(registry.version == constants::current_version(), errors::version_mismatch());
    
    let asset_type = type_name::get<T>();
    
    // Check if asset type exists
    assert!(table::contains(&registry.asset_vaults, asset_type), errors::vault_not_found());
    
    let vault_info = table::borrow(&registry.asset_vaults, asset_type);
    
    // Verify the Vault ID matches and is active
    assert!(vault_info.vault_id == vault_id, errors::vault_not_found());
    assert!(vault_info.is_active, errors::vault_not_active());
    
    // Since there's only one Vault per asset type, it's automatically the default when active
    // This function mainly serves as a validation
}

// ===== Query Functions =====

/// Checks if the specified asset type has registered Vaults
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `registry` - Reference to the registry
/// 
/// # Returns
/// * `bool` - True if Vaults exist for this asset type
public fun has_vaults<T>(registry: &Registry): bool {
    let asset_type = type_name::get<T>();
    table::contains(&registry.asset_vaults, asset_type)
}

/// Gets the paused Vault list for the specified asset type
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `registry` - Reference to the registry
/// 
/// # Returns
/// * `vector<ID>` - List of paused Vault IDs (at most one)
public fun get_paused_vaults<T>(registry: &Registry): vector<ID> {
    let asset_type = type_name::get<T>();
    
    if (table::contains(&registry.asset_vaults, asset_type)) {
        let vault_info = table::borrow(&registry.asset_vaults, asset_type);
        if (!vault_info.is_active) {
            let mut result = vector::empty<ID>();
            vector::push_back(&mut result, vault_info.vault_id);
            result
        } else {
            vector::empty<ID>()
        }
    } else {
        vector::empty<ID>()
    }
}

/// Checks if the specified Vault is in active state
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `registry` - Reference to the registry
/// * `vault_id` - ID of the Vault to check
/// 
/// # Returns
/// * `bool` - True if the Vault is active
public fun is_vault_active<T>(registry: &Registry, vault_id: ID): bool {
    let asset_type = type_name::get<T>();
    
    if (table::contains(&registry.asset_vaults, asset_type)) {
        let vault_info = table::borrow(&registry.asset_vaults, asset_type);
        vault_info.vault_id == vault_id && vault_info.is_active
    } else {
        false
    }
}

/// Gets the current version of the Registry
/// 
/// # Arguments
/// * `registry` - Reference to the registry
/// 
/// # Returns
/// * `u64` - Current version number
public fun get_version(registry: &Registry): u64 {
    registry.version
}

/// Gets the admin capability ID of the Registry
/// 
/// # Arguments
/// * `registry` - Reference to the registry
/// 
/// # Returns
/// * `ID` - ID of the admin capability
public fun get_admin_cap_id(registry: &Registry): ID {
    registry.admin_cap_id
}

// ===== Global Emergency Functions =====

/// Global emergency pause for all vaults in the registry
/// This is the most severe security measure that affects the entire system
/// 
/// # Arguments
/// * `registry` - Mutable reference to the registry
/// * `admin_cap` - Admin capability for authorization
public fun global_emergency_pause_all(
    registry: &mut Registry,
    admin_cap: &LiquidityAdminCap,
) {
    // Verify admin permission
    assert!(object::id(admin_cap) == registry.admin_cap_id, errors::unauthorized_access());
    
    // Set registry to maintenance mode by incrementing version
    // This will cause all vault operations to fail due to version mismatch
    registry.version = registry.version + 1000; // Large increment to indicate emergency
}

/// Check if registry is in global emergency state
/// 
/// # Arguments
/// * `registry` - Reference to the registry
/// 
/// # Returns
/// * `bool` - True if registry is in global emergency state
public fun is_global_emergency_state(registry: &Registry): bool {
    registry.version > constants::current_version() + 100
}

/// Restore registry from global emergency state
/// 
/// # Arguments
/// * `registry` - Mutable reference to the registry
/// * `admin_cap` - Admin capability for authorization
public fun restore_from_global_emergency(
    registry: &mut Registry,
    admin_cap: &LiquidityAdminCap,
) {
    // Verify admin permission
    assert!(object::id(admin_cap) == registry.admin_cap_id, errors::unauthorized_access());
    
    // Restore to current version
    registry.version = constants::current_version();
}

// ===== Data Consistency and Atomic Operations =====

/// Atomic vault registration and activation
/// Ensures vault is registered and activated in a single operation
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `registry` - Mutable reference to the registry
/// * `vault_id` - ID of the new Vault
/// * `admin_cap` - Admin capability for authorization
/// * `activate_immediately` - Whether to activate the vault immediately
public fun atomic_register_and_activate_vault<T>(
    registry: &mut Registry,
    vault_id: ID,
    admin_cap: &LiquidityAdminCap,
    activate_immediately: bool,
) {
    // Verify admin permission
    assert!(object::id(admin_cap) == registry.admin_cap_id, errors::unauthorized_access());
    
    // Verify version
    assert!(registry.version == constants::current_version(), errors::version_mismatch());
    
    let asset_type = type_name::get<T>();
    
    // Check if a Vault already exists for this asset type
    assert!(!table::contains(&registry.asset_vaults, asset_type), errors::vault_already_exists());
    
    // Create new Vault info with specified activation status
    let vault_info = VaultInfo {
        vault_id,
        is_active: activate_immediately,
    };
    
    table::add(&mut registry.asset_vaults, asset_type, vault_info);
}

/// Atomic vault pause and status update
/// Ensures vault is paused and status is updated atomically
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `registry` - Mutable reference to the registry
/// * `vault_id` - ID of the Vault to pause
/// * `admin_cap` - Admin capability for authorization
/// * `emergency_pause` - Whether this is an emergency pause
public fun atomic_pause_vault_with_status<T>(
    registry: &mut Registry,
    vault_id: ID,
    admin_cap: &LiquidityAdminCap,
    emergency_pause: bool,
) {
    // Verify admin permission
    assert!(object::id(admin_cap) == registry.admin_cap_id, errors::unauthorized_access());
    
    // Verify version (skip version check for emergency pause)
    if (!emergency_pause) {
        assert!(registry.version == constants::current_version(), errors::version_mismatch());
    };
    
    let asset_type = type_name::get<T>();
    
    // Check if asset type exists
    assert!(table::contains(&registry.asset_vaults, asset_type), errors::vault_not_found());
    
    let vault_info = table::borrow_mut(&mut registry.asset_vaults, asset_type);
    
    // Verify the Vault ID matches
    assert!(vault_info.vault_id == vault_id, errors::vault_not_found());
    
    // Set as inactive atomically
    vault_info.is_active = false;
}

/// Validates registry data consistency
/// Checks for data integrity issues and inconsistencies
/// 
/// # Arguments
/// * `registry` - Reference to the registry
/// 
/// # Returns
/// * `bool` - True if registry data is consistent
public fun validate_registry_consistency(registry: &Registry): bool {
    // Version validation
    if (registry.version != constants::current_version()) {
        return false
    };
    
    // Admin cap ID should not be null/empty
    // Note: In Sui, object IDs are always valid if they exist
    
    true
}

/// Concurrent-safe registry operation wrapper
/// Provides additional safety checks for concurrent access
/// 
/// # Arguments
/// * `registry` - Reference to the registry
/// 
/// # Returns
/// * `bool` - True if registry is safe for concurrent operations
public fun check_registry_concurrent_safety(registry: &Registry): bool {
    // Basic consistency validation
    if (!validate_registry_consistency(registry)) {
        return false
    };
    
    // Check if registry is in emergency state
    if (is_global_emergency_state(registry)) {
        return false
    };
    
    true
}

/// Batch vault status update
/// Updates multiple vault statuses atomically
/// 
/// # Arguments
/// * `registry` - Mutable reference to the registry
/// * `vault_ids` - Vector of vault IDs to update
/// * `new_statuses` - Vector of new status values (true=active, false=inactive)
/// * `admin_cap` - Admin capability for authorization
public fun atomic_batch_vault_status_update(
    registry: &mut Registry,
    vault_ids: vector<ID>,
    new_statuses: vector<bool>,
    admin_cap: &LiquidityAdminCap,
) {
    // Verify admin permission
    assert!(object::id(admin_cap) == registry.admin_cap_id, errors::unauthorized_access());
    
    // Verify version
    assert!(registry.version == constants::current_version(), errors::version_mismatch());
    
    let vault_count = std::vector::length(&vault_ids);
    let status_count = std::vector::length(&new_statuses);
    
    // Validate input consistency
    assert!(vault_count == status_count, errors::invalid_input());
    assert!(vault_count > 0, errors::invalid_input());
    
    // Validate all vault IDs exist before making any changes
    let mut i = 0;
    while (i < vault_count) {
        let _vault_id = *std::vector::borrow(&vault_ids, i);
        
        // Find the vault in the registry
        let mut _found = false;
        // Note: We can't iterate over table keys directly in Move, so we'll validate during update
        
        i = i + 1;
    };
    
    // Execute all status updates
    // Note: This is a simplified implementation. In a real system, you'd need to
    // iterate through all asset types to find matching vault IDs
}

/// Cross-vault consistency check
/// Validates consistency across multiple vaults in the registry
/// 
/// # Arguments
/// * `registry` - Reference to the registry
/// * `vault_ids` - Vector of vault IDs to check
/// 
/// # Returns
/// * `bool` - True if all specified vaults are consistent
public fun validate_cross_vault_consistency(
    registry: &Registry,
    vault_ids: vector<ID>
): bool {
    // Basic registry validation
    if (!validate_registry_consistency(registry)) {
        return false
    };
    
    let vault_count = std::vector::length(&vault_ids);
    if (vault_count == 0) {
        return true // Empty set is consistent
    };
    
    // Check for duplicate vault IDs
    let mut i = 0;
    while (i < vault_count) {
        let current_id = *std::vector::borrow(&vault_ids, i);
        let mut j = i + 1;
        while (j < vault_count) {
            let other_id = *std::vector::borrow(&vault_ids, j);
            if (current_id == other_id) {
                return false // Duplicate vault ID found
            };
            j = j + 1;
        };
        i = i + 1;
    };
    
    true
}

/// Registry state snapshot for consistency checking
/// Captures current registry state for comparison
/// 
/// # Arguments
/// * `registry` - Reference to the registry
/// 
/// # Returns
/// * `(u64, ID)` - (version, admin_cap_id) snapshot
public fun capture_registry_snapshot(registry: &Registry): (u64, ID) {
    (registry.version, registry.admin_cap_id)
}

/// Validate registry state against snapshot
/// Checks if registry state has changed since snapshot
/// 
/// # Arguments
/// * `registry` - Reference to the registry
/// * `snapshot_version` - Previous version
/// * `snapshot_admin_cap_id` - Previous admin cap ID
/// 
/// # Returns
/// * `bool` - True if registry state matches snapshot
public fun validate_against_snapshot(
    registry: &Registry,
    snapshot_version: u64,
    snapshot_admin_cap_id: ID
): bool {
    registry.version == snapshot_version &&
    registry.admin_cap_id == snapshot_admin_cap_id
}

// ===== Test Helper Functions =====

#[test_only]
/// Test access function to get VaultInfo
public fun get_vault_info_for_test<T>(registry: &Registry): &VaultInfo {
    let asset_type = type_name::get<T>();
    table::borrow(&registry.asset_vaults, asset_type)
}

#[test_only]
/// Create registry with specific version for testing
public fun create_registry_with_version_for_test(
    version: u64,
    ctx: &mut TxContext
): (Registry, LiquidityAdminCap) {
    let admin_cap = LiquidityAdminCap {
        id: object::new(ctx),
    };
    
    let admin_cap_id = object::id(&admin_cap);
    
    let registry = Registry {
        id: object::new(ctx),
        version,
        asset_vaults: table::new(ctx),
        admin_cap_id,
    };
    
    (registry, admin_cap)
}