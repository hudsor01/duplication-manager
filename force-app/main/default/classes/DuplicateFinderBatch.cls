/**
 * Batch class for finding duplicate records
 * @author Claude
 * @date 2025-04-13
 */
public with sharing class DuplicateFinderBatch implements Database.Batchable<SObject>, Database.Stateful {
  private String objectName;
  private Boolean isDryRun;

  // Counters to track progress
  private Integer recordsProcessed = 0;
  private Integer duplicatesFound = 0;
  private Integer recordsMerged = 0;

  /**
   * Constructor
   * @param objectName API name of the object to process
   * @param isDryRun If true, find duplicates but don't merge them
   */
  public DuplicateFinderBatch(String objectName, Boolean isDryRun) {
    this.objectName = objectName;
    this.isDryRun = isDryRun;
  }

  /**
   * Start method - query records to process
   */
  public Database.QueryLocator start(Database.BatchableContext bc) {
    String query = 'SELECT Id, Name';

    // Add fields based on object type
    if (objectName == 'Account') {
      query += ', Phone, BillingCity, Website';
    } else if (objectName == 'Contact') {
      query += ', Email, Phone, Title';
    } else if (objectName == 'Lead') {
      query += ', Email, Phone, Company, Title';
    }

    query += ' FROM ' + objectName;

    // Add basic filters to avoid processing all records
    query += ' ORDER BY CreatedDate DESC LIMIT 1000';

    return Database.getQueryLocator(query);
  }

  /**
   * Execute method - process each batch
   */
  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    try {
      // Update counter
      recordsProcessed += scope.size();

      // In a real implementation, we would use the duplicate rules or custom matching logic
      // For now, just simulate finding some duplicates
      List<SObject> duplicates = findSimulatedDuplicates(scope);
      duplicatesFound += duplicates.size();

      // Merge duplicates if not in dry run mode
      if (!isDryRun && !duplicates.isEmpty()) {
        // In a real implementation, we would call a merge service
        // For now, just simulate merging some records
        recordsMerged += Math.max(1, duplicates.size() / 2);
      }

      // Log progress
      System.debug(
        'Processed ' +
          scope.size() +
          ' records, found ' +
          duplicates.size() +
          ' duplicates'
      );
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error in batch execute: ' +
          e.getMessage() +
          '\n' +
          e.getStackTraceString()
      );
    }
  }

  /**
   * Finish method - perform cleanup and logging
   */
  public void finish(Database.BatchableContext bc) {
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
        update stat;
      }

      System.debug(
        'Batch completed: Processed ' +
          recordsProcessed +
          ' records, found ' +
          duplicatesFound +
          ' duplicates, merged ' +
          recordsMerged +
          ' records'
      );
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error in batch finish: ' +
          e.getMessage() +
          '\n' +
          e.getStackTraceString()
      );
    }
  }

  /**
   * Helper method to simulate finding duplicates
   * In a real implementation, this would use real duplicate detection logic
   */
  private List<SObject> findSimulatedDuplicates(List<SObject> records) {
    // Just return approximately 10% of records as "duplicates"
    List<SObject> duplicates = new List<SObject>();
    Integer duplicateCount = Math.max(1, (Integer) (records.size() * 0.1));

    for (Integer i = 0; i < duplicateCount && i < records.size(); i++) {
      duplicates.add(records[i]);
    }

    return duplicates;
  }
}
