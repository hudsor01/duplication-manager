/**
 * DuplicateRunResultService
 * @description Service class for handling duplicate run results operations
 */
public with sharing class DuplicateRunResultService {
  /**
   * Gets a run result by batch job ID
   *
   * @param batchJobId ID of the batch job
   * @return The run result record
   */
  public DuplicateRunResult__c getRunResultByBatchId(String batchJobId) {
    validateAccess();

    List<DuplicateRunResult__c> runResults = [
      SELECT
        Id,
        BatchJobId__c,
        ConfigurationName__c,
        ObjectApiName__c,
        IsDryRun__c,
        DuplicatesFound__c,
        RecordsProcessed__c,
        RecordsMerged__c,
        ProcessingTimeMs__c,
        AverageMatchScore__c,
        Status__c,
        ErrorMessage__c
      FROM DuplicateRunResult__c
      WHERE BatchJobId__c = :batchJobId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];

    if (runResults.isEmpty()) {
      throw new duplicateException(
        'No duplicate run results found for job ID: ' + batchJobId
      );
    }

    return runResults[0];
  }

  /**
   * Gets the count of duplicate groups for a run result
   *
   * @param runResultId ID of the run result
   * @return Count of duplicate groups
   */
  public Integer getGroupCount(Id runResultId) {
    validateGroupAccess();

    return [
      SELECT COUNT()
      FROM DuplicateGroupDetail__c
      WHERE DuplicateRunResult__c = :runResultId
      WITH SECURITY_ENFORCED
    ];
  }

  /**
   * Gets paginated duplicate groups for a run result
   *
   * @param runResultId ID of the run result
   * @param pageSize Number of records per page
   * @param pageNumber Current page number
   * @return List of duplicate group details
   */
  public List<DuplicateGroupDetail__c> getGroups(
    Id runResultId,
    Integer pageSize,
    Integer pageNumber
  ) {
    validateGroupAccess();

    Integer offset = (pageNumber - 1) * pageSize;

    return [
      SELECT
        Id,
        GroupKey__c,
        RecordCount__c,
        MatchScore__c,
        FieldValues__c,
        MasterRecordId__c,
        DuplicateRecordIds__c,
        ObjectName__c
      FROM DuplicateGroupDetail__c
      WHERE DuplicateRunResult__c = :runResultId
      WITH SECURITY_ENFORCED
      ORDER BY MatchScore__c DESC
      LIMIT :pageSize
      OFFSET :offset
    ];
  }

  /**
   * Convert a duplicate group to a Map for API response
   *
   * @param dupGroup Duplicate group record
   * @return Map representation of the group
   */
  public Map<String, Object> convertGroupToMap(
    DuplicateGroupDetail__c dupGroup
  ) {
    Map<String, Object> groupMap = new Map<String, Object>();
    groupMap.put('id', dupGroup.Id);
    groupMap.put('groupKey', dupGroup.GroupKey__c);
    groupMap.put('recordCount', dupGroup.RecordCount__c);
    groupMap.put('matchScore', dupGroup.MatchScore__c);
    groupMap.put('fieldValues', dupGroup.FieldValues__c);
    groupMap.put('masterRecordId', dupGroup.MasterRecordId__c);
    groupMap.put('objectName', dupGroup.ObjectName__c);

    // Parse duplicate record IDs
    if (String.isNotBlank(dupGroup.DuplicateRecordIds__c)) {
      List<String> recordIds = dupGroup.DuplicateRecordIds__c.split(',');
      groupMap.put('duplicateRecordIds', recordIds);
    } else {
      groupMap.put('duplicateRecordIds', new List<String>());
    }

    return groupMap;
  }

  /**
   * Validates access to DuplicateRunResult__c
   */
  private void validateAccess() {
    if (!Schema.sObjectType.DuplicateRunResult__c.isAccessible()) {
      throw new duplicateException('Access denied for DuplicateRunResult__c');
    }
  }

  /**
   * Validates access to DuplicateGroupDetail__c
   */
  private void validateGroupAccess() {
    if (!Schema.sObjectType.DuplicateGroupDetail__c.isAccessible()) {
      throw new duplicateException('Access denied for DuplicateGroupDetail__c');
    }
  }
}
