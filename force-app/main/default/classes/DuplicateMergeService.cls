/**
 * DuplicateMergeService
 * @description Service class for handling duplicate merge operations
 * 
 * @author Richard Hudson
 * @date April 2025
 */
public with sharing class DuplicateMergeService {

    /**
     * Get merge conflicts between records
     * @param masterId ID of master record
     * @param duplicateIds IDs of duplicate records
     * @return Map of field name to conflict information
     */
    public static Map<String, Object> getMergeConflicts(Id masterId, List<Id> duplicateIds) {
        Map<String, Object> result = new Map<String, Object>();

        try {
            // Determine object type from ID
            Schema.SObjectType objectType = masterId.getSObjectType();
            String objectName = objectType.getDescribe().getName();

            // Get all record IDs
            List<Id> allIds = new List<Id>{masterId};
            allIds.addAll(duplicateIds);

            // Get fields to query
            List<String> fields = getFieldsForObject(objectType);

            // Query records
            String query = 'SELECT ' + String.join(fields, ', ') +
                          ' FROM ' + objectName +
                          ' WHERE Id IN :allIds';

            List<SObject> records = Database.query(query);

            // Create maps for easier access
            Map<Id, SObject> recordsById = new Map<Id, SObject>();
            for (SObject record : records) {
                recordsById.put(record.Id, record);
            }

            // Get master record
            SObject master = recordsById.get(masterId);
            if (master == null) {
                throw new DuplicateException('Master record not found');
            }

            // Build record information
            Map<String, Object> recordInfo = new Map<String, Object>();
            recordInfo.put('master', buildRecordInfo(master));

            List<Map<String, Object>> duplicateInfo = new List<Map<String, Object>>();
            for (Id dupId : duplicateIds) {
                SObject dup = recordsById.get(dupId);
                if (dup != null) {
                    duplicateInfo.add(buildRecordInfo(dup));
                }
            }
            recordInfo.put('duplicates', duplicateInfo);

            // Identify conflicts
            Map<String, Object> conflicts = findConflicts(master, duplicateIds, recordsById);

            // Build result
            result.put('objectName', objectName);
            result.put('records', recordInfo);
            result.put('conflicts', conflicts);
            result.put('mergeOptions', getMergeOptions(objectName));

        } catch (Exception e) {
            handleError(result, 'Error getting merge conflicts', e);
        }

        return result;
    }

    /**
     * Merges specific duplicate records based on user selection
     *
     * @param masterRecordId ID of the record to use as master
     * @param duplicateRecordIds List of duplicate record IDs to merge
     * @param objectApiName API name of the object
     * @return Map containing the result of the merge operation
     */
    public Map<String, Object> mergeRecords(Id masterRecordId, List<String> duplicateRecordIds, String objectApiName) {
        validateInputs(masterRecordId, duplicateRecordIds, objectApiName);

        List<Id> validDuplicateIds = validateAndConvertIds(duplicateRecordIds);

        SObject masterRecord = getMasterRecord(masterRecordId, objectApiName);
        List<SObject> duplicateRecords = getDuplicateRecords(validDuplicateIds, objectApiName);

        // Create a duplicate group for merging
        DuplicateGroup dupGroup = createDuplicateGroup(masterRecord, duplicateRecords, masterRecordId);

        // Perform the merge
        Map<String, Object> result = executeMerge(dupGroup);
        result.put('masterRecordId', masterRecordId);

        // Save the statistics
        try {
            saveMergeStatistics(objectApiName, dupGroup);
        } catch (Exception e) {
            // Don't fail the operation if stats can't be saved
            System.debug('Error saving statistics for manual merge: ' + e.getMessage());
        }

        return result;
    }
    
    /**
     * Merges records with the specified object name, master ID and duplicate IDs
     * This method is needed by DuplicateRecordBatch
     * 
     * @param objectApiName API name of the object
     * @param masterId ID of the master record
     * @param duplicateIds List of duplicate record IDs
     */
    public void mergeRecords(String objectApiName, Id masterId, List<Id> duplicateIds) {
        try {
            // Convert List<Id> to List<String>
            List<String> stringIds = new List<String>();
            for (Id dupId : duplicateIds) {
                stringIds.add(dupId);
            }
            
            // Call the main merge method
            Map<String, Object> result = mergeRecords(masterId, stringIds, objectApiName);
            
            // Log results
            System.debug('Merge complete: ' + result);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in mergeRecords: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, e.getStackTraceString());
            throw e;
        }
    }

    /**
     * Merge duplicate records
     * @param masterId ID of master record
     * @param duplicateIds IDs of duplicate records
     * @param fieldSelections Map of field name to selected record ID for conflicts
     * @return Result of merge operation
     */
    public static Map<String, Object> mergeRecords(
        Id masterId,
        List<Id> duplicateIds,
        Map<String, String> fieldSelections
    ) {
        Map<String, Object> result = new Map<String, Object>();

        try {
            // Determine object type from ID
            Schema.SObjectType objectType = masterId.getSObjectType();
            String objectName = objectType.getDescribe().getName();

            // Get all record IDs
            List<Id> allIds = new List<Id>{masterId};
            allIds.addAll(duplicateIds);

            // Get fields to query
            List<String> fields = getFieldsForObject(objectType);

            // Query records
            String query = 'SELECT ' + String.join(fields, ', ') +
                          ' FROM ' + objectName +
                          ' WHERE Id IN :allIds';

            List<SObject> records = Database.query(query);

            // Create maps for easier access
            Map<Id, SObject> recordsById = new Map<Id, SObject>();
            for (SObject record : records) {
                recordsById.put(record.Id, record);
            }

            // Get master record
            SObject master = recordsById.get(masterId);
            if (master == null) {
                throw new DuplicateException('Master record not found');
            }

            // Apply field selections
            if (fieldSelections != null && !fieldSelections.isEmpty()) {
                applyFieldSelections(master, fieldSelections, recordsById);
            }

            // Create merge log for detailed field changes
            Map<String, List<Object>> conflicts = captureFieldConflicts(master, duplicateIds, recordsById);

            // Perform merge in batches (max 2 records per merge)
            List<List<Id>> batches = batchIds(duplicateIds, 2);
            Integer mergeCount = 0;

            for (List<Id> batch : batches) {
                try {
                    // Perform merge
                    if (batch.size() == 1) {
                        Database.merge(master, batch[0]);
                    } else if (batch.size() == 2) {
                        Database.merge(master, batch);
                    }

                    mergeCount += batch.size();
                } catch (Exception e) {
                    handleError(result, 'Error merging records: ' + batch, e);
                }
            }

            // Create merge log
            DuplicateServicesUtil.createMergeLog(
                masterId,
                duplicateIds,
                objectName,
                null,
                conflicts,
                result.containsKey('error') ? String.valueOf(result.get('error')) : null
            );

            // Build result
            result.put('success', mergeCount > 0);
            result.put('mergeCount', mergeCount);
            result.put('masterId', masterId);
            result.put('mergedIds', duplicateIds);

        } catch (Exception e) {
            handleError(result, 'Error merging records', e);
        }

        return result;
    }

    /**
     * Validates the input parameters
     */
    private void validateInputs(Id masterRecordId, List<String> duplicateRecordIds, String objectApiName) {
        if (masterRecordId == null) {
            throw new DuplicateException('Master record ID is required');
        }

        if (duplicateRecordIds == null || duplicateRecordIds.isEmpty()) {
            throw new DuplicateException('At least one duplicate record ID is required');
        }

        if (String.isBlank(objectApiName)) {
            throw new DuplicateException('Object API name is required');
        }
    }

    /**
     * Validates and converts the duplicate record IDs
     */
    private List<Id> validateAndConvertIds(List<String> duplicateRecordIds) {
        List<Id> validDuplicateIds = new List<Id>();

        for (String idStr : duplicateRecordIds) {
            if (String.isNotBlank(idStr)) {
                try {
                    Id validId = Id.valueOf(idStr);
                    validDuplicateIds.add(validId);
                } catch (Exception e) {
                    System.debug('Invalid ID format: ' + idStr);
                }
            }
        }

        if (validDuplicateIds.isEmpty()) {
            throw new DuplicateException('No valid duplicate record IDs provided');
        }

        return validDuplicateIds;
    }

    /**
     * Queries for the master record
     */
    private SObject getMasterRecord(Id masterRecordId, String objectApiName) {
        String queryMaster = 'SELECT Id FROM ' + String.escapeSingleQuotes(objectApiName)
            + ' WHERE Id = :masterRecordId LIMIT 1 WITH SECURITY_ENFORCED';
        List<SObject> masterRecords = Database.query(queryMaster);

        if (masterRecords.isEmpty()) {
            throw new DuplicateException('Master record not found');
        }

        return masterRecords[0];
    }

    /**
     * Queries for the duplicate records
     */
    private List<SObject> getDuplicateRecords(List<Id> validDuplicateIds, String objectApiName) {
        String queryDuplicates = 'SELECT Id FROM ' + String.escapeSingleQuotes(objectApiName)
            + ' WHERE Id IN :validDuplicateIds WITH SECURITY_ENFORCED';
        List<SObject> duplicateRecords = Database.query(queryDuplicates);

        if (duplicateRecords.isEmpty()) {
            throw new DuplicateException('No duplicate records found');
        }

        return duplicateRecords;
    }

    /**
     * Creates a duplicate group from master and duplicate records
     */
    private DuplicateGroup createDuplicateGroup(SObject masterRecord, List<SObject> duplicateRecords, Id masterRecordId) {
        List<SObject> allRecords = new List<SObject>();
        allRecords.add(masterRecord);
        allRecords.addAll(duplicateRecords);

        return new DuplicateGroup(
            allRecords,
            100, // match score
            'manual-' + masterRecordId, // group key
            true // exact match
        );
    }

    /**
     * Executes the merge operation
     */
    private Map<String, Object> executeMerge(DuplicateGroup dupGroup) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('success', false);

        DuplicateMergeUtility.MergeResult mergeResult = DuplicateMergeUtility.mergeGroup(dupGroup, 'ManualSelection');

        // Safely handle the merge result
        try {
            Map<String, Object> resultMap = (Map<String, Object>)JSON.deserializeUntyped(
                JSON.serialize(mergeResult)
            );

            if (resultMap.containsKey('success')) {
                result.put('success', (Boolean)resultMap.get('success'));
            }

            if (resultMap.containsKey('recordsMerged')) {
                result.put('recordsMerged', Integer.valueOf(resultMap.get('recordsMerged')));
            } else {
                result.put('recordsMerged', 0);
            }

            if (resultMap.containsKey('errors')) {
                result.put('errors', (List<String>)resultMap.get('errors'));
            }
        } catch (Exception e) {
            System.debug('Error parsing merge result: ' + e.getMessage());
            // Fall back to defaults
        }

        return result;
    }

    /**
     * Saves statistics for the merge operation
     */
    private void saveMergeStatistics(String objectApiName, DuplicateGroup dupGroup) {
        DuplicateJobStatistic__c stats = new DuplicateJobStatistic__c(
            ConfigurationName__c = 'Manual Merge',
            ObjectApiName__c = objectApiName,
            DuplicatesFound__c = 1, // One group
            RecordsProcessed__c = dupGroup.getRecordCount(),
            IsDryRun__c = false,
            Status__c = 'Completed'
        );

        if(!Schema.sObjectType.DuplicateJobStatistic__c.isCreateable()){
            throw new DuplicateException('Access denied for DuplicateJobStatistic__c');
        }
        insert stats;
    }

    /**
     * Apply field selections to master record
     * @param master Master record
     * @param fieldSelections Map of field name to selected record ID
     * @param recordsById Map of records by ID
     */
    private static void applyFieldSelections(
        SObject master,
        Map<String, String> fieldSelections,
        Map<Id, SObject> recordsById
    ) {
        for (String fieldName : fieldSelections.keySet()) {
            String selectedRecordId = fieldSelections.get(fieldName);

            // Skip if selecting master record
            if (selectedRecordId == master.Id) {
                continue;
            }

            // Get selected record
            SObject selectedRecord = recordsById.get(selectedRecordId);
            if (selectedRecord == null) {
                continue;
            }

            // Copy field value from selected record to master
            Object fieldValue = selectedRecord.get(fieldName);
            if (fieldValue != null) {
                master.put(fieldName, fieldValue);
            }
        }

        // Update master record
        update master;
    }

    /**
     * Capture field conflicts between records
     * @param master Master record
     * @param duplicateIds IDs of duplicate records
     * @param recordsById Map of records by ID
     * @return Map of field name to list of conflicting values
     */
    private static Map<String, List<Object>> captureFieldConflicts(
        SObject master,
        List<Id> duplicateIds,
        Map<Id, SObject> recordsById
    ) {
        Map<String, List<Object>> conflicts = new Map<String, List<Object>>();
        Map<String, Object> masterFields = master.getPopulatedFieldsAsMap();

        // Check each duplicate
        for (Id dupId : duplicateIds) {
            SObject duplicate = recordsById.get(dupId);
            if (duplicate == null) continue;

            Map<String, Object> dupFields = duplicate.getPopulatedFieldsAsMap();

            // Check fields
            for (String fieldName : dupFields.keySet()) {
                // Skip system fields and ID fields
                if (isSystemField(fieldName) || fieldName.endsWith('Id')) {
                    continue;
                }

                // Get values
                Object dupValue = dupFields.get(fieldName);
                Object masterValue = masterFields.containsKey(fieldName) ? masterFields.get(fieldName) : null;

                // Record conflict if duplicate has non-null value that differs from master
                if (dupValue != null && !areEqual(dupValue, masterValue)) {
                    if (!conflicts.containsKey(fieldName)) {
                        conflicts.put(fieldName, new List<Object>{masterValue});
                    }

                    conflicts.get(fieldName).add(dupValue);
                }
            }
        }

        return conflicts;
    }

    /**
     * Find conflicts between records
     * @param master Master record
     * @param duplicateIds IDs of duplicate records
     * @param recordsById Map of records by ID
     * @return Map of field name to conflict information
     */
    private static Map<String, Object> findConflicts(
        SObject master,
        List<Id> duplicateIds,
        Map<Id, SObject> recordsById
    ) {
        Map<String, Object> conflicts = new Map<String, Object>();
        Map<String, Object> masterFields = master.getPopulatedFieldsAsMap();

        // Check each duplicate
        for (Id dupId : duplicateIds) {
            SObject duplicate = recordsById.get(dupId);
            if (duplicate == null) continue;

            Map<String, Object> dupFields = duplicate.getPopulatedFieldsAsMap();

            // Check fields
            for (String fieldName : dupFields.keySet()) {
                // Skip system fields and ID fields
                if (isSystemField(fieldName) || fieldName.endsWith('Id')) {
                    continue;
                }

                // Get values
                Object dupValue = dupFields.get(fieldName);
                Object masterValue = masterFields.containsKey(fieldName) ? masterFields.get(fieldName) : null;

                // Record conflict if duplicate has non-null value that differs from master
                if (dupValue != null && !areEqual(dupValue, masterValue)) {
                    if (!conflicts.containsKey(fieldName)) {
                        Map<String, Object> conflict = new Map<String, Object>{
                            'fieldName' => fieldName,
                            'values' => new Map<String, Object>()
                        };

                        conflicts.put(fieldName, conflict);
                    }

                    Map<String, Object> conflict = (Map<String, Object>)conflicts.get(fieldName);
                    Map<String, Object> values = (Map<String, Object>)conflict.get('values');

                    // Add master value if not already added
                    if (!values.containsKey(master.Id)) {
                        values.put(master.Id, new Map<String, Object>{
                            'value' => masterValue,
                            'isMaster' => true
                        });
                    }

                    // Add duplicate value
                    values.put(dupId, new Map<String, Object>{
                        'value' => dupValue,
                        'isMaster' => false
                    });
                }
            }
        }

        return conflicts;
    }

    /**
     * Build record information
     * @param record SObject record
     * @return Map of record information
     */
    private static Map<String, Object> buildRecordInfo(SObject record) {
        Map<String, Object> info = new Map<String, Object>{
            'id' => record.Id,
            'fields' => record.getPopulatedFieldsAsMap()
        };

        // Add created/modified date info if available
        if (record.get('CreatedDate') != null) {
            info.put('createdDate', record.get('CreatedDate'));
        }

        if (record.get('LastModifiedDate') != null) {
            info.put('lastModifiedDate', record.get('LastModifiedDate'));
        }

        return info;
    }

    /**
     * Get fields to query for an object
     * @param objectType SObject type
     * @return List of field names
     */
    private static List<String> getFieldsForObject(Schema.SObjectType objectType) {
        List<String> fields = new List<String>{'Id'};

        // Get field map
        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();

        // Add queryable fields
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult describe = fieldMap.get(fieldName).getDescribe();

            if (describe.isAccessible() && !isSystemField(fieldName)) {
                fields.add(fieldName);
            }
        }

        return fields;
    }

    /**
     * Get merge options for an object
     * @param objectName API name of the object
     * @return Map of merge options
     */
    private static Map<String, Object> getMergeOptions(String objectName) {
        Map<String, Object> options = new Map<String, Object>{
            'strategies' => new List<Map<String, Object>>{
                new Map<String, Object>{'value' => 'mostRecent', 'label' => 'Most Recently Modified'},
                new Map<String, Object>{'value' => 'oldest', 'label' => 'Oldest Record'},
                new Map<String, Object>{'value' => 'mostComplete', 'label' => 'Most Complete Record'}
            }
        };

        return options;
    }

    /**
     * Split a list of IDs into batches
     * @param ids List of IDs
     * @param batchSize Size of each batch
     * @return List of batches
     */
    private static List<List<Id>> batchIds(List<Id> ids, Integer batchSize) {
        List<List<Id>> batches = new List<List<Id>>();

        if (ids == null || ids.isEmpty()) {
            return batches;
        }

        Integer size = batchSize > 0 ? batchSize : 2;

        for (Integer i = 0; i < ids.size(); i += size) {
            List<Id> batch = new List<Id>();

            for (Integer j = i; j < i + size && j < ids.size(); j++) {
                batch.add(ids[j]);
            }

            batches.add(batch);
        }

        return batches;
    }

    /**
     * Check if two values are equal
     * @param a First value
     * @param b Second value
     * @return Whether they're equal
     */
    private static Boolean areEqual(Object a, Object b) {
        if (a == null && b == null) return true;
        if (a == null || b == null) return false;
        return String.valueOf(a).equals(String.valueOf(b));
    }

    /**
     * Check if a field is a system field
     * @param fieldName Field name
     * @return Whether it's a system field
     */
    private static Boolean isSystemField(String fieldName) {
        return (fieldName == 'Id' || fieldName == 'IsDeleted' ||
               fieldName == 'CreatedDate' || fieldName == 'CreatedById' ||
               fieldName == 'LastModifiedDate' || fieldName == 'LastModifiedById' ||
               fieldName == 'SystemModstamp');
    }

    /**
     * Handle error in service method
     * @param result Result map to update
     * @param message Error message
     * @param e Exception
     */
    private static void handleError(Map<String, Object> result, String message, Exception e) {
        String errorMsg = message + ': ' + e.getMessage();
        System.debug(LoggingLevel.ERROR, errorMsg);
        System.debug(LoggingLevel.ERROR, e.getStackTraceString());

        result.put('success', false);
        result.put('error', errorMsg);
    }
}