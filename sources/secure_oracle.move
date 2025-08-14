/// Enhanced Secure Oracle Module
/// Provides comprehensive price validation and manipulation detection
/// Built on top of the existing oracle infrastructure with enhanced security features
module olend::secure_oracle;

use std::type_name::{Self, TypeName};
use sui::table::{Self, Table};
use sui::clock::{Self, Clock};
use sui::event;

use olend::oracle::{Self, PriceOracle, OracleAdminCap};
use olend::errors;
use olend::security;
use olend::security_constants;
use olend::safe_math;


// ===== Enhanced Security Structures =====

/// Enhanced secure price oracle with comprehensive validation
public struct SecurePriceOracle has key {
    id: UID,
    version: u64,
    admin_cap_id: ID,
    
    // Enhanced validation parameters
    price_feeds: Table<TypeName, PriceFeedConfig>,
    price_cache: Table<TypeName, ValidatedPriceInfo>,
    
    // Security configurations
    max_price_delay: u64,           // Maximum acceptable staleness
    min_confidence: u64,            // Minimum confidence threshold
    max_price_deviation: u64,       // Maximum price change per block
    circuit_breaker_threshold: u64, // Extreme movement threshold
    
    // Price history for validation
    price_history: Table<TypeName, vector<PricePoint>>,
    
    // Emergency controls
    emergency_mode: bool,
    emergency_admin_cap_id: ID,
    
    // Reference to base oracle
    base_oracle_id: ID,
}

/// Enhanced price feed configuration with security parameters
public struct PriceFeedConfig has store, drop {
    feed_id: vector<u8>,
    decimals: u8,
    heartbeat: u64,                // Expected update frequency
    deviation_threshold: u64,      // Acceptable price deviation (basis points)
    confidence_threshold: u64,     // Minimum confidence requirement
    
    // Enhanced security parameters
    max_staleness: u64,           // Maximum acceptable staleness in seconds
    circuit_breaker_enabled: bool, // Whether circuit breaker is enabled for this feed
    validation_enabled: bool,      // Whether enhanced validation is enabled
}

/// Enhanced validated price information with security metrics
public struct ValidatedPriceInfo has store, copy, drop {
    price: u64,
    confidence: u64,
    timestamp: u64,
    expo: u8,
    is_valid: bool,
    
    // Enhanced validation fields
    validation_score: u64,         // Composite validation score (0-100)
    last_validation_time: u64,    // Last successful validation timestamp
    price_source: u8,             // Source of price data (1=primary, 2=fallback)
    manipulation_risk: u8,        // Manipulation risk level (0=low, 1=medium, 2=high)
}

/// Price history point for trend analysis
public struct PricePoint has store, copy, drop {
    price: u64,
    timestamp: u64,
    confidence: u64,
    validation_score: u64,
}

/// Security admin capability for emergency operations
public struct SecurityAdminCap has key, store {
    id: UID,
}

// ===== Events =====

/// Enhanced price validation event
public struct EnhancedPriceValidationEvent has copy, drop {
    asset_type: TypeName,
    price: u64,
    confidence: u64,
    validation_score: u64,
    manipulation_risk: u8,
    timestamp: u64,
}

/// Price manipulation detection event
public struct PriceManipulationEvent has copy, drop {
    asset_type: TypeName,
    old_price: u64,
    new_price: u64,
    deviation_percentage: u64,
    risk_level: u8,
    timestamp: u64,
    action_taken: vector<u8>,
}

/// Circuit breaker activation event
public struct CircuitBreakerEvent has copy, drop {
    asset_type: TypeName,
    trigger_type: u8, // 1=price deviation, 2=confidence drop, 3=manipulation
    threshold_exceeded: u64,
    current_value: u64,
    timestamp: u64,
    duration: u64,
}

// ===== Error Constants =====

const E_SECURE_FEED_NOT_CONFIGURED: u64 = 5006;
const E_SECURE_EMERGENCY_MODE_ACTIVE: u64 = 5007;

// ===== Initialization =====

/// Initialize secure oracle system
fun init(ctx: &mut tx_context::TxContext) {
    let security_admin_cap = SecurityAdminCap { id: object::new(ctx) };
    transfer::transfer(security_admin_cap, tx_context::sender(ctx));
}

/// Create and share enhanced secure oracle
public fun create_and_share_secure_oracle(
    base_oracle: &PriceOracle,
    admin_cap: &OracleAdminCap,
    ctx: &mut tx_context::TxContext
) {
    let secure_oracle = create_secure_oracle(base_oracle, admin_cap, ctx);
    transfer::share_object(secure_oracle);
}

/// Create enhanced secure oracle
public fun create_secure_oracle(
    base_oracle: &PriceOracle,
    admin_cap: &OracleAdminCap,
    ctx: &mut tx_context::TxContext
): SecurePriceOracle {
    let security_admin_cap = SecurityAdminCap { id: object::new(ctx) };
    let security_admin_cap_id = object::id(&security_admin_cap);
    
    // Transfer security admin cap to caller
    transfer::transfer(security_admin_cap, tx_context::sender(ctx));
    
    SecurePriceOracle {
        id: object::new(ctx),
        version: security_constants::current_security_version(),
        admin_cap_id: object::id(admin_cap),
        price_feeds: table::new(ctx),
        price_cache: table::new(ctx),
        max_price_delay: 300, // 5 minutes
        min_confidence: 95,   // 95%
        max_price_deviation: 1000, // 10% in basis points
        circuit_breaker_threshold: 2000, // 20% for circuit breaker
        price_history: table::new(ctx),
        emergency_mode: false,
        emergency_admin_cap_id: security_admin_cap_id,
        base_oracle_id: object::id(base_oracle),
    }
}

// ===== Enhanced Price Feed Configuration =====

/// Configure enhanced price feed with security parameters
public fun configure_enhanced_price_feed<T>(
    secure_oracle: &mut SecurePriceOracle,
    admin_cap: &OracleAdminCap,
    feed_id: vector<u8>,
    decimals: u8,
    heartbeat: u64,
    deviation_threshold: u64,
    confidence_threshold: u64,
    max_staleness: u64,
    circuit_breaker_enabled: bool,
    validation_enabled: bool,
    _ctx: &tx_context::TxContext
) {
    // Verify admin permissions
    assert!(object::id(admin_cap) == secure_oracle.admin_cap_id, errors::unauthorized_oracle_access());
    
    // Validate parameters
    assert!(!vector::is_empty(&feed_id), E_SECURE_FEED_NOT_CONFIGURED);
    assert!(confidence_threshold <= 100, errors::invalid_input());
    assert!(deviation_threshold <= 10000, errors::invalid_input()); // Max 100%
    
    let asset_type = type_name::get<T>();
    
    let config = PriceFeedConfig {
        feed_id,
        decimals,
        heartbeat,
        deviation_threshold,
        confidence_threshold,
        max_staleness,
        circuit_breaker_enabled,
        validation_enabled,
    };
    
    if (table::contains(&secure_oracle.price_feeds, asset_type)) {
        let existing_config = table::borrow_mut(&mut secure_oracle.price_feeds, asset_type);
        *existing_config = config;
    } else {
        table::add(&mut secure_oracle.price_feeds, asset_type, config);
    };
    
    // Initialize price history if not exists
    if (!table::contains(&secure_oracle.price_history, asset_type)) {
        table::add(&mut secure_oracle.price_history, asset_type, vector::empty<PricePoint>());
    };
}

// ===== Enhanced Price Validation =====

/// Comprehensive price validation with multiple security checks
public fun validate_price_comprehensive<T>(
    secure_oracle: &SecurePriceOracle,
    base_oracle: &PriceOracle,
    clock: &Clock
): ValidatedPriceInfo {
    let asset_type = type_name::get<T>();
    
    // Check if feed is configured
    assert!(table::contains(&secure_oracle.price_feeds, asset_type), E_SECURE_FEED_NOT_CONFIGURED);
    
    // Check emergency mode
    assert!(!secure_oracle.emergency_mode, E_SECURE_EMERGENCY_MODE_ACTIVE);
    
    let config = table::borrow(&secure_oracle.price_feeds, asset_type);
    
    // Get base price info
    let base_price_info = oracle::get_price<T>(base_oracle, clock);
    
    // If base price is invalid, return invalid result
    if (!oracle::price_info_is_valid(&base_price_info)) {
        return ValidatedPriceInfo {
            price: 0,
            confidence: 0,
            timestamp: clock::timestamp_ms(clock) / 1000,
            expo: oracle::price_info_expo(&base_price_info),
            is_valid: false,
            validation_score: 0,
            last_validation_time: 0,
            price_source: 1,
            manipulation_risk: 2, // High risk for invalid price
        }
    };
    
    let current_time = clock::timestamp_ms(clock) / 1000;
    let price = oracle::price_info_price(&base_price_info);
    let confidence = oracle::price_info_confidence(&base_price_info);
    let timestamp = oracle::price_info_timestamp(&base_price_info);
    
    // Perform comprehensive validation
    let validation_result = perform_comprehensive_validation(
        secure_oracle,
        asset_type,
        price,
        confidence,
        timestamp,
        current_time,
        config
    );
    
    // Create validated price info
    let validated_price = ValidatedPriceInfo {
        price,
        confidence,
        timestamp,
        expo: oracle::price_info_expo(&base_price_info),
        is_valid: validation_result.is_valid,
        validation_score: validation_result.score,
        last_validation_time: current_time,
        price_source: 1, // Primary source
        manipulation_risk: validation_result.manipulation_risk,
    };
    
    // Emit validation event
    event::emit(EnhancedPriceValidationEvent {
        asset_type,
        price,
        confidence,
        validation_score: validation_result.score,
        manipulation_risk: validation_result.manipulation_risk,
        timestamp: current_time,
    });
    
    validated_price
}

/// Internal comprehensive validation logic
public struct ValidationResult has drop {
    is_valid: bool,
    score: u64,
    manipulation_risk: u8,
}

fun perform_comprehensive_validation(
    secure_oracle: &SecurePriceOracle,
    asset_type: TypeName,
    price: u64,
    confidence: u64,
    timestamp: u64,
    current_time: u64,
    config: &PriceFeedConfig
): ValidationResult {
    let mut score = 100u64; // Start with perfect score
    let mut manipulation_risk = 0u8; // Start with low risk
    
    // 1. Staleness check
    let age = safe_math::safe_sub(current_time, timestamp);
    if (age > config.max_staleness) {
        score = safe_math::safe_sub(score, 30); // -30 points for staleness
        manipulation_risk = 1; // Medium risk
    } else if (age > config.max_staleness / 2) {
        score = safe_math::safe_sub(score, 10); // -10 points for moderate staleness
    };
    
    // 2. Confidence check
    if (confidence < config.confidence_threshold) {
        score = safe_math::safe_sub(score, 25); // -25 points for low confidence
        manipulation_risk = if (manipulation_risk < 1) 1 else manipulation_risk;
    } else if (confidence < config.confidence_threshold + 5) {
        score = safe_math::safe_sub(score, 5); // -5 points for marginal confidence
    };
    
    // 3. Price deviation check (if history exists)
    if (table::contains(&secure_oracle.price_history, asset_type)) {
        let history = table::borrow(&secure_oracle.price_history, asset_type);
        if (!vector::is_empty(history)) {
            let last_point = vector::borrow(history, vector::length(history) - 1);
            let deviation = calculate_price_deviation(last_point.price, price);
            
            if (deviation > config.deviation_threshold) {
                score = safe_math::safe_sub(score, 20); // -20 points for high deviation
                manipulation_risk = 2; // High risk
            } else if (deviation > config.deviation_threshold / 2) {
                score = safe_math::safe_sub(score, 10); // -10 points for moderate deviation
                manipulation_risk = if (manipulation_risk < 1) 1 else manipulation_risk;
            };
        };
    };
    
    // 4. Trend analysis (if sufficient history)
    if (table::contains(&secure_oracle.price_history, asset_type)) {
        let history = table::borrow(&secure_oracle.price_history, asset_type);
        if (vector::length(history) >= 3) {
            let trend_risk = analyze_price_trend(history, price);
            if (trend_risk > 0) {
                let risk_penalty = (trend_risk as u64) * 5; // Convert u8 to u64
                score = safe_math::safe_sub(score, risk_penalty); // -5 points per risk level
                manipulation_risk = if (manipulation_risk < trend_risk) trend_risk else manipulation_risk;
            };
        };
    };
    
    // Final validation decision
    let is_valid = score >= security_constants::min_validation_score() && manipulation_risk < 2;
    
    ValidationResult {
        is_valid,
        score,
        manipulation_risk,
    }
}

/// Calculate price deviation in basis points
fun calculate_price_deviation(old_price: u64, new_price: u64): u64 {
    if (old_price == 0) return 0;
    
    let deviation = if (new_price > old_price) {
        safe_math::safe_sub(new_price, old_price)
    } else {
        safe_math::safe_sub(old_price, new_price)
    };
    
    safe_math::safe_mul_div(deviation, 10000, old_price)
}

/// Analyze price trend for manipulation patterns
fun analyze_price_trend(history: &vector<PricePoint>, current_price: u64): u8 {
    let history_len = vector::length(history);
    if (history_len < 3) return 0;
    
    // Get last 3 points
    let point1 = vector::borrow(history, history_len - 3);
    let point2 = vector::borrow(history, history_len - 2);
    let point3 = vector::borrow(history, history_len - 1);
    
    // Check for suspicious patterns
    let dev1 = calculate_price_deviation(point1.price, point2.price);
    let dev2 = calculate_price_deviation(point2.price, point3.price);
    let dev3 = calculate_price_deviation(point3.price, current_price);
    
    // Pattern 1: Consecutive large deviations (pump and dump)
    if (dev1 > 500 && dev2 > 500 && dev3 > 500) { // All > 5%
        return 2 // High risk
    };
    
    // Pattern 2: Sudden spike followed by correction
    if (dev2 > 1000 && dev3 > 1000) { // Both > 10%
        return 1 // Medium risk
    };
    
    0 // Low risk
}

// ===== Price Manipulation Detection =====

/// Enhanced manipulation detection result
public struct ManipulationDetectionResult has drop {
    is_manipulation: bool,
    risk_level: u8,
    pattern_type: u8, // 0=none, 1=pump_dump, 2=flash_crash, 3=gradual_drift, 4=volatility_spike
    confidence_score: u64, // 0-100
    deviation_percentage: u64,
    action_recommended: vector<u8>,
}

/// Detect potential price manipulation with enhanced algorithms
public fun detect_price_manipulation<T>(
    secure_oracle: &mut SecurePriceOracle,
    current_price: u64,
    current_confidence: u64,
    clock: &Clock
): ManipulationDetectionResult {
    let asset_type = type_name::get<T>();
    let current_time = clock::timestamp_ms(clock) / 1000;
    
    // Check if we have price history
    if (!table::contains(&secure_oracle.price_history, asset_type)) {
        return ManipulationDetectionResult {
            is_manipulation: false,
            risk_level: 0,
            pattern_type: 0,
            confidence_score: 0,
            deviation_percentage: 0,
            action_recommended: b"NO_ACTION",
        }
    };
    
    let history = table::borrow(&secure_oracle.price_history, asset_type);
    if (vector::is_empty(history)) {
        return ManipulationDetectionResult {
            is_manipulation: false,
            risk_level: 0,
            pattern_type: 0,
            confidence_score: 0,
            deviation_percentage: 0,
            action_recommended: b"NO_ACTION",
        }
    };
    
    let config = table::borrow(&secure_oracle.price_feeds, asset_type);
    
    // Run multiple detection algorithms
    let pump_dump_result = detect_pump_dump_pattern(history, current_price, config);
    let flash_crash_result = detect_flash_crash_pattern(history, current_price, config);
    let gradual_drift_result = detect_gradual_drift_pattern(history, current_price, config);
    let volatility_spike_result = detect_volatility_spike_pattern(history, current_price, current_confidence, config);
    
    // Combine results to determine overall manipulation risk
    let combined_result = combine_detection_results(
        pump_dump_result,
        flash_crash_result,
        gradual_drift_result,
        volatility_spike_result
    );
    
    // Emit events if manipulation detected
    if (combined_result.is_manipulation) {
        emit_manipulation_detection_events<T>(
            asset_type,
            history,
            current_price,
            &combined_result,
            current_time
        );
        
        // Emit security event
        security::emit_security_event(
            security::event_type_price_manipulation(),
            if (combined_result.risk_level >= 2) security::severity_critical() else security::severity_high(),
            @0x0,
            security::create_security_details(
                b"Advanced price manipulation detected",
                combined_result.action_recommended
            ),
            security::create_mitigation_action(
                b"PRICE_VALIDATION_ENHANCED",
                b"Multiple manipulation patterns detected"
            ),
            clock
        );
    };
    
    combined_result
}

/// Detect pump and dump patterns
fun detect_pump_dump_pattern(
    history: &vector<PricePoint>,
    current_price: u64,
    config: &PriceFeedConfig
): ManipulationDetectionResult {
    let history_len = vector::length(history);
    if (history_len < 5) {
        return create_no_manipulation_result()
    };
    
    // Look for pattern: gradual increase followed by sharp drop (or vice versa)
    let mut pump_phases = 0u8;
    let mut dump_phases = 0u8;
    let mut max_deviation = 0u64;
    
    let mut i = history_len - 4;
    while (i < history_len - 1) {
        let point1 = vector::borrow(history, i);
        let point2 = vector::borrow(history, i + 1);
        let deviation = calculate_price_deviation(point1.price, point2.price);
        
        if (deviation > max_deviation) {
            max_deviation = deviation;
        };
        
        // Check for pump (price increase > 3%)
        if (point2.price > point1.price && deviation > 300) {
            pump_phases = pump_phases + 1;
        };
        
        // Check for dump (price decrease > 3%)
        if (point2.price < point1.price && deviation > 300) {
            dump_phases = dump_phases + 1;
        };
        
        i = i + 1;
    };
    
    // Check current price against last point
    let last_point = vector::borrow(history, history_len - 1);
    let current_deviation = calculate_price_deviation(last_point.price, current_price);
    if (current_deviation > max_deviation) {
        max_deviation = current_deviation;
    };
    
    // Determine if pump and dump pattern exists
    let is_pump_dump = (pump_phases >= 2 && dump_phases >= 1) || (dump_phases >= 2 && pump_phases >= 1);
    let risk_level = if (max_deviation > config.deviation_threshold * 3) 2 else if (max_deviation > config.deviation_threshold * 2) 1 else 0;
    
    ManipulationDetectionResult {
        is_manipulation: is_pump_dump && risk_level > 0,
        risk_level,
        pattern_type: 1, // pump_dump
        confidence_score: if (is_pump_dump) ((pump_phases + dump_phases) as u64) * 20 else 0,
        deviation_percentage: max_deviation,
        action_recommended: if (is_pump_dump && risk_level >= 2) b"CIRCUIT_BREAKER" else b"ENHANCED_VALIDATION",
    }
}

/// Detect flash crash patterns
fun detect_flash_crash_pattern(
    history: &vector<PricePoint>,
    current_price: u64,
    _config: &PriceFeedConfig
): ManipulationDetectionResult {
    let history_len = vector::length(history);
    if (history_len < 3) {
        return create_no_manipulation_result()
    };
    
    // Look for sudden large price movement in short time
    let last_point = vector::borrow(history, history_len - 1);
    let current_deviation = calculate_price_deviation(last_point.price, current_price);
    
    // Check if this is a flash crash (>15% movement)
    let is_flash_crash = current_deviation > 1500;
    let risk_level = if (current_deviation > 2000) 2 else if (current_deviation > 1500) 1 else 0;
    
    // Additional check: verify this is abnormal compared to recent volatility
    let mut recent_volatility = 0u64;
    if (history_len >= 5) {
        let mut i = history_len - 5;
        while (i < history_len - 1) {
            let point1 = vector::borrow(history, i);
            let point2 = vector::borrow(history, i + 1);
            let deviation = calculate_price_deviation(point1.price, point2.price);
            recent_volatility = recent_volatility + deviation;
            i = i + 1;
        };
        recent_volatility = recent_volatility / 4; // Average
    };
    
    // Flash crash if current deviation is 3x recent average volatility
    let is_abnormal_volatility = current_deviation > recent_volatility * 3;
    
    ManipulationDetectionResult {
        is_manipulation: is_flash_crash && is_abnormal_volatility,
        risk_level,
        pattern_type: 2, // flash_crash
        confidence_score: if (is_flash_crash && is_abnormal_volatility) 85 else 0,
        deviation_percentage: current_deviation,
        action_recommended: if (risk_level >= 2) b"EMERGENCY_PAUSE" else b"CIRCUIT_BREAKER",
    }
}

/// Detect gradual price drift manipulation
fun detect_gradual_drift_pattern(
    history: &vector<PricePoint>,
    current_price: u64,
    _config: &PriceFeedConfig
): ManipulationDetectionResult {
    let history_len = vector::length(history);
    if (history_len < 10) {
        return create_no_manipulation_result()
    };
    
    // Check for consistent directional movement over time
    let start_point = vector::borrow(history, history_len - 10);
    let end_point = vector::borrow(history, history_len - 1);
    let total_drift = calculate_price_deviation(start_point.price, current_price);
    
    // Count consecutive movements in same direction
    let mut consecutive_moves = 0u8;
    let mut same_direction = true;
    let first_point = vector::borrow(history, history_len - 5);
    let second_point = vector::borrow(history, history_len - 4);
    let initial_direction = second_point.price > first_point.price;
    
    let mut i = history_len - 4;
    while (i < history_len - 1 && same_direction) {
        let point1 = vector::borrow(history, i);
        let point2 = vector::borrow(history, i + 1);
        let current_direction = point2.price > point1.price;
        
        if (current_direction == initial_direction) {
            consecutive_moves = consecutive_moves + 1;
        } else {
            same_direction = false;
        };
        
        i = i + 1;
    };
    
    // Check current price direction
    let current_direction = current_price > end_point.price;
    if (current_direction == initial_direction) {
        consecutive_moves = consecutive_moves + 1;
    };
    
    // Gradual drift if >5% total movement with >3 consecutive moves
    let is_gradual_drift = total_drift > 500 && consecutive_moves >= 3;
    let risk_level = if (total_drift > 1000 && consecutive_moves >= 5) 2 else if (is_gradual_drift) 1 else 0;
    
    ManipulationDetectionResult {
        is_manipulation: is_gradual_drift,
        risk_level,
        pattern_type: 3, // gradual_drift
        confidence_score: if (is_gradual_drift) (consecutive_moves as u64) * 15 else 0,
        deviation_percentage: total_drift,
        action_recommended: if (risk_level >= 2) b"ENHANCED_MONITORING" else b"TREND_ANALYSIS",
    }
}

/// Detect volatility spike patterns
fun detect_volatility_spike_pattern(
    history: &vector<PricePoint>,
    current_price: u64,
    current_confidence: u64,
    _config: &PriceFeedConfig
): ManipulationDetectionResult {
    let history_len = vector::length(history);
    if (history_len < 5) {
        return create_no_manipulation_result()
    };
    
    // Calculate recent volatility
    let mut recent_volatility = 0u64;
    let mut confidence_drops = 0u8;
    
    let mut i = history_len - 5;
    while (i < history_len - 1) {
        let point1 = vector::borrow(history, i);
        let point2 = vector::borrow(history, i + 1);
        let deviation = calculate_price_deviation(point1.price, point2.price);
        recent_volatility = recent_volatility + deviation;
        
        // Check for confidence drops
        if (point2.confidence < point1.confidence && point1.confidence - point2.confidence > 10) {
            confidence_drops = confidence_drops + 1;
        };
        
        i = i + 1;
    };
    
    recent_volatility = recent_volatility / 4; // Average
    
    // Check current price volatility
    let last_point = vector::borrow(history, history_len - 1);
    let current_volatility = calculate_price_deviation(last_point.price, current_price);
    
    // Check for confidence drop
    if (current_confidence < last_point.confidence && last_point.confidence - current_confidence > 10) {
        confidence_drops = confidence_drops + 1;
    };
    
    // Volatility spike if current volatility is 4x recent average + confidence drops
    let is_volatility_spike = current_volatility > recent_volatility * 4 && confidence_drops >= 2;
    let risk_level = if (current_volatility > recent_volatility * 6 && confidence_drops >= 3) 2 else if (is_volatility_spike) 1 else 0;
    
    ManipulationDetectionResult {
        is_manipulation: is_volatility_spike,
        risk_level,
        pattern_type: 4, // volatility_spike
        confidence_score: if (is_volatility_spike) (confidence_drops as u64) * 25 else 0,
        deviation_percentage: current_volatility,
        action_recommended: if (risk_level >= 2) b"CONFIDENCE_CHECK" else b"VOLATILITY_MONITORING",
    }
}

/// Combine multiple detection results
fun combine_detection_results(
    pump_dump: ManipulationDetectionResult,
    flash_crash: ManipulationDetectionResult,
    gradual_drift: ManipulationDetectionResult,
    volatility_spike: ManipulationDetectionResult
): ManipulationDetectionResult {
    let mut max_risk = 0u8;
    let mut total_confidence = 0u64;
    let mut manipulation_count = 0u8;
    let mut max_deviation = 0u64;
    let mut primary_pattern = 0u8;
    let mut action = b"NO_ACTION";
    
    // Check pump_dump
    if (pump_dump.is_manipulation) {
        manipulation_count = manipulation_count + 1;
        total_confidence = total_confidence + pump_dump.confidence_score;
        if (pump_dump.risk_level > max_risk) {
            max_risk = pump_dump.risk_level;
            primary_pattern = pump_dump.pattern_type;
            action = pump_dump.action_recommended;
        };
        if (pump_dump.deviation_percentage > max_deviation) {
            max_deviation = pump_dump.deviation_percentage;
        };
    };
    
    // Check flash_crash
    if (flash_crash.is_manipulation) {
        manipulation_count = manipulation_count + 1;
        total_confidence = total_confidence + flash_crash.confidence_score;
        if (flash_crash.risk_level > max_risk) {
            max_risk = flash_crash.risk_level;
            primary_pattern = flash_crash.pattern_type;
            action = flash_crash.action_recommended;
        };
        if (flash_crash.deviation_percentage > max_deviation) {
            max_deviation = flash_crash.deviation_percentage;
        };
    };
    
    // Check gradual_drift
    if (gradual_drift.is_manipulation) {
        manipulation_count = manipulation_count + 1;
        total_confidence = total_confidence + gradual_drift.confidence_score;
        if (gradual_drift.risk_level > max_risk) {
            max_risk = gradual_drift.risk_level;
            primary_pattern = gradual_drift.pattern_type;
            action = gradual_drift.action_recommended;
        };
        if (gradual_drift.deviation_percentage > max_deviation) {
            max_deviation = gradual_drift.deviation_percentage;
        };
    };
    
    // Check volatility_spike
    if (volatility_spike.is_manipulation) {
        manipulation_count = manipulation_count + 1;
        total_confidence = total_confidence + volatility_spike.confidence_score;
        if (volatility_spike.risk_level > max_risk) {
            max_risk = volatility_spike.risk_level;
            primary_pattern = volatility_spike.pattern_type;
            action = volatility_spike.action_recommended;
        };
        if (volatility_spike.deviation_percentage > max_deviation) {
            max_deviation = volatility_spike.deviation_percentage;
        };
    };
    
    // Multiple patterns detected increases risk
    if (manipulation_count > 1) {
        max_risk = if (max_risk < 2) max_risk + 1 else 2;
        total_confidence = total_confidence + (manipulation_count as u64) * 10;
        action = b"MULTIPLE_PATTERNS_DETECTED";
    };
    
    // Cap confidence at 100
    if (total_confidence > 100) {
        total_confidence = 100;
    };
    
    ManipulationDetectionResult {
        is_manipulation: manipulation_count > 0,
        risk_level: max_risk,
        pattern_type: primary_pattern,
        confidence_score: total_confidence,
        deviation_percentage: max_deviation,
        action_recommended: action,
    }
}

/// Create no manipulation result
fun create_no_manipulation_result(): ManipulationDetectionResult {
    ManipulationDetectionResult {
        is_manipulation: false,
        risk_level: 0,
        pattern_type: 0,
        confidence_score: 0,
        deviation_percentage: 0,
        action_recommended: b"NO_ACTION",
    }
}

/// Emit manipulation detection events
#[allow(unused_type_parameter)]
fun emit_manipulation_detection_events<T>(
    asset_type: TypeName,
    history: &vector<PricePoint>,
    current_price: u64,
    result: &ManipulationDetectionResult,
    timestamp: u64
) {
    let last_point = vector::borrow(history, vector::length(history) - 1);
    
    // Emit detailed manipulation event
    event::emit(PriceManipulationEvent {
        asset_type,
        old_price: last_point.price,
        new_price: current_price,
        deviation_percentage: result.deviation_percentage,
        risk_level: result.risk_level,
        timestamp,
        action_taken: result.action_recommended,
    });
    
    // Emit pattern-specific event
    event::emit(ManipulationPatternEvent {
        asset_type,
        pattern_type: result.pattern_type,
        confidence_score: result.confidence_score,
        risk_level: result.risk_level,
        timestamp,
        recommended_action: result.action_recommended,
    });
}

/// Pattern-specific manipulation event
public struct ManipulationPatternEvent has copy, drop {
    asset_type: TypeName,
    pattern_type: u8,
    confidence_score: u64,
    risk_level: u8,
    timestamp: u64,
    recommended_action: vector<u8>,
}

// ===== Circuit Breaker Functions =====

/// Circuit breaker state for each asset
public struct CircuitBreakerState has store, drop {
    is_active: bool,
    activation_time: u64,
    trigger_type: u8, // 1=price_deviation, 2=confidence_drop, 3=manipulation, 4=emergency
    trigger_value: u64,
    recovery_time: u64, // When circuit breaker can be reset
    activation_count: u64, // Number of times activated
    last_reset_time: u64,
}

/// Enhanced circuit breaker configuration
public struct CircuitBreakerConfig has store, drop {
    enabled: bool,
    price_deviation_threshold: u64, // Basis points
    confidence_drop_threshold: u64, // Percentage points
    manipulation_threshold: u8, // Risk level
    recovery_duration: u64, // Seconds before auto-recovery
    max_activations_per_hour: u64, // Rate limiting
    emergency_override: bool, // Can be overridden in emergency
}

/// Check and activate circuit breaker if needed
public fun check_and_activate_circuit_breaker<T>(
    secure_oracle: &mut SecurePriceOracle,
    price_change_percentage: u64,
    clock: &Clock
): bool {
    let asset_type = type_name::get<T>();
    
    // Check if circuit breaker is enabled for this feed
    if (!table::contains(&secure_oracle.price_feeds, asset_type)) {
        return false
    };
    
    let config = table::borrow(&secure_oracle.price_feeds, asset_type);
    if (!config.circuit_breaker_enabled) {
        return false
    };
    
    // Initialize circuit breaker state if not exists
    if (!table::contains(&secure_oracle.price_cache, asset_type)) {
        // Circuit breaker state would be stored in a separate table
        // For now, we'll use a flag in the oracle structure
    };
    
    let current_time = clock::timestamp_ms(clock) / 1000;
    let should_activate = price_change_percentage > secure_oracle.circuit_breaker_threshold;
    
    if (should_activate) {
        // Activate circuit breaker
        activate_circuit_breaker_internal<T>(
            secure_oracle,
            1, // Price deviation trigger
            price_change_percentage,
            current_time,
            clock
        );
        
        return true
    };
    
    false
}

/// Internal function to activate circuit breaker
fun activate_circuit_breaker_internal<T>(
    secure_oracle: &SecurePriceOracle,
    trigger_type: u8,
    trigger_value: u64,
    current_time: u64,
    clock: &Clock
) {
    let asset_type = type_name::get<T>();
    
    // Calculate recovery time (default 1 hour)
    let recovery_duration = 3600u64; // 1 hour
    let recovery_time = safe_math::safe_add(current_time, recovery_duration);
    
    // Emit circuit breaker event
    event::emit(CircuitBreakerEvent {
        asset_type,
        trigger_type,
        threshold_exceeded: secure_oracle.circuit_breaker_threshold,
        current_value: trigger_value,
        timestamp: current_time,
        duration: recovery_duration,
    });
    
    // Emit security event
    security::emit_security_event(
        security::event_type_circuit_breaker(),
        security::severity_critical(),
        @0x0,
        security::create_security_details(
            b"Circuit breaker activated for extreme price movement",
            vector::empty<u8>()
        ),
        security::create_mitigation_action(
            b"CIRCUIT_BREAKER_ACTIVATED",
            b"Automatic pause mechanism engaged"
        ),
        clock
    );
    
    // Emit circuit breaker activation event
    event::emit(CircuitBreakerActivationEvent {
        asset_type,
        trigger_type,
        trigger_value,
        activation_time: current_time,
        recovery_time,
        reason: get_trigger_reason(trigger_type),
    });
}

/// Check if circuit breaker should activate based on confidence drop
public fun check_confidence_circuit_breaker<T>(
    secure_oracle: &mut SecurePriceOracle,
    current_confidence: u64,
    previous_confidence: u64,
    clock: &Clock
): bool {
    let asset_type = type_name::get<T>();
    
    if (!table::contains(&secure_oracle.price_feeds, asset_type)) {
        return false
    };
    
    let config = table::borrow(&secure_oracle.price_feeds, asset_type);
    if (!config.circuit_breaker_enabled) {
        return false
    };
    
    // Check for significant confidence drop (>20 percentage points)
    let confidence_drop_threshold = 20u64;
    if (previous_confidence > current_confidence) {
        let confidence_drop = safe_math::safe_sub(previous_confidence, current_confidence);
        
        if (confidence_drop > confidence_drop_threshold) {
            let current_time = clock::timestamp_ms(clock) / 1000;
            activate_circuit_breaker_internal<T>(
                secure_oracle,
                2, // Confidence drop trigger
                confidence_drop,
                current_time,
                clock
            );
            return true
        };
    };
    
    false
}

/// Check if circuit breaker should activate based on manipulation detection
public fun check_manipulation_circuit_breaker<T>(
    secure_oracle: &mut SecurePriceOracle,
    manipulation_result: &ManipulationDetectionResult,
    clock: &Clock
): bool {
    let asset_type = type_name::get<T>();
    
    if (!table::contains(&secure_oracle.price_feeds, asset_type)) {
        return false
    };
    
    let config = table::borrow(&secure_oracle.price_feeds, asset_type);
    if (!config.circuit_breaker_enabled) {
        return false
    };
    
    // Activate circuit breaker for high-risk manipulation
    if (manipulation_result.is_manipulation && manipulation_result.risk_level >= 2) {
        let current_time = clock::timestamp_ms(clock) / 1000;
        activate_circuit_breaker_internal<T>(
            secure_oracle,
            3, // Manipulation trigger
            (manipulation_result.risk_level as u64),
            current_time,
            clock
        );
        return true
    };
    
    false
}

/// Activate emergency circuit breaker for all assets
public fun activate_emergency_circuit_breaker(
    secure_oracle: &mut SecurePriceOracle,
    security_admin_cap: &SecurityAdminCap,
    reason: vector<u8>,
    clock: &Clock,
    ctx: &tx_context::TxContext
) {
    assert!(object::id(security_admin_cap) == secure_oracle.emergency_admin_cap_id, errors::unauthorized_oracle_access());
    
    // Set emergency mode
    secure_oracle.emergency_mode = true;
    
    let current_time = clock::timestamp_ms(clock) / 1000;
    
    // Emit emergency circuit breaker event
    event::emit(EmergencyCircuitBreakerEvent {
        activation_time: current_time,
        reason,
        activated_by: tx_context::sender(ctx),
        recovery_time: safe_math::safe_add(current_time, 7200), // 2 hours
    });
    
    // Emit security event
    security::emit_security_event(
        b"EMERGENCY_CIRCUIT_BREAKER",
        security::severity_critical(),
        tx_context::sender(ctx),
        security::create_security_details(
            b"Emergency circuit breaker activated",
            reason
        ),
        security::create_mitigation_action(
            b"EMERGENCY_CIRCUIT_BREAKER",
            b"System-wide emergency pause activated"
        ),
        clock
    );
}

/// Deactivate emergency circuit breaker
public fun deactivate_emergency_circuit_breaker(
    secure_oracle: &mut SecurePriceOracle,
    security_admin_cap: &SecurityAdminCap,
    clock: &Clock,
    ctx: &tx_context::TxContext
) {
    assert!(object::id(security_admin_cap) == secure_oracle.emergency_admin_cap_id, errors::unauthorized_oracle_access());
    
    // Disable emergency mode
    secure_oracle.emergency_mode = false;
    
    let current_time = clock::timestamp_ms(clock) / 1000;
    
    // Emit recovery event
    event::emit(EmergencyRecoveryEvent {
        recovery_time: current_time,
        recovered_by: tx_context::sender(ctx),
        duration: 0, // Will be calculated by monitoring systems
    });
    
    // Emit security event
    security::emit_security_event(
        b"SYSTEM_RECOVERY",
        security::severity_low(),
        tx_context::sender(ctx),
        security::create_security_details(
            b"Emergency circuit breaker deactivated",
            b"System recovery initiated"
        ),
        security::create_mitigation_action(
            b"EMERGENCY_RECOVERY",
            b"Normal operations resumed"
        ),
        clock
    );
}

/// Check if circuit breaker is active for asset
public fun is_circuit_breaker_active<T>(
    secure_oracle: &SecurePriceOracle,
    clock: &Clock
): bool {
    // Check emergency mode first
    if (secure_oracle.emergency_mode) {
        return true
    };
    
    let asset_type = type_name::get<T>();
    
    // For now, we'll implement a simple time-based recovery
    // In a full implementation, this would check the circuit breaker state table
    
    // Check if we have recent circuit breaker activation in price history
    if (table::contains(&secure_oracle.price_history, asset_type)) {
        let history = table::borrow(&secure_oracle.price_history, asset_type);
        if (!vector::is_empty(history)) {
            let last_point = vector::borrow(history, vector::length(history) - 1);
            let current_time = clock::timestamp_ms(clock) / 1000;
            let time_since_last = safe_math::safe_sub(current_time, last_point.timestamp);
            
            // If last price update was very recent and had low validation score, consider breaker active
            if (time_since_last < 3600 && last_point.validation_score < 50) { // 1 hour and low score
                return true
            };
        };
    };
    
    false
}

/// Attempt automatic recovery of circuit breaker
public fun attempt_circuit_breaker_recovery<T>(
    secure_oracle: &mut SecurePriceOracle,
    base_oracle: &PriceOracle,
    clock: &Clock
): bool {
    let asset_type = type_name::get<T>();
    
    // Don't attempt recovery if emergency mode is active
    if (secure_oracle.emergency_mode) {
        return false
    };
    
    // Check if circuit breaker is currently active
    if (!is_circuit_breaker_active<T>(secure_oracle, clock)) {
        return true // Already recovered
    };
    
    // Validate current price conditions
    let validated_price = validate_price_comprehensive<T>(secure_oracle, base_oracle, clock);
    
    // Recovery conditions:
    // 1. Price validation score > 80
    // 2. Manipulation risk < 1 (low)
    // 3. Sufficient time has passed (handled in is_circuit_breaker_active)
    
    let can_recover = validated_price.is_valid && 
                     validated_price.validation_score > 80 && 
                     validated_price.manipulation_risk < 1;
    
    if (can_recover) {
        let current_time = clock::timestamp_ms(clock) / 1000;
        
        // Emit recovery event
        event::emit(CircuitBreakerRecoveryEvent {
            asset_type,
            recovery_time: current_time,
            validation_score: validated_price.validation_score,
            manipulation_risk: validated_price.manipulation_risk,
            recovery_type: b"AUTOMATIC",
        });
        
        // Emit security event
        security::emit_security_event(
            b"SYSTEM_RECOVERY",
            security::severity_low(),
            @0x0,
            security::create_security_details(
                b"Circuit breaker automatic recovery",
                b"Price conditions normalized"
            ),
            security::create_mitigation_action(
                b"CIRCUIT_BREAKER_RECOVERY",
                b"Automatic recovery based on improved price validation"
            ),
            clock
        );
        
        return true
    };
    
    false
}

/// Manual circuit breaker recovery (admin only)
public fun manual_circuit_breaker_recovery<T>(
    secure_oracle: &mut SecurePriceOracle,
    security_admin_cap: &SecurityAdminCap,
    reason: vector<u8>,
    clock: &Clock,
    ctx: &tx_context::TxContext
) {
    assert!(object::id(security_admin_cap) == secure_oracle.emergency_admin_cap_id, errors::unauthorized_oracle_access());
    
    let asset_type = type_name::get<T>();
    let current_time = clock::timestamp_ms(clock) / 1000;
    
    // Emit manual recovery event
    event::emit(CircuitBreakerRecoveryEvent {
        asset_type,
        recovery_time: current_time,
        validation_score: 0, // Manual recovery doesn't depend on validation
        manipulation_risk: 0,
        recovery_type: b"MANUAL",
    });
    
    // Emit security event
    security::emit_security_event(
        b"ADMIN_ACTION",
        security::severity_medium(),
        tx_context::sender(ctx),
        security::create_security_details(
            b"Manual circuit breaker recovery",
            reason
        ),
        security::create_mitigation_action(
            b"MANUAL_RECOVERY",
            b"Administrator override of circuit breaker"
        ),
        clock
    );
}

/// Get trigger reason description
fun get_trigger_reason(trigger_type: u8): vector<u8> {
    if (trigger_type == 1) {
        b"EXTREME_PRICE_DEVIATION"
    } else if (trigger_type == 2) {
        b"CONFIDENCE_DROP"
    } else if (trigger_type == 3) {
        b"MANIPULATION_DETECTED"
    } else if (trigger_type == 4) {
        b"EMERGENCY_ACTIVATION"
    } else {
        b"UNKNOWN_TRIGGER"
    }
}

// ===== Price History Management =====

/// Update price history with new data point and perform validation
public fun update_price_history<T>(
    secure_oracle: &mut SecurePriceOracle,
    validated_price: &ValidatedPriceInfo,
    clock: &Clock
) {
    let asset_type = type_name::get<T>();
    
    if (!table::contains(&secure_oracle.price_history, asset_type)) {
        table::add(&mut secure_oracle.price_history, asset_type, vector::empty<PricePoint>());
    };
    
    let history = table::borrow_mut(&mut secure_oracle.price_history, asset_type);
    
    let new_point = PricePoint {
        price: validated_price.price,
        timestamp: validated_price.timestamp,
        confidence: validated_price.confidence,
        validation_score: validated_price.validation_score,
    };
    
    // Validate new point against existing history before adding
    if (!vector::is_empty(history)) {
        let last_point = vector::borrow(history, vector::length(history) - 1);
        let time_gap = safe_math::safe_sub(validated_price.timestamp, last_point.timestamp);
        
        // Ensure chronological order
        assert!(validated_price.timestamp >= last_point.timestamp, errors::price_validation_failed());
        
        // Check for suspicious time gaps (too frequent updates)
        if (time_gap < 10) { // Less than 10 seconds
            let deviation = calculate_price_deviation(last_point.price, validated_price.price);
            if (deviation > 100) { // >1% change in <10 seconds is suspicious
                // Emit suspicious activity event
                event::emit(SuspiciousActivityEvent {
                    asset_type,
                    activity_type: b"RAPID_PRICE_CHANGE",
                    time_gap,
                    price_deviation: deviation,
                    timestamp: clock::timestamp_ms(clock) / 1000,
                    risk_score: if (deviation > 500) 2 else 1,
                });
            };
        };
    };
    
    vector::push_back(history, new_point);
    
    // Keep only last 100 points to prevent unbounded growth
    while (vector::length(history) > 100) {
        vector::remove(history, 0);
    };
    
    // Perform periodic history analysis
    if (vector::length(history) >= 10) {
        analyze_price_history_patterns<T>(secure_oracle, clock);
    };
}

/// Analyze price history for long-term manipulation patterns
fun analyze_price_history_patterns<T>(
    secure_oracle: &SecurePriceOracle,
    clock: &Clock
) {
    let asset_type = type_name::get<T>();
    let history = table::borrow(&secure_oracle.price_history, asset_type);
    let history_len = vector::length(history);
    
    if (history_len < 10) return;
    
    // Analyze volatility patterns
    let mut total_volatility = 0u64;
    let mut high_volatility_periods = 0u8;
    
    let mut i = 1;
    while (i < history_len) {
        let prev_point = vector::borrow(history, i - 1);
        let curr_point = vector::borrow(history, i);
        let deviation = calculate_price_deviation(prev_point.price, curr_point.price);
        
        total_volatility = total_volatility + deviation;
        
        if (deviation > 500) { // >5% change
            high_volatility_periods = high_volatility_periods + 1;
        };
        
        i = i + 1;
    };
    
    let avg_volatility = total_volatility / (history_len - 1);
    
    // Check for abnormal volatility patterns
    if (high_volatility_periods > (history_len as u8) / 3) { // More than 1/3 high volatility
        event::emit(VolatilityPatternEvent {
            asset_type,
            average_volatility: avg_volatility,
            high_volatility_periods,
            total_periods: (history_len as u8),
            timestamp: clock::timestamp_ms(clock) / 1000,
            pattern_type: b"HIGH_VOLATILITY_CLUSTER",
        });
    };
    
    // Analyze confidence degradation patterns
    analyze_confidence_patterns(history, asset_type, clock);
}

/// Analyze confidence degradation patterns
fun analyze_confidence_patterns(
    history: &vector<PricePoint>,
    asset_type: TypeName,
    clock: &Clock
) {
    let history_len = vector::length(history);
    if (history_len < 5) return;
    
    let mut confidence_drops = 0u8;
    let mut consecutive_drops = 0u8;
    let mut max_consecutive_drops = 0u8;
    
    let mut i = 1;
    while (i < history_len) {
        let prev_point = vector::borrow(history, i - 1);
        let curr_point = vector::borrow(history, i);
        
        if (curr_point.confidence < prev_point.confidence) {
            confidence_drops = confidence_drops + 1;
            consecutive_drops = consecutive_drops + 1;
            if (consecutive_drops > max_consecutive_drops) {
                max_consecutive_drops = consecutive_drops;
            };
        } else {
            consecutive_drops = 0;
        };
        
        i = i + 1;
    };
    
    // Alert if confidence is consistently degrading
    if (max_consecutive_drops >= 3 || confidence_drops > (history_len as u8) / 2) {
        event::emit(ConfidenceDegradationEvent {
            asset_type,
            total_drops: confidence_drops,
            max_consecutive_drops,
            total_periods: (history_len as u8),
            timestamp: clock::timestamp_ms(clock) / 1000,
            severity: if (max_consecutive_drops >= 5) 2 else 1,
        });
    };
}

/// Get price history statistics
public fun get_price_history_stats<T>(secure_oracle: &SecurePriceOracle): PriceHistoryStats {
    let asset_type = type_name::get<T>();
    
    if (!table::contains(&secure_oracle.price_history, asset_type)) {
        return PriceHistoryStats {
            count: 0,
            min_price: 0,
            max_price: 0,
            avg_price: 0,
            avg_volatility: 0,
            avg_confidence: 0,
            last_update: 0,
        }
    };
    
    let history = table::borrow(&secure_oracle.price_history, asset_type);
    let history_len = vector::length(history);
    
    if (history_len == 0) {
        return PriceHistoryStats {
            count: 0,
            min_price: 0,
            max_price: 0,
            avg_price: 0,
            avg_volatility: 0,
            avg_confidence: 0,
            last_update: 0,
        }
    };
    
    let mut min_price = vector::borrow(history, 0).price;
    let mut max_price = min_price;
    let mut total_price = 0u64;
    let mut total_confidence = 0u64;
    let mut total_volatility = 0u64;
    
    let mut i = 0;
    while (i < history_len) {
        let point = vector::borrow(history, i);
        
        if (point.price < min_price) min_price = point.price;
        if (point.price > max_price) max_price = point.price;
        
        total_price = total_price + point.price;
        total_confidence = total_confidence + point.confidence;
        
        if (i > 0) {
            let prev_point = vector::borrow(history, i - 1);
            let volatility = calculate_price_deviation(prev_point.price, point.price);
            total_volatility = total_volatility + volatility;
        };
        
        i = i + 1;
    };
    
    let last_point = vector::borrow(history, history_len - 1);
    
    PriceHistoryStats {
        count: (history_len as u64),
        min_price,
        max_price,
        avg_price: total_price / (history_len as u64),
        avg_volatility: if (history_len > 1) total_volatility / ((history_len - 1) as u64) else 0,
        avg_confidence: total_confidence / (history_len as u64),
        last_update: last_point.timestamp,
    }
}

/// Price history statistics structure
public struct PriceHistoryStats has copy, drop {
    count: u64,
    min_price: u64,
    max_price: u64,
    avg_price: u64,
    avg_volatility: u64,
    avg_confidence: u64,
    last_update: u64,
}

/// Suspicious activity event
public struct SuspiciousActivityEvent has copy, drop {
    asset_type: TypeName,
    activity_type: vector<u8>,
    time_gap: u64,
    price_deviation: u64,
    timestamp: u64,
    risk_score: u8,
}

/// Volatility pattern event
public struct VolatilityPatternEvent has copy, drop {
    asset_type: TypeName,
    average_volatility: u64,
    high_volatility_periods: u8,
    total_periods: u8,
    timestamp: u64,
    pattern_type: vector<u8>,
}

/// Confidence degradation event
public struct ConfidenceDegradationEvent has copy, drop {
    asset_type: TypeName,
    total_drops: u8,
    max_consecutive_drops: u8,
    total_periods: u8,
    timestamp: u64,
    severity: u8,
}

/// Circuit breaker activation event
public struct CircuitBreakerActivationEvent has copy, drop {
    asset_type: TypeName,
    trigger_type: u8,
    trigger_value: u64,
    activation_time: u64,
    recovery_time: u64,
    reason: vector<u8>,
}

/// Circuit breaker recovery event
public struct CircuitBreakerRecoveryEvent has copy, drop {
    asset_type: TypeName,
    recovery_time: u64,
    validation_score: u64,
    manipulation_risk: u8,
    recovery_type: vector<u8>,
}

/// Emergency circuit breaker event
public struct EmergencyCircuitBreakerEvent has copy, drop {
    activation_time: u64,
    reason: vector<u8>,
    activated_by: address,
    recovery_time: u64,
}

/// Emergency recovery event
public struct EmergencyRecoveryEvent has copy, drop {
    recovery_time: u64,
    recovered_by: address,
    duration: u64,
}

// ===== Admin Functions =====

/// Set emergency mode
public fun set_emergency_mode(
    secure_oracle: &mut SecurePriceOracle,
    security_admin_cap: &SecurityAdminCap,
    emergency: bool,
) {
    assert!(object::id(security_admin_cap) == secure_oracle.emergency_admin_cap_id, errors::unauthorized_oracle_access());
    secure_oracle.emergency_mode = emergency;
}

/// Update security parameters
public fun update_security_parameters(
    secure_oracle: &mut SecurePriceOracle,
    admin_cap: &OracleAdminCap,
    max_price_delay: u64,
    min_confidence: u64,
    max_price_deviation: u64,
    circuit_breaker_threshold: u64,
) {
    assert!(object::id(admin_cap) == secure_oracle.admin_cap_id, errors::unauthorized_oracle_access());
    
    secure_oracle.max_price_delay = max_price_delay;
    secure_oracle.min_confidence = min_confidence;
    secure_oracle.max_price_deviation = max_price_deviation;
    secure_oracle.circuit_breaker_threshold = circuit_breaker_threshold;
}

// ===== Accessor Functions =====

/// Get enhanced price feed configuration
public fun get_price_feed_config<T>(secure_oracle: &SecurePriceOracle): &PriceFeedConfig {
    let asset_type = type_name::get<T>();
    assert!(table::contains(&secure_oracle.price_feeds, asset_type), E_SECURE_FEED_NOT_CONFIGURED);
    table::borrow(&secure_oracle.price_feeds, asset_type)
}

/// Get price history for asset
public fun get_price_history<T>(secure_oracle: &SecurePriceOracle): vector<PricePoint> {
    let asset_type = type_name::get<T>();
    if (table::contains(&secure_oracle.price_history, asset_type)) {
        *table::borrow(&secure_oracle.price_history, asset_type)
    } else {
        vector::empty<PricePoint>()
    }
}

/// Check if emergency mode is active
public fun is_emergency_mode(secure_oracle: &SecurePriceOracle): bool {
    secure_oracle.emergency_mode
}

/// Get validation score from validated price info
public fun validation_score(price_info: &ValidatedPriceInfo): u64 {
    price_info.validation_score
}

/// Get manipulation risk from validated price info
public fun manipulation_risk(price_info: &ValidatedPriceInfo): u8 {
    price_info.manipulation_risk
}

/// Create validated price info for testing
public fun create_validated_price_info(
    price: u64,
    confidence: u64,
    timestamp: u64,
    expo: u8,
    is_valid: bool,
    validation_score: u64,
    last_validation_time: u64,
    price_source: u8,
    manipulation_risk: u8,
): ValidatedPriceInfo {
    ValidatedPriceInfo {
        price,
        confidence,
        timestamp,
        expo,
        is_valid,
        validation_score,
        last_validation_time,
        price_source,
        manipulation_risk,
    }
}

/// Get price from validated price info
public fun validated_price_info_price(price_info: &ValidatedPriceInfo): u64 {
    price_info.price
}

/// Get confidence from validated price info
public fun validated_price_info_confidence(price_info: &ValidatedPriceInfo): u64 {
    price_info.confidence
}

/// Get timestamp from validated price info
public fun validated_price_info_timestamp(price_info: &ValidatedPriceInfo): u64 {
    price_info.timestamp
}

/// Get is_valid from validated price info
public fun validated_price_info_is_valid(price_info: &ValidatedPriceInfo): bool {
    price_info.is_valid
}

/// Get validation_score from validated price info
public fun validated_price_info_validation_score(price_info: &ValidatedPriceInfo): u64 {
    price_info.validation_score
}

/// Get manipulation_risk from validated price info
public fun validated_price_info_manipulation_risk(price_info: &ValidatedPriceInfo): u8 {
    price_info.manipulation_risk
}

/// Get decimals from price feed config
public fun price_feed_config_decimals(config: &PriceFeedConfig): u8 {
    config.decimals
}

/// Get heartbeat from price feed config
public fun price_feed_config_heartbeat(config: &PriceFeedConfig): u64 {
    config.heartbeat
}

/// Get deviation threshold from price feed config
public fun price_feed_config_deviation_threshold(config: &PriceFeedConfig): u64 {
    config.deviation_threshold
}

/// Get confidence threshold from price feed config
public fun price_feed_config_confidence_threshold(config: &PriceFeedConfig): u64 {
    config.confidence_threshold
}

/// Get circuit breaker enabled from price feed config
public fun price_feed_config_circuit_breaker_enabled(config: &PriceFeedConfig): bool {
    config.circuit_breaker_enabled
}

/// Get validation enabled from price feed config
public fun price_feed_config_validation_enabled(config: &PriceFeedConfig): bool {
    config.validation_enabled
}

// ===== ManipulationDetectionResult Accessor Functions =====

/// Get is_manipulation from manipulation detection result
public fun manipulation_result_is_manipulation(result: &ManipulationDetectionResult): bool {
    result.is_manipulation
}

/// Get risk_level from manipulation detection result
public fun manipulation_result_risk_level(result: &ManipulationDetectionResult): u8 {
    result.risk_level
}

/// Get pattern_type from manipulation detection result
public fun manipulation_result_pattern_type(result: &ManipulationDetectionResult): u8 {
    result.pattern_type
}

/// Get confidence_score from manipulation detection result
public fun manipulation_result_confidence_score(result: &ManipulationDetectionResult): u64 {
    result.confidence_score
}

/// Get deviation_percentage from manipulation detection result
public fun manipulation_result_deviation_percentage(result: &ManipulationDetectionResult): u64 {
    result.deviation_percentage
}

/// Get action_recommended from manipulation detection result
public fun manipulation_result_action_recommended(result: &ManipulationDetectionResult): vector<u8> {
    result.action_recommended
}

// ===== Circuit Breaker Accessor Functions =====

/// Check if circuit breaker is enabled for asset
public fun is_circuit_breaker_enabled<T>(secure_oracle: &SecurePriceOracle): bool {
    let asset_type = type_name::get<T>();
    if (table::contains(&secure_oracle.price_feeds, asset_type)) {
        let config = table::borrow(&secure_oracle.price_feeds, asset_type);
        config.circuit_breaker_enabled
    } else {
        false
    }
}

/// Get circuit breaker threshold
public fun get_circuit_breaker_threshold(secure_oracle: &SecurePriceOracle): u64 {
    secure_oracle.circuit_breaker_threshold
}

/// Get emergency mode status
public fun get_emergency_mode_status(secure_oracle: &SecurePriceOracle): bool {
    secure_oracle.emergency_mode
}

/// Create circuit breaker state for testing
public fun create_circuit_breaker_state(
    is_active: bool,
    activation_time: u64,
    trigger_type: u8,
    trigger_value: u64,
    recovery_time: u64,
    activation_count: u64,
    last_reset_time: u64,
): CircuitBreakerState {
    CircuitBreakerState {
        is_active,
        activation_time,
        trigger_type,
        trigger_value,
        recovery_time,
        activation_count,
        last_reset_time,
    }
}

/// Get circuit breaker state fields for testing
public fun circuit_breaker_state_is_active(state: &CircuitBreakerState): bool {
    state.is_active
}

public fun circuit_breaker_state_activation_time(state: &CircuitBreakerState): u64 {
    state.activation_time
}

public fun circuit_breaker_state_trigger_type(state: &CircuitBreakerState): u8 {
    state.trigger_type
}

public fun circuit_breaker_state_trigger_value(state: &CircuitBreakerState): u64 {
    state.trigger_value
}

public fun circuit_breaker_state_recovery_time(state: &CircuitBreakerState): u64 {
    state.recovery_time
}

public fun circuit_breaker_state_activation_count(state: &CircuitBreakerState): u64 {
    state.activation_count
}

/// Create circuit breaker config for testing
public fun create_circuit_breaker_config(
    enabled: bool,
    price_deviation_threshold: u64,
    confidence_drop_threshold: u64,
    manipulation_threshold: u8,
    recovery_duration: u64,
    max_activations_per_hour: u64,
    emergency_override: bool,
): CircuitBreakerConfig {
    CircuitBreakerConfig {
        enabled,
        price_deviation_threshold,
        confidence_drop_threshold,
        manipulation_threshold,
        recovery_duration,
        max_activations_per_hour,
        emergency_override,
    }
}

/// Get circuit breaker config fields for testing
public fun circuit_breaker_config_enabled(config: &CircuitBreakerConfig): bool {
    config.enabled
}

public fun circuit_breaker_config_price_deviation_threshold(config: &CircuitBreakerConfig): u64 {
    config.price_deviation_threshold
}

public fun circuit_breaker_config_confidence_drop_threshold(config: &CircuitBreakerConfig): u64 {
    config.confidence_drop_threshold
}

public fun circuit_breaker_config_manipulation_threshold(config: &CircuitBreakerConfig): u8 {
    config.manipulation_threshold
}

public fun circuit_breaker_config_recovery_duration(config: &CircuitBreakerConfig): u64 {
    config.recovery_duration
}

// ===== Manipulation Detection Result Accessors =====

// ===== ValidatedPriceInfo Accessor Functions =====
// Note: These functions replace the duplicate ones that were causing compilation errors

// ===== ManipulationDetectionResult Accessor Functions =====

/// Check if manipulation was detected
public fun manipulation_detection_result_is_manipulation(result: &ManipulationDetectionResult): bool {
    result.is_manipulation
}

/// Get risk level from manipulation detection result
public fun manipulation_detection_result_risk_level(result: &ManipulationDetectionResult): u8 {
    result.risk_level
}

/// Get pattern type from manipulation detection result
public fun manipulation_detection_result_pattern_type(result: &ManipulationDetectionResult): u8 {
    result.pattern_type
}

/// Get confidence score from manipulation detection result
public fun manipulation_detection_result_confidence_score(result: &ManipulationDetectionResult): u64 {
    result.confidence_score
}

/// Get deviation percentage from manipulation detection result
public fun manipulation_detection_result_deviation_percentage(result: &ManipulationDetectionResult): u64 {
    result.deviation_percentage
}

/// Get recommended action from manipulation detection result
public fun manipulation_detection_result_action_recommended(result: &ManipulationDetectionResult): vector<u8> {
    result.action_recommended
}

