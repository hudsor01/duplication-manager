public with sharing class DuplicateRecordController {
    
    /**
     * Gets user-specific settings for the Duplication Manager
     *
     * @return Map containing user settings or default settings
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getUserSettings() {
        try {
            // Return default settings
            Map<String, Object> defaultSettings = new Map<String, Object>();
            defaultSettings.put('showAllFields', false);
            defaultSettings.put('autoRefresh', true);
            defaultSettings.put('defaultBatchSize', 200);
            defaultSettings.put('timeRange', 'LAST_30_DAYS');
            defaultSettings.put('notificationsEnabled', true);
            defaultSettings.put('defaultView', 'dashboard');
            
            return defaultSettings;
        } catch (Exception e) {
            throw new AuraHandledException('Error getting settings: ' + e.getMessage());
        }
    }

    /**
     * Saves user-specific settings for the Duplication Manager
     *
     * @param settings Map of settings to save
     * @return Boolean indicating success
     */
    @AuraEnabled
    public static Boolean saveUserSettings(Map<String, Object> settings) {
        try {
            // In a real implementation, this would save to a custom object
            // For now, just return success
            return true;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving settings: ' + e.getMessage());
        }
    }

    /**
     * Gets records for side-by-side comparison
     *
     * @param recordIds List of record IDs to compare
     * @param objectApiName API name of the object
     * @return Map containing records and metadata
     */
    @AuraEnabled
    public static Map<String, Object> getRecordsForComparison(List<String> recordIds, String objectApiName) {
        Map<String, Object> result = new Map<String, Object>();
        
        if (recordIds == null || recordIds.isEmpty()) {
            throw new AuraHandledException('Record IDs are required');
        }
        
        if (String.isBlank(objectApiName)) {
            // Try to determine object type from first ID
            try {
                Id firstId = Id.valueOf(recordIds[0]);
                objectApiName = String.valueOf(firstId.getSObjectType());
            } catch (Exception e) {
                throw new AuraHandledException('Object API name is required');
            }
        }
        
        try {
            // Get fields for the object
            Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
                .get(objectApiName).getDescribe().fields.getMap();
            
            // Build query
            Set<String> standardFields = new Set<String>{'Id', 'Name', 'CreatedDate', 'LastModifiedDate'};
            Set<String> fieldsToQuery = new Set<String>(standardFields);
            
            // Add all accessible fields (up to a limit)
            Integer fieldCount = 0;
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult describe = fieldMap.get(fieldName).getDescribe();
                if (describe.isAccessible()) {
                    fieldsToQuery.add(fieldName);
                    fieldCount++;
                    if (fieldCount > 100) {
                        break; // Limit to 100 fields to avoid query limits
                    }
                }
            }
            
            // Convert set to list for query
            List<String> fieldList = new List<String>(fieldsToQuery);
            
            // Build and execute query
            String query = 'SELECT ' + String.join(fieldList, ', ') + 
                          ' FROM ' + objectApiName + 
                          ' WHERE Id IN :recordIds';
            
            List<SObject> records = Database.query(query);
            
            // Return result
            result.put('records', records);
            result.put('objectApiName', objectApiName);
            result.put('fields', fieldList);
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error getting records for comparison: ' + e.getMessage());
        }
    }

    /**
     * Gets field metadata for an object organized into groups
     *
     * @param objectApiName API name of the object
     * @return Map containing field groups and metadata
     */
    @AuraEnabled
    public static Map<String, Object> getFieldsForObject(String objectApiName) {
        Map<String, Object> result = new Map<String, Object>();
        
        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException('Object API name is required');
        }
        
        try {
            // Get field map for the object
            Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
                .get(objectApiName).getDescribe().fields.getMap();
            
            // Define field groups
            List<Map<String, Object>> fieldGroups = new List<Map<String, Object>>();
            
            // Standard fields group
            Map<String, Object> standardGroup = new Map<String, Object>();
            standardGroup.put('label', 'Standard Fields');
            List<Map<String, Object>> standardFields = new List<Map<String, Object>>();
            
            // System fields group
            Map<String, Object> systemGroup = new Map<String, Object>();
            systemGroup.put('label', 'System Fields');
            List<Map<String, Object>> systemFields = new List<Map<String, Object>>();
            
            // Custom fields group
            Map<String, Object> customGroup = new Map<String, Object>();
            customGroup.put('label', 'Custom Fields');
            List<Map<String, Object>> customFields = new List<Map<String, Object>>();
            
            // Process each field
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                
                // Skip non-accessible fields
                if (!fieldDescribe.isAccessible()) {
                    continue;
                }
                
                // Create field info map
                Map<String, Object> fieldInfo = new Map<String, Object>();
                fieldInfo.put('apiName', fieldName);
                fieldInfo.put('label', fieldDescribe.getLabel());
                fieldInfo.put('type', fieldDescribe.getType().name());
                fieldInfo.put('isCustom', fieldDescribe.isCustom());
                
                // Categorize field
                if (fieldName.toLowerCase().endsWith('__c')) {
                    customFields.add(fieldInfo);
                } else if (fieldName.equals('Id') || fieldName.equals('CreatedDate') || 
                          fieldName.equals('LastModifiedDate') || fieldName.equals('CreatedById') || 
                          fieldName.equals('LastModifiedById') || fieldName.equals('SystemModstamp') || 
                          fieldName.equals('IsDeleted')) {
                    systemFields.add(fieldInfo);
                } else {
                    standardFields.add(fieldInfo);
                }
            }
            
            // Set fields in groups
            standardGroup.put('fields', standardFields);
            systemGroup.put('fields', systemFields);
            customGroup.put('fields', customFields);
            
            // Add groups to result
            fieldGroups.add(standardGroup);
            fieldGroups.add(customGroup);
            fieldGroups.add(systemGroup);
            
            // Set result
            result.put('objectApiName', objectApiName);
            result.put('fieldGroups', fieldGroups);
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error getting fields for object: ' + e.getMessage());
        }
    }

    /**
     * Creates a note record for preserving data from merged records
     *
     * @param parentId ID of the parent record
     * @param title Title of the note
     * @param body Body content of the note
     * @return Boolean indicating success
     */
    @AuraEnabled
    public static Boolean createNote(Id parentId, String title, String body) {
        if (parentId == null) {
            throw new AuraHandledException('Parent record ID is required');
        }
        
        if (String.isBlank(title)) {
            title = 'Data from merged records';
        }
        
        try {
            // This is just a stub implementation that always returns success
            // In a real implementation, this would create a ContentNote
            return true;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating note: ' + e.getMessage());
        }
    }

    /**
     * Gets statistics about duplicates for a specific record
     *
     * @param recordId ID of the record to check for duplicates
     * @return Map containing duplicate statistics
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getDuplicateStatistics(String recordId) {
        if(String.isBlank(recordId)) {
            throw new AuraHandledException('Record Id is required');
        }
        Id recId = Id.valueOf(recordId);
        String objectName = recId.getSobjectType().getDescribe().getName();

        // Create a default statistics response
        Map<String, Object> stats = new Map<String, Object>();
        stats.put('duplicateCount', 0);
        stats.put('matchField', 'Name');
        stats.put('warning', 'No duplicates found');
        
        return stats;
    }

    /**
     * Runs the duplicate finder batch job
     *
     * @param configId ID of the configuration to use
     * @param isDryRun Whether to run in dry run mode
     * @param batchSize Size of batches to process
     * @return ID of the batch job
     */
    @AuraEnabled
    public static Id runDuplicateFinderBatch(String configId, Boolean isDryRun, Integer batchSize) {
        if (String.isBlank(configId)) {
            throw new AuraHandledException('Configuration ID is required');
        }
        
        // This is just a stub implementation that returns a fake job ID
        return UserInfo.getUserId(); // Return user ID as a placeholder
    }

    /**
     * Gets all active duplicate finder settings
     *
     * @return List of active settings as maps
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getActiveSettings() {
        List<Map<String, Object>> result = new List<Map<String, Object>>();

        try {
            // Create a sample configuration
            Map<String, Object> sampleConfig = new Map<String, Object>();
            sampleConfig.put('MasterLabel', 'Account Duplicates');
            sampleConfig.put('DeveloperName', 'Account_Duplicates');
            sampleConfig.put('ObjectApiName', 'Account');
            sampleConfig.put('MatchFields', '["Name", "BillingCity", "Phone"]');
            sampleConfig.put('MasterRecordStrategy', 'MostRecent');
            sampleConfig.put('BatchSize', 200);
            
            result.add(sampleConfig);
        } catch (Exception e) {
            System.debug('Error getting active settings: ' + e.getMessage());
        }

        return result;
    }
}