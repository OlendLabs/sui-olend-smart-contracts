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

/// Admin capability for permission control
/// Used to authorize administrative operations
public struct AdminCap has key, store {
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
/// * `AdminCap` - Admin capability for permission control
fun create_registry(ctx: &mut TxContext): (Registry, AdminCap) {
    let admin_cap = AdminCap {
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
    admin_cap: &AdminCap,
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
    admin_cap: &AdminCap,
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
    admin_cap: &AdminCap,
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
    admin_cap: &AdminCap,
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

// ===== Test Helper Functions =====

#[test_only]
/// Test access function to get VaultInfo
public fun get_vault_info_for_test<T>(registry: &Registry): &VaultInfo {
    let asset_type = type_name::get<T>();
    table::borrow(&registry.asset_vaults, asset_type)
}