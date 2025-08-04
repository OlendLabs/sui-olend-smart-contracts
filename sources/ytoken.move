/// YToken Module - Simple share token implementation
/// Represents shares in a vault using a simple struct
module olend::ytoken;

/// YToken represents shares in a specific vault
/// Simple struct design for better performance and clarity
public struct YToken<phantom T> has drop {}

/// Creates a YToken witness for supply creation
/// This function allows other modules to create YToken supplies
/// 
/// # Type Parameters
/// * `T` - The underlying asset type
/// 
/// # Returns
/// * `YToken<T>` - YToken witness
public fun create_witness<T>(): YToken<T> {
    YToken<T> {}
}