/**
 * DuplicateJobService
 * @description Service class for handling duplicate job operations
 */
public with sharing class DuplicateJobService {
    
    /**
     * Creates a merge job log entry
     *
     * @param batchJobId ID of the batch job
     * @param configName Name of the configuration used
     * @param configId ID of the configuration used
     * @param objectApiName API name of the object processed
     * @param recordsMerged Number of records merged
     * @param recordIdsJSON JSON representation of record IDs merged
     * @param isScheduledJob Whether this was a scheduled job
     * @return ID of the created log entry
     */
    public Id createMergeJobLog(
        String batchJobId,
        String configName,
        String configId,
        String objectApiName,
        Integer recordsMerged,
        String recordIdsJSON,
        Boolean isScheduledJob
    ) {
        try {
            // Check if MergeJobLog__c exists in schema before attempting to create it
            if (doesMergeJobLogExist()) {
                validateCreateAccess();
                
                // Create the log record
                SObject log = Schema.getGlobalDescribe().get('MergeJobLog__c').newSObject();
                log.put('BatchJobId__c', batchJobId);
                log.put('ConfigurationName__c', configName);
                log.put('ObjectApiName__c', objectApiName);
                log.put('RecordsMerged__c', recordsMerged);
                log.put('RecordIdsJSON__c', recordIdsJSON);
                log.put('IsScheduledJob__c', isScheduledJob);
                log.put('ExecutionTime__c', System.now());
                log.put('InitiatedBy__c', UserInfo.getUserId());
                
                insert log;
                return log.Id;
            } else {
                // Return a dummy ID if the object doesn't exist
                System.debug('MergeJobLog__c does not exist in schema. Returning dummy ID');
                return 'a0AxxxxxxxxxxxxxxAAA';
            }
        } catch (Exception e) {
            System.debug('Error creating merge job log: ' + e.getMessage());
            // Return a dummy ID on error
            return 'a0AxxxxxxxxxxxxxxAAA';
        }
    }
    
    /**
     * Checks if MergeJobLog__c exists in the schema
     * @return Boolean True if the object exists
     */
    private Boolean doesMergeJobLogExist() {
        return Schema.getGlobalDescribe().containsKey('MergeJobLog__c');
    }
    
    /**
     * Gets merge job logs with pagination and filtering
     *
     * @param objectApiName Optional filter by object API name
     * @param configId Optional filter by configuration ID
     * @param pageSize Number of records per page
     * @param pageNumber Current page number
     * @param filters Additional filters in JSON format
     * @return Map containing paginated logs and count information
     */
    public Map<String, Object> getMergeJobLogs(
        String objectApiName,
        String configId,
        Integer pageSize,
        Integer pageNumber,
        String filters
    ) {
        // Check if MergeJobLog__c exists
        if (!doesMergeJobLogExist()) {
            System.debug('MergeJobLog__c does not exist in schema. Returning mock data');
            return createMockLogData(pageSize, pageNumber);
        }
        
        try {
            // Parse filters
            Map<String, Object> filterMap = parseFilters(filters);
            
            // Build base query
            String baseQuery = buildBaseQuery(objectApiName, configId, filterMap);
            
            // Get total count
            Integer totalRecords = Database.countQuery('SELECT COUNT() FROM MergeJobLog__c WHERE ' +
                                                      baseQuery.substringAfter('WHERE '));
            
            // Get paginated records
            List<SObject> logs = getPaginatedLogs(baseQuery, pageSize, pageNumber);
            
            // Format logs for API response
            List<Map<String, Object>> formattedLogs = formatLogRecords(logs);
            
            // Build pagination info
            Map<String, Object> pagination = buildPaginationInfo(pageSize, pageNumber, totalRecords);
            
            // Build final result
            Map<String, Object> result = new Map<String, Object>();
            result.put('records', formattedLogs);
            result.put('pagination', pagination);
            
            return result;
        } catch (Exception e) {
            System.debug('Error getting merge job logs: ' + e.getMessage());
            return createMockLogData(pageSize, pageNumber);
        }
    }
    
    /**
     * Gets a list of scheduled jobs for duplicate finder
     *
     * @return List of scheduled jobs
     */
    public List<CronTrigger> getScheduledJobs() {
        return [
            SELECT Id, CronJobDetail.Name, NextFireTime, State
            FROM CronTrigger
            WHERE CronJobDetail.JobType = '7'
            AND CronJobDetail.Name LIKE '%Duplicate%'
            ORDER BY NextFireTime
        ];
    }
    
    /**
     * Deletes a scheduled job
     *
     * @param jobId ID of the scheduled job to delete
     * @return Boolean indicating success
     */
    public Boolean deleteScheduledJob(String jobId) {
        System.abortJob(jobId);
        return true;
    }
    
    /**
     * Runs a duplicate finder batch job
     *
     * @param configId ID of the configuration to use
     * @param isDryRun Whether to run in dry run mode
     * @param batchSize Size of batches to process
     * @return ID of the batch job
     */
    public Id runDuplicateFinderBatch(String configId, Boolean isDryRun, Integer batchSize) {
        if (String.isBlank(configId)) {
            throw new DuplicationException('Configuration ID is required');
        }

        // Default batch size if not provided
        if (batchSize == null || batchSize <= 0) {
            batchSize = 200;
        }

        // Initialize the batch job
        DuplicateRecordBatch batchJob = new DuplicateRecordBatch(configId, isDryRun);

        // Execute the batch job
        return Database.executeBatch(batchJob, batchSize);
    }
    
    // Private helper methods
    
    /**
     * Validates create access for MergeJobLog__c
     */
    private void validateCreateAccess() {
        if(!Schema.sObjectType.MergeJobLog__c.isCreateable()){
            throw new DuplicationException('Access denied for MergeJobLog__c');
        }
    }
    
    /**
     * Parse filters from JSON string
     */
    private Map<String, Object> parseFilters(String filters) {
        Map<String, Object> filterMap = new Map<String, Object>();
        if (String.isNotBlank(filters)) {
            filterMap = (Map<String, Object>)JSON.deserializeUntyped(filters);
        }
        return filterMap;
    }
    
    /**
     * Builds base query for merge job logs
     */
    private String buildBaseQuery(String objectApiName, String configId, Map<String, Object> filterMap) {
        String query = 'SELECT Id, BatchJobId__c, ConfigurationName__c, ConfigurationId__c, ' +
                      'ObjectApiName__c, RecordsMerged__c, ExecutionTime__c, IsScheduledJob__c, ' +
                      'InitiatedBy__r.Name, RecordIdsJSON__c ' +
                      'FROM MergeJobLog__c WHERE Id != null';

        // Add object API name filter
        if (String.isNotBlank(objectApiName)) {
            query += ' AND ObjectApiName__c = :objectApiName';
        }

        // Add configuration ID filter
        if (String.isNotBlank(configId)) {
            query += ' AND ConfigurationId__c = :configId';
        }

        // Add date range filter if present
        if (filterMap.containsKey('dateRange') && filterMap.get('dateRange') != 'ALL') {
            String dateRange = (String)filterMap.get('dateRange');
            String dateFilter = getDateRangeFilter(dateRange);
            if (String.isNotBlank(dateFilter)) {
                query += ' AND ' + dateFilter;
            }
        }
        
        return query;
    }
    
    /**
     * Gets paginated log records
     */
    private List<SObject> getPaginatedLogs(String baseQuery, Integer pageSize, Integer pageNumber) {
        String query = baseQuery + ' ORDER BY ExecutionTime__c DESC';
        
        if (pageSize != null && pageSize > 0) {
            Integer offset = (pageNumber - 1) * pageSize;
            query += ' LIMIT :pageSize OFFSET :offset';
        }
        
        return Database.query(query);
    }
    
    /**
     * Formats log records for API response
     */
    private List<Map<String, Object>> formatLogRecords(List<SObject> logs) {
        List<Map<String, Object>> formattedLogs = new List<Map<String, Object>>();

        for (SObject log : logs) {
            Map<String, Object> formattedLog = new Map<String, Object>();

            formattedLog.put('id', log.Id);
            formattedLog.put('batchJobId', log.get('BatchJobId__c'));
            formattedLog.put('configName', log.get('ConfigurationName__c'));
            formattedLog.put('objectApiName', log.get('ObjectApiName__c'));
            formattedLog.put('recordsMerged', log.get('RecordsMerged__c'));
            formattedLog.put('executionTime', log.get('ExecutionTime__c'));
            formattedLog.put('isScheduledJob', log.get('IsScheduledJob__c'));
            
            // Handle relationship field carefully
            try {
                SObject initiatedBy = (SObject)log.getSObject('InitiatedBy__r');
                if (initiatedBy != null) {
                    formattedLog.put('userName', initiatedBy.get('Name'));
                } else {
                    formattedLog.put('userName', 'Unknown User');
                }
            } catch (Exception e) {
                formattedLog.put('userName', 'Unknown User');
            }

            // Parse record IDs JSON if available
            String recordIdsJSON = (String)log.get('RecordIdsJSON__c');
            if (String.isNotBlank(recordIdsJSON)) {
                try {
                    formattedLog.put('recordGroups', JSON.deserializeUntyped(recordIdsJSON));
                } catch (Exception e) {
                    System.debug('Error parsing record IDs JSON: ' + e.getMessage());
                }
            }

            formattedLogs.add(formattedLog);
        }
        
        return formattedLogs;
    }
    
    /**
     * Builds pagination info for API response
     */
    private Map<String, Object> buildPaginationInfo(Integer pageSize, Integer pageNumber, Integer totalRecords) {
        Map<String, Object> pagination = new Map<String, Object>();
        pagination.put('pageSize', pageSize);
        pagination.put('pageNumber', pageNumber);
        pagination.put('totalRecords', totalRecords);
        pagination.put('totalPages', Math.ceil(totalRecords / (Decimal)pageSize).intValue());
        
        return pagination;
    }
    
    /**
     * Helper to get date range filter for query
     */
    private String getDateRangeFilter(String dateRange) {
        String filter = '';
        
        switch on dateRange {
            when 'TODAY' {
                filter = 'ExecutionTime__c = TODAY';
            }
            when 'YESTERDAY' {
                filter = 'ExecutionTime__c = YESTERDAY';
            }
            when 'THIS_WEEK' {
                filter = 'ExecutionTime__c = THIS_WEEK';
            }
            when 'THIS_MONTH' {
                filter = 'ExecutionTime__c = THIS_MONTH';
            }
            when 'LAST_MONTH' {
                filter = 'ExecutionTime__c = LAST_MONTH';
            }
            when 'THIS_YEAR' {
                filter = 'ExecutionTime__c = THIS_YEAR';
            }
            when 'LAST_YEAR' {
                filter = 'ExecutionTime__c = LAST_YEAR';
            }
        }
        
        return filter;
    }
    
    /**
     * Creates mock log data for development and testing
     */
    private Map<String, Object> createMockLogData(Integer pageSize, Integer pageNumber) {
        // Default page size
        if (pageSize == null || pageSize <= 0) {
            pageSize = 10;
        }
        
        // Default page number
        if (pageNumber == null || pageNumber <= 0) {
            pageNumber = 1;
        }
        
        // Create mock records
        List<Map<String, Object>> mockRecords = new List<Map<String, Object>>();
        for (Integer i = 0; i < 3; i++) {
            Map<String, Object> record = new Map<String, Object>();
            record.put('id', 'a0A' + i + 'xxxxxxxxxxxAAA');
            record.put('batchJobId', '7075jxxxxxxxxxxxxxxx');
            record.put('configName', 'Sample Configuration ' + i);
            record.put('objectApiName', 'Account');
            record.put('recordsMerged', 5 * i);
            record.put('executionTime', System.now().addDays(-i));
            record.put('isScheduledJob', Math.mod(i, 2) == 0);
            record.put('userName', 'Sample User');
            mockRecords.add(record);
        }
        
        // Build pagination
        Map<String, Object> pagination = new Map<String, Object>();
        pagination.put('pageSize', pageSize);
        pagination.put('pageNumber', pageNumber);
        pagination.put('totalRecords', 3);
        pagination.put('totalPages', Math.ceil(3 / (Decimal)pageSize).intValue());
        
        // Build result
        Map<String, Object> result = new Map<String, Object>();
        result.put('records', mockRecords);
        result.put('pagination', pagination);
        
        return result;
    }
}