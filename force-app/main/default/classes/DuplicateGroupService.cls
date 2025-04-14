/**
 * Service class for duplicate Groups
 * Handles duplicate group operations
 *
 * @author Richard Hudson
 * @date April 2025
 */
public with sharing class DuplicateGroupService {
  /**
   * Get duplicate groups for a run result
   * @param runResultId ID of the run result
   * @return List of duplicate group information
   */
  public static List<DuplicateGroupInfo> getDuplicateGroupsForResult(
    String runResultId
  ) {
    List<DuplicateGroupInfo> result = new List<DuplicateGroupInfo>();

    try {
      // Query duplicate groups
      List<DuplicateGroupDetail__c> groups = [
        SELECT
          Id,
          GroupKey__c,
          ObjectName__c,
          RecordCount__c,
          MasterRecordId__c,
          DuplicateRecordIds__c,
          MatchScore__c,
          FieldValues__c,
          DuplicateRunResult__c
        FROM DuplicateGroupDetail__c
        WHERE DuplicateRunResult__c = :runResultId
        ORDER BY RecordCount__c DESC, MatchScore__c DESC
      ];

      // Convert to info objects
      for (DuplicateGroupDetail__c grpRecord : groups) {
        // Parse record IDs
        List<String> recordIds = new List<String>();

        if (String.isNotBlank(grpRecord.DuplicateRecordIds__c)) {
          recordIds = grpRecord.DuplicateRecordIds__c.split(',');
        }

        // Parse field values
        Map<String, Object> fieldValues = new Map<String, Object>();

        if (String.isNotBlank(grpRecord.FieldValues__c)) {
          try {
            fieldValues = (Map<String, Object>) JSON.deserializeUntyped(
              grpRecord.FieldValues__c
            );
          } catch (Exception e) {
            System.debug(
              LoggingLevel.ERROR,
              'Error parsing field values: ' + e.getMessage()
            );
          }
        }

        // Create info object
        DuplicateGroupInfo info = new DuplicateGroupInfo(
          grpRecord.Id,
          grpRecord.GroupKey__c,
          grpRecord.ObjectName__c,
          Integer.valueOf(grpRecord.RecordCount__c),
          grpRecord.MasterRecordId__c,
          recordIds,
          grpRecord.MatchScore__c,
          fieldValues
        );

        result.add(info);
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error getting duplicate groups: ' + e.getMessage()
      );
      throw e;
    }

    return result;
  }

  /**
   * Create a duplicate group record
   * @param objectName API name of the object
   * @param groupKey Key identifying the group
   * @param masterRecordId ID of the master record
   * @param duplicateRecordIds IDs of duplicate records
   * @param matchScore Score of the match
   * @param fieldValues Map of field values for the group
   * @param runResultId ID of the run result
   * @return ID of the created group record
   */
  public static Id createDuplicateGroup(
    String objectName,
    String groupKey,
    Id masterRecordId,
    List<Id> duplicateRecordIds,
    Decimal matchScore,
    Map<String, Object> fieldValues,
    Id runResultId
  ) {
    try {
      // Create group record
      DuplicateGroupDetail__c grpRecord = new DuplicateGroupDetail__c(
        ObjectName__c = objectName,
        GroupKey__c = groupKey,
        MasterRecordId__c = masterRecordId,
        DuplicateRecordIds__c = String.join(duplicateRecordIds, ','),
        RecordCount__c = duplicateRecordIds.size() + 1, // Include master
        MatchScore__c = matchScore,
        FieldValues__c = JSON.serialize(fieldValues),
        DuplicateRunResult__c = runResultId
      );

      insert grpRecord;
      return grpRecord.Id;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error creating duplicate group: ' + e.getMessage()
      );
      throw e;
    }
  }

  /**
   * Class to hold duplicate group information
   */
  public class DuplicateGroupInfo {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String groupKey;
    @AuraEnabled
    public String objectName;
    @AuraEnabled
    public Integer recordCount;
    @AuraEnabled
    public String masterId;
    @AuraEnabled
    public List<String> duplicateIds;
    @AuraEnabled
    public Decimal matchScore;
    @AuraEnabled
    public Map<String, Object> fieldValues;

    public DuplicateGroupInfo(
      String id,
      String groupKey,
      String objectName,
      Integer recordCount,
      String masterId,
      List<String> duplicateIds,
      Decimal matchScore,
      Map<String, Object> fieldValues
    ) {
      this.id = id;
      this.groupKey = groupKey;
      this.objectName = objectName;
      this.recordCount = recordCount;
      this.masterId = masterId;
      this.duplicateIds = duplicateIds;
      this.matchScore = matchScore;
      this.fieldValues = fieldValues;
    }
  }
}
