/**
 * Constants class for the Duplication Manager application
 * Centralizes all configuration values that were previously hardcoded
 * 
 * @author Richard Hudson
 * @date April 2025
 */
public without sharing class DuplicateConstants {
    
    // Match thresholds
    public static final Integer FUZZY_MATCH_THRESHOLD = 65;
    public static final Integer EMAIL_SIMILARITY_THRESHOLD = 80;
    public static final Integer NAME_SIMILARITY_THRESHOLD = 70;
    public static final Integer BUSINESS_NAME_SIMILARITY_THRESHOLD = 75;
    
    // Cache sizes
    public static final Integer MAX_CACHE_SIZE = 1000;
    public static final Integer MAX_STRING_CACHE_LENGTH = 200;
    
    // Batch processing
    public static final Integer DEFAULT_BATCH_SIZE = 200;
    public static final Integer MIN_CHUNK_SIZE = 100;
    public static final Integer MAX_CHUNK_SIZE = 5000;
    public static final Integer DEFAULT_CHUNK_SIZE = 2000;
    
    // Time ranges
    public static final Integer LOG_RETENTION_DAYS = 90;
    public static final Integer RECORD_TIME_RANGE_DAYS = 90;
    
    // Field weights
    public static final Decimal EMAIL_FIELD_WEIGHT = 2.5;
    public static final Decimal PHONE_FIELD_WEIGHT = 2.0;
    public static final Decimal NAME_FIELD_WEIGHT = 1.7;
    public static final Decimal ADDRESS_FIELD_WEIGHT = 1.5;
    public static final Decimal DEFAULT_FIELD_WEIGHT = 1.0;
    
    // CPU usage threshold for queueable processing
    public static final Decimal CPU_USAGE_THRESHOLD = 0.7; // 70% of limit
    public static final Decimal HEAP_USAGE_THRESHOLD = 0.7; // 70% of limit
    public static final Decimal QUERY_USAGE_THRESHOLD = 0.7; // 70% of limit
    public static final Decimal DML_USAGE_THRESHOLD = 0.7; // 70% of limit
    
    /**
     * Get field weights for different field types
     * @return Map of field type to weight
     */
    public static Map<String, Decimal> getFieldTypeWeights() {
        return new Map<String, Decimal>{
            'email' => EMAIL_FIELD_WEIGHT,
            'phone' => PHONE_FIELD_WEIGHT,
            'name' => NAME_FIELD_WEIGHT,
            'address' => ADDRESS_FIELD_WEIGHT,
            'default' => DEFAULT_FIELD_WEIGHT
        };
    }
    
    /**
     * Get a configurable value from custom metadata if available, falling back to default
     * @param key The configuration key
     * @param defaultValue The default value if not found
     * @return The configuration value
     */
    public static Integer getConfigInteger(String key, Integer defaultValue) {
        Integer value = defaultValue;
        try {
            List<DuplicationConfiguration__mdt> configs = [
                SELECT Value__c FROM DuplicationConfiguration__mdt 
                WHERE DeveloperName = :key 
                LIMIT 1
            ];
            
            if (!configs.isEmpty() && configs[0].Value__c != null) {
                value = Integer.valueOf(configs[0].Value__c);
            }
        } catch (Exception e) {
            DuplicateLogger.warn('DuplicateConstants', 'Error fetching configuration value for ' + key + ': ' + e.getMessage());
        }
        
        return value;
    }
}