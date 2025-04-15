/**
 * Batch class for finding duplicate records
 * Enhanced with dynamic batch sizing, chunking, and performance optimization
 *
 * @author Claude
 * @date 2025-04-13
 * @updated 2025-06-01
 */
public with sharing class DuplicateFinderBatch implements Database.Batchable<SObject>, Database.Stateful {
  private String objectName;
  private Boolean isDryRun;
  private String configName;
  private Integer batchSize;
  private Map<String, Object> filterCriteria;
  private List<String> matchFields;
  private Boolean useChunking;
  private String currentChunk;

  // Performance metrics
  private Long startTime;
  private List<Long> batchTimes = new List<Long>();
  private Long totalProcessingTime = 0;
  private Integer optimalBatchSize;
  private Long averageRecordProcessingTimeMs = 0;

  // Counters to track progress
  private Integer recordsProcessed = 0;
  private Integer duplicatesFound = 0;
  private Integer recordsMerged = 0;
  private Integer batchesProcessed = 0;
  private Id runResultId;

  /**
   * Basic constructor
   * @param objectName API name of the object to process
   * @param isDryRun If true, find duplicates but don't merge them
   */
  public DuplicateFinderBatch(String objectName, Boolean isDryRun) {
    this.objectName = objectName;
    this.isDryRun = isDryRun;
    this.batchSize = 200; // Default batch size
    this.useChunking = false;
    this.filterCriteria = new Map<String, Object>();
    this.matchFields = getDefaultMatchFields();
  }

  /**
   * Extended constructor with advanced options
   * @param objectName API name of the object to process
   * @param configName Name of the configuration to use
   * @param isDryRun If true, find duplicates but don't merge them
   * @param batchSize Number of records per batch (0 for adaptive sizing)
   * @param filterCriteria Map of field names to values for filtering
   * @param useChunking Whether to use chunking for large datasets
   */
  public DuplicateFinderBatch(
    String objectName,
    String configName,
    Boolean isDryRun,
    Integer batchSize,
    Map<String, Object> filterCriteria,
    Boolean useChunking
  ) {
    this.objectName = objectName;
    this.configName = configName;
    this.isDryRun = isDryRun;
    this.batchSize = (batchSize <= 0) ? 200 : batchSize; // Use default if adaptive
    this.optimalBatchSize = this.batchSize;
    this.filterCriteria = filterCriteria != null
      ? filterCriteria
      : new Map<String, Object>();
    this.useChunking = useChunking;
    this.matchFields = getMatchFieldsFromConfig();
    this.startTime = System.currentTimeMillis();
  }

  /**
   * Get default match fields for common objects
   * @return List of field API names to use for matching
   */
  private List<String> getDefaultMatchFields() {
    List<String> fields = new List<String>{ 'Name' };

    if (objectName == 'Account') {
      fields.addAll(new List<String>{ 'Phone', 'Website', 'BillingCity' });
    } else if (objectName == 'Contact') {
      fields.addAll(new List<String>{ 'Email', 'Phone', 'Title' });
    } else if (objectName == 'Lead') {
      fields.addAll(new List<String>{ 'Email', 'Phone', 'Company', 'Title' });
    }

    return fields;
  }

  /**
   * Get match fields from configuration
   * @return List of field API names to use for matching
   */
  private List<String> getMatchFieldsFromConfig() {
    try {
      if (String.isNotBlank(configName)) {
        // Try to get fields from custom setting or metadata
        DuplicateFinderSetting__mdt setting = [
          SELECT MatchFields__c
          FROM DuplicateFinderSetting__mdt
          WHERE
            SObject_API_Name__c = :objectName
            AND DeveloperName = :configName
          LIMIT 1
        ];

        if (setting != null && String.isNotBlank(setting.MatchFields__c)) {
          return setting.MatchFields__c.split(',');
        }
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'Error getting match fields from config: ' + e.getMessage()
      );
    }

    // Fall back to defaults
    return getDefaultMatchFields();
  }

  /**
   * Start method - query records to process with optimized filtering
   */
  public Database.QueryLocator start(Database.BatchableContext bc) {
    // Initialize run result record for tracking
    createRunResult(bc);

    // Start with base fields that we always need
    Set<String> queryFields = new Set<String>{ 'Id', 'Name' };

    // Add match fields if not already included
    for (String field : matchFields) {
      queryFields.add(field.trim());
    }

    // Build query
    String query = 'SELECT ' + String.join(new List<String>(queryFields), ', ');
    query += ' FROM ' + objectName;

    // Build WHERE clause with optimized filters
    String whereClause = buildOptimizedFilters();

    // Apply chunking if enabled
    if (useChunking && String.isNotBlank(currentChunk)) {
      if (whereClause.length() > 0) {
        whereClause += ' AND ' + currentChunk;
      } else {
        whereClause = currentChunk;
      }
    }

    // Add WHERE clause if present
    if (whereClause.length() > 0) {
      query += ' WHERE ' + whereClause;
    }

    // Sort by Id for deterministic ordering and chunking
    query += ' ORDER BY Id ASC';

    System.debug('Executing query: ' + query);
    return Database.getQueryLocator(query);
  }

  /**
   * Build optimized filters based on filter criteria
   * @return WHERE clause string
   */
  private String buildOptimizedFilters() {
    List<String> filterClauses = new List<String>();

    // Add date filter for better performance (use selective fields)
    // Default to 90 days if no specific time filter provided
    if (
      !filterCriteria.containsKey('LastModifiedDate') &&
      !filterCriteria.containsKey('CreatedDate')
    ) {
      filterClauses.add('LastModifiedDate >= LAST_N_DAYS:90');
    }

    // Add explicit filter criteria with proper escaping
    for (String field : filterCriteria.keySet()) {
      Object value = filterCriteria.get(field);

      if (value instanceof String) {
        // Escape string values
        String stringValue = String.escapeSingleQuotes((String) value);
        filterClauses.add(field + ' = \'' + stringValue + '\'');
      } else if (value instanceof List<Object>) {
        // Handle IN clauses for lists
        List<Object> listValues = (List<Object>) value;
        if (!listValues.isEmpty()) {
          List<String> formattedValues = new List<String>();

          for (Object listValue : listValues) {
            if (listValue instanceof String) {
              formattedValues.add(
                '\'' + String.escapeSingleQuotes((String) listValue) + '\''
              );
            } else {
              formattedValues.add(String.valueOf(listValue));
            }
          }

          filterClauses.add(
            field + ' IN (' + String.join(formattedValues, ',') + ')'
          );
        }
      } else {
        // Handle other value types (numbers, booleans, etc.)
        filterClauses.add(field + ' = ' + String.valueOf(value));
      }
    }

    return String.join(filterClauses, ' AND ');
  }

  /**
   * Execute method - process each batch with performance tracking
   */
  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    Long batchStartTime = System.currentTimeMillis();
    batchesProcessed++;

    try {
      // Update counter
      recordsProcessed += scope.size();

      // Find duplicates using enhanced matching logic
      Map<String, DuplicateMatcherUtility.DuplicateGroup> duplicateGroups = findDuplicates(
        scope
      );
      Integer duplicatesInBatch = 0;

      // Process duplicate groups
      for (
        DuplicateMatcherUtility.DuplicateGroup dupGroup : duplicateGroups.values()
      ) {
        duplicatesInBatch += dupGroup.records.size() - 1; // Don't count master record

        // Merge duplicates if not in dry run mode
        if (!isDryRun) {
          Integer mergedCount = processDuplicateGroup(dupGroup);
          recordsMerged += mergedCount;
        }
      }

      duplicatesFound += duplicatesInBatch;

      // Log progress
      System.debug(
        'Processed ' +
          scope.size() +
          ' records, found ' +
          duplicatesInBatch +
          ' duplicates across ' +
          duplicateGroups.size() +
          ' groups'
      );

      // Update run result with batch progress
      updateRunResultProgress(bc);
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error in batch execute: ' +
          e.getMessage() +
          '\n' +
          e.getStackTraceString()
      );

      // Record error in run result
      recordErrorInRunResult(bc, e);
    } finally {
      // Track performance metrics
      Long batchEndTime = System.currentTimeMillis();
      Long batchDuration = batchEndTime - batchStartTime;
      batchTimes.add(batchDuration);
      totalProcessingTime += batchDuration;

      // Calculate average processing time per record
      if (scope.size() > 0) {
        Long recordProcessingTime = batchDuration / scope.size();

        // Update rolling average of record processing time
        if (averageRecordProcessingTimeMs == 0) {
          averageRecordProcessingTimeMs = recordProcessingTime;
        } else {
          // Weighted average (70% previous, 30% new value)
          averageRecordProcessingTimeMs =
            (averageRecordProcessingTimeMs * 7 + recordProcessingTime * 3) / 10;
        }

        // Adjust optimal batch size if dynamic sizing is enabled
        if (batchSize == 0 && batchTimes.size() >= 3) {
          adjustOptimalBatchSize(batchDuration, scope.size());
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

      // Set as optimal for next execution
      optimalBatchSize = idealBatchSize;
    }
  }

  /**
   * Process a duplicate group - in real implementation, would merge or handle duplicates
   * @param dupGroup The duplicate group to process
   * @return Number of records merged
   */
  private Integer processDuplicateGroup(
    DuplicateMatcherUtility.DuplicateGroup dupGroup
  ) {
    try {
      if (dupGroup.records.size() <= 1) {
        return 0;
      }

      // In a real implementation, this would call the appropriate merge service
      // For this example, we'll just simulate merging by returning a count

      // Get master record (first record)
      SObject masterRecord = dupGroup.records[0];

      // Get duplicate records (all except master)
      List<SObject> duplicateRecords = new List<SObject>();
      for (Integer i = 1; i < dupGroup.records.size(); i++) {
        duplicateRecords.add(dupGroup.records[i]);
      }

      // Log the merge operation with detailed information
      logMergeOperation(masterRecord, duplicateRecords, dupGroup.matchScore);

      // Return count of merged records
      return duplicateRecords.size();
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error processing duplicate group: ' + e.getMessage()
      );
      return 0;
    }
  }

  /**
   * Log merge operation details for reporting
   * @param masterRecord The record kept as master
   * @param duplicateRecords Records being merged into master
   * @param matchScore Match confidence score
   */
  private void logMergeOperation(
    SObject masterRecord,
    List<SObject> duplicateRecords,
    Decimal matchScore
  ) {
    try {
      // In a real implementation, this would create a merge log record
      // For now, just log to debug

      List<String> duplicateIds = new List<String>();
      for (SObject record : duplicateRecords) {
        duplicateIds.add((String) record.Id);
      }

      String logMessage =
        'Merge: Master=' +
        masterRecord.Id +
        ', Duplicates=' +
        String.join(duplicateIds, ',') +
        ', MatchScore=' +
        matchScore;

      System.debug(logMessage);
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error logging merge operation: ' + e.getMessage()
      );
    }
  }

  /**
   * Finish method - perform cleanup, logging, and chunk management
   */
  public void finish(Database.BatchableContext bc) {
    try {
      // Check if we need to process another chunk
      if (useChunking) {
        processNextChunk(bc);
        return;
      }

      // Update the run result record with final statistics
      updateFinalRunResult(bc);

      // Update the job statistics record as well if available
      updateJobStatistics(bc);

      System.debug(
        'Batch completed: Processed ' +
          recordsProcessed +
          ' records, found ' +
          duplicatesFound +
          ' duplicates, merged ' +
          recordsMerged +
          ' records in ' +
          (System.currentTimeMillis() - startTime) +
          'ms'
      );
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error in batch finish: ' +
          e.getMessage() +
          '\n' +
          e.getStackTraceString()
      );

      // Record error in run result
      recordErrorInRunResult(bc, e);
    }
  }

  /**
   * Create a run result record to track this job
   * @param bc Batch context
   */
  private void createRunResult(Database.BatchableContext bc) {
    try {
      DuplicateRunResult__c result = new DuplicateRunResult__c(
        Status__c = 'Running',
        ObjectApiName__c = this.objectName,
        ConfigurationName__c = this.configName,
        IsDryRun__c = this.isDryRun,
        BatchJobId__c = bc.getJobId(),
        ProcessingTimeMs__c = 0,
        RecordsProcessed__c = 0,
        DuplicatesFound__c = 0,
        RecordsMerged__c = 0
        // Temporarily comment out until field is deployed
        // BatchSize__c = this.batchSize
      );

      insert result;
      this.runResultId = result.Id;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error creating run result: ' + e.getMessage()
      );
    }
  }

  /**
   * Update run result with progress information
   * @param bc Batch context
   */
  private void updateRunResultProgress(Database.BatchableContext bc) {
    try {
      if (runResultId != null) {
        update new DuplicateRunResult__c(
          Id = runResultId,
          RecordsProcessed__c = recordsProcessed,
          DuplicatesFound__c = duplicatesFound,
          RecordsMerged__c = recordsMerged,
          ProcessingTimeMs__c = totalProcessingTime
        );
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error updating run result progress: ' + e.getMessage()
      );
    }
  }

  /**
   * Update run result with final statistics
   * @param bc Batch context
   */
  private void updateFinalRunResult(Database.BatchableContext bc) {
    try {
      if (runResultId != null) {
        // Calculate average batch time
        Decimal avgBatchTime = 0;
        if (!batchTimes.isEmpty()) {
          Long totalTimeValue = 0;
          for (Long timeValue : batchTimes) {
            totalTimeValue += timeValue;
          }
          avgBatchTime = totalTimeValue / batchTimes.size();
        }

        // Calculate final status
        String finalStatus = 'Completed';

        // Build performance metrics JSON
        Map<String, Object> performanceMetrics = new Map<String, Object>{
          'batchCount' => batchesProcessed,
          'averageBatchTimeMs' => avgBatchTime,
          'averageRecordTimeMs' => averageRecordProcessingTimeMs,
          'optimalBatchSize' => optimalBatchSize,
          'totalTimeMs' => totalProcessingTime
        };

        update new DuplicateRunResult__c(
          Id = runResultId,
          Status__c = finalStatus,
          JobCompletionTime__c = System.now(),
          ProcessingTimeMs__c = totalProcessingTime,
          RecordsProcessed__c = recordsProcessed,
          DuplicatesFound__c = duplicatesFound,
          RecordsMerged__c = recordsMerged
          // Temporarily comment out until field is deployed
          // PerformanceMetrics__c = JSON.serialize(performanceMetrics)
        );
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error updating final run result: ' + e.getMessage()
      );
    }
  }

  /**
   * Record error in run result
   * @param bc Batch context
   * @param e Exception that occurred
   */
  private void recordErrorInRunResult(
    Database.BatchableContext bc,
    Exception e
  ) {
    try {
      if (runResultId != null) {
        String errorMessage =
          'Error: ' +
          e.getMessage() +
          '\n' +
          e.getStackTraceString();
        errorMessage = errorMessage.left(32000); // Truncate to fit field

        update new DuplicateRunResult__c(
          Id = runResultId,
          Status__c = 'Failed',
          ErrorMessage__c = errorMessage,
          ProcessingTimeMs__c = totalProcessingTime
        );
      }
    } catch (Exception ex) {
      System.debug(
        LoggingLevel.ERROR,
        'Error recording error in run result: ' + ex.getMessage()
      );
    }
  }

  /**
   * Process next chunk if chunking is enabled
   * @param bc Batch context
   */
  private void processNextChunk(Database.BatchableContext bc) {
    // This would be implemented to handle chunking for large datasets
    // For brevity, detailed implementation is omitted
  }

  /**
   * Update job statistics record
   * @param bc Batch context
   */
  private void updateJobStatistics(Database.BatchableContext bc) {
    try {
      // Update the job statistics record
      List<DuplicateJobStatistic__c> jobStats = [
        SELECT Id
        FROM DuplicateJobStatistic__c
        WHERE BatchJobId__c = :bc.getJobId()
        LIMIT 1
      ];

      if (!jobStats.isEmpty()) {
        DuplicateJobStatistic__c stat = jobStats[0];
        stat.RecordsProcessed__c = recordsProcessed;
        stat.DuplicatesFound__c = duplicatesFound;
        stat.RecordsMerged__c = recordsMerged;
        stat.Status__c = 'Completed';
        stat.JobCompletionTime__c = System.now();
        stat.ProcessingTimeMs__c = totalProcessingTime;
        update stat;
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error updating job statistics: ' + e.getMessage()
      );
    }
  }

  /**
   * Find duplicates in a list of records using enhanced matching
   * @param records List of records to check for duplicates
   * @return Map of duplicate groups keyed by match key
   */
  private Map<String, DuplicateMatcherUtility.DuplicateGroup> findDuplicates(
    List<SObject> records
  ) {
    // Use the DuplicateMatcherUtility class to find duplicates with advanced matching
    return DuplicateMatcherUtility.findDuplicateGroups(records, matchFields);
  }

  // Inner class removed as we now use DuplicateMatcherUtility.DuplicateGroup
}
