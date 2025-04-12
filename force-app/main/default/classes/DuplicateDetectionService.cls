/**
 * DuplicateDetectionService
 * @description Service class for handling duplicate detection operations
 */
public with sharing class DuplicateDetectionService {
    
    /**
     * Performs a direct duplicate check on a single record
     *
     * @param objectApiName API name of the object to check
     * @param recordId ID of the record to check
     * @param matchFields List of fields to use for matching
     * @return Map containing duplicate information
     */
    public Map<String, Object> checkForDuplicates(String objectApiName, Id recordId, List<String> matchFields) {
        // Validate inputs
        validateInputs(objectApiName, recordId, matchFields);
        
        // Get the source record with match fields
        SObject record = getSourceRecord(objectApiName, recordId, matchFields);
        
        // Find potential duplicate records
        List<SObject> potentialDupes = findPotentialDuplicates(objectApiName, recordId, matchFields, record);
        
        // Score and filter duplicates
        List<Map<String, Object>> duplicates = scoreAndFilterDuplicates(potentialDupes, record, matchFields);
        
        // Build result
        Map<String, Object> result = new Map<String, Object>();
        result.put('duplicatesFound', duplicates.size());
        result.put('duplicates', duplicates);
        
        return result;
    }
    
    /**
     * Gets statistics about duplicates for a record using Name field
     * 
     * @param recordId ID of the record to check for duplicates
     * @return Map containing duplicate statistics
     */
    public Map<String, Object> getDuplicateStatistics(String recordId) {
        if(String.isBlank(recordId)) {
            throw new DuplicationException('Record Id is required');
        }
        
        Id recId = Id.valueOf(recordId);
        String objectName = recId.getSobjectType().getDescribe().getName();

        // Query the record and get name
        SObject record = queryRecordName(recordId, objectName);
        String name = (String) record.get('Name');

        // Count duplicates based on Name field
        Integer dupCount = countDuplicatesByName(objectName, recordId, name);

        // Build result
        Map<String, Object> stats = new Map<String, Object>();
        stats.put('duplicateCount', dupCount);
        stats.put('matchField', 'Name');
        stats.put('originalName', name);
        stats.put('warning', dupCount > 0 ? 'Duplicates found' : 'No duplicates found');
        return stats;
    }
    
    /**
     * Gets duplicate records for a specific record using Name field
     * 
     * @param recordId ID of the record to get duplicates for
     * @return List of duplicate records
     */
    public List<SObject> getDuplicateRecords(String recordId) {
        if(String.isBlank(recordId)) {
            throw new DuplicationException('Record Id is required');
        }
        
        Id recId = Id.valueOf(recordId);
        String objectName = recId.getSobjectType().getDescribe().getName();

        // Query the record and get name
        SObject record = queryRecordName(recordId, objectName);
        String name = (String) record.get('Name');

        // Query duplicate records
        String dupQuery = buildNameDuplicateQuery(objectName, recordId, name);
        return Database.query(dupQuery + ' WITH SECURITY_ENFORCED');
    }
    
    // Private helper methods
    
    /**
     * Validates check for duplicates inputs
     */
    private void validateInputs(String objectApiName, Id recordId, List<String> matchFields) {
        if (String.isBlank(objectApiName) || recordId == null || matchFields == null || matchFields.isEmpty()) {
            throw new DuplicationException('Missing required parameters');
        }
    }
    
    /**
     * Gets the source record with all match fields
     */
    private SObject getSourceRecord(String objectApiName, Id recordId, List<String> matchFields) {
        // Build query to get record with match fields
        String recordQuery = buildSourceRecordQuery(objectApiName, recordId, matchFields);
        
        // Get the record
        List<SObject> records = Database.query(recordQuery);
        if (records.isEmpty()) {
            throw new DuplicationException('Record not found');
        }
        
        return records[0];
    }
    
    /**
     * Builds query to get source record with match fields
     */
    private String buildSourceRecordQuery(String objectApiName, Id recordId, List<String> matchFields) {
        String recordQuery = 'SELECT Id';
        for (String field : matchFields) {
            recordQuery += ', ' + field.trim();
        }
        recordQuery += ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1';
        
        return recordQuery;
    }
    
    /**
     * Finds potential duplicates based on match fields
     */
    private List<SObject> findPotentialDuplicates(String objectApiName, Id recordId, List<String> matchFields, SObject record) {
        // Build query with conditions based on field values
        String potentialDupesQuery = buildPotentialDupesQuery(objectApiName, recordId, matchFields, record);
        System.debug('Duplicate search query: ' + potentialDupesQuery);
        
        // Execute query
        return Database.query(potentialDupesQuery);
    }
    
    /**
     * Builds query for potential duplicates
     */
    private String buildPotentialDupesQuery(String objectApiName, Id recordId, List<String> matchFields, SObject record) {
        String query = 'SELECT Id';
        
        // Add fields
        for (String field : matchFields) {
            query += ', ' + field.trim();
        }
        query += ' FROM ' + objectApiName + ' WHERE Id != :recordId';
        
        // Add field conditions
        List<String> fieldConditions = buildFieldConditions(matchFields, record);
        
        if (!fieldConditions.isEmpty()) {
            query += ' AND (' + String.join(fieldConditions, ' OR ') + ')';
        }
        
        return query;
    }
    
    /**
     * Builds field conditions for potential duplicates query
     */
    private List<String> buildFieldConditions(List<String> matchFields, SObject record) {
        List<String> fieldConditions = new List<String>();
        
        for (String field : matchFields) {
            String fieldName = field.trim();
            Object fieldValue = record.get(fieldName);

            if (fieldValue != null) {
                if (fieldValue instanceof String) {
                    // For strings, use LIKE for partial matching
                    String strValue = (String)fieldValue;
                    if (String.isNotBlank(strValue)) {
                        fieldConditions.add(fieldName + ' LIKE \'%' + String.escapeSingleQuotes(strValue) + '%\'');
                    }
                } else {
                    // For other types, use exact matching
                    fieldConditions.add(fieldName + ' = \'' + fieldValue + '\'');
                }
            }
        }
        
        return fieldConditions;
    }
    
    /**
     * Scores and filters potential duplicates
     */
    private List<Map<String, Object>> scoreAndFilterDuplicates(List<SObject> potentialDupes, SObject record, List<String> matchFields) {
        List<Map<String, Object>> duplicates = new List<Map<String, Object>>();
        
        for (SObject potentialDupe : potentialDupes) {
            Map<String, Object> scoreResult = calculateMatchScore(potentialDupe, record, matchFields);
            Decimal matchScore = (Decimal)scoreResult.get('score');
            
            if (matchScore > 50) {
                Map<String, Object> dupInfo = new Map<String, Object>();
                dupInfo.put('id', potentialDupe.Id);
                dupInfo.put('matchScore', matchScore);
                dupInfo.put('isExactMatch', scoreResult.get('isExactMatch'));
                duplicates.add(dupInfo);
            }
        }
        
        return duplicates;
    }
    
    /**
     * Calculates match score between two records
     */
    private Map<String, Object> calculateMatchScore(SObject dupeRecord, SObject sourceRecord, List<String> matchFields) {
        Decimal matchScore = 0;
        Integer matchCount = 0;
        
        for (String field : matchFields) {
            Object origValue = sourceRecord.get(field);
            Object dupeValue = dupeRecord.get(field);

            if (origValue != null && dupeValue != null) {
                if (origValue == dupeValue) {
                    // Exact match
                    matchScore += 1.0;
                    matchCount++;
                } else if (origValue instanceof String && dupeValue instanceof String) {
                    // Partial string match
                    String origStr = ((String)origValue).toLowerCase();
                    String dupeStr = ((String)dupeValue).toLowerCase();

                    if (origStr.contains(dupeStr) || dupeStr.contains(origStr)) {
                        matchScore += 0.7;
                        matchCount++;
                    }
                }
            }
        }

        // Normalize score based on number of fields
        if (matchFields.size() > 0) {
            matchScore = (matchScore / matchFields.size()) * 100;
        }
        
        Map<String, Object> result = new Map<String, Object>();
        result.put('score', matchScore);
        result.put('isExactMatch', (matchCount == matchFields.size()));
        
        return result;
    }
    
    /**
     * Queries a record to get its Name field
     */
    private SObject queryRecordName(String recordId, String objectName) {
        try {
            SObject record = Database.query('SELECT Name FROM ' + 
                                           String.escapeSingleQuotes(objectName) + 
                                           ' WHERE Id = :recordId LIMIT 1 WITH SECURITY_ENFORCED');
            
            if(record == null) {
                throw new DuplicationException('Record not found for Id: ' + recordId);
            }
            
            return record;
        } catch(Exception e) {
            throw new DuplicationException('Record query failed: ' + e.getMessage());
        }
    }
    
    /**
     * Counts duplicate records based on Name field
     */
    private Integer countDuplicatesByName(String objectName, String recordId, String name) {
        String countQuery = 'SELECT COUNT() FROM ' + 
                           String.escapeSingleQuotes(objectName) + 
                           ' WHERE Name = :name AND Id != :recordId WITH SECURITY_ENFORCED';
        
        return Database.countQuery(countQuery);
    }
    
    /**
     * Builds query to find duplicates by Name field
     */
    private String buildNameDuplicateQuery(String objectName, String recordId, String name) {
        return 'SELECT Id, Name FROM ' + 
               String.escapeSingleQuotes(objectName) + 
               ' WHERE Name = :name AND Id != :recordId';
    }
}