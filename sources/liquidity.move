/// Liquidity Module - Unified liquidity management system
/// Implements Registry and Vault management for the Olend DeFi platform
module olend::liquidity;

use sui::object::{UID, ID};
use sui::tx_context::TxContext;
use sui::table::{Self, Table};
use sui::transfer;
use std::type_name::{Self, TypeName};
use std::option::{Self, Option};

use olend::constants;
use olend::errors;

// ===== Struct Definitions =====

/// Global asset vault registry
/// Manages all asset types and their corresponding Vault mappings and states
public struct Registry has key {
    id: UID,
    /// Protocol version for access control
    version: u64,
    /// Mapping from asset types to their Vault lists
    asset_vaults: Table<TypeName, VaultList>,
    /// Admin capability ID for permission control
    admin_cap_id: ID,
}

/// Vault list management for a single asset type
/// Supports multiple Vault instances for the same asset type
public struct VaultList has store {
    /// List of active Vaults
    active_vaults: vector<ID>,
    /// Default Vault for new deposits
    default_vault: Option<ID>,
    /// List of paused Vaults
    paused_vaults: vector<ID>,
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
/// Only allows creating a new Vault if no active Vaults exist for this asset type
/// The new Vault automatically becomes the default Vault
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
    
    // Check if Vault list already exists for this asset type
    if (table::contains(&registry.asset_vaults, asset_type)) {
        let vault_list = table::borrow(&registry.asset_vaults, asset_type);
        
        // Check if there are any active Vaults - if so, cannot create new Vault
        assert!(vector::is_empty(&vault_list.active_vaults), errors::vault_already_exists());
        
        // If no active Vaults, we can create a new one
        let vault_list = table::borrow_mut(&mut registry.asset_vaults, asset_type);
        vector::push_back(&mut vault_list.active_vaults, vault_id);
        vault_list.default_vault = option::some(vault_id);
    } else {
        // Create new Vault list with the new Vault as default
        let mut active_vaults = vector::empty<ID>();
        vector::push_back(&mut active_vaults, vault_id);
        
        let vault_list = VaultList {
            active_vaults,
            default_vault: option::some(vault_id),
            paused_vaults: vector::empty<ID>(),
        };
        
        table::add(&mut registry.asset_vaults, asset_type, vault_list);
    };
}

/// Gets the default active Vault for the specified asset type
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `registry` - Reference to the registry
/// 
/// # Returns
/// * `Option<ID>` - ID of the default Vault, or None if it doesn't exist
public fun get_default_vault<T>(registry: &Registry): Option<ID> {
    let asset_type = type_name::get<T>();
    
    if (table::contains(&registry.asset_vaults, asset_type)) {
        let vault_list = table::borrow(&registry.asset_vaults, asset_type);
        vault_list.default_vault
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
/// * `vector<ID>` - List of active Vault IDs
public fun get_active_vaults<T>(registry: &Registry): vector<ID> {
    let asset_type = type_name::get<T>();
    
    if (table::contains(&registry.asset_vaults, asset_type)) {
        let vault_list = table::borrow(&registry.asset_vaults, asset_type);
        vault_list.active_vaults
    } else {
        vector::empty<ID>()
    }
}

/// Pauses the specified Vault
/// Moves the Vault from active list to paused list
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
    
    let vault_list = table::borrow_mut(&mut registry.asset_vaults, asset_type);
    
    // Find and remove from active list
    let (found, index) = vector::index_of(&vault_list.active_vaults, &vault_id);
    assert!(found, errors::vault_not_found());
    
    vector::remove(&mut vault_list.active_vaults, index);
    
    // Add to paused list
    vector::push_back(&mut vault_list.paused_vaults, vault_id);
    
    // Clear default setting if the paused Vault was the default
    if (option::is_some(&vault_list.default_vault)) {
        let default_id = *option::borrow(&vault_list.default_vault);
        if (default_id == vault_id) {
            vault_list.default_vault = option::none<ID>();
        };
    };
}

/// Resumes a paused Vault
/// Moves the Vault from paused list back to active list
/// 
/// # Type Parameters
/// * `T` - Asset type
/// 
/// # Arguments
/// * `registry` - Mutable reference to the registry
/// * `vault_id` - ID of the Vault to resume
/// * `admin_cap` - Admin capability for authorization
/// * `set_as_default` - Whether to set as the default Vault
public fun resume_vault<T>(
    registry: &mut Registry,
    vault_id: ID,
    admin_cap: &AdminCap,
    set_as_default: bool,
) {
    // 验证管理员权限
    assert!(object::id(admin_cap) == registry.admin_cap_id, errors::unauthorized_access());
    
    // 验证版本
    assert!(registry.version == constants::current_version(), errors::version_mismatch());
    
    let asset_type = type_name::get<T>();
    
    // 检查资产类型是否存在
    assert!(table::contains(&registry.asset_vaults, asset_type), errors::vault_not_found());
    
    let vault_list = table::borrow_mut(&mut registry.asset_vaults, asset_type);
    
    // 从暂停列表中查找并移除
    let (found, index) = vector::index_of(&vault_list.paused_vaults, &vault_id);
    assert!(found, errors::vault_not_found());
    
    vector::remove(&mut vault_list.paused_vaults, index);
    
    // 添加到活跃列表
    vector::push_back(&mut vault_list.active_vaults, vault_id);
    
    // 如果需要设置为默认 Vault
    if (set_as_default) {
        vault_list.default_vault = option::some(vault_id);
    };
}

/// Sets the default Vault for the specified asset type
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
    // 验证管理员权限
    assert!(object::id(admin_cap) == registry.admin_cap_id, errors::unauthorized_access());
    
    // 验证版本
    assert!(registry.version == constants::current_version(), errors::version_mismatch());
    
    let asset_type = type_name::get<T>();
    
    // 检查资产类型是否存在
    assert!(table::contains(&registry.asset_vaults, asset_type), errors::vault_not_found());
    
    let vault_list = table::borrow_mut(&mut registry.asset_vaults, asset_type);
    
    // 验证 Vault 在活跃列表中
    assert!(vector::contains(&vault_list.active_vaults, &vault_id), errors::vault_not_active());
    
    // 设置为默认 Vault
    vault_list.default_vault = option::some(vault_id);
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
/// * `vector<ID>` - List of paused Vault IDs
public fun get_paused_vaults<T>(registry: &Registry): vector<ID> {
    let asset_type = type_name::get<T>();
    
    if (table::contains(&registry.asset_vaults, asset_type)) {
        let vault_list = table::borrow(&registry.asset_vaults, asset_type);
        vault_list.paused_vaults
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
        let vault_list = table::borrow(&registry.asset_vaults, asset_type);
        vector::contains(&vault_list.active_vaults, &vault_id)
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
/// Test access function to get VaultList
public fun get_vault_list_for_test<T>(registry: &Registry): &VaultList {
    let asset_type = type_name::get<T>();
    table::borrow(&registry.asset_vaults, asset_type)
}