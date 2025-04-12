/**
 * @description Class for saving user-specific settings for the Duplication Manager
 * @author Richard Hudson
 * @date 2025-04-11
 */
public with sharing class DRCSaveSettings {
    /**
     * @description Static method for saving user-specific settings for the Duplication Manager
     *
     * @param settingsJson JSON string of user settings
     * @return Boolean indicating success
     */
    @AuraEnabled
    public static Boolean saveUserSettings(String settingsJson) {
        if (String.isBlank(settingsJson)) {
            throw new AuraHandledException('Settings data is required');
        }
        
        try {
            // Parse the settings to validate JSON format
            JSON.deserializeUntyped(settingsJson);
            
            // Check CRUD permissions before SOQL/DML
            if (!Schema.sObjectType.FlowPersonalConfiguration__c.isAccessible() ||
                !Schema.sObjectType.FlowPersonalConfiguration__c.isCreateable() ||
                !Schema.sObjectType.FlowPersonalConfiguration__c.isUpdateable() ||
                !Schema.sObjectType.FlowPersonalConfiguration__c.fields.Configuration__c.isUpdateable()) {
                throw new AuraHandledException('Insufficient permissions on FlowPersonalConfiguration__c object');
            }
            
            // Get or create the settings record for this user
            List<FlowPersonalConfiguration__c> userConfigs = [
                SELECT Id, Configuration__c
                FROM FlowPersonalConfiguration__c
                WHERE OwnerId = :UserInfo.getUserId()
                AND Name = 'DuplicationManagerSettings'
                LIMIT 1
            ];
            
            FlowPersonalConfiguration__c config;
            if (userConfigs.isEmpty()) {
                config = new FlowPersonalConfiguration__c(
                    Name = 'DuplicationManagerSettings',
                    OwnerId = UserInfo.getUserId()
                );
            } else {
                config = userConfigs[0];
            }
            
            // Update the configuration with validated and sanitized data
            config.Configuration__c = settingsJson;
            
            // Save with sharing rules applied
            upsert config;
            
            return true;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving settings: ' + e.getMessage());
        }
    }
}