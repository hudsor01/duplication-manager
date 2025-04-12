/**
 * Utility class for accessing Duplication Manager settings
 * Provides a unified interface for all components to access metadata settings
 * 
 * @author Richard Hudson
 * @since April 2025
 * @updated May 2025 Added support for DuplicationConfiguration__mdt
 */
public with sharing class DuplicationSettingsUtil {
    // Cache for settings to minimize metadata queries
    private static Map<String, DuplicationSetting__mdt> settingsCache;
    
    // Cache for settings by category
    private static Map<String, List<DuplicationSetting__mdt>> categoryCache;
    
    // Cache for settings by object
    private static Map<String, List<DuplicationSetting__mdt>> objectCache;
    
    // Cache for duplication configurations
    private static Map<String, DuplicationConfiguration__mdt> configCache = new Map<String, DuplicationConfiguration__mdt>();
    
    // SECTION 1: ORIGINAL SETTINGS METHODS
    
    /**
     * Get all settings
     * @return Map of setting key to setting metadata
     */
    public static Map<String, DuplicationSetting__mdt> getAllSettings() {
        return getSettingsCache();
    }
    
    /**
     * Get a flat map of all setting keys to values
     * @return Map of setting key to setting value
     */
    public static Map<String, String> getAllSettingValues() {
        Map<String, String> settingValues = new Map<String, String>();
        
        for (DuplicationSetting__mdt setting : getSettingsCache().values()) {
            if (setting.IsActive__c) {
                settingValues.put(setting.Key__c, setting.Value__c);
            }
        }
        
        return settingValues;
    }
    
    /**
     * Get settings by category
     * @param category The category of settings to retrieve
     * @return List of settings in the specified category
     */
    public static List<DuplicationSetting__mdt> getSettingsByCategory(String category) {
        if (categoryCache == null) {
            categoryCache = new Map<String, List<DuplicationSetting__mdt>>();
        }
        
        if (!categoryCache.containsKey(category)) {
            List<DuplicationSetting__mdt> categorySettings = new List<DuplicationSetting__mdt>();
            
            for (DuplicationSetting__mdt setting : getSettingsCache().values()) {
                if (setting.Category__c == category) {
                    categorySettings.add(setting);
                }
            }
            
            categoryCache.put(category, categorySettings);
        }
        
        return categoryCache.get(category);
    }
    
    /**
     * Get settings by object
     * @param objectApiName API name of the object
     * @return List of settings for the specified object
     */
    public static List<DuplicationSetting__mdt> getSettingsByObject(String objectApiName) {
        if (objectCache == null) {
            objectCache = new Map<String, List<DuplicationSetting__mdt>>();
        }
        
        if (!objectCache.containsKey(objectApiName)) {
            List<DuplicationSetting__mdt> objectSettings = new List<DuplicationSetting__mdt>();
            
            for (DuplicationSetting__mdt setting : getSettingsCache().values()) {
                if (setting.ObjectApiName__c == objectApiName) {
                    objectSettings.add(setting);
                }
            }
            
            objectCache.put(objectApiName, objectSettings);
        }
        
        return objectCache.get(objectApiName);
    }
    
    /**
     * Get setting values by category
     * @param category The category of settings to retrieve
     * @return Map of setting key to setting value
     */
    public static Map<String, String> getValuesByCategory(String category) {
        Map<String, String> settingValues = new Map<String, String>();
        
        for (DuplicationSetting__mdt setting : getSettingsByCategory(category)) {
            if (setting.IsActive__c) {
                settingValues.put(setting.Key__c, setting.Value__c);
            }
        }
        
        return settingValues;
    }
    
    /**
     * Get a specific setting
     * @param key The setting key
     * @return The setting metadata, or null if not found
     */
    public static DuplicationSetting__mdt getSetting(String key) {
        return getSettingsCache().get(key);
    }
    
    /**
     * Get a specific setting value
     * @param key The setting key
     * @return The setting value, or null if not found
     */
    public static String getValue(String key) {
        DuplicationSetting__mdt setting = getSetting(key);
        return (setting != null && setting.IsActive__c) ? setting.Value__c : null;
    }
    
    /**
     * Get a specific setting value as an Integer
     * @param key The setting key
     * @param defaultValue The default value if setting not found or not a valid integer
     * @return The setting value as an Integer
     */
    public static Integer getIntegerValue(String key, Integer defaultValue) {
        String value = getValue(key);
        if (value == null) {
            return defaultValue;
        }
        
        try {
            return Integer.valueOf(value);
        } catch (Exception e) {
            return defaultValue;
        }
    }
    
    /**
     * Get a specific setting value as a Decimal
     * @param key The setting key
     * @param defaultValue The default value if setting not found or not a valid decimal
     * @return The setting value as a Decimal
     */
    public static Decimal getDecimalValue(String key, Decimal defaultValue) {
        String value = getValue(key);
        if (value == null) {
            return defaultValue;
        }
        
        try {
            return Decimal.valueOf(value);
        } catch (Exception e) {
            return defaultValue;
        }
    }
    
    /**
     * Get a specific setting value as a Boolean
     * @param key The setting key
     * @param defaultValue The default value if setting not found
     * @return The setting value as a Boolean
     */
    public static Boolean getBooleanValue(String key, Boolean defaultValue) {
        String value = getValue(key);
        if (value == null) {
            return defaultValue;
        }
        
        return 'true'.equalsIgnoreCase(value);
    }
    
    /**
     * Get a specific setting value as a List<String>
     * @param key The setting key
     * @return The setting value as a List<String>, or empty list if not found
     */
    public static List<String> getStringListValue(String key) {
        String value = getValue(key);
        if (value == null) {
            return new List<String>();
        }
        
        return value.split(',');
    }
    
    /**
     * Get a specific setting value as a Map<String, Object>
     * @param key The setting key
     * @return The setting value as a Map<String, Object>, or empty map if not found or not valid JSON
     */
    public static Map<String, Object> getJsonValue(String key) {
        String value = getValue(key);
        if (value == null) {
            return new Map<String, Object>();
        }
        
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(value);
        } catch (Exception e) {
            return new Map<String, Object>();
        }
    }
    
    /**
     * Initialize or get the settings cache
     * @return Map of setting key to setting metadata
     */
    private static Map<String, DuplicationSetting__mdt> getSettingsCache() {
        if (settingsCache == null) {
            settingsCache = new Map<String, DuplicationSetting__mdt>();
            
            // Query all settings
            for (DuplicationSetting__mdt setting : [
                SELECT Id, DeveloperName, MasterLabel, 
                       Key__c, Value__c, Category__c, 
                       IsActive__c, ObjectApiName__c, Description__c 
                FROM DuplicationSetting__mdt
            ]) {
                settingsCache.put(setting.Key__c, setting);
            }
        }
        
        return settingsCache;
    }
    
    // SECTION 2: NEW DUPLICATION CONFIGURATION METHODS
    
    /**
     * Get all active duplication configurations
     * @return List<DuplicationConfiguration__mdt> List of active configurations
     */
    public static List<DuplicationConfiguration__mdt> getAllActiveConfigurations() {
        return [
            SELECT 
                Id, DeveloperName, MasterLabel, ObjectApiName__c, MatchFields__c, 
                BatchSize__c, MasterRecordStrategy__c, IsActive__c, MatchThreshold__c,
                MatchFieldWeights__c, PreMergeApexHandler__c, PostMergeApexHandler__c,
                Version__c, Description__c
            FROM DuplicationConfiguration__mdt 
            WHERE IsActive__c = true
            ORDER BY MasterLabel
        ];
    }
    
    /**
     * Get a specific configuration by developer name
     * @param configName The developer name of the configuration
     * @return DuplicationConfiguration__mdt The configuration record
     */
    public static DuplicationConfiguration__mdt getConfigurationByName(String configName) {
        // Check cache first
        if (configCache.containsKey(configName)) {
            return configCache.get(configName);
        }
        
        // Query if not in cache
        try {
            DuplicationConfiguration__mdt config = [
                SELECT 
                    Id, DeveloperName, MasterLabel, ObjectApiName__c, MatchFields__c, 
                    BatchSize__c, MasterRecordStrategy__c, IsActive__c, MatchThreshold__c,
                    MatchFieldWeights__c, PreMergeApexHandler__c, PostMergeApexHandler__c,
                    Version__c, Description__c
                FROM DuplicationConfiguration__mdt 
                WHERE DeveloperName = :configName
                LIMIT 1
            ];
            
            // Add to cache
            configCache.put(configName, config);
            return config;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error retrieving configuration: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * Get configurations for a specific object
     * @param objectApiName The API name of the object
     * @return List<DuplicationConfiguration__mdt> List of configurations for the object
     */
    public static List<DuplicationConfiguration__mdt> getConfigurationsForObject(String objectApiName) {
        return [
            SELECT 
                Id, DeveloperName, MasterLabel, ObjectApiName__c, MatchFields__c, 
                BatchSize__c, MasterRecordStrategy__c, IsActive__c, MatchThreshold__c,
                MatchFieldWeights__c, PreMergeApexHandler__c, PostMergeApexHandler__c,
                Version__c, Description__c
            FROM DuplicationConfiguration__mdt 
            WHERE ObjectApiName__c = :objectApiName
            AND IsActive__c = true
            ORDER BY MasterLabel
        ];
    }
    
    /**
     * Parse match fields from configuration
     * @param config The duplication configuration
     * @return List<String> List of match field API names
     */
    public static List<String> parseMatchFields(DuplicationConfiguration__mdt config) {
        if (config == null || String.isBlank(config.MatchFields__c)) {
            return new List<String>();
        }
        
        // Split the comma-separated list and trim whitespace
        List<String> fields = new List<String>();
        for (String field : config.MatchFields__c.split(',')) {
            fields.add(field.trim());
        }
        
        return fields;
    }
    
    /**
     * Parse match field weights from configuration
     * @param config The duplication configuration
     * @return Map<String, Decimal> Map of field name to weight
     */
    public static Map<String, Decimal> parseFieldWeights(DuplicationConfiguration__mdt config) {
        Map<String, Decimal> fieldWeights = new Map<String, Decimal>();
        
        if (config == null || String.isBlank(config.MatchFieldWeights__c)) {
            // Return empty map if no weights defined
            return fieldWeights;
        }
        
        try {
            // Parse JSON map of field weights
            Map<String, Object> parsedMap = (Map<String, Object>)JSON.deserializeUntyped(config.MatchFieldWeights__c);
            
            // Convert to appropriate types
            for (String fieldName : parsedMap.keySet()) {
                Object value = parsedMap.get(fieldName);
                if (value instanceof Decimal) {
                    fieldWeights.put(fieldName, (Decimal)value);
                } else if (value instanceof Integer) {
                    fieldWeights.put(fieldName, Decimal.valueOf((Integer)value));
                } else if (value instanceof String) {
                    try {
                        fieldWeights.put(fieldName, Decimal.valueOf((String)value));
                    } catch (Exception e) {
                        System.debug(LoggingLevel.WARN, 'Invalid weight value for field ' + fieldName);
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error parsing field weights: ' + e.getMessage());
        }
        
        return fieldWeights;
    }
    
    /**
     * Create a DuplicateConfig object from metadata configuration
     * @param configName The developer name of the configuration
     * @return DuplicateConfig The configuration object
     */
    public static DuplicateConfig createConfigFromMetadata(String configName) {
        DuplicationConfiguration__mdt metadata = getConfigurationByName(configName);
        
        if (metadata == null) {
            return new DuplicateConfig();
        }
        
        // Create new config with parsed values
        DuplicateConfig config = new DuplicateConfig();
        config.objectApiName = metadata.ObjectApiName__c;
        config.matchFields = parseMatchFields(metadata);
        config.batchSize = (Integer)metadata.BatchSize__c;
        config.masterRecordStrategy = metadata.MasterRecordStrategy__c;
        config.isActive = metadata.IsActive__c;
        
        return config;
    }
    
    // SECTION 3: CACHE MANAGEMENT
    
    /**
     * Clear all caches (useful for testing)
     */
    @TestVisible
    private static void clearCaches() {
        settingsCache = null;
        categoryCache = null;
        objectCache = null;
        configCache.clear();
    }
    
    /**
     * Clear just the configuration cache
     */
    public static void clearConfigCache() {
        configCache.clear();
    }
}