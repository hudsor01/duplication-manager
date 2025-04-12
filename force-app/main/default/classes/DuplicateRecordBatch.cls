/**
 * Batch Apex class for identifying and merging duplicate records
 * Implements stateful pattern to maintain state between batch executions
 * Handles governor limits and implements chained processing
 *
 * @author Richard Hudson
 * @since April 2025
 */
global class DuplicateRecordBatch implements Database.Batchable<SObject>, Database.Stateful {

    // State variables to track across batch execution
    private String objectApiName;
    private String configId;
    private String queryString;
    private Boolean isDryRun;
    private Integer batchSize;
    private Integer totalRecordsProcessed = 0;
    private Integer totalDuplicatesFound = 0;
    private Integer totalRecordsMerged = 0;
    private Long startTime;
    private Map<String, Object> configSettings;
    private List<String> errors = new List<String>();
    private String jobId;

    /**
     * Constructor for batch job
     * @param configId Configuration ID to use for duplicate detection
     * @param isDryRun Whether to perform a dry run (find only, no merge)
     */
    public DuplicateRecordBatch(String configId, Boolean isDryRun) {
        this.configId = configId;
        this.isDryRun = isDryRun;
        this.startTime = System.now().getTime();
        this.jobId = null;
        this.initializeFromConfig();
    }

    /**
     * Constructor with additional parameters for testing and advanced usage
     * @param objectName Object API name to process
     * @param fieldList List of fields to match
     * @param masterStrategy Master record selection strategy
     * @param batchSz Batch size
     * @param isDryRun Whether to perform a dry run
     */
    public DuplicateRecordBatch(String objectName, List<String> fieldList, String masterStrategy, Integer batchSz, Boolean isDryRun) {
        this.objectApiName = objectName;
        this.isDryRun = isDryRun;
        this.batchSize = (batchSz != null && batchSz > 0) ? batchSz : 200;
        this.startTime = System.now().getTime();
        this.jobId = null;

        // Initialize configuration settings
        this.configSettings = new Map<String, Object>{
            'matchFields' => buildMatchFieldsConfig(fieldList),
            'masterRecordStrategy' => masterStrategy
        };

        // Build query string based on object and fields
        this.buildQueryString();
    }

    /**
     * Initialize batch settings from configuration
     */
    private void initializeFromConfig() {
        try {
            // Replace configuration query with default configuration values
            this.objectApiName = 'Account'; // default object
            this.batchSize = 200; // default batch size
            this.configSettings = new Map<String, Object>{
                'matchFields' => new List<Object>{
                    new Map<String, Object>{ 'field' => 'Name', 'required' => true, 'matchType' => 'exact' }
                },
                'filters' => ''
            };

            // Build query string based on object and fields
            this.buildQueryString();

        } catch (Exception e) {
            errors.add('Error initializing batch: ' + e.getMessage());
            throw e;
        }
    }

    /**
     * Build the query string based on configuration
     */
    private void buildQueryString() {
        // Get all fields needed for matching and merging
        Set<String> fields = new Set<String>{'Id', 'Name'};

        // Add match fields from configuration
        if (configSettings.containsKey('matchFields')) {
            List<Object> matchFields = (List<Object>)configSettings.get('matchFields');
            for (Object fieldObj : matchFields) {
                Map<String, Object> fieldMap = (Map<String, Object>)fieldObj;
                String fieldName = (String)fieldMap.get('field');
                if (String.isNotBlank(fieldName)) {
                    fields.add(fieldName);
                }
            }
        }

        // Build the query
        this.queryString = 'SELECT ' + String.join(new List<String>(fields), ', ') +
                          ' FROM ' + this.objectApiName;

        // Add filters if specified
        if (configSettings.containsKey('filters')) {
            String whereClause = (String)configSettings.get('filters');
            if (String.isNotBlank(whereClause)) {
                this.queryString += ' WHERE ' + whereClause;
            }
        }
    }

    /**
     * Start method - define the query locator for batch processing
     * @param bc BatchableContext
     * @return QueryLocator
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        this.jobId = bc.getJobId();

        // Create job statistics record
        insertJobStatistics(bc.getJobId(), 'Running');

        return Database.getQueryLocator(this.queryString);
    }

    /**
     * Execute method - process each batch of records
     * @param bc BatchableContext
     * @param scope List of records to process
     */
    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        // Check if we're approaching governor limits
        if (Limits.getQueries() > Limits.getLimitQueries() * 0.8 ||
            Limits.getDMLStatements() > Limits.getLimitDMLStatements() * 0.8) {
            pauseExecution(120);
        }

        try {
            // Track records processed
            totalRecordsProcessed += scope.size();

            // Identify duplicates
            Map<String, List<SObject>> duplicates = identifyDuplicates(scope);

            // Process duplicate groups
            for (String key : duplicates.keySet()) {
                List<SObject> dupGroup = duplicates.get(key);
                if (dupGroup.size() > 1) {
                    totalDuplicatesFound += dupGroup.size() - 1;

                    if (!isDryRun) {
                        mergeWithLogging(dupGroup);
                    }
                }
            }

        } catch (Exception e) {
            String errorMsg = 'Error in batch execution: ' + e.getMessage() + ' ' + e.getStackTraceString();
            errors.add(errorMsg);
            System.debug(LoggingLevel.ERROR, errorMsg);
        }
    }

    /**
     * Finish method - called after all batches are processed
     * @param bc BatchableContext
     */
    global void finish(Database.BatchableContext bc) {
        try {
            // Calculate processing time
            Long endTime = System.now().getTime();
            Long processingTimeMs = endTime - startTime;

            // Update job statistics record
            updateJobStatistics(bc.getJobId(), 'Completed', processingTimeMs);

            // Chain to next batch if needed
            Integer remaining = getObjectCount();
            if (remaining > 0 && totalDuplicatesFound > 0 && !isDryRun) {
                // Only chain if we found duplicates and aren't in dry run mode
                Database.executeBatch(new DuplicateRecordBatch(configId, isDryRun), batchSize);
            }

        } catch (Exception e) {
            String errorMsg = 'Error in batch finish: ' + e.getMessage();
            errors.add(errorMsg);
            System.debug(LoggingLevel.ERROR, errorMsg);

            // Update job statistics with error
            updateJobStatistics(bc.getJobId(), 'Failed', null);
        }
    }

    /**
     * Get the count of remaining records in the object
     * @return Count of records
     */
    private Integer getObjectCount() {
        String countQuery = 'SELECT COUNT() FROM ' + objectApiName;

        // Add filters if specified
        if (configSettings.containsKey('filters')) {
            String whereClause = (String)configSettings.get('filters');
            if (String.isNotBlank(whereClause)) {
                countQuery += ' WHERE ' + whereClause;
            }
        }

        return Database.countQuery(countQuery);
    }

    /**
     * Pause execution to avoid hitting governor limits
     * @param seconds Number of seconds to pause
     */
    private void pauseExecution(Integer seconds) {
        Long start = System.now().getTime();
        while(System.now().getTime() < start + seconds*1000){}
    }

    /**
     * Identify duplicate records based on configuration
     * @param records List of records to check for duplicates
     * @return Map of duplicate key to list of duplicate records
     */
    private Map<String, List<SObject>> identifyDuplicates(List<SObject> records) {
        Map<String, List<SObject>> duplicatesMap = new Map<String, List<SObject>>();

        // Get match fields from configuration
        List<Object> matchFields = new List<Object>();
        if (configSettings.containsKey('matchFields')) {
            matchFields = (List<Object>)configSettings.get('matchFields');
        }

        // Default to Name field if no match fields specified
        if (matchFields.isEmpty()) {
            for(SObject rec : records) {
                String name = (String)rec.get('Name');
                if (String.isBlank(name)) continue;

                String key = name.trim().toLowerCase();
                if(!duplicatesMap.containsKey(key)) {
                    duplicatesMap.put(key, new List<SObject>());
                }
                duplicatesMap.get(key).add(rec);
            }
        } else {
            // Use configured match fields
            for(SObject rec : records) {
                String key = buildMatchKey(rec, matchFields);
                if (String.isBlank(key)) continue;

                if(!duplicatesMap.containsKey(key)) {
                    duplicatesMap.put(key, new List<SObject>());
                }
                duplicatesMap.get(key).add(rec);
            }
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
     * Build a match key for a record based on match fields
     * @param record SObject to build key for
     * @param matchFields List of match field configurations
     * @return Match key string
     */
    private String buildMatchKey(SObject record, List<Object> matchFields) {
        List<String> keyParts = new List<String>();

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
                    // Phonetic matching (basic implementation - could be enhanced)
                    keyPart = getPhoneticRepresentation(strValue);
                } else if (matchType == 'fuzzy') {
                    // Fuzzy matching (simplified implementation)
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
     * Get a phonetic representation of a string (simplified)
     * @param input String to convert
     * @return Phonetic representation
     */
    private String getPhoneticRepresentation(String input) {
        if (String.isBlank(input)) return '';

        // Very basic phonetic algorithm (not a true implementation)
        // In a real system, implement a proper algorithm like Soundex or Metaphone
        String normalized = input.trim().toLowerCase().replaceAll('[^a-z]', '');
        if (normalized.length() <= 2) return normalized;

        // Keep first letter and remove vowels except first letter
        String result = normalized.substring(0, 1);
        result += normalized.substring(1).replaceAll('[aeiou]', '');

        return result;
    }

    /**
     * Merge duplicate records with full logging
     * @param duplicates List of duplicate records
     */
    private void mergeWithLogging(List<SObject> duplicates) {
        if (duplicates.size() < 2) return;

        // Select master record based on configuration
        SObject master = selectMasterRecord(duplicates);
        List<SObject> records = new List<SObject>();
        for (SObject rec : duplicates) {
            if (rec.Id != master.Id) {
                records.add(rec);
            }
        }

        if (records.isEmpty()) return;

        // Capture field conflicts for logging
        Map<String, List<Object>> conflicts = captureFieldConflicts(master, records);

        try {
            // Perform merge operation
            Database.merge(master, getRecordIds(records), false);

            // Log successful merge
            logMerge(master, records, conflicts, null);

            // Update count of merged records
            totalRecordsMerged += records.size();

        } catch (Exception e) {
            // Log failed merge
            logMerge(master, records, conflicts, e.getMessage());
        }
    }

    /**
     * Select the master record from a list of duplicates
     * @param duplicates List of duplicate records
     * @return Selected master record
     */
    private SObject selectMasterRecord(List<SObject> duplicates) {
        // Get master record strategy from configuration
        String strategy = 'mostRecent';
        if (configSettings.containsKey('masterRecordStrategy')) {
            strategy = (String)configSettings.get('masterRecordStrategy');
        }

        // Default to first record
        SObject masterRecord = duplicates[0];

        // Apply selection strategy
        if (strategy == 'mostComplete') {
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
        } else if (strategy == 'oldest') {
            // Select oldest record by CreatedDate
            Datetime oldestDate = Datetime.now();

            for (SObject rec : duplicates) {
                Datetime createdDate = (Datetime)rec.get('CreatedDate');
                if (createdDate != null && createdDate < oldestDate) {
                    oldestDate = createdDate;
                    masterRecord = rec;
                }
            }
        } else if (strategy == 'mostRecent') {
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
     * @param duplicates List of duplicate records
     * @return Map of field name to list of conflicting values
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
     * Get a list of record IDs from a list of SObjects
     * @param records List of SObjects
     * @return List of record IDs
     */
    private List<Id> getRecordIds(List<SObject> records) {
        List<Id> ids = new List<Id>();
        for (SObject rec : records) {
            ids.add(rec.Id);
        }
        return ids;
    }

    /**
     * Log a merge operation
     * @param master Master record
     * @param duplicates List of merged duplicate records
     * @param conflicts Map of field conflicts
     * @param errorMessage Error message, if any
     */
    private void logMerge(SObject master, List<SObject> duplicates,
                          Map<String, List<Object>> conflicts, String errorMessage) {
        try {
            // Create merge log record
            DuplicateMergeLog__c log = new DuplicateMergeLog__c(
                MasterId__c = master.Id,
                MergedIds__c = JSON.serialize(getRecordIds(duplicates)),
                ObjectApiName__c = objectApiName,
                MergeTime__c = System.now(),
                JobId__c = this.jobId,
                UserId__c = UserInfo.getUserId(),
                // MatchScore__c seems to be missing from the field definition
                // MatchScore__c = 100, // Default score
                FieldMergeDetails__c = JSON.serialize(conflicts),
                ErrorMessages__c = errorMessage // Use ErrorMessages__c instead of ErrorMessage__c
            );

            insert log;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error creating merge log: ' + e.getMessage());
        }
    }

    /**
     * Insert initial job statistics record
     * @param batchJobId Batch job ID
     * @param status Initial status
     */
    private void insertJobStatistics(String batchJobId, String status) {
        try {
            // Create job statistics record
            DuplicateJobStatistic__c stats = new DuplicateJobStatistic__c(
                BatchJobId__c = batchJobId,
                ConfigurationName__c = String.valueOf(configId),
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
     * Update job statistics record with results
     * @param batchJobId Batch job ID
     * @param status Final status
     * @param processingTimeMs Processing time in milliseconds
     */
    private void updateJobStatistics(String batchJobId, String status, Long processingTimeMs) {
        try {
            // Find existing job statistics record
            List<DuplicateJobStatistic__c> statsList = [
                SELECT Id, DuplicatesFound__c, RecordsMerged__c, RecordsProcessed__c
                FROM DuplicateJobStatistic__c
                WHERE BatchJobId__c = :batchJobId
                LIMIT 1
            ];

            if (!statsList.isEmpty()) {
                DuplicateJobStatistic__c stats = statsList[0];

                // Update with final values
                stats.Status__c = status; // Status field
                stats.DuplicatesFound__c = totalDuplicatesFound;
                stats.RecordsMerged__c = totalRecordsMerged;
                stats.RecordsProcessed__c = totalRecordsProcessed;
                stats.JobCompletionTime__c = System.now();
                stats.ProcessingTimeMs__c = processingTimeMs;
                stats.ErrorMessages__c = errors.isEmpty() ? null : String.join(errors, '\n');

                update stats;
            } else {
                // Create new record if not found
                DuplicateJobStatistic__c stats = new DuplicateJobStatistic__c(
                    BatchJobId__c = batchJobId,
                    ConfigurationName__c = String.valueOf(configId),
                    ObjectApiName__c = objectApiName,
                    DuplicatesFound__c = totalDuplicatesFound,
                    RecordsMerged__c = totalRecordsMerged,
                    RecordsProcessed__c = totalRecordsProcessed,
                    IsDryRun__c = isDryRun,
                    Status__c = status, // Status field
                    JobCompletionTime__c = System.now(),
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
     * Builds match fields configuration from a simple list of field names
     * @param fieldList List of field API names to match on
     * @return List of match field configuration objects
     */
    private List<Object> buildMatchFieldsConfig(List<String> fieldList) {
        List<Object> matchFields = new List<Object>();

        if (fieldList == null || fieldList.isEmpty()) {
            // Default to Name field if no fields provided
            Map<String, Object> defaultField = new Map<String, Object>{
                'field' => 'Name',
                'required' => true,
                'matchType' => 'exact'
            };
            matchFields.add(defaultField);
        } else {
            // Convert each field name to a match field configuration
            for (String fieldName : fieldList) {
                if (String.isNotBlank(fieldName)) {
                    Map<String, Object> fieldConfig = new Map<String, Object>{
                        'field' => fieldName,
                        'required' => false,
                        'matchType' => 'exact'
                    };
                    matchFields.add(fieldConfig);
                }
            }
        }

        return matchFields;
    }

    /**
     * Custom exception class for duplication errors
     */
    public class DuplicationException extends Exception {}
}
