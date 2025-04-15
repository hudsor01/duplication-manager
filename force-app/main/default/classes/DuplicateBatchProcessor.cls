/**
 * DuplicateBatchProcessor
 * Enhanced batch processor framework with improved error handling, metrics, and logging
 * Optimized for large-scale processing with dynamic batch sizing and checkpointing
 *
 * @author Richard Hudson
 * @created April 2025
 * @updated June 2025
 */
public abstract class DuplicateBatchProcessor implements Database.Batchable<SObject>, Database.Stateful {
  // Batch configuration
  protected Integer batchSize;
  protected String objectName;
  protected Boolean isAsync;
  protected Boolean useDynamicBatchSizing = true; // New feature for adaptive batch sizing

  // Performance tracking
  protected List<Long> batchExecutionTimes = new List<Long>();
  protected Integer optimalBatchSize;
  protected Long averageRecordProcessingTimeMs = 0;

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
  public DuplicateBatchProcessor(
    Integer batchSize,
    String objectName,
    Boolean isAsync
  ) {
    this.batchSize = batchSize;
    this.objectName = objectName;
    this.isAsync = isAsync;
    this.startTime = DateTime.now();

    // Set initial optimal batch size based on input or defaults
    this.optimalBatchSize = batchSize;
  }

  /**
   * Extended constructor with dynamic batch sizing option
   * @param batchSize Number of records per batch
   * @param objectName API name of object being processed
   * @param isAsync Whether to run asynchronously (true) or in current transaction (false)
   * @param useDynamicBatchSizing Whether to adjust batch size dynamically based on performance
   */
  public DuplicateBatchProcessor(
    Integer batchSize,
    String objectName,
    Boolean isAsync,
    Boolean useDynamicBatchSizing
  ) {
    this(batchSize, objectName, isAsync);
    this.useDynamicBatchSizing = useDynamicBatchSizing;
  }

  /**
   * Required start method to get batch data
   * @param bc Batchable context
   * @return Database.QueryLocator Query for the records to process
   */
  public abstract Database.QueryLocator start(Database.BatchableContext bc);

  /**
   * Template method for processing a batch with performance metrics and dynamic sizing
   * @param bc Batchable context
   * @param scope Records to process
   */
  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    Long batchStartTime = System.currentTimeMillis();
    batchesProcessed++;
    recordsProcessed += scope.size();
    Integer scopeSize = scope.size();

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
      errorMessages.add(
        'Batch error: ' + e.getMessage() + ' - ' + e.getStackTraceString()
      );
      handleBatchError(bc, scope, e);
    } finally {
      // Track processing time
      Long batchEndTime = System.currentTimeMillis();
      Long batchExecutionTime = batchEndTime - batchStartTime;
      processingTimeMs += batchExecutionTime;

      // Record batch execution time for performance analysis
      batchExecutionTimes.add(batchExecutionTime);

      // Calculate average processing time per record for this batch
      if (scopeSize > 0) {
        Long recordProcessingTime = batchExecutionTime / scopeSize;

        // Update rolling average of record processing time (simple moving average)
        if (averageRecordProcessingTimeMs == 0) {
          averageRecordProcessingTimeMs = recordProcessingTime;
        } else {
          // Weighted average (70% previous, 30% new value)
          averageRecordProcessingTimeMs =
            (averageRecordProcessingTimeMs * 7 + recordProcessingTime * 3) / 10;
        }

        // Adjust optimal batch size if dynamic sizing is enabled and we have enough data
        if (useDynamicBatchSizing && batchExecutionTimes.size() >= 3) {
          adjustOptimalBatchSize(batchExecutionTime, scopeSize);
        }
      }
    }
  }

  /**
   * Adjusts the optimal batch size based on performance metrics
   * @param lastBatchTime Execution time of the last batch in ms
   * @param lastBatchSize Size of the last batch in records
   */
  private void adjustOptimalBatchSize(
    Long lastBatchTime,
    Integer lastBatchSize
  ) {
    // Target execution time per batch (5 seconds seems optimal for most operations)
    final Long TARGET_BATCH_TIME_MS = 5000;

    // Don't allow batch sizes smaller than 50 or larger than 2000
    final Integer MIN_BATCH_SIZE = 50;
    final Integer MAX_BATCH_SIZE = 2000;

    // Calculate ideal batch size based on processing time
    if (averageRecordProcessingTimeMs > 0) {
      Integer idealBatchSize = (Integer) (TARGET_BATCH_TIME_MS /
      averageRecordProcessingTimeMs);

      // Apply limits and dampen change rate
      Integer currentOptimal = optimalBatchSize;
      if (idealBatchSize < MIN_BATCH_SIZE) {
        idealBatchSize = MIN_BATCH_SIZE;
      } else if (idealBatchSize > MAX_BATCH_SIZE) {
        idealBatchSize = MAX_BATCH_SIZE;
      }

      // Smooth transitions - don't change by more than 30% at once
      Decimal maxChange = currentOptimal * 0.3;
      Integer maxNewSize = currentOptimal + Integer.valueOf(maxChange);
      Integer minNewSize = Math.max(
        MIN_BATCH_SIZE,
        currentOptimal - Integer.valueOf(maxChange)
      );

      if (idealBatchSize > maxNewSize) {
        idealBatchSize = maxNewSize;
      } else if (idealBatchSize < minNewSize) {
        idealBatchSize = minNewSize;
      }

      // Round to nearest 10 for cleaner numbers
      idealBatchSize = Math.round(idealBatchSize / 10) * 10;

      // Set as optimal for next execution (if needed)
      optimalBatchSize = idealBatchSize;
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
      System.debug(
        LoggingLevel.ERROR,
        'Error in finish method: ' + e.getMessage()
      );
      errorMessages.add('Finish error: ' + e.getMessage());
    }
  }

  /**
   * Pre-processing hook called before processing each batch
   * @param bc Batchable context
   * @param scope Records to process
   */
  protected virtual void preProcess(
    Database.BatchableContext bc,
    List<SObject> scope
  ) {
    // Default implementation does nothing - can be overridden
  }

  /**
   * Abstract method to process records - must be implemented by subclasses
   * @param bc Batchable context
   * @param scope Records to process
   * @return Map<Id, ProcessingResult> Results of processing each record
   */
  protected abstract Map<Id, ProcessingResult> processRecords(
    Database.BatchableContext bc,
    List<SObject> scope
  );

  /**
   * Post-processing hook called after processing each batch
   * @param bc Batchable context
   * @param scope Records processed
   * @param results Results of processing
   */
  protected virtual void postProcess(
    Database.BatchableContext bc,
    List<SObject> scope,
    Map<Id, ProcessingResult> results
  ) {
    // Default implementation does nothing - can be overridden
  }

  /**
   * Error handling hook for batch-level errors
   * @param bc Batchable context
   * @param scope Records being processed
   * @param e Exception that occurred
   */
  protected virtual void handleBatchError(
    Database.BatchableContext bc,
    List<SObject> scope,
    Exception e
  ) {
    // Default implementation logs error
    System.debug(
      LoggingLevel.ERROR,
      'Batch error: ' + e.getMessage() + ' - ' + e.getStackTraceString()
    );
  }

  /**
   * Finish processing hook called at the end of all batches
   * @param bc Batchable context
   */
  protected virtual void onFinish(Database.BatchableContext bc) {
    // Default implementation does nothing - can be overridden
  }

  /**
   * Update run result with final statistics and performance metrics
   * @param bc Batchable context
   */
  protected virtual void updateRunResult(Database.BatchableContext bc) {
    if (runResultId != null) {
      try {
        // Calculate average batch execution time if available
        Decimal avgBatchTime = 0;
        if (!batchExecutionTimes.isEmpty()) {
          Long totalTimeValue = 0;
          for (Long timeValue : batchExecutionTimes) {
            totalTimeValue += timeValue;
          }
          avgBatchTime = totalTimeValue / batchExecutionTimes.size();
        }

        // Calculate final status (can be Completed, Completed with Errors, or Failed)
        String finalStatus = 'Completed';
        if (recordsFailed > 0) {
          if (recordsFailed >= recordsProcessed * 0.5) {
            finalStatus = 'Failed'; // More than 50% failure rate
          } else {
            finalStatus = 'Completed with Errors';
          }
        }

        // Build performance metrics JSON
        Map<String, Object> performanceMetrics = new Map<String, Object>{
          'batchCount' => batchesProcessed,
          'averageBatchTimeMs' => avgBatchTime,
          'averageRecordTimeMs' => averageRecordProcessingTimeMs,
          'optimalBatchSize' => optimalBatchSize,
          'dynamicSizingEnabled' => useDynamicBatchSizing
        };

        // Format error messages for readability
        String formattedErrors = '';
        if (!errorMessages.isEmpty()) {
          formattedErrors = String.join(errorMessages, '\n').left(131072); // Truncate to fit field
        }

        // Update the result record with all metrics
        DuplicateRunResult__c result = new DuplicateRunResult__c(
          Id = runResultId,
          Status__c = finalStatus,
          JobCompletionTime__c = this.endTime,
          ProcessingTimeMs__c = this.processingTimeMs,
          RecordsProcessed__c = this.recordsProcessed,
          RecordsSucceeded__c = this.recordsSucceeded,
          RecordsFailed__c = this.recordsFailed,
          ErrorMessage__c = formattedErrors
          // Temporarily comment out until field is deployed
          // PerformanceMetrics__c = JSON.serialize(performanceMetrics)
        );

        update result;
      } catch (Exception e) {
        // Handle error in updating run result
        System.debug(
          LoggingLevel.ERROR,
          'Error updating run result: ' +
            e.getMessage() +
            ' - ' +
            e.getStackTraceString()
        );

        // Try once more with minimal fields
        try {
          update new DuplicateRunResult__c(
            Id = runResultId,
            Status__c = 'Error in Final Update',
            JobCompletionTime__c = DateTime.now(),
            ErrorMessage__c = 'Error updating final statistics: ' +
              e.getMessage().left(32000)
          );
        } catch (Exception ex) {
          // Last resort logging
          System.debug(
            LoggingLevel.ERROR,
            'Critical error updating run result: ' + ex.getMessage()
          );
        }
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
      System.debug(
        LoggingLevel.ERROR,
        'Error creating run result: ' + e.getMessage()
      );
      return null;
    }
  }

  /**
   * Execute this batch job with improved error handling and dynamic batch sizing
   * @param configName Name of the configuration used
   * @param isDryRun Whether this is a dry run
   * @return Id Job ID
   */
  public Id execute(String configName, Boolean isDryRun) {
    // Create run result
    createRunResult(configName, isDryRun);

    try {
      // Execute batch
      if (isAsync) {
        // Use dynamically determined optimal batch size if available
        Integer execBatchSize = (useDynamicBatchSizing &&
          optimalBatchSize != null)
          ? optimalBatchSize
          : this.batchSize;

        Id jobId = Database.executeBatch(this, execBatchSize);

        // Update run result with job ID
        if (runResultId != null) {
          try {
            update new DuplicateRunResult__c(
              Id = runResultId,
              BatchJobId__c = jobId
              // Temporarily comment out until field is deployed
              // BatchSize__c = execBatchSize
            );
          } catch (Exception e) {
            System.debug(
              LoggingLevel.ERROR,
              'Error updating run result with job ID: ' + e.getMessage()
            );
          }
        }

        return jobId;
      } else {
        // Execute synchronously with chunking and progress tracking
        Database.QueryLocator queryLocator = this.start(null);
        Iterator<SObject> iterator = queryLocator.iterator();

        // Process in chunks with dynamic batch sizing for better memory management
        List<SObject> batch = new List<SObject>();
        Integer recordCount = 0;
        Integer totalProcessed = 0;

        // Use smaller batch size for synchronous execution to avoid timeout
        Integer syncBatchSize = Math.min(this.batchSize, 200);

        try {
          while (iterator.hasNext()) {
            // Check if we need to adjust batch size based on performance
            if (useDynamicBatchSizing && batchExecutionTimes.size() >= 3) {
              syncBatchSize = Math.min(optimalBatchSize, 200); // Cap at 200 for sync
            }

            batch.add(iterator.next());
            recordCount++;

            // Process when batch reaches target size
            if (batch.size() >= syncBatchSize) {
              this.execute(null, batch);
              totalProcessed += batch.size();
              batch.clear();

              // Check for governor limits approaching
              if (
                Limits.getCpuTime() > Limits.getLimitCpuTime() * 0.8 ||
                Limits.getHeapSize() > Limits.getLimitHeapSize() * 0.8
              ) {
                // Log warning about approaching limits
                String warningMsg =
                  'Approaching governor limits, processed ' +
                  totalProcessed +
                  ' records so far. Consider using async execution.';
                errorMessages.add(warningMsg);
                System.debug(LoggingLevel.WARN, warningMsg);
                break; // Exit processing to avoid hitting limits
              }
            }
          }

          // Process any remaining records
          if (!batch.isEmpty()) {
            this.execute(null, batch);
            totalProcessed += batch.size();
          }
        } catch (Exception e) {
          // Handle errors during processing
          errorMessages.add(
            'Error during synchronous execution: ' + e.getMessage()
          );
          System.debug(
            LoggingLevel.ERROR,
            'Error during synchronous execution: ' +
              e.getMessage() +
              ' - ' +
              e.getStackTraceString()
          );
        } finally {
          // Always call finish to ensure stats are saved
          this.finish(null);
        }

        return null; // No job ID for synchronous execution
      }
    } catch (Exception e) {
      // Handle errors during job setup
      if (runResultId != null) {
        try {
          // Update run result with error
          update new DuplicateRunResult__c(
            Id = runResultId,
            Status__c = 'Failed',
            ErrorMessage__c = 'Job initialization error: ' + e.getMessage(),
            JobCompletionTime__c = DateTime.now()
          );
        } catch (Exception ex) {
          // Last resort error logging
          System.debug(
            LoggingLevel.ERROR,
            'Critical error: ' +
              e.getMessage() +
              ' AND could not update run result'
          );
        }
      }

      // Re-throw the exception
      throw e;
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
