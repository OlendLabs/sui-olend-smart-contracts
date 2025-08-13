/// Test module for Pyth Network adapter functionality
#[test_only]
module olend::test_pyth_adapter;

use sui::test_scenario::{Self as test, next_tx, ctx};
use sui::clock;

use olend::oracle::{Self, PriceOracle, OracleAdminCap};
use olend::pyth_adapter;

// Test asset types
public struct BTC has drop {}
public struct ETH has drop {}

const ADMIN: address = @0xAD;

/// Test Pyth adapter initialization and basic functionality
#[test]
fun test_pyth_adapter_basic() {
    let mut scenario = test::begin(ADMIN);
    let clock = clock::create_for_testing(ctx(&mut scenario));
=======
    let mut clock = clock::create_for_testing(ctx(&mut scenario));
    
    // Initialize oracle
    next_tx(&mut scenario, ADMIN);
    {
        let admin_cap = oracle::initialize_oracle(ctx(&mut scenario));
        transfer::public_transfer(admin_cap, ADMIN);
    };
    
        // Configure price feed and test basic functionality
    next_tx(&mut scenario, ADMIN);
    {
        let mut oracle = test::take_shared<PriceOracle>(&scenario);
        let admin_cap = test::take_from_sender<OracleAdminCap>(&scenario);
        
        // Configure BTC price feed with a 32-byte identifier
        let btc_feed_id = x"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
        pyth_adapter::configure_pyth_price_feed<BTC>(&mut oracle, &admin_cap, btc_feed_id, ctx(&mut scenario));
        
        // Verify feed is configured
        assert!(oracle::has_price_feed<BTC>(&oracle), 0);
        assert!(oracle::get_price_feed_id<BTC>(&oracle) == btc_feed_id, 1);
        
        test::return_to_sender(&scenario, admin_cap);
        test::return_shared(oracle);
    };
    
        clock::destroy_for_testing(clock);
    test::end(scenario);
}

/// Test Pyth price feed configuration validation
#[test]
fun test_pyth_price_feed_configuration() {
    let mut scenario = test::begin(ADMIN);
    
    // Initialize oracle
    next_tx(&mut scenario, ADMIN);
    {
        let admin_cap = oracle::initialize_oracle(ctx(&mut scenario));
        transfer::public_transfer(admin_cap, ADMIN);
    };
    
    // Test price feed configuration
    next_tx(&mut scenario, ADMIN);
    {
        let mut oracle = test::take_shared<PriceOracle>(&scenario);
        let admin_cap = test::take_from_sender<OracleAdminCap>(&scenario);
        
        // Configure BTC price feed
        let btc_feed_id = x"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
        pyth_adapter::configure_pyth_price_feed<BTC>(&mut oracle, &admin_cap, btc_feed_id, ctx(&mut scenario));
        
        // Verify configuration
        assert!(oracle::has_price_feed<BTC>(&oracle), 0);
        assert!(oracle::get_price_feed_id<BTC>(&oracle) == btc_feed_id, 1);
        
        test::return_to_sender(&scenario, admin_cap);
        test::return_shared(oracle);
    };
    
        test::end(scenario);
}

/// Test multiple price feed configurations
#[test]
fun test_multiple_price_feeds() {
    let mut scenario = test::begin(ADMIN);
    
    // Initialize oracle
    next_tx(&mut scenario, ADMIN);
    {
        let admin_cap = oracle::initialize_oracle(ctx(&mut scenario));
        transfer::public_transfer(admin_cap, ADMIN);
    };
    
    // Configure multiple price feeds
    next_tx(&mut scenario, ADMIN);
    {
        let mut oracle = test::take_shared<PriceOracle>(&scenario);
        let admin_cap = test::take_from_sender<OracleAdminCap>(&scenario);
        
        // Configure BTC price feed
        let btc_feed_id = x"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
        pyth_adapter::configure_pyth_price_feed<BTC>(&mut oracle, &admin_cap, btc_feed_id, ctx(&mut scenario));
        
        // Configure ETH price feed
        let eth_feed_id = x"fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210";
        pyth_adapter::configure_pyth_price_feed<ETH>(&mut oracle, &admin_cap, eth_feed_id, ctx(&mut scenario));
        
        // Verify both configurations
        assert!(oracle::has_price_feed<BTC>(&oracle), 0);
        assert!(oracle::has_price_feed<ETH>(&oracle), 1);
        assert!(oracle::get_price_feed_id<BTC>(&oracle) == btc_feed_id, 2);
        assert!(oracle::get_price_feed_id<ETH>(&oracle) == eth_feed_id, 3);
        
        test::return_to_sender(&scenario, admin_cap);
        test::return_shared(oracle);
    };
    
    test::end(scenario);
}

/// Test price feed configuration validation
#[test]
#[expected_failure(abort_code = 2054, location = olend::pyth_adapter)]
fun test_invalid_price_feed_id() {
    let mut scenario = test::begin(ADMIN);
    
    // Initialize oracle
    next_tx(&mut scenario, ADMIN);
    {
        let admin_cap = oracle::initialize_oracle(ctx(&mut scenario));
        transfer::public_transfer(admin_cap, ADMIN);
    };
    
    // Try to configure with invalid price feed ID (should fail)
    next_tx(&mut scenario, ADMIN);
    {
        let mut oracle = test::take_shared<PriceOracle>(&scenario);
        let admin_cap = test::take_from_sender<OracleAdminCap>(&scenario);
        
        // Use invalid feed ID (not 32 bytes)
        let invalid_feed_id = x"0123456789abcdef"; // Only 8 bytes
        
        // This should abort with EInvalidPriceFeedId
        pyth_adapter::configure_pyth_price_feed<BTC>(&mut oracle, &admin_cap, invalid_feed_id, ctx(&mut scenario));
        
        test::return_to_sender(&scenario, admin_cap);
        test::return_shared(oracle);
    };
    
     test::end(scenario);
}

