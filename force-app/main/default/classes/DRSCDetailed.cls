/**
 * @description Class for retrieving detailed statistics for the duplicate manager dashboard
 * @author Richard Hudson
 * @date 2025-04-11
 */
public with sharing class DRSCDetailed {
  /**
   * @description Static method for retrieving detailed statistics for the dashboard
   *
   * @param timeRange String representing time range filter
   * @return Map containing statistics
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getDetailedStatistics(String timeRange) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      // Default time range if not provided
      if (String.isBlank(timeRange)) {
        timeRange = 'LAST_30_DAYS';
      }

      // Get date range
      Date startDate = DRSCDate.getStartDateForRange(timeRange);
      Date endDate = Date.today();

      // Get total duplicates found and merged
      Integer totalDuplicates = 0;
      Integer totalMerged = 0;

      // Query for duplicates found by object
      // Verify object and field-level security
      if (
        !Schema.sObjectType.DuplicateJobStatistic__c.isAccessible() ||
        !Schema.sObjectType.DuplicateJobStatistic__c.fields.ObjectApiName__c.isAccessible() ||
        !Schema.sObjectType.DuplicateJobStatistic__c.fields.DuplicatesFound__c.isAccessible() ||
        !Schema.sObjectType.DuplicateJobStatistic__c.fields.JobCompletionTime__c.isAccessible()
      ) {
        throw new AuraHandledException(
          'Insufficient access to DuplicateJobStatistic__c object or fields'
        );
      }

      // Build query with parameters using bind variables for security
      String dupQuery =
        'SELECT ObjectApiName__c, SUM(DuplicatesFound__c) totalDuplicates ' +
        'FROM DuplicateJobStatistic__c';

      if (startDate != null) {
        dupQuery += ' WHERE JobCompletionTime__c >= :startDate AND JobCompletionTime__c <= :endDate';
      }

      dupQuery += ' GROUP BY ObjectApiName__c';

      // Using Database.query with bind variables (startDate and endDate) for proper security
      // Since object and field access was verified earlier, this is secure
      AggregateResult[] dupResults = Database.query(dupQuery);

      // Query for records merged by object
      // Verify object and field-level security for DuplicateMergeLog__c
      if (
        !Schema.sObjectType.DuplicateMergeLog__c.isAccessible() ||
        !Schema.sObjectType.DuplicateMergeLog__c.fields.ObjectApiName__c.isAccessible() ||
        !Schema.sObjectType.DuplicateMergeLog__c.fields.MergeTime__c.isAccessible()
      ) {
        throw new AuraHandledException(
          'Insufficient access to DuplicateMergeLog__c object or fields'
        );
      }

      String mergeQuery =
        'SELECT ObjectApiName__c, COUNT() totalMerged ' +
        'FROM DuplicateMergeLog__c';

      if (startDate != null) {
        mergeQuery += ' WHERE MergeTime__c >= :startDate AND MergeTime__c <= :endDate';
      }

      mergeQuery += ' GROUP BY ObjectApiName__c';

      // Using Database.query with bind variables (startDate and endDate) for proper security
      // Since object and field access was verified earlier, this is secure
      AggregateResult[] mergeResults = Database.query(mergeQuery);

      // Process results by object
      Map<String, Map<String, Object>> byObject = new Map<String, Map<String, Object>>();

      // Process duplicates found
      for (AggregateResult ar : dupResults) {
        String objectName = (String) ar.get('ObjectApiName__c');
        Decimal dups = (Decimal) ar.get('totalDuplicates');
        Integer dupsInt = dups != null ? dups.intValue() : 0;

        totalDuplicates += dupsInt;

        if (String.isNotBlank(objectName)) {
          Map<String, Object> objStats = byObject.containsKey(objectName)
            ? byObject.get(objectName)
            : new Map<String, Object>();

          objStats.put('totalDuplicates', dupsInt);
          byObject.put(objectName, objStats);
        }
      }

      // Process records merged
      for (AggregateResult ar : mergeResults) {
        String objectName = (String) ar.get('ObjectApiName__c');
        Integer merged = (Integer) ar.get('totalMerged');

        totalMerged += merged;

        if (String.isNotBlank(objectName)) {
          Map<String, Object> objStats = byObject.containsKey(objectName)
            ? byObject.get(objectName)
            : new Map<String, Object>();

          objStats.put('totalMerged', merged);
          byObject.put(objectName, objStats);
        }
      }

      // Get recent merge operations
      List<Map<String, Object>> recentMerges = new List<Map<String, Object>>();

      // Verify additional field access for DuplicateMergeLog__c
      if (
        !Schema.sObjectType.DuplicateMergeLog__c.fields.Id.isAccessible() ||
        !Schema.sObjectType.DuplicateMergeLog__c.fields.MergedIds__c.isAccessible() ||
        !Schema.sObjectType.DuplicateMergeLog__c.fields.JobId__c.isAccessible()
      ) {
        throw new AuraHandledException(
          'Insufficient access to required DuplicateMergeLog__c fields'
        );
      }

      String recentMergesQuery =
        'SELECT Id, ObjectApiName__c, ' +
        'MergeTime__c, MergedIds__c, JobId__c ' +
        'FROM DuplicateMergeLog__c';

      if (startDate != null) {
        recentMergesQuery += ' WHERE MergeTime__c >= :startDate AND MergeTime__c <= :endDate';
      }

      recentMergesQuery += ' ORDER BY MergeTime__c DESC LIMIT 10';

      // Using Database.query with bind variables (startDate and endDate) for proper security
      // Since object and field access was verified earlier, this is secure
      List<DuplicateMergeLog__c> mergeLogRecords = Database.query(
        recentMergesQuery
      );

      for (DuplicateMergeLog__c log : mergeLogRecords) {
        Map<String, Object> mergeInfo = new Map<String, Object>();
        mergeInfo.put('id', log.Id);
        mergeInfo.put('objectApiName', log.ObjectApiName__c);
        // ConfigurationName__c field doesn't exist on DuplicateMergeLog__c
        mergeInfo.put('configName', '');

        // Use MergedIds__c field to determine count of merged records
        // If it's a text field containing comma-separated IDs, calculate the count
        Integer recordCount = 0;
        if (String.isNotBlank(log.MergedIds__c)) {
          recordCount = log.MergedIds__c.split(',').size();
        }
        mergeInfo.put('count', recordCount);

        mergeInfo.put('isDryRun', false);
        mergeInfo.put('timestamp', log.MergeTime__c);
        // Use JobId__c instead of BatchJobId__c
        mergeInfo.put('jobId', log.JobId__c);

        recentMerges.add(mergeInfo);
      }

      // Get recent dry run operations
      // Verify additional field access for DuplicateJobStatistic__c
      if (
        !Schema.sObjectType.DuplicateJobStatistic__c.fields.Id.isAccessible() ||
        !Schema.sObjectType.DuplicateJobStatistic__c.fields.ConfigurationName__c.isAccessible() ||
        !Schema.sObjectType.DuplicateJobStatistic__c.fields.DuplicatesFound__c.isAccessible() ||
        !Schema.sObjectType.DuplicateJobStatistic__c.fields.IsDryRun__c.isAccessible() ||
        !Schema.sObjectType.DuplicateJobStatistic__c.fields.BatchJobId__c.isAccessible()
      ) {
        throw new AuraHandledException(
          'Insufficient access to required DuplicateJobStatistic__c fields'
        );
      }

      String dryRunsQuery =
        'SELECT Id, ObjectApiName__c, ConfigurationName__c, ' +
        'JobCompletionTime__c, DuplicatesFound__c, IsDryRun__c, BatchJobId__c ' +
        'FROM DuplicateJobStatistic__c ' +
        'WHERE IsDryRun__c = true';

      if (startDate != null) {
        dryRunsQuery += ' AND JobCompletionTime__c >= :startDate AND JobCompletionTime__c <= :endDate';
      }

      dryRunsQuery += ' ORDER BY JobCompletionTime__c DESC LIMIT 5';

      // Using Database.query with bind variables (startDate and endDate) for proper security
      // Since object and field access was verified earlier, this is secure
      List<DuplicateJobStatistic__c> dryRunRecords = Database.query(
        dryRunsQuery
      );

      for (DuplicateJobStatistic__c stat : dryRunRecords) {
        Map<String, Object> dryRunInfo = new Map<String, Object>();
        dryRunInfo.put('id', stat.Id);
        dryRunInfo.put('objectApiName', stat.ObjectApiName__c);
        dryRunInfo.put('configName', stat.ConfigurationName__c);
        dryRunInfo.put('count', stat.DuplicatesFound__c);
        dryRunInfo.put('isDryRun', true);
        dryRunInfo.put('timestamp', stat.JobCompletionTime__c);
        dryRunInfo.put('jobId', stat.BatchJobId__c);

        recentMerges.add(dryRunInfo);
      }

      // Sort combined recent operations by timestamp manually (newest first)
      if (recentMerges.size() > 1) {
        // Simple bubble sort by timestamp
        for (Integer i = 0; i < recentMerges.size() - 1; i++) {
          for (Integer j = i + 1; j < recentMerges.size(); j++) {
            Datetime timeI = (Datetime) recentMerges[i].get('timestamp');
            Datetime timeJ = (Datetime) recentMerges[j].get('timestamp');

            // If timeJ is newer than timeI, swap them (descending sort)
            if (timeJ != null && (timeI == null || timeJ > timeI)) {
              Map<String, Object> temp = recentMerges[i];
              recentMerges[i] = recentMerges[j];
              recentMerges[j] = temp;
            }
          }
        }
      }

      // Limit to 10 most recent (already sorted)
      if (recentMerges.size() > 10) {
        List<Map<String, Object>> limitedList = new List<Map<String, Object>>();
        for (Integer i = 0; i < 10 && i < recentMerges.size(); i++) {
          limitedList.add(recentMerges[i]);
        }
        recentMerges = limitedList;
      }

      // Calculate merge rate
      Double mergeRate = totalDuplicates > 0
        ? (Double) totalMerged / totalDuplicates
        : 0;

      // Build result
      result.put('totalDuplicates', totalDuplicates);
      result.put('totalMerged', totalMerged);
      result.put('mergeRate', mergeRate);
      result.put('byObject', byObject);
      result.put('recentMerges', recentMerges);
      result.put('timeRange', timeRange);
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error getting detailed statistics: ' + e.getMessage()
      );
      throw new AuraHandledException(
        'Error getting statistics: ' + e.getMessage()
      );
    }

    return result;
  }
}
