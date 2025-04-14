/**
 * Base batch class for duplicate detection and merging operations
 * Implements common functionality for all duplicate batch processes
 *
 * @author Richard Hudson
 * @date April 2025
 */
global abstract class DuplicateBaseBatch implements Database.Batchable<SObject>, Database.Stateful {
    
    // Configuration properties
    protected String objectApiName;
    protected Boolean isDryRun;
    protected Integer batchSize;
    protected String configurationName;
    
    // Job state tracking
    protected String batchJobId;
    protected Integer recordsProcessed = 0;
    protected Integer duplicatesFound = 0;
    protected Integer recordsMerged = 0;
    protected Long startTime;
    protected List<String> errors = new List<String>();
    
    // Abstract methods to be implemented by subclasses
    global abstract Database.QueryLocator buildQueryLocator();
    global abstract Map<String, List<SObject>> findDuplicates(List<SObject> scope);
    global abstract void processDuplicates(Map<String, List<SObject>> duplicates);
    
    /**
     * Constructor with common parameters
     * 
     * @param objectApiName API name of the object being processed
     * @param isDryRun Whether to perform a dry run (find only, no merge)
     * @param batchSize Batch size to use for processing
     * @param configurationName Name of the configuration being used
     */
    public DuplicateBaseBatch(String objectApiName, Boolean isDryRun, Integer batchSize, String configurationName) {
        this.objectApiName = objectApiName;
        this.isDryRun = isDryRun;
        this.batchSize = (batchSize != null && batchSize > 0) ? batchSize : 200;
        this.configurationName = configurationName;
        this.startTime = System.now().getTime();
    }
    
    /**
     * Simplified constructor with default configuration name
     */
    public DuplicateBaseBatch(String objectApiName, Boolean isDryRun, Integer batchSize) {
        this(objectApiName, isDryRun, batchSize, 'Standard Configuration');
    }
    
    /**
     * Start method - define query locator for batch processing
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        this.batchJobId = bc.getJobId();
        
        // Create initial job statistics record
        createJobStatistics(bc.getJobId(), 'Running');
        
        // Get query locator from subclass implementation
        return buildQueryLocator();
    }
    
    /**
     * Execute method - process each batch of records
     */
    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {
            // Pre-process hook for subclasses
            preProcessBatch(bc, scope);
            
            // Update records processed count
            recordsProcessed += scope.size();
            
            // Find duplicates using subclass implementation
            Map<String, List<SObject>> duplicates = findDuplicates(scope);
            
            // Process duplicates using subclass implementation
            processDuplicates(duplicates);
            
            // Post-process hook for subclasses
            postProcessBatch(bc, scope, duplicates);
            
            // Update job statistics
            updateJobStatistics(bc.getJobId(), 'Running', null);
            
        } catch (Exception e) {
            logError('Error in batch execution', e);
        }
    }
    
    /**
     * Finish method - called after all batches processed
     */
    global void finish(Database.BatchableContext bc) {
        try {
            // Calculate processing time
            Long endTime = System.now().getTime();
            Long processingTimeMs = endTime - startTime;
            
            // Final processing hook for subclasses
            finalizeBatch(bc);
            
            // Update job statistics record
            updateJobStatistics(bc.getJobId(), 'Completed', processingTimeMs);
            
        } catch (Exception e) {
            logError('Error in batch finish', e);
            // Update job statistics to indicate failure
            updateJobStatistics(bc.getJobId(), 'Failed', null);
        }
    }
    
    /**
     * Pre-process hook - can be overridden by subclasses
     */
    protected virtual void preProcessBatch(Database.BatchableContext bc, List<SObject> scope) {
        // Default implementation does nothing
    }
    
    /**
     * Post-process hook - can be overridden by subclasses
     */
    protected virtual void postProcessBatch(Database.BatchableContext bc, List<SObject> scope, Map<String, List<SObject>> duplicates) {
        // Default implementation does nothing
    }
    
    /**
     * Finalize batch hook - can be overridden by subclasses
     */
    protected virtual void finalizeBatch(Database.BatchableContext bc) {
        // Default implementation does nothing
    }
    
    /**
     * Log an error
     */
    protected void logError(String message, Exception e) {
        String errorMsg = message + ': ' + e.getMessage() + '\n' + e.getStackTraceString();
        errors.add(errorMsg);
        System.debug(LoggingLevel.ERROR, errorMsg);
    }
    
    /**
     * Create job statistics record
     */
    protected void createJobStatistics(String jobId, String status) {
        try {
            // Create unified job statistics record
            DuplicateJobStatistic__c stats = new DuplicateJobStatistic__c(
                BatchJobId__c = jobId,
                ObjectApiName__c = objectApiName,
                ConfigurationName__c = configurationName,
                RecordsProcessed__c = 0,
                DuplicatesFound__c = 0,
                RecordsMerged__c = 0,
                Status__c = status,
                IsDryRun__c = isDryRun,
                JobStartTime__c = System.now()
            );
            
            insert stats;
        } catch (Exception e) {
            logError('Error creating job statistics', e);
        }
    }
    
    /**
     * Update job statistics record
     */
    protected void updateJobStatistics(String jobId, String status, Long processingTimeMs) {
        try {
            // Find existing job statistics record
            List<DuplicateJobStatistic__c> statsList = [
                SELECT Id
                FROM DuplicateJobStatistic__c
                WHERE BatchJobId__c = :jobId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            
            if (!statsList.isEmpty()) {
                DuplicateJobStatistic__c stats = statsList[0];
                
                // Update with current values
                stats.Status__c = status;
                stats.RecordsProcessed__c = recordsProcessed;
                stats.DuplicatesFound__c = duplicatesFound;
                stats.RecordsMerged__c = recordsMerged;
                
                if (status == 'Completed' || status == 'Failed') {
                    stats.JobCompletionTime__c = System.now();
                    
                    if (processingTimeMs != null) {
                        stats.ProcessingTimeMs__c = processingTimeMs;
                    }
                }
                
                if (!errors.isEmpty()) {
                    stats.ErrorMessage__c = String.join(errors, '\n').left(32000);
                }
                
                update stats;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error updating job statistics: ' + e.getMessage());
        }
    }
    
    /**
     * Select master record from a group of duplicates
     * Uses configured strategy
     */
    protected SObject selectMasterRecord(List<SObject> duplicates, String strategy) {
        if (duplicates == null || duplicates.isEmpty()) {
            return null;
        }
        
        // Default to first record
        SObject masterRecord = duplicates[0];
        
        // Apply selected strategy
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
        } else if (strategy == 'OldestCreated') {
            // Select oldest record by CreatedDate
            Datetime oldestDate = Datetime.now();
            
            for (SObject rec : duplicates) {
                Datetime createdDate = (Datetime)rec.get('CreatedDate');
                if (createdDate != null && createdDate < oldestDate) {
                    oldestDate = createdDate;
                    masterRecord = rec;
                }
            }
        } else if (strategy == 'NewestModified') {
            // Select most recently modified record
            Datetime newestDate = Datetime.valueOf('1900-01-01 00:00:00');
            
            for (SObject rec : duplicates) {
                Datetime modifiedDate = (Datetime)rec.get('LastModifiedDate');
                if (modifiedDate != null && modifiedDate > newestDate) {
                    newestDate = modifiedDate;
                    masterRecord = rec;
                }
            }
        }
        
        return masterRecord;
    }
    
    /**
     * Creates a duplicate group record for tracking and reporting
     */
    protected Id createDuplicateGroup(List<SObject> duplicates, SObject masterRecord, Decimal matchScore) {
        try {
            // Create a unique key for this group based on record IDs
            Set<Id> recordIds = new Set<Id>();
            for (SObject rec : duplicates) {
                recordIds.add((Id)rec.get('Id'));
            }
            String groupKey = String.valueOf(recordIds.hashCode());
            
            // Create the group detail record
            DuplicateGroupDetail__c groupDetail = new DuplicateGroupDetail__c(
                GroupKey__c = groupKey,
                ObjectName__c = objectApiName,
                RecordCount__c = duplicates.size(),
                MasterRecordId__c = masterRecord != null ? (Id)masterRecord.get('Id') : null,
                MatchScore__c = matchScore,
                DuplicateRecordIds__c = String.join(new List<Id>(recordIds), ',')
            );
            
            insert groupDetail;
            return groupDetail.Id;
            
        } catch (Exception e) {
            logError('Error creating duplicate group', e);
            return null;
        }
    }
}