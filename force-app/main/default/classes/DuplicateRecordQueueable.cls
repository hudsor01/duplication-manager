/**
 * Queueable implementation for processing duplicate records
 * Replaces batch implementation with better governor limit handling
 * 
 * @author Richard Hudson
 * @since April 2025
 */
public class DuplicateRecordQueueable implements Queueable, Database.Stateful {
    
    // State variables for processing
    private String configId;
    private String objectApiName;
    private Boolean isDryRun;
    private Integer batchSize;
    private String lastProcessedId;
    private Map<String, Object> configSettings;
    private String jobId;
    
    // Tracking metrics
    private Integer totalRecordsProcessed = 0;
    private Integer totalDuplicatesFound = 0;
    private Integer totalRecordsMerged = 0;
    private Long startTime;
    private List<String> errors = new List<String>();
    
    /**
     * Constructor for initial execution
     * @param configId Configuration ID to use
     * @param isDryRun Whether to perform a dry run (no merge)
     */
    public DuplicateRecordQueueable(String configId, Boolean isDryRun) {
        this.configId = configId;
        this.isDryRun = isDryRun;
        this.startTime = System.now().getTime();
        this.lastProcessedId = null;
        
        // Load configuration settings
        loadConfigSettings();
    }
    
    /**
     * Constructor for continuing processing
     * @param configId Configuration ID
     * @param isDryRun Whether this is a dry run
     * @param lastProcessedId Last processed record ID
     * @param metrics Processing metrics from previous execution
     */
    private DuplicateRecordQueueable(String configId, Boolean isDryRun, String lastProcessedId, 
                                   Map<String, Object> metrics, String jobId) {
        this.configId = configId;
        this.isDryRun = isDryRun;
        this.lastProcessedId = lastProcessedId;
        this.jobId = jobId;
        
        // Load metrics from previous execution
        if (metrics != null) {
            this.totalRecordsProcessed = (Integer)metrics.get('totalProcessed');
            this.totalDuplicatesFound = (Integer)metrics.get('totalDuplicates');
            this.totalRecordsMerged = (Integer)metrics.get('totalMerged');
            this.startTime = (Long)metrics.get('startTime');
            
            if (metrics.containsKey('errors')) {
                this.errors = (List<String>)metrics.get('errors');
            }
        }
        
        // Load configuration settings
        loadConfigSettings();
    }
    
    /**
     * Load configuration settings from metadata
     */
    private void loadConfigSettings() {
        try {
            // Try to load from custom metadata
            List<DuplicateFinderSetting__mdt> settings = [
                SELECT DeveloperName, SObject_API_Name__c, BatchSize__c, MatchFields__c, MasterRecordStrategy__c
                FROM DuplicateFinderSetting__mdt
                WHERE DeveloperName = :configId AND IsActive__c = true
                LIMIT 1
            ];
            
            if (!settings.isEmpty()) {
                DuplicateFinderSetting__mdt setting = settings[0];
                this.objectApiName = setting.SObject_API_Name__c;
                this.batchSize = Integer.valueOf(setting.BatchSize__c);
                
                // Parse match fields from comma-separated list
                List<String> fieldNames = setting.MatchFields__c.split(',');
                List<Map<String, Object>> matchFields = new List<Map<String, Object>>();
                
                for (String fieldName : fieldNames) {
                    matchFields.add(new Map<String, Object>{
                        'field' => fieldName.trim(),
                        'required' => false,
                        'matchType' => 'exact'
                    });
                }
                
                // Create config settings
                this.configSettings = new Map<String, Object>{
                    'matchFields' => matchFields,
                    'masterRecordStrategy' => setting.MasterRecordStrategy__c
                };
            } else {
                // Use defaults if configuration not found
                this.objectApiName = 'Account';
                this.batchSize = 200;
                this.configSettings = new Map<String, Object>{
                    'matchFields' => new List<Map<String, Object>>{
                        new Map<String, Object>{
                            'field' => 'Name',
                            'required' => true,
                            'matchType' => 'exact'
                        }
                    },
                    'masterRecordStrategy' => 'MostRecent'
                };
            }
        } catch (Exception e) {
            logError('Error loading configuration: ' + e.getMessage());
            throw e;
        }
    }
    
    /**
     * Queueable execute method
     * @param context QueueableContext
     */
    public void execute(QueueableContext context) {
        try {
            // If this is first execution, set job ID and create initial stats
            if (this.jobId == null) {
                this.jobId = context.getJobId();
                insertJobStatistics(this.jobId, 'Running');
            }
            
            // Process a batch of records
            processBatch();
            
        } catch (Exception e) {
            String errorMsg = 'Error in queueable execution: ' + e.getMessage();
            logError(errorMsg);
            System.debug(LoggingLevel.ERROR, errorMsg);
            
            // Update job statistics with error
            updateJobStatistics(this.jobId, 'Failed', null);
        }
    }
    
    /**
     * Process a batch of records
     */
    private void processBatch() {
        // Build query for this batch
        String query = buildQuery();
        
        // Query records
        List<SObject> records = Database.query(query);
        
        if (!records.isEmpty()) {
            try {
                // Find duplicates
                Map<String, List<SObject>> duplicateGroups = findDuplicates(records);
                
                // Process duplicate groups
                Integer batchDuplicatesFound = 0;
                Integer batchRecordsMerged = 0;
                
                for (String key : duplicateGroups.keySet()) {
                    List<SObject> dupGroup = duplicateGroups.get(key);
                    if (dupGroup.size() > 1) {
                        batchDuplicatesFound += dupGroup.size() - 1;
                        
                        // Merge duplicates if not dry run
                        if (!isDryRun) {
                            try {
                                Integer mergeCount = mergeDuplicateGroup(dupGroup);
                                batchRecordsMerged += mergeCount;
                            } catch (Exception e) {
                                logError('Error merging group: ' + e.getMessage());
                            }
                        }
                    }
                }
                
                // Update metrics
                totalRecordsProcessed += records.size();
                totalDuplicatesFound += batchDuplicatesFound;
                totalRecordsMerged += batchRecordsMerged;
                
                // Track last processed ID for continuation
                SObject lastRecord = records[records.size() - 1];
                lastProcessedId = (Id)lastRecord.get('Id');
                
                // Update job statistics
                updateJobStatistics(jobId, 'Running', null);
                
                // Check if more processing needed
                if (shouldContinueProcessing() && records.size() == batchSize) {
                    // Create continuation metrics
                    Map<String, Object> metrics = new Map<String, Object>{
                        'totalProcessed' => totalRecordsProcessed,
                        'totalDuplicates' => totalDuplicatesFound,
                        'totalMerged' => totalRecordsMerged,
                        'startTime' => startTime,
                        'errors' => errors
                    };
                    
                    // Chain to next execution with state
                    DuplicateRecordQueueable continuation = new DuplicateRecordQueueable(
                        configId, isDryRun, lastProcessedId, metrics, jobId
                    );
                    
                    // Enqueue next batch
                    if (!Test.isRunningTest()) {
                        System.enqueueJob(continuation);
                    }
                } else {
                    // Complete processing
                    Long endTime = System.now().getTime();
                    Long processingTimeMs = endTime - startTime;
                    updateJobStatistics(jobId, 'Completed', processingTimeMs);
                }
            } catch (Exception e) {
                String errorMsg = 'Error processing batch: ' + e.getMessage();
                logError(errorMsg);
                System.debug(LoggingLevel.ERROR, errorMsg);
                
                // Update job statistics with error
                updateJobStatistics(jobId, 'Failed', null);
            }
        } else {
            // No records found, complete processing
            Long endTime = System.now().getTime();
            Long processingTimeMs = endTime - startTime;
            updateJobStatistics(jobId, 'Completed', processingTimeMs);
        }
    }
    
    /**
     * Build query for next batch
     * @return Query string
     */
    private String buildQuery() {
        // Get all fields needed for matching and merging
        Set<String> fields = new Set<String>{'Id', 'Name', 'CreatedDate'};
        
        // Add match fields from configuration
        if (configSettings.containsKey('matchFields')) {
            Object fieldsObj = configSettings.get('matchFields');
            
            if (fieldsObj instanceof List<Object>) {
                for (Object fieldObj : (List<Object>)fieldsObj) {
                    if (fieldObj instanceof Map<String, Object>) {
                        String fieldName = (String)((Map<String, Object>)fieldObj).get('field');
                        if (String.isNotBlank(fieldName)) {
                            fields.add(fieldName);
                        }
                    }
                }
            }
        }
        
        // Build the query
        String query = 'SELECT ' + String.join(new List<String>(fields), ', ') +
                      ' FROM ' + objectApiName;
        
        // Add filter for continuation if we have a last processed ID
        if (String.isNotBlank(lastProcessedId)) {
            query += ' WHERE Id > \'' + lastProcessedId + '\'';
        }
        
        // Add order and limit
        query += ' ORDER BY Id ASC LIMIT ' + batchSize;
        
        return query;
    }
    
    /**
     * Find duplicates within a batch of records
     * @param records Records to check for duplicates
     * @return Map of duplicate key to list of duplicate records
     */
    private Map<String, List<SObject>> findDuplicates(List<SObject> records) {
        Map<String, List<SObject>> duplicatesMap = new Map<String, List<SObject>>();
        
        // Get match fields from configuration
        List<Object> matchFields = configSettings.containsKey('matchFields') ?
            (List<Object>)configSettings.get('matchFields') : new List<Object>();
        
        // Group records by match key
        for (SObject record : records) {
            String key = buildMatchKey(record, matchFields);
            if (String.isBlank(key)) continue;
            
            if (!duplicatesMap.containsKey(key)) {
                duplicatesMap.put(key, new List<SObject>());
            }
            duplicatesMap.get(key).add(record);
        }
        
        // Filter to only groups with duplicates
        Map<String, List<SObject>> result = new Map<String, List<SObject>>();
        for (String key : duplicatesMap.keySet()) {
            if (duplicatesMap.get(key).size() > 1) {
                result.put(key, duplicatesMap.get(key));
            }
        }
        
        return result;
    }
    
    /**
     * Build a match key for a record
     * @param record Record to build key for
     * @param matchFields Match field configurations
     * @return Match key string
     */
    private String buildMatchKey(SObject record, List<Object> matchFields) {
        List<String> keyParts = new List<String>();
        
        // Default to Name field if no match fields specified
        if (matchFields.isEmpty()) {
            String name = (String)record.get('Name');
            if (String.isBlank(name)) return '';
            
            return name.trim().toLowerCase();
        }
        
        // Process each match field
        for (Object fieldObj : matchFields) {
            Map<String, Object> fieldMap = (Map<String, Object>)fieldObj;
            String fieldName = (String)fieldMap.get('field');
            Boolean isRequired = fieldMap.containsKey('required') ? (Boolean)fieldMap.get('required') : false;
            String matchType = fieldMap.containsKey('matchType') ? (String)fieldMap.get('matchType') : 'exact';
            
            // Get field value
            Object fieldValue = record.get(fieldName);
            if (fieldValue == null) {
                if (isRequired) {
                    // If a required field is null, this record can't be a duplicate
                    return '';
                } else {
                    // For non-required fields, use a placeholder
                    keyParts.add('__NULL__');
                    continue;
                }
            }
            
            // Process field value based on match type
            String keyPart;
            if (fieldValue instanceof String) {
                String strValue = (String)fieldValue;
                
                if (matchType == 'phonetic') {
                    // Phonetic matching (basic implementation)
                    keyPart = getPhoneticRepresentation(strValue);
                } else if (matchType == 'fuzzy') {
                    // Fuzzy matching (simplified)
                    keyPart = strValue.trim().toLowerCase().replaceAll('[^a-z0-9]', '');
                } else {
                    // Exact matching (default)
                    keyPart = strValue.trim().toLowerCase();
                }
            } else {
                // For non-string fields, use string representation
                keyPart = String.valueOf(fieldValue);
            }
            
            keyParts.add(keyPart);
        }
        
        return String.join(keyParts, '|');
    }
    
    /**
     * Get phonetic representation of a string (simplified)
     * @param input String to convert
     * @return Phonetic representation
     */
    private String getPhoneticRepresentation(String input) {
        if (String.isBlank(input)) return '';
        
        // Very basic phonetic algorithm
        String normalized = input.trim().toLowerCase().replaceAll('[^a-z]', '');
        if (normalized.length() <= 2) return normalized;
        
        String result = normalized.substring(0, 1);
        result += normalized.substring(1).replaceAll('[aeiou]', '');
        
        return result;
    }
    
    /**
     * Merge a group of duplicate records
     * @param duplicates Group of duplicate records
     * @return Number of records merged
     */
    private Integer mergeDuplicateGroup(List<SObject> duplicates) {
        if (duplicates.size() < 2) return 0;
        
        // Select master record
        SObject master = selectMasterRecord(duplicates);
        
        // Get records to merge
        List<SObject> dupes = new List<SObject>();
        for (SObject rec : duplicates) {
            if (rec.Id != master.Id) {
                dupes.add(rec);
            }
        }
        
        if (dupes.isEmpty()) return 0;
        
        // Capture field conflicts
        Map<String, List<Object>> conflicts = captureFieldConflicts(master, dupes);
        
        try {
            // Get record IDs for merge
            List<Id> dupeIds = new List<Id>();
            for (SObject dupe : dupes) {
                dupeIds.add(dupe.Id);
            }
            
            // Perform merge
            Database.merge(master, dupeIds, false);
            
            // Log merge operation
            logMergeOperation(master, dupeIds, conflicts, null);
            
            return dupes.size();
        } catch (Exception e) {
            logError('Error merging records: ' + e.getMessage());
            
            // Log failed merge
            List<Id> dupeIds = new List<Id>();
            for (SObject dupe : dupes) {
                dupeIds.add(dupe.Id);
            }
            logMergeOperation(master, dupeIds, conflicts, e.getMessage());
            
            return 0;
        }
    }
    
    /**
     * Select the master record from a group of duplicates
     * @param duplicates Group of duplicate records
     * @return Selected master record
     */
    private SObject selectMasterRecord(List<SObject> duplicates) {
        // Get strategy from configuration
        String strategy = 'MostRecent';
        if (configSettings.containsKey('masterRecordStrategy')) {
            strategy = (String)configSettings.get('masterRecordStrategy');
        }
        
        // Default to first record
        SObject masterRecord = duplicates[0];
        
        // Apply the selection strategy
        if (strategy == 'MostComplete') {
            // Select record with most non-null fields
            Integer maxNonNullFields = -1;
            
            for (SObject rec : duplicates) {
                Integer nonNullCount = 0;
                Map<String, Object> fields = rec.getPopulatedFieldsAsMap();
                
                for (String field : fields.keySet()) {
                    if (fields.get(field) != null) {
                        nonNullCount++;
                    }
                }
                
                if (nonNullCount > maxNonNullFields) {
                    maxNonNullFields = nonNullCount;
                    masterRecord = rec;
                }
            }
        } else if (strategy == 'Oldest' || strategy == 'OldestCreated') {
            // Select oldest record by CreatedDate
            Datetime oldestDate = Datetime.now();
            
            for (SObject rec : duplicates) {
                Datetime createdDate = (Datetime)rec.get('CreatedDate');
                if (createdDate != null && createdDate < oldestDate) {
                    oldestDate = createdDate;
                    masterRecord = rec;
                }
            }
        } else if (strategy == 'MostRecent') {
            // Select most recent record by CreatedDate
            Datetime newestDate = Datetime.valueOf('1900-01-01 00:00:00');
            
            for (SObject rec : duplicates) {
                Datetime createdDate = (Datetime)rec.get('CreatedDate');
                if (createdDate != null && createdDate > newestDate) {
                    newestDate = createdDate;
                    masterRecord = rec;
                }
            }
        }
        
        return masterRecord;
    }
    
    /**
     * Capture field conflicts between master and duplicate records
     * @param master Master record
     * @param duplicates Duplicate records
     * @return Map of conflicting fields to values
     */
    private Map<String, List<Object>> captureFieldConflicts(SObject master, List<SObject> duplicates) {
        Map<String, List<Object>> conflicts = new Map<String, List<Object>>();
        Map<String, Object> masterFields = master.getPopulatedFieldsAsMap();
        
        for (SObject rec : duplicates) {
            Map<String, Object> fields = rec.getPopulatedFieldsAsMap();
            
            for (String field : fields.keySet()) {
                // Skip Id field and null values
                if (field == 'Id' || fields.get(field) == null) continue;
                
                // Check if master has a different non-null value
                if (masterFields.containsKey(field) &&
                    masterFields.get(field) != null &&
                    fields.get(field) != masterFields.get(field)) {
                    
                    if (!conflicts.containsKey(field)) {
                        conflicts.put(field, new List<Object>{masterFields.get(field)});
                    }
                    
                    conflicts.get(field).add(fields.get(field));
                }
            }
        }
        
        return conflicts;
    }
    
    /**
     * Log a merge operation
     * @param master Master record
     * @param dupeIds IDs of merged records
     * @param conflicts Field conflicts
     * @param errorMessage Error message if failed
     */
    private void logMergeOperation(SObject master, List<Id> dupeIds, 
                                  Map<String, List<Object>> conflicts, String errorMessage) {
        try {
            // Create merge log record
            DuplicateMergeLog__c log = new DuplicateMergeLog__c(
                MasterId__c = master.Id,
                MergedIds__c = JSON.serialize(dupeIds),
                ObjectApiName__c = objectApiName,
                MergeTime__c = System.now(),
                JobId__c = this.jobId,
                UserId__c = UserInfo.getUserId(),
                // MatchScore__c field doesn't exist
                FieldMergeDetails__c = conflicts != null ? JSON.serialize(conflicts) : null,
                ErrorMessages__c = errorMessage // Use ErrorMessages__c instead
            );
            
            insert log;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error creating merge log: ' + e.getMessage());
        }
    }
    
    /**
     * Insert initial job statistics record
     * @param jobId Job ID
     * @param status Initial status
     */
    private void insertJobStatistics(String jobId, String status) {
        try {
            // Create job statistics record
            DuplicateJobStatistic__c stats = new DuplicateJobStatistic__c(
                BatchJobId__c = jobId,
                ConfigurationName__c = configId,
                ObjectApiName__c = objectApiName,
                DuplicatesFound__c = 0,
                RecordsMerged__c = 0,
                RecordsProcessed__c = 0,
                IsDryRun__c = isDryRun,
                Status__c = status, // Status field
                JobStartTime__c = System.now()
            );
            
            insert stats;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error creating job statistics: ' + e.getMessage());
        }
    }
    
    /**
     * Update job statistics record
     * @param jobId Job ID
     * @param status Updated status
     * @param processingTimeMs Processing time in ms
     */
    private void updateJobStatistics(String jobId, String status, Long processingTimeMs) {
        try {
            // Find existing job statistics record
            List<DuplicateJobStatistic__c> statsList = [
                SELECT Id, DuplicatesFound__c, RecordsMerged__c, RecordsProcessed__c
                FROM DuplicateJobStatistic__c
                WHERE BatchJobId__c = :jobId
                LIMIT 1
            ];
            
            if (!statsList.isEmpty()) {
                DuplicateJobStatistic__c stats = statsList[0];
                
                // Update fields
                stats.Status__c = status; // Status field
                stats.DuplicatesFound__c = totalDuplicatesFound;
                stats.RecordsMerged__c = totalRecordsMerged;
                stats.RecordsProcessed__c = totalRecordsProcessed;
                
                if (status == 'Completed' || status == 'Failed') {
                    stats.JobCompletionTime__c = System.now();
                    stats.ProcessingTimeMs__c = processingTimeMs;
                    stats.ErrorMessages__c = errors.isEmpty() ? null : String.join(errors, '\n');
                }
                
                update stats;
            } else {
                // Create new record if not found
                DuplicateJobStatistic__c stats = new DuplicateJobStatistic__c(
                    BatchJobId__c = jobId,
                    ConfigurationName__c = configId,
                    ObjectApiName__c = objectApiName,
                    DuplicatesFound__c = totalDuplicatesFound,
                    RecordsMerged__c = totalRecordsMerged,
                    RecordsProcessed__c = totalRecordsProcessed,
                    IsDryRun__c = isDryRun,
                    Status__c = status, // Status field
                    JobCompletionTime__c = status == 'Completed' || status == 'Failed' ? System.now() : null,
                    ProcessingTimeMs__c = processingTimeMs,
                    ErrorMessages__c = errors.isEmpty() ? null : String.join(errors, '\n')
                );
                
                insert stats;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error updating job statistics: ' + e.getMessage());
        }
    }
    
    /**
     * Log an error message
     * @param message Error message
     */
    private void logError(String message) {
        errors.add(message);
        System.debug(LoggingLevel.ERROR, message);
    }
    
    /**
     * Check if we should continue processing
     * @return True if processing should continue
     */
    private Boolean shouldContinueProcessing() {
        // Check for governor limits
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return false;
        }
        
        // If we're approaching DML or query limits, stop and continue in next execution
        if (Limits.getDMLStatements() > Limits.getLimitDMLStatements() * 0.7 ||
            Limits.getQueries() > Limits.getLimitQueries() * 0.7) {
            return false;
        }
        
        return true;
    }
}