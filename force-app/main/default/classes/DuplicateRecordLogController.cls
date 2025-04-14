/**
 * Controller for managing audit logs of merge operations
 *
 * @author Richard Hudson
 * @date April 2025
 */
public with sharing class DuplicateRecordLogController {
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
  @AuraEnabled
  public static Id createMergeJobLog(
    String batchJobId,
    String configName,
    String configId,
    String objectApiName,
    Integer recordsMerged,
    String recordIdsJSON,
    Boolean isScheduledJob
  ) {
    try {
      MergeJobLog__c log = new MergeJobLog__c(
        BatchJobId__c = batchJobId,
        ConfigurationName__c = configName,
        ConfigurationId__c = configId,
        ObjectApiName__c = objectApiName,
        RecordsMerged__c = recordsMerged,
        RecordIdsJSON__c = recordIdsJSON,
        IsScheduledJob__c = isScheduledJob,
        ExecutionTime__c = System.now(),
        InitiatedBy__c = UserInfo.getUserId()
      );

      insert log;
      return log.Id;
    } catch (Exception e) {
      System.debug('Error creating merge job log: ' + e.getMessage());
      throw new AuraHandledException(
        'Error creating merge job log: ' + e.getMessage()
      );
    }
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
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getMergeJobLogs(
    String objectApiName,
    String configId,
    Integer pageSize,
    Integer pageNumber,
    String filters
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      // Parse filters if provided
      Map<String, Object> filterMap = new Map<String, Object>();
      if (String.isNotBlank(filters)) {
        filterMap = (Map<String, Object>) JSON.deserializeUntyped(filters);
      }

      // Build query
      String query =
        'SELECT Id, BatchJobId__c, ConfigurationName__c, ConfigurationId__c, ' +
        'ObjectApiName__c, RecordsMerged__c, ExecutionTime__c, IsScheduledJob__c, ' +
        'InitiatedBy__r.Name, RecordIdsJSON__c ' +
        'FROM MergeJobLog__c WHERE Id != null';

      // Add filters
      if (String.isNotBlank(objectApiName)) {
        query += ' AND ObjectApiName__c = :objectApiName';
      }

      if (String.isNotBlank(configId)) {
        query += ' AND ConfigurationId__c = :configId';
      }

      // Add date range filter if present
      if (
        filterMap.containsKey('dateRange') &&
        filterMap.get('dateRange') != 'ALL'
      ) {
        String dateRange = (String) filterMap.get('dateRange');
        String dateFilter = getDateRangeFilter(dateRange);
        if (String.isNotBlank(dateFilter)) {
          query += ' AND ' + dateFilter;
        }
      }

      // Get total count
      Integer totalRecords = Database.countQuery(
        'SELECT COUNT() FROM MergeJobLog__c WHERE ' +
        query.substringAfter('WHERE ')
      );

      // Add order by and pagination
      query += ' ORDER BY ExecutionTime__c DESC';

      if (pageSize != null && pageSize > 0) {
        Integer offset = (pageNumber - 1) * pageSize;
        query += ' LIMIT :pageSize OFFSET :offset';
      }

      // Execute query
      List<MergeJobLog__c> logs = Database.query(query);

      // Format records for UI
      List<Map<String, Object>> formattedLogs = new List<Map<String, Object>>();

      for (MergeJobLog__c log : logs) {
        Map<String, Object> formattedLog = new Map<String, Object>();

        formattedLog.put('id', log.Id);
        formattedLog.put('batchJobId', log.BatchJobId__c);
        formattedLog.put('configName', log.ConfigurationName__c);
        formattedLog.put('objectApiName', log.ObjectApiName__c);
        formattedLog.put('recordsMerged', log.RecordsMerged__c);
        formattedLog.put('executionTime', log.ExecutionTime__c);
        formattedLog.put('isScheduledJob', log.IsScheduledJob__c);
        formattedLog.put('userName', log.InitiatedBy__r.Name);

        // Parse record IDs JSON if available
        if (String.isNotBlank(log.RecordIdsJSON__c)) {
          try {
            formattedLog.put(
              'recordGroups',
              JSON.deserializeUntyped(log.RecordIdsJSON__c)
            );
          } catch (Exception e) {
            System.debug('Error parsing record IDs JSON: ' + e.getMessage());
          }
        }

        formattedLogs.add(formattedLog);
      }

      // Build pagination info
      Map<String, Object> pagination = new Map<String, Object>();
      pagination.put('pageSize', pageSize);
      pagination.put('pageNumber', pageNumber);
      pagination.put('totalRecords', totalRecords);
      pagination.put(
        'totalPages',
        Math.ceil(totalRecords / (Decimal) pageSize).intValue()
      );

      // Build result
      result.put('records', formattedLogs);
      result.put('pagination', pagination);
    } catch (Exception e) {
      System.debug('Error getting merge job logs: ' + e.getMessage());
      throw new AuraHandledException(
        'Error getting merge job logs: ' + e.getMessage()
      );
    }

    return result;
  }

  /**
   * Helper to get date range filter for query
   *
   * @param dateRange Date range identifier
   * @return String containing the date filter clause
   */
  private static String getDateRangeFilter(String dateRange) {
    String filter = '';

    Date today = Date.today();
    DateTime now = DateTime.now();

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
      when else {
        // No filter
      }
    }

    return filter;
  }
}
