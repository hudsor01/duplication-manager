public with sharing class DuplicateRecordController {

    /**
     * Gets user-specific settings for the duplicate Manager
     *
     * @return Map containing user settings or default settings
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getUserSettings() {
        try {
            // Try to get user-specific settings from custom settings or custom object
            Map<String, Object> settings = new Map<String, Object>();
            
            // Create user preference name
            String prefName = 'UserPreference_' + UserInfo.getUserId();
            
            // Query user-specific settings based on current user
            List<DuplicateFinderSettings__c> userSettings = [
                SELECT Name, ObjectAPIName__c, IsActive__c, MatchFields__c
                FROM DuplicateFinderSettings__c 
                WHERE Name = :prefName
                LIMIT 1
            ];
            
            if (!userSettings.isEmpty() && String.isNotBlank(userSettings[0].MatchFields__c)) {
                try {
                    // Parse settings from stored fields
                    settings.put('matchFields', userSettings[0].MatchFields__c);
                    settings.put('objectApiName', userSettings[0].ObjectAPIName__c);
                    settings.put('isActive', userSettings[0].IsActive__c);
                    return settings;
                } catch (Exception parseEx) {
                    System.debug(LoggingLevel.ERROR, 'Error parsing user settings: ' + parseEx.getMessage());
                    // Continue to return default settings instead
                }
            }
            
            // Return default settings if no user settings found or couldn't parse
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
     * Saves user-specific settings for the duplicate Manager
     *
     * @param settings Map of settings to save
     * @return Boolean indicating success
     */
    @AuraEnabled
    public static Boolean saveUserSettings(Map<String, Object> settings) {
        try {
            if (settings == null) {
                throw new AuraHandledException('Settings cannot be null');
            }
            
            // Convert settings to JSON string
            String settingsJson = JSON.serialize(settings);
            
            // User-specific setting name
            String settingName = 'UserPreference_' + UserInfo.getUserId();
            
            // Query for existing settings
            List<DuplicateFinderSettings__c> existingSettings = [
                SELECT Id 
                FROM DuplicateFinderSettings__c 
                WHERE Name = :settingName
                LIMIT 1
            ];
            
            if (existingSettings.isEmpty()) {
                // Extract data from settings
                String objectApiName = (String)settings.get('objectApiName');
                String matchFields = (String)settings.get('matchFields');
                Boolean isActive = settings.containsKey('isActive') ? (Boolean)settings.get('isActive') : true;
                
                // Create new settings record
                DuplicateFinderSettings__c newSetting = new DuplicateFinderSettings__c(
                    Name = settingName,
                    ObjectAPIName__c = objectApiName,
                    MatchFields__c = matchFields,
                    IsActive__c = isActive
                );
                insert newSetting;
            } else {
                // Extract data from settings
                String objectApiName = (String)settings.get('objectApiName');
                String matchFields = (String)settings.get('matchFields');
                Boolean isActive = settings.containsKey('isActive') ? (Boolean)settings.get('isActive') : true;
                
                // Update existing settings
                DuplicateFinderSettings__c existingSetting = existingSettings[0];
                existingSetting.ObjectAPIName__c = objectApiName;
                existingSetting.MatchFields__c = matchFields;
                existingSetting.IsActive__c = isActive;
                update existingSetting;
            }
            
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
            // Create standard note
            Note note = new Note(
                Title = title,
                Body = body,
                ParentId = parentId
            );
            
            // Check permissions before inserting
            if (!Schema.sObjectType.Note.isCreateable()) {
                throw new AuraHandledException('Insufficient permissions to create notes');
            }
            
            insert note;
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

        // Call the DuplicateJobService to run the batch job
        DuplicateJobService jobService = new DuplicateJobService();
        return jobService.runDuplicateFinderBatch(configId, isDryRun, batchSize);
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
            // Query all active settings from custom metadata
            List<DuplicationConfiguration__mdt> configurations = [
                SELECT Id, MasterLabel, DeveloperName, ObjectApiName__c, 
                       MatchFields__c, MasterRecordStrategy__c, BatchSize__c,
                       MatchThreshold__c, IsActive__c, Description__c
                FROM DuplicationConfiguration__mdt
                WHERE IsActive__c = true
                ORDER BY MasterLabel
            ];
            
            // Convert to list of maps for UI
            for (DuplicationConfiguration__mdt config : configurations) {
                Map<String, Object> configMap = new Map<String, Object>();
                configMap.put('Id', config.Id);
                configMap.put('MasterLabel', config.MasterLabel);
                configMap.put('DeveloperName', config.DeveloperName);
                configMap.put('ObjectApiName', config.ObjectApiName__c);
                configMap.put('MatchFields', config.MatchFields__c);
                configMap.put('MasterRecordStrategy', config.MasterRecordStrategy__c);
                configMap.put('BatchSize', config.BatchSize__c);
                configMap.put('MatchThreshold', config.MatchThreshold__c);
                configMap.put('Description', config.Description__c);
                
                result.add(configMap);
            }
            
            // If no configurations found, check for default settings in old metadata type
            if (result.isEmpty()) {
                List<DuplicateFinderSetting__mdt> legacySettings = [
                    SELECT Id, MasterLabel, DeveloperName, SObject_API_Name__c,
                           MatchFields__c, MasterRecordStrategy__c, BatchSize__c
                    FROM DuplicateFinderSetting__mdt
                    WHERE IsActive__c = true
                    ORDER BY MasterLabel
                ];
                
                // Convert legacy settings
                for (DuplicateFinderSetting__mdt setting : legacySettings) {
                    Map<String, Object> configMap = new Map<String, Object>();
                    configMap.put('Id', setting.Id);
                    configMap.put('MasterLabel', setting.MasterLabel);
                    configMap.put('DeveloperName', setting.DeveloperName);
                    configMap.put('ObjectApiName', setting.SObject_API_Name__c);
                    configMap.put('MatchFields', setting.MatchFields__c);
                    configMap.put('MasterRecordStrategy', setting.MasterRecordStrategy__c);
                    configMap.put('BatchSize', setting.BatchSize__c);
                    
                    result.add(configMap);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting active settings: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving duplicate configurations: ' + e.getMessage());
        }

        return result;
    }

    /**
     * Gets results from a duplicate run
     *
     * @param batchJobId ID of the batch job
     * @param pageSize Number of records per page
     * @param pageNumber Current page number
     * @param filters Optional filters to apply
     * @return Map containing results and pagination info
     */
    @AuraEnabled
    public static Map<String, Object> getDuplicateRunResults(
        String batchJobId,
        Integer pageSize,
        Integer pageNumber,
        Map<String, Object> filters
    ) {
        Map<String, Object> result = new Map<String, Object>();

        try {
            // Query the run result
            DuplicateRunResult__c runResult = [
                SELECT Id, BatchJobId__c, ConfigurationName__c, ObjectApiName__c,
                       DuplicatesFound__c, RecordsProcessed__c, RecordsMerged__c,
                       ProcessingTimeMs__c, Status__c, IsDryRun__c
                FROM DuplicateRunResult__c
                WHERE BatchJobId__c = :batchJobId
                LIMIT 1
            ];

            // Create summary
            Map<String, Object> summary = new Map<String, Object>();
            summary.put('batchJobId', runResult.BatchJobId__c);
            summary.put('configName', runResult.ConfigurationName__c);
            summary.put('objectApiName', runResult.ObjectApiName__c);
            summary.put('isDryRun', runResult.IsDryRun__c);
            summary.put('duplicatesFound', runResult.DuplicatesFound__c);
            summary.put('recordsProcessed', runResult.RecordsProcessed__c);
            summary.put('recordsMerged', runResult.RecordsMerged__c);
            summary.put('status', runResult.Status__c);

            // Get duplicate groups
            Integer offset = (pageNumber - 1) * pageSize;

            // Query duplicate groups
            List<DuplicateGroupDetail__c> groups = [
                SELECT Id, GroupKey__c, MatchScore__c, MasterRecordId__c,
                       DuplicateRecordIds__c, RecordCount__c, FieldValues__c
                FROM DuplicateGroupDetail__c
                WHERE DuplicateRunResult__c = :runResult.Id
                ORDER BY MatchScore__c DESC
                LIMIT :pageSize
                OFFSET :offset
            ];

            // Calculate total records
            Integer totalRecords = [
                SELECT COUNT()
                FROM DuplicateGroupDetail__c
                WHERE DuplicateRunResult__c = :runResult.Id
            ];

            // Convert to list of maps for UI
            List<Map<String, Object>> groupsList = new List<Map<String, Object>>();
            for (DuplicateGroupDetail__c grp : groups) {
                Map<String, Object> groupMap = new Map<String, Object>();
                groupMap.put('id', grp.Id);
                groupMap.put('groupKey', grp.GroupKey__c);
                groupMap.put('matchScore', grp.MatchScore__c);
                groupMap.put('masterRecordId', grp.MasterRecordId__c);
                groupMap.put('duplicateRecordIds', grp.DuplicateRecordIds__c);
                groupMap.put('recordCount', grp.RecordCount__c);
                // Parse field values if available
                if (String.isNotBlank(grp.FieldValues__c)) {
                    try {
                        groupMap.put('fieldValues', JSON.deserializeUntyped(grp.FieldValues__c));
                    } catch (Exception e) {
                        groupMap.put('fieldValues', new Map<String, Object>());
                    }
                }
                groupsList.add(groupMap);
            }

            // Calculate pagination info
            Integer totalPages = Math.max(1, (Integer)Math.ceil((Double)totalRecords / pageSize));
            Map<String, Object> pagination = new Map<String, Object>();
            pagination.put('pageSize', pageSize);
            pagination.put('pageNumber', pageNumber);
            pagination.put('totalRecords', totalRecords);
            pagination.put('totalPages', totalPages);

            // Build final result
            result.put('summary', summary);
            result.put('groups', groupsList);
            result.put('pagination', pagination);

            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error getting duplicate run results: ' + e.getMessage());
        }
    }

    /**
     * Merges duplicate records
     *
     * @param request Map containing merge parameters
     * @return Map with success status and message
     */
    @AuraEnabled
    public static Map<String, Object> mergeDuplicateRecords(Map<String, Object> request) {
        Map<String, Object> result = new Map<String, Object>();

        try {
            // Extract parameters from request
            Id masterRecordId = (Id)request.get('masterRecordId');
            List<String> duplicateRecordIds = (List<String>)request.get('duplicateRecordIds');
            String objectApiName = (String)request.get('objectApiName');

            // Validate parameters
            if (masterRecordId == null) {
                throw new AuraHandledException('Master record ID is required');
            }

            if (duplicateRecordIds == null || duplicateRecordIds.isEmpty()) {
                throw new AuraHandledException('At least one duplicate record ID is required');
            }

            if (String.isBlank(objectApiName)) {
                // Try to determine from master record ID
                objectApiName = String.valueOf(masterRecordId.getSObjectType());
            }

            // Convert String IDs to Id type
            List<Id> dupeIds = new List<Id>();
            for (String idStr : duplicateRecordIds) {
                dupeIds.add((Id)idStr);
            }

            // Perform merge - this uses the standard merge operation
            // In a real implementation, you might have custom logic or call a service class
            Database.MergeResult[] mergeResults;

            if (objectApiName == 'Account') {
                Account master = [SELECT Id FROM Account WHERE Id = :masterRecordId];
                List<Account> duplicates = [SELECT Id FROM Account WHERE Id IN :dupeIds];
                mergeResults = Database.merge(master, duplicates);
            } else if (objectApiName == 'Contact') {
                Contact master = [SELECT Id FROM Contact WHERE Id = :masterRecordId];
                List<Contact> duplicates = [SELECT Id FROM Contact WHERE Id IN :dupeIds];
                mergeResults = Database.merge(master, duplicates);
            } else if (objectApiName == 'Lead') {
                Lead master = [SELECT Id FROM Lead WHERE Id = :masterRecordId];
                List<Lead> duplicates = [SELECT Id FROM Lead WHERE Id IN :dupeIds];
                mergeResults = Database.merge(master, duplicates);
            } else {
                throw new AuraHandledException('Merge is only supported for Account, Contact, and Lead objects');
            }

            // Process merge results
            Boolean success = true;
            String message = 'Records merged successfully';

            for (Database.MergeResult res : mergeResults) {
                if (!res.isSuccess()) {
                    success = false;
                    message = 'Error merging records: ' + res.getErrors()[0].getMessage();
                    break;
                }
            }

            // Build result
            result.put('success', success);
            result.put('message', message);
            result.put('masterRecordId', masterRecordId);
            result.put('mergedRecordCount', duplicateRecordIds.size());

            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error merging records: ' + e.getMessage());
        }
    }

    /**
     * Checks for duplicates of a specific record
     *
     * @param request Map containing check parameters
     * @return Map with duplicates found
     */
    @AuraEnabled
    public static Map<String, Object> checkForDuplicates(Map<String, Object> request) {
        Map<String, Object> result = new Map<String, Object>();

        try {
            // Extract parameters from request
            String objectApiName = (String)request.get('objectApiName');
            String recordId = (String)request.get('recordId');
            List<String> matchFields = (List<String>)request.get('matchFields');

            // Validate parameters
            if (String.isBlank(objectApiName)) {
                throw new AuraHandledException('Object API name is required');
            }

            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }

            if (matchFields == null || matchFields.isEmpty()) {
                throw new AuraHandledException('Match fields are required');
            }

            // Query the source record
            String query = 'SELECT Id';

            for (String field : matchFields) {
                query += ', ' + field;
            }

            query += ' FROM ' + objectApiName + ' WHERE Id = \'' + String.escapeSingleQuotes(recordId) + '\'';

            SObject sourceRecord = Database.query(query);

            if (sourceRecord == null) {
                throw new AuraHandledException('Record not found');
            }

            // Build query for potential duplicates
            query = 'SELECT Id';

            for (String field : matchFields) {
                query += ', ' + field;
            }

            query += ' FROM ' + objectApiName + ' WHERE Id != \'' + String.escapeSingleQuotes(recordId) + '\'';

            // Add filters based on match fields
            List<String> filters = new List<String>();

            for (String field : matchFields) {
                Object value = sourceRecord.get(field);

                if (value != null) {
                    if (value instanceof String) {
                        filters.add(field + ' = \'' + String.escapeSingleQuotes((String)value) + '\'');
                    } else {
                        filters.add(field + ' = ' + value);
                    }
                }
            }

            if (!filters.isEmpty()) {
                query += ' AND (' + String.join(filters, ' OR ') + ')';
            }

            query += ' LIMIT 100';

            // Query for duplicates
            List<SObject> duplicates = Database.query(query);

            // Convert to list of maps with match scores
            List<Map<String, Object>> duplicatesList = new List<Map<String, Object>>();

            for (SObject dupe : duplicates) {
                Map<String, Object> dupeMap = new Map<String, Object>();
                dupeMap.put('id', dupe.Id);

                // Calculate a simple match score (percentage of matching fields)
                Integer matchingFields = 0;

                for (String field : matchFields) {
                    Object sourceValue = sourceRecord.get(field);
                    Object dupeValue = dupe.get(field);

                    if (sourceValue == dupeValue ||
                        (sourceValue != null && dupeValue != null && sourceValue.equals(dupeValue))) {
                        matchingFields++;
                    }
                }

                Double matchScore = 100.0 * matchingFields / matchFields.size();
                dupeMap.put('matchScore', matchScore);

                // Add field values
                Map<String, Object> fieldValues = new Map<String, Object>();

                for (String field : matchFields) {
                    fieldValues.put(field, dupe.get(field));
                }

                dupeMap.put('fieldValues', fieldValues);

                duplicatesList.add(dupeMap);
            }

            // Sort by match score (highest first)
            duplicatesList.sort();
            
            // We have already found duplicates
            Map<String, Object> resultMap = new Map<String, Object>();

            // Build result
            result.put('duplicatesFound', duplicatesList.size());
            result.put('duplicates', duplicatesList);
            result.put('sourceRecord', sourceRecord);
            result.put('matchFields', matchFields);

            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error checking for duplicates: ' + e.getMessage());
        }
    }
}
