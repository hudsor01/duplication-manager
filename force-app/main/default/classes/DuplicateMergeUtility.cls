/**
 * Utility class for merging duplicate records
 *
 * @author Richard Hudson
 * @date April 2025
 */
public class DuplicateMergeUtility {
  /**
   * Merges a group of duplicate records
   *
   * @param duplicateGroup The duplicate group to merge
   * @param masterRecordStrategy Strategy for selecting master record
   * @return Result containing merge statistics
   */
  public static MergeResult mergeGroup(
    DuplicateMatcherUtility.DuplicateGroup duplicateGroup,
    String masterRecordStrategy
  ) {
    // Skip if no duplicates
    if (duplicateGroup.getRecordCount() <= 1) {
      return new MergeResult(0, 'No duplicates to merge');
    }

    // Get master record - for DuplicateMatcherUtility.DuplicateGroup, we need to select the first record as master
    SObject masterRecord = duplicateGroup.records[0];
    if (masterRecord == null) {
      return new MergeResult(0, 'Could not determine master record');
    }

    // Get duplicate IDs - collect IDs from all records except master
    List<Id> duplicateIds = new List<Id>();
    for (Integer i = 1; i < duplicateGroup.records.size(); i++) {
      duplicateIds.add(duplicateGroup.records[i].Id);
    }

    if (duplicateIds.isEmpty()) {
      return new MergeResult(0, 'No duplicates to merge');
    }

    // Perform the merge
    return mergeRecords(masterRecord.Id, duplicateIds);
  }

  /**
   * Merges duplicate records into a master record
   *
   * @param masterId ID of the master record
   * @param duplicateIds List of IDs of duplicate records to merge
   * @return Result containing merge statistics
   */
  public static MergeResult mergeRecords(Id masterId, List<Id> duplicateIds) {
    if (duplicateIds == null || duplicateIds.isEmpty()) {
      return new MergeResult(0, 'No duplicates to merge');
    }

    // Create documentation before merge
    try {
      createMergeDocumentationNote(masterId, duplicateIds);
    } catch (Exception e) {
      System.debug('Error creating merge documentation: ' + e.getMessage());
      // Continue with merge even if documentation fails
    }

    // Get the SObject type from the ID
    Schema.SObjectType sot = masterId.getSobjectType();

    // Keep track of successful merges
    Integer mergeCount = 0;
    List<String> errors = new List<String>();

    // Process duplicates in batches to avoid governor limits
    List<List<Id>> batches = batchIds(duplicateIds, 100);

    for (List<Id> batch : batches) {
      try {
        // Create SObject instances for the merge
        SObject masterRecord = sot.newSObject(masterId);

        for (Id dupeId : batch) {
          try {
            SObject duplicateRecord = sot.newSObject(dupeId);
            Database.merge(masterRecord, duplicateRecord);
            mergeCount++;
          } catch (Exception e) {
            String errorMsg = 'Error merging ' + dupeId + ': ' + e.getMessage();
            errors.add(errorMsg);
            System.debug(errorMsg);
          }
        }
      } catch (Exception e) {
        String errorMsg = 'Error processing batch: ' + e.getMessage();
        errors.add(errorMsg);
        System.debug(errorMsg);
      }
    }

    // Return results
    MergeResult result = new MergeResult(mergeCount, 'Merge completed');
    result.errors.addAll(errors);
    return result;
  }

  /**
   * Creates a detailed note on the master record documenting the merge with field conflicts
   *
   * @param masterId ID of the master record
   * @param duplicateIds List of IDs of duplicate records being merged
   * @return The ID of the created note
   */
  private static Id createMergeDocumentationNote(
    Id masterId,
    List<Id> duplicateIds
  ) {
    try {
      // Get the SObject type from the ID
      Schema.SObjectType sot = masterId.getSobjectType();
      String objectType = sot.getDescribe().getName();

      // Build note content
      String noteTitle = 'Record Merge Documentation';
      String noteBody = 'MERGE SUMMARY\n';
      noteBody += '============\n';
      noteBody += '- Master Record: ' + masterId + '\n';
      noteBody += '- Object Type: ' + objectType + '\n';
      noteBody +=
        '- Merged On: ' +
        Datetime.now().format('yyyy-MM-dd HH:mm:ss') +
        '\n';
      noteBody +=
        '- Performed By: ' +
        UserInfo.getName() +
        ' (' +
        UserInfo.getUserId() +
        ')\n\n';

      noteBody += 'MERGED RECORDS\n';
      noteBody += '==============\n';
      for (Id dupeId : duplicateIds) {
        noteBody += '- ' + dupeId + '\n';
      }

      // Get field data for the master and duplicates
      Map<String, Object> fieldData = getRecordFieldData(
        masterId,
        duplicateIds,
        objectType
      );
      List<Map<String, Object>> conflicts = getFieldConflicts(fieldData);

      // Add conflict information if any exists
      if (!conflicts.isEmpty()) {
        noteBody += '\nFIELD CONFLICTS\n';
        noteBody += '===============\n';
        noteBody += 'The following fields had different values that needed resolution:\n\n';

        for (Map<String, Object> conflict : conflicts) {
          String fieldName = (String) conflict.get('field');
          String fieldLabel = (String) conflict.get('fieldLabel');
          Object masterValue = conflict.get('masterValue');
          Object duplicateValue = conflict.get('dupValue');
          Id duplicateId = (Id) conflict.get('dupRecordId');

          noteBody += fieldLabel + ' (' + fieldName + '):\n';
          noteBody += '  - Master Value: ' + formatValue(masterValue) + '\n';
          noteBody +=
            '  - Duplicate Value: ' +
            formatValue(duplicateValue) +
            ' (from ' +
            duplicateId +
            ')\n';
          noteBody += '  - KEPT VALUE: ' + formatValue(masterValue) + '\n\n';
        }
      }

      // Add non-conflicting data that was lost
      List<Map<String, Object>> nonMergeableData = getNonMergeableData(
        fieldData
      );
      if (!nonMergeableData.isEmpty()) {
        noteBody += '\nADDITIONAL DATA NOT MERGED\n';
        noteBody += '=========================\n';
        noteBody += 'The following data existed only in duplicate records and was not merged:\n\n';

        for (Map<String, Object> data : nonMergeableData) {
          String fieldName = (String) data.get('field');
          String fieldLabel = (String) data.get('fieldLabel');
          Object value = data.get('value');
          Id duplicateId = (Id) data.get('dupRecordId');

          noteBody += fieldLabel + ' (' + fieldName + '):\n';
          noteBody +=
            '  - Value: ' +
            formatValue(value) +
            ' (from ' +
            duplicateId +
            ')\n\n';
        }
      }

      // Use the DRCNote class to create the note
      if (!DRCNote.createNote(masterId, noteTitle, noteBody)) {
        System.debug(
          LoggingLevel.ERROR,
          'Failed to create merge documentation note'
        );

        // Fallback to direct creation if DRCNote fails
        if (
          Schema.sObjectType.Note.isCreateable() &&
          Schema.sObjectType.Note.fields.Title.isCreateable() &&
          Schema.sObjectType.Note.fields.Body.isCreateable() &&
          Schema.sObjectType.Note.fields.ParentId.isCreateable()
        ) {
          Note note = new Note();
          note.Title = noteTitle;
          note.Body = noteBody;
          note.ParentId = masterId;
          insert note;
          return note.Id;
        }
      } else {
        // Note created successfully via DRCNote
        return null; // We don't have the ID when using DRCNote
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error creating merge documentation note: ' + e.getMessage()
      );
    }

    return null;
  }

  /**
   * Formats a value for display in notes
   *
   * @param value The value to format
   * @return Formatted string representation
   */
  private static String formatValue(Object value) {
    if (value == null) {
      return '(null)';
    }

    if (value instanceof Datetime) {
      return ((Datetime) value).format('yyyy-MM-dd HH:mm:ss');
    } else if (value instanceof Date) {
      return String.valueOf(value);
    } else if (value instanceof Boolean) {
      return (Boolean) value ? 'True' : 'False';
    } else if (value instanceof Blob) {
      return '(Binary Data)';
    } else if (value instanceof String && String.isEmpty((String) value)) {
      return '(empty string)';
    }

    return String.valueOf(value);
  }

  /**
   * Retrieves field data for master and duplicate records for conflict detection
   *
   * @param masterId ID of the master record
   * @param duplicateIds List of IDs of duplicate records
   * @param objectType API name of the object type
   * @return Map containing record data
   */
  private static Map<String, Object> getRecordFieldData(
    Id masterId,
    List<Id> duplicateIds,
    String objectType
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      // Get field map for the object
      Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
        .get(objectType)
        .getDescribe()
        .fields.getMap();

      // Get all accessible fields
      Set<String> fieldsToQuery = new Set<String>();
      Map<String, String> fieldLabels = new Map<String, String>();

      for (String fieldName : fieldMap.keySet()) {
        Schema.DescribeFieldResult describe = fieldMap.get(fieldName)
          .getDescribe();
        if (describe.isAccessible()) {
          fieldsToQuery.add(fieldName);
          fieldLabels.put(fieldName, describe.getLabel());
        }
      }

      // Convert to list for query
      List<String> fieldList = new List<String>(fieldsToQuery);

      // Query all records
      List<Id> allIds = new List<Id>{ masterId };
      allIds.addAll(duplicateIds);

      // Secure query building
      String fields = String.join(fieldList, ', ');
      String queryObject = String.escapeSingleQuotes(objectType);
      String query =
        'SELECT ' +
        fields +
        ' FROM ' +
        queryObject +
        ' WHERE Id IN :allIds WITH SECURITY_ENFORCED';

      // Query the records
      List<SObject> records = Database.query(query);

      // Find master record and duplicates
      SObject masterRecord = null;
      List<SObject> dupRecords = new List<SObject>();

      for (SObject record : records) {
        if (record.Id == masterId) {
          masterRecord = record;
        } else {
          dupRecords.add(record);
        }
      }

      // Store results
      result.put('masterRecord', masterRecord);
      result.put('duplicateRecords', dupRecords);
      result.put('fieldMap', fieldMap);
      result.put('fieldLabels', fieldLabels);

      return result;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error getting record field data: ' + e.getMessage()
      );
      return result;
    }
  }

  /**
   * Identifies field conflicts between master and duplicate records
   *
   * @param fieldData Map containing record data from getRecordFieldData
   * @return List of conflict information
   */
  private static List<Map<String, Object>> getFieldConflicts(
    Map<String, Object> fieldData
  ) {
    List<Map<String, Object>> conflicts = new List<Map<String, Object>>();

    try {
      // Extract data from field data map
      SObject masterRecord = (SObject) fieldData.get('masterRecord');
      List<SObject> dupRecords = (List<SObject>) fieldData.get(
        'duplicateRecords'
      );
      Map<String, Schema.SObjectField> fieldMap = (Map<String, Schema.SObjectField>) fieldData.get(
        'fieldMap'
      );
      Map<String, String> fieldLabels = (Map<String, String>) fieldData.get(
        'fieldLabels'
      );

      if (
        masterRecord == null ||
        dupRecords == null ||
        dupRecords.isEmpty() ||
        fieldMap == null
      ) {
        return conflicts;
      }

      // Check each duplicate record for conflicts
      for (SObject dupRecord : dupRecords) {
        for (String fieldName : fieldMap.keySet()) {
          // Skip system fields
          if (
            fieldName == 'Id' ||
            fieldName == 'IsDeleted' ||
            fieldName == 'SystemModstamp'
          ) {
            continue;
          }

          Object masterValue = masterRecord.get(fieldName);
          Object dupValue = dupRecord.get(fieldName);

          // Check if field has a value in duplicate that differs from master
          if (
            dupValue != null &&
            masterValue != null &&
            dupValue != masterValue
          ) {
            Map<String, Object> conflict = new Map<String, Object>();
            conflict.put('field', fieldName);
            conflict.put(
              'fieldLabel',
              fieldLabels.containsKey(fieldName)
                ? fieldLabels.get(fieldName)
                : fieldName
            );
            conflict.put('masterValue', masterValue);
            conflict.put('dupValue', dupValue);
            conflict.put('dupRecordId', dupRecord.Id);
            conflicts.add(conflict);
          }
        }
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error identifying field conflicts: ' + e.getMessage()
      );
    }

    return conflicts;
  }

  /**
   * Identifies non-mergeable data (data that exists only in duplicate records)
   *
   * @param fieldData Map containing record data from getRecordFieldData
   * @return List of non-mergeable data information
   */
  private static List<Map<String, Object>> getNonMergeableData(
    Map<String, Object> fieldData
  ) {
    List<Map<String, Object>> nonMergeableData = new List<Map<String, Object>>();

    try {
      // Extract data from field data map
      SObject masterRecord = (SObject) fieldData.get('masterRecord');
      List<SObject> dupRecords = (List<SObject>) fieldData.get(
        'duplicateRecords'
      );
      Map<String, Schema.SObjectField> fieldMap = (Map<String, Schema.SObjectField>) fieldData.get(
        'fieldMap'
      );
      Map<String, String> fieldLabels = (Map<String, String>) fieldData.get(
        'fieldLabels'
      );

      if (
        masterRecord == null ||
        dupRecords == null ||
        dupRecords.isEmpty() ||
        fieldMap == null
      ) {
        return nonMergeableData;
      }

      // Check each duplicate record for data that exists only in the duplicate
      for (SObject dupRecord : dupRecords) {
        for (String fieldName : fieldMap.keySet()) {
          // Skip system fields
          if (
            fieldName == 'Id' ||
            fieldName == 'IsDeleted' ||
            fieldName == 'SystemModstamp'
          ) {
            continue;
          }

          Object masterValue = masterRecord.get(fieldName);
          Object dupValue = dupRecord.get(fieldName);

          // Check for data that exists only in duplicate record
          if (
            dupValue != null &&
            (masterValue == null ||
            (masterValue instanceof String &&
            String.isBlank((String) masterValue)))
          ) {
            Map<String, Object> nonMergeable = new Map<String, Object>();
            nonMergeable.put('field', fieldName);
            nonMergeable.put(
              'fieldLabel',
              fieldLabels.containsKey(fieldName)
                ? fieldLabels.get(fieldName)
                : fieldName
            );
            nonMergeable.put('value', dupValue);
            nonMergeable.put('dupRecordId', dupRecord.Id);
            nonMergeableData.add(nonMergeable);
          }
        }
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error identifying non-mergeable data: ' + e.getMessage()
      );
    }

    return nonMergeableData;
  }

  /**
   * Splits a list of IDs into batches
   *
   * @param ids List of IDs to batch
   * @param batchSize Size of each batch
   * @return List of ID batches
   */
  private static List<List<Id>> batchIds(List<Id> ids, Integer batchSize) {
    List<List<Id>> batches = new List<List<Id>>();

    Integer batchCount = (ids.size() + batchSize - 1) / batchSize;
    for (Integer i = 0; i < batchCount; i++) {
      Integer startIndex = i * batchSize;
      Integer endIndex = Math.min(startIndex + batchSize, ids.size());

      // Create a new batch and add the relevant IDs
      List<Id> batch = new List<Id>();
      for (Integer j = startIndex; j < endIndex; j++) {
        batch.add(ids[j]);
      }
      batches.add(batch);
    }

    return batches;
  }

  /**
   * Class to encapsulate merge operation results
   */
  public class MergeResult {
    public Integer recordsMerged { get; private set; }
    public String message { get; private set; }
    public List<String> errors { get; private set; }
    public Datetime timestamp { get; private set; }

    /**
     * Constructor
     *
     * @param recordsMerged Number of records merged
     * @param message Result message
     */
    public MergeResult(Integer recordsMerged, String message) {
      this.recordsMerged = recordsMerged;
      this.message = message;
      this.errors = new List<String>();
      this.timestamp = Datetime.now();
    }

    /**
     * Check if there were any errors
     *
     * @return True if there were errors
     */
    public Boolean hasErrors() {
      return !this.errors.isEmpty();
    }

    /**
     * Get error count
     *
     * @return Number of errors
     */
    public Integer getErrorCount() {
      return this.errors.size();
    }
  }
}
