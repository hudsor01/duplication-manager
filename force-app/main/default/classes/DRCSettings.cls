/**
 * @description Class for retrieving user-specific settings for the Duplication Manager
 * @author Richard Hudson
 * @date 2025-04-11
 */
public with sharing class DRCSettings {
    /**
     * @description Static method for retrieving user-specific settings for the Duplication Manager
     *
     * @return Map containing user settings or default settings
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getUserSettings() {
        try {
            // Check CRUD permissions before querying
            if (!Schema.sObjectType.FlowPersonalConfiguration__c.isAccessible() ||
                !Schema.sObjectType.FlowPersonalConfiguration__c.fields.Configuration__c.isAccessible()) {
                // Return default settings if no access
                return getDefaultSettings();
            }
            
            // Get the settings record for this user
            List<FlowPersonalConfiguration__c> userConfigs = [
                SELECT Id, Configuration__c
                FROM FlowPersonalConfiguration__c
                WHERE OwnerId = :UserInfo.getUserId()
                AND Name = 'DuplicationManagerSettings'
                LIMIT 1
            ];
            
            // If settings exist, return them
            if (!userConfigs.isEmpty() && String.isNotBlank(userConfigs[0].Configuration__c)) {
                return (Map<String, Object>)JSON.deserializeUntyped(userConfigs[0].Configuration__c);
            }
            
            // Otherwise, return default settings
            return getDefaultSettings();
        } catch (Exception e) {
            throw new AuraHandledException('Error getting settings: ' + e.getMessage());
        }
    }
    
    /**
     * @description Returns default settings when user-specific settings are not available
     * @return Map containing default settings
     */
    private static Map<String, Object> getDefaultSettings() {
        Map<String, Object> defaultSettings = new Map<String, Object>();
        defaultSettings.put('showAllFields', false);
        defaultSettings.put('autoRefresh', true);
        defaultSettings.put('defaultBatchSize', 200);
        defaultSettings.put('timeRange', 'LAST_30_DAYS');
        defaultSettings.put('notificationsEnabled', true);
        defaultSettings.put('defaultView', 'dashboard');
        
        return defaultSettings;
    }
}