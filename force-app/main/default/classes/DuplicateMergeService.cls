/**
 * DuplicateMergeService
 * @description Service class for handling duplicate merge operations
 */
public with sharing class DuplicateMergeService {
    
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
     * Validates the input parameters
     */
    private void validateInputs(Id masterRecordId, List<String> duplicateRecordIds, String objectApiName) {
        if (masterRecordId == null) {
            throw new DuplicationException('Master record ID is required');
        }

        if (duplicateRecordIds == null || duplicateRecordIds.isEmpty()) {
            throw new DuplicationException('At least one duplicate record ID is required');
        }

        if (String.isBlank(objectApiName)) {
            throw new DuplicationException('Object API name is required');
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
            throw new DuplicationException('No valid duplicate record IDs provided');
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
            throw new DuplicationException('Master record not found');
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
            throw new DuplicationException('No duplicate records found');
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
            throw new DuplicationException('Access denied for DuplicateJobStatistic__c');
        }
        insert stats;
    }
}