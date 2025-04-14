/**
 * DuplicateBatchProcessor
 * Enhanced batch processor framework with improved error handling, metrics, and logging
 *
 * @author Richard Hudson
 * @created April 2025
 */
public abstract class DuplicateBatchProcessor implements Database.Batchable<SObject>, Database.Stateful {

    // Batch configuration
    protected Integer batchSize;
    protected String objectName;
    protected Boolean isAsync;

    // Processing statistics
    protected Integer recordsProcessed = 0;
    protected Integer recordsSucceeded = 0;
    protected Integer recordsFailed = 0;
    protected Integer batchesProcessed = 0;
    protected Long processingTimeMs = 0;
    protected List<String> errorMessages = new List<String>();
    protected Id runResultId;

    // Timestamps for metrics
    protected DateTime startTime;
    protected DateTime endTime;

    /**
     * Constructor
     * @param batchSize Number of records per batch
     * @param objectName API name of object being processed
     * @param isAsync Whether to run asynchronously (true) or in current transaction (false)
     */
    public DuplicateBatchProcessor(Integer batchSize, String objectName, Boolean isAsync) {
        this.batchSize = batchSize;
        this.objectName = objectName;
        this.isAsync = isAsync;
        this.startTime = DateTime.now();
    }

    /**
     * Required start method to get batch data
     * @param bc Batchable context
     * @return Database.QueryLocator Query for the records to process
     */
    public abstract Database.QueryLocator start(Database.BatchableContext bc);

    /**
     * Template method for processing a batch
     * @param bc Batchable context
     * @param scope Records to process
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Long batchStartTime = System.currentTimeMillis();
        batchesProcessed++;
        recordsProcessed += scope.size();

        try {
            // Pre-processing steps
            preProcess(bc, scope);

            // Process records
            Map<Id, ProcessingResult> results = processRecords(bc, scope);

            // Track results
            for (ProcessingResult result : results.values()) {
                if (result.success) {
                    recordsSucceeded++;
                } else {
                    recordsFailed++;
                    if (String.isNotBlank(result.errorMessage)) {
                        errorMessages.add(result.errorMessage);
                    }
                }
            }

            // Post-processing steps
            postProcess(bc, scope, results);

        } catch (Exception e) {
            // Handle batch-level errors
            recordsFailed += scope.size();
            errorMessages.add('Batch error: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            handleBatchError(bc, scope, e);
        } finally {
            // Track processing time
            Long batchEndTime = System.currentTimeMillis();
            processingTimeMs += (batchEndTime - batchStartTime);
        }
    }

    /**
     * Template method for post-processing after all batches
     * @param bc Batchable context
     */
    public void finish(Database.BatchableContext bc) {
        this.endTime = DateTime.now();

        try {
            // Update run result with final statistics
            updateRunResult(bc);

            // Additional finish processing
            onFinish(bc);

        } catch (Exception e) {
            // Log finish errors
            System.debug(LoggingLevel.ERROR, 'Error in finish method: ' + e.getMessage());
            errorMessages.add('Finish error: ' + e.getMessage());
        }
    }

    /**
     * Pre-processing hook called before processing each batch
     * @param bc Batchable context
     * @param scope Records to process
     */
    protected virtual void preProcess(Database.BatchableContext bc, List<SObject> scope) {
        // Default implementation does nothing - can be overridden
    }

    /**
     * Abstract method to process records - must be implemented by subclasses
     * @param bc Batchable context
     * @param scope Records to process
     * @return Map<Id, ProcessingResult> Results of processing each record
     */
    protected abstract Map<Id, ProcessingResult> processRecords(Database.BatchableContext bc, List<SObject> scope);

    /**
     * Post-processing hook called after processing each batch
     * @param bc Batchable context
     * @param scope Records processed
     * @param results Results of processing
     */
    protected virtual void postProcess(Database.BatchableContext bc, List<SObject> scope, Map<Id, ProcessingResult> results) {
        // Default implementation does nothing - can be overridden
    }

    /**
     * Error handling hook for batch-level errors
     * @param bc Batchable context
     * @param scope Records being processed
     * @param e Exception that occurred
     */
    protected virtual void handleBatchError(Database.BatchableContext bc, List<SObject> scope, Exception e) {
        // Default implementation logs error
        System.debug(LoggingLevel.ERROR, 'Batch error: ' + e.getMessage() + ' - ' + e.getStackTraceString());
    }

    /**
     * Finish processing hook called at the end of all batches
     * @param bc Batchable context
     */
    protected virtual void onFinish(Database.BatchableContext bc) {
        // Default implementation does nothing - can be overridden
    }

    /**
     * Update run result with final statistics
     * @param bc Batchable context
     */
    protected virtual void updateRunResult(Database.BatchableContext bc) {
        if (runResultId != null) {
            try {
                DuplicateRunResult__c result = new DuplicateRunResult__c(
                    Id = runResultId,
                    Status__c = 'Completed',
                    JobCompletionTime__c = this.endTime,
                    ProcessingTimeMs__c = this.processingTimeMs,
                    RecordsProcessed__c = this.recordsProcessed,
                    ErrorMessage__c = String.join(errorMessages, '\n').left(131072) // Truncate to fit
                );

                update result;
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Error updating run result: ' + e.getMessage());
            }
        }
    }

    /**
     * Create run result record to track this job
     * @param configName Name of the configuration used
     * @param isDryRun Whether this is a dry run
     * @return Id of the created run result
     */
    protected Id createRunResult(String configName, Boolean isDryRun) {
        try {
            DuplicateRunResult__c result = new DuplicateRunResult__c(
                Status__c = 'Running',
                ObjectApiName__c = this.objectName,
                ConfigurationName__c = configName,
                IsDryRun__c = isDryRun,
                BatchJobId__c = null, // Will be populated when job is executed
                ProcessingTimeMs__c = 0,
                RecordsProcessed__c = 0,
                DuplicatesFound__c = 0,
                RecordsMerged__c = 0
            );

            insert result;
            this.runResultId = result.Id;
            return result.Id;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error creating run result: ' + e.getMessage());
            return null;
        }
    }

    /**
     * Execute this batch job
     * @param configName Name of the configuration used
     * @param isDryRun Whether this is a dry run
     * @return Id Job ID
     */
    public Id execute(String configName, Boolean isDryRun) {
        // Create run result
        createRunResult(configName, isDryRun);

        // Starting execution

        // Execute batch
        if (isAsync) {
            Id jobId = Database.executeBatch(this, this.batchSize);

            // Update run result with job ID
            if (runResultId != null) {
                try {
                    update new DuplicateRunResult__c(
                        Id = runResultId,
                        BatchJobId__c = jobId
                    );
                } catch (Exception e) {
                    System.debug(LoggingLevel.ERROR, 'Error updating run result with job ID: ' + e.getMessage());
                }
            }

            // Job is now running asynchronously

            return jobId;
        } else {
            // Execute synchronously for testing or immediate execution
            Database.QueryLocator queryLocator = this.start(null);
            Iterator<SObject> iterator = queryLocator.iterator();

            List<SObject> batch = new List<SObject>();
            while (iterator.hasNext()) {
                batch.add(iterator.next());

                // Process in batches of batchSize
                if (batch.size() == this.batchSize) {
                    this.execute(null, batch);
                    batch.clear();
                }
            }

            // Process any remaining records
            if (!batch.isEmpty()) {
                this.execute(null, batch);
            }

            // Call finish
            this.finish(null);

            return null; // No job ID for synchronous execution
        }
    }

    /**
     * Inner class for tracking processing results
     */
    public class ProcessingResult {
        public Boolean success { get; set; }
        public String errorMessage { get; set; }
        public Map<String, Object> additionalInfo { get; set; }

        public ProcessingResult() {
            this.success = true;
            this.errorMessage = '';
            this.additionalInfo = new Map<String, Object>();
        }

        public ProcessingResult(Boolean success, String errorMessage) {
            this.success = success;
            this.errorMessage = errorMessage;
            this.additionalInfo = new Map<String, Object>();
        }
    }
}