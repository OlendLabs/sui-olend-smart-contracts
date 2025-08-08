/// Test helper functions module
/// Provides commonly used helper functions and tools for testing
#[test_only]
module olend::test_helpers;
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use std::string;
    
    // ===== Test Constants =====
    
    /// Test user addresses
    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;
    const USER2: address = @0x2;
    const USER3: address = @0x3;
    
    /// Test amounts
    const TEST_AMOUNT_SMALL: u64 = 1_000_000; // 1 SUI
    const TEST_AMOUNT_MEDIUM: u64 = 100_000_000; // 100 SUI
    const TEST_AMOUNT_LARGE: u64 = 1_000_000_000; // 1000 SUI
    
    // ===== Test Helper Functions =====
    
    /// Create test scenario
    public fun create_test_scenario(): Scenario {
        test_scenario::begin(admin())
    }
    
    /// Create SUI coins for testing
    public fun mint_sui_for_testing(amount: u64, ctx: &mut TxContext): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ctx)
    }
    
    /// Get test user address list
    public fun get_test_users(): vector<address> {
        vector[USER1, USER2, USER3]
    }
    
    /// Get admin address
    public fun admin(): address { ADMIN }
    
    /// Get user1 address
    public fun user1(): address { USER1 }
    
    /// Get user2 address
    public fun user2(): address { USER2 }
    
    /// Get user3 address
    public fun user3(): address { USER3 }
    
    /// Get small test amount
    public fun test_amount_small(): u64 { TEST_AMOUNT_SMALL }
    
    /// Get medium test amount
    public fun test_amount_medium(): u64 { TEST_AMOUNT_MEDIUM }
    
    /// Get large test amount
    public fun test_amount_large(): u64 { TEST_AMOUNT_LARGE }
    
    /// Create test string
    public fun create_test_string(content: vector<u8>): string::String {
        string::utf8(content)
    }
    
    /// Assert vector contains specified element
    public fun assert_vector_contains<T: drop>(vec: &vector<T>, item: &T) {
        let len = std::vector::length(vec);
        let mut i = 0;
        let mut found = false;
        
        while (i < len) {
            if (std::vector::borrow(vec, i) == item) {
                found = true;
                break
            };
            i = i + 1;
        };
        
        assert!(found, 0);
    }
    
    /// Assert vector does not contain specified element
    public fun assert_vector_not_contains<T: drop>(vec: &vector<T>, item: &T) {
        let len = std::vector::length(vec);
        let mut i = 0;
        
        while (i < len) {
            assert!(std::vector::borrow(vec, i) != item, 0);
            i = i + 1;
        };
    }
    
    /// Assert two vectors are equal
    public fun assert_vectors_equal<T: drop>(vec1: &vector<T>, vec2: &vector<T>) {
        assert!(std::vector::length(vec1) == std::vector::length(vec2), 0);
        
        let len = std::vector::length(vec1);
        let mut i = 0;
        
        while (i < len) {
            assert!(std::vector::borrow(vec1, i) == std::vector::borrow(vec2, i), 0);
            i = i + 1;
        };
    }