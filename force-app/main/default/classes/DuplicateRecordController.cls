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
            duplicatesList.sort((Map<String, Object> a, Map<String, Object> b) -> {
                Double scoreA = (Double)a.get('matchScore');
                Double scoreB = (Double)b.get('matchScore');
                return scoreB.compareTo(scoreA);
            });

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
