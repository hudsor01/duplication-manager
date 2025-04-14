/**
 * Controller for managing statistics about duplicate jobs
 *
 * @author Richard Hudson
 * @date April 2025
 */
public with sharing class DuplicateRecordStatisticsController {
  /**
   * Gets the start date based on the time range
   *
   * @param timeRange String identifying the time range (TODAY, YESTERDAY, etc.)
   * @return Date The start date for the range
   */
  @AuraEnabled
  public static Date getStartDateForRange(String timeRange) {
    return DRSCDate.getStartDateForRange(timeRange);
  }

  /**
   * Retrieves statistics about duplicate finder jobs
   *
   * @return Map containing statistics about duplicate finder jobs
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getDuplicateStatistics() {
    Map<String, Object> results = new Map<String, Object>();

    try {
      // Get summary statistics using ObjectApiName__c
      AggregateResult[] summaryStats = [
        SELECT
          SUM(DuplicatesFound__c) totalDuplicates,
          SUM(RecordsMerged__c) totalMerged,
          COUNT(Id) totalJobs
        FROM DuplicateJobStatistic__c
      ];

      if (!summaryStats.isEmpty()) {
        results.put('totalDuplicates', summaryStats[0].get('totalDuplicates'));
        results.put('totalMerged', summaryStats[0].get('totalMerged'));
        results.put('totalJobs', summaryStats[0].get('totalJobs'));
      } else {
        results.put('totalDuplicates', 0);
        results.put('totalMerged', 0);
        results.put('totalJobs', 0);
      }

      // Get statistics by object
      AggregateResult[] objectStats = [
        SELECT
          ObjectApiName__c objectName,
          SUM(DuplicatesFound__c) duplicates,
          SUM(RecordsMerged__c) merged,
          COUNT(Id) jobs
        FROM DuplicateJobStatistic__c
        GROUP BY ObjectApiName__c
      ];

      Map<String, Map<String, Object>> byObject = new Map<String, Map<String, Object>>();

      for (AggregateResult ar : objectStats) {
        String objectName = (String) ar.get('objectName');
        if (objectName != null) {
          Map<String, Object> stats = new Map<String, Object>();

          stats.put('totalDuplicates', ar.get('duplicates'));
          stats.put('totalMerged', ar.get('merged'));
          stats.put('totalJobs', ar.get('jobs'));

          byObject.put(objectName, stats);
        }
      }

      results.put('byObject', byObject);

      // Get recent merge operations
      List<DuplicateJobStatistic__c> recentJobs = [
        SELECT
          Id,
          ObjectApiName__c,
          ConfigurationName__c,
          DuplicatesFound__c,
          RecordsMerged__c,
          IsDryRun__c,
          JobCompletionTime__c
        FROM DuplicateJobStatistic__c
        ORDER BY JobCompletionTime__c DESC
        LIMIT 10
      ];

      List<Map<String, Object>> recentMerges = new List<Map<String, Object>>();

      for (DuplicateJobStatistic__c job : recentJobs) {
        Map<String, Object> jobMap = new Map<String, Object>();

        jobMap.put('id', job.Id);
        jobMap.put('objectApiName', job.ObjectApiName__c);
        jobMap.put('configName', job.ConfigurationName__c);
        jobMap.put(
          'count',
          job.IsDryRun__c ? job.DuplicatesFound__c : job.RecordsMerged__c
        );
        jobMap.put('isDryRun', job.IsDryRun__c);
        jobMap.put('timestamp', job.JobCompletionTime__c);

        recentMerges.add(jobMap);
      }

      results.put('recentMerges', recentMerges);

      // Get statistics by configuration
      AggregateResult[] configStats = [
        SELECT
          ConfigurationName__c configName,
          SUM(DuplicatesFound__c) duplicates,
          SUM(RecordsMerged__c) merged,
          COUNT(Id) jobs,
          MAX(JobCompletionTime__c) lastRun
        FROM DuplicateJobStatistic__c
        GROUP BY ConfigurationName__c
      ];

      Map<String, Map<String, Object>> byConfig = new Map<String, Map<String, Object>>();

      for (AggregateResult ar : configStats) {
        String configName = (String) ar.get('configName');
        if (configName != null) {
          Map<String, Object> stats = new Map<String, Object>();

          stats.put('totalDuplicates', ar.get('duplicates'));
          stats.put('totalMerged', ar.get('merged'));
          stats.put('totalJobs', ar.get('jobs'));
          stats.put('lastRun', ar.get('lastRun'));

          byConfig.put(configName, stats);
        }
      }

      results.put('byConfig', byConfig);

      // Calculate efficiency metrics
      if (
        summaryStats[0].get('totalDuplicates') != null &&
        Integer.valueOf(summaryStats[0].get('totalDuplicates')) > 0
      ) {
        Decimal totalDupes = (Decimal) summaryStats[0].get('totalDuplicates');
        Decimal totalMerged = (Decimal) summaryStats[0].get('totalMerged');

        if (totalMerged != null && totalDupes != null) {
          Decimal mergeRate = (totalMerged / totalDupes * 100).setScale(2);
          results.put('mergeRate', mergeRate);
        }
      }
    } catch (Exception e) {
      System.debug('Error getting statistics: ' + e.getMessage());
      throw new AuraHandledException(
        'Error retrieving statistics: ' + e.getMessage()
      );
    }

    return results;
  }

  /**
   * Retrieves job records for the paginated jobs list
   *
   * @param pageSize Number of records per page
   * @param pageNumber Current page number
   * @return Map containing the paginated jobs and total counts
   */
  @AuraEnabled
  public static Map<String, Object> getPaginatedJobStatistics(
    Integer pageSize,
    Integer pageNumber
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      // Calculate offset
      Integer offset = (pageNumber - 1) * pageSize;

      // Get count of total records
      Integer totalRecords = [SELECT COUNT() FROM DuplicateJobStatistic__c];

      // Get paginated records
      List<DuplicateJobStatistic__c> jobs = [
        SELECT
          Id,
          ObjectApiName__c,
          ConfigurationName__c,
          DuplicatesFound__c,
          RecordsMerged__c,
          RecordsProcessed__c,
          IsDryRun__c,
          JobCompletionTime__c,
          ProcessingTimeMs__c,
          BatchJobId__c,
          ErrorMessage__c
        FROM DuplicateJobStatistic__c
        ORDER BY JobCompletionTime__c DESC
        LIMIT :pageSize
        OFFSET :offset
      ];

      List<Map<String, Object>> jobMaps = new List<Map<String, Object>>();

      for (DuplicateJobStatistic__c job : jobs) {
        Map<String, Object> jobMap = new Map<String, Object>();

        jobMap.put('id', job.Id);
        jobMap.put('objectApiName', job.ObjectApiName__c);
        jobMap.put('configName', job.ConfigurationName__c);
        jobMap.put('duplicatesFound', job.DuplicatesFound__c);
        jobMap.put('recordsMerged', job.RecordsMerged__c);
        jobMap.put('recordsProcessed', job.RecordsProcessed__c);
        jobMap.put('isDryRun', job.IsDryRun__c);
        jobMap.put('completionTime', job.JobCompletionTime__c);
        jobMap.put('processingTimeMs', job.ProcessingTimeMs__c);
        jobMap.put('batchJobId', job.BatchJobId__c);
        jobMap.put('hasErrors', String.isNotBlank(job.ErrorMessage__c));

        // Calculate processing time in seconds
        if (job.ProcessingTimeMs__c != null) {
          jobMap.put('processingTimeSec', job.ProcessingTimeMs__c / 1000);
        }

        jobMaps.add(jobMap);
      }

      // Calculate total pages
      Integer totalPages = Math.ceil(totalRecords / (Decimal) pageSize)
        .intValue();

      result.put('records', jobMaps);
      result.put('totalRecords', totalRecords);
      result.put('totalPages', totalPages);
      result.put('pageSize', pageSize);
      result.put('pageNumber', pageNumber);
    } catch (Exception e) {
      System.debug('Error getting paginated job statistics: ' + e.getMessage());
      throw new AuraHandledException(
        'Error retrieving job statistics: ' + e.getMessage()
      );
    }

    return result;
  }

  /**
   * Clears all job statistics (for testing/reset)
   *
   * @return Number of records deleted
   */
  @AuraEnabled
  public static Integer clearAllJobStatistics() {
    Integer deleteCount = 0;

    try {
      List<DuplicateJobStatistic__c> records = [
        SELECT Id
        FROM DuplicateJobStatistic__c
        LIMIT 50000
      ];
      delete records;
      deleteCount = records.size();
    } catch (Exception e) {
      System.debug('Error clearing job statistics: ' + e.getMessage());
      throw new AuraHandledException(
        'Error clearing job statistics: ' + e.getMessage()
      );
    }

    return deleteCount;
  }
}
