/**
 * Utility class for identifying and merging duplicate records
 *
 * @author Richard Hudson
 * @date April 2025
 */
public class DuplicateRecordUtility {
  /**
   * Creates a composite key for a record based on the specified fields
   *
   * @param record The SObject record to process
   * @param fields List of field API names to include in the key
   * @return A string key representing the normalized values of the fields
   */
  public static String createCompositeKey(SObject record, List<String> fields) {
    List<String> keyParts = new List<String>();

    for (String field : fields) {
      // Get field value, convert to lowercase string, and handle nulls
      Object fieldValue = record.get(field);
      String stringValue = '';

      if (fieldValue != null) {
        stringValue = String.valueOf(fieldValue).toLowerCase().trim();
      }

      keyParts.add(stringValue);
    }

    // Join all parts with a separator unlikely to appear in the data
    return String.join(keyParts, '|#|');
  }

  /**
   * Groups records by composite key to identify potential duplicates
   *
   * @param records List of SObject records to process
   * @param fields List of field API names to use for matching
   * @return Map of composite key to list of potential duplicate records
   */
  public static Map<String, List<SObject>> groupDuplicates(
    List<SObject> records,
    List<String> fields
  ) {
    Map<String, List<SObject>> duplicateGroups = new Map<String, List<SObject>>();

    for (SObject record : records) {
      String key = createCompositeKey(record, fields);

      if (!duplicateGroups.containsKey(key)) {
        duplicateGroups.put(key, new List<SObject>());
      }

      duplicateGroups.get(key).add(record);
    }

    // Filter to only groups with multiple records (actual duplicates)
    Map<String, List<SObject>> finalGroups = new Map<String, List<SObject>>();
    for (String key : duplicateGroups.keySet()) {
      if (duplicateGroups.get(key).size() > 1) {
        finalGroups.put(key, duplicateGroups.get(key));
      }
    }

    return finalGroups;
  }

  /**
   * Determines the master record from a group of duplicates based on strategy
   *
   * @param records List of duplicate records
   * @param strategy The strategy to use (OldestCreated, NewestCreated, MostComplete)
   * @return The record that should be used as the master
   */
  public static SObject determineMasterRecord(
    List<SObject> records,
    String strategy
  ) {
    if (records == null || records.isEmpty()) {
      return null;
    }

    // Clone the list to avoid modifying the original
    List<SObject> recordsToSort = new List<SObject>(records);

    if (strategy == 'OldestCreated') {
      // Sort by CreatedDate ascending
      List<SObjectWithCreatedDate> wrappers = new List<SObjectWithCreatedDate>();

      // Create wrapper objects
      for (SObject record : recordsToSort) {
        wrappers.add(new SObjectWithCreatedDate(record, true));
      }

      // Sort the wrappers
      wrappers.sort();

      // Return the first record (oldest)
      return wrappers[0].getRecord();
    } else if (strategy == 'NewestCreated') {
      // Sort by CreatedDate descending
      List<SObjectWithCreatedDate> wrappers = new List<SObjectWithCreatedDate>();

      // Create wrapper objects
      for (SObject record : recordsToSort) {
        wrappers.add(new SObjectWithCreatedDate(record, false));
      }

      // Sort the wrappers
      wrappers.sort();

      // Return the first record (newest)
      return wrappers[0].getRecord();
    } else if (strategy == 'MostComplete') {
      // Find record with most non-null fields
      SObject mostComplete = recordsToSort[0];
      Integer maxNonNullCount = countNonNullFields(mostComplete);

      for (Integer i = 1; i < recordsToSort.size(); i++) {
        SObject record = recordsToSort[i];
        Integer nonNullCount = countNonNullFields(record);

        if (nonNullCount > maxNonNullCount) {
          mostComplete = record;
          maxNonNullCount = nonNullCount;
        }
      }

      return mostComplete;
    }

    // Default to oldest created if strategy not recognized
    List<SObjectWithCreatedDate> wrappers = new List<SObjectWithCreatedDate>();
    for (SObject record : recordsToSort) {
      wrappers.add(new SObjectWithCreatedDate(record, true));
    }
    wrappers.sort();
    return wrappers[0].getRecord();
  }

  /**
   * Counts non-null fields in a record
   *
   * @param record The record to check
   * @return Number of fields with non-null values
   */
  private static Integer countNonNullFields(SObject record) {
    Integer count = 0;
    Map<String, Object> fieldsToValue = record.getPopulatedFieldsAsMap();

    for (String field : fieldsToValue.keySet()) {
      if (fieldsToValue.get(field) != null) {
        count++;
      }
    }

    return count;
  }

  /**
   * Creates a note on the master record documenting the merge
   *
   * @param masterId ID of the master record
   * @param duplicateIds List of IDs of duplicate records being merged
   * @return The ID of the created note
   */
  public static Id createMergeDocumentationNote(
    Id masterId,
    List<Id> duplicateIds
  ) {
    // Build note content
    String noteTitle = 'Record Merge Documentation';
    String noteBody = 'The following duplicate records were merged into this record:\n\n';

    for (Id dupeId : duplicateIds) {
      noteBody +=
        '- Record ID: ' +
        dupeId +
        ' (merged on ' +
        Datetime.now().format('yyyy-MM-dd HH:mm:ss') +
        ')\n';
    }

    // Create a standard Note
    Note note = new Note();
    note.Title = noteTitle;
    note.Body = noteBody;
    note.ParentId = masterId;

    insert note;

    return note.Id;
  }

  /**
   * Merges duplicate records into a master record
   *
   * @param objectApiName API name of the object type
   * @param masterId ID of the master record
   * @param duplicateIds List of IDs of duplicate records to merge
   * @return Number of successfully merged records
   */
  public static Integer mergeRecords(
    String objectApiName,
    Id masterId,
    List<Id> duplicateIds
  ) {
    return mergeRecords(masterId, duplicateIds);
  }

  /**
   * Merges duplicate records into a master record
   *
   * @param masterId ID of the master record
   * @param duplicateIds List of IDs of duplicate records to merge
   * @return Number of successfully merged records
   */
  public static Integer mergeRecords(Id masterId, List<Id> duplicateIds) {
    if (duplicateIds == null || duplicateIds.isEmpty()) {
      return 0;
    }

    // Create documentation before merge
    createMergeDocumentationNote(masterId, duplicateIds);

    // Get the SObject type from the ID
    Schema.SObjectType sot = masterId.getSobjectType();

    // Keep track of successful merges
    Integer mergeCount = 0;

    // Process each duplicate
    for (Id dupeId : duplicateIds) {
      try {
        // Create SObject instances for the merge
        SObject masterRecord = sot.newSObject(masterId);
        SObject duplicateRecord = sot.newSObject(dupeId);

        // Perform the merge
        Database.merge(masterRecord, duplicateRecord);
        mergeCount++;
      } catch (Exception e) {
        System.debug(
          'Error merging records: Master=' +
            masterId +
            ', Duplicate=' +
            dupeId +
            '. Error: ' +
            e.getMessage()
        );
      }
    }

    return mergeCount;
  }

  /**
   * Wrapper class for SObject that implements Comparable interface
   * for sorting by CreatedDate
   */
  private class SObjectWithCreatedDate implements Comparable {
    private SObject record;
    private Boolean ascending;

    public SObjectWithCreatedDate(SObject record, Boolean ascending) {
      this.record = record;
      this.ascending = ascending;
    }

    public SObject getRecord() {
      return this.record;
    }

    public Integer compareTo(Object compareTo) {
      SObjectWithCreatedDate other = (SObjectWithCreatedDate) compareTo;

      Datetime date1 = (Datetime) this.record.get('CreatedDate');
      Datetime date2 = (Datetime) other.record.get('CreatedDate');

      if (date1 == date2)
        return 0;

      if (ascending) {
        return date1 > date2 ? 1 : -1;
      } else {
        return date1 < date2 ? 1 : -1;
      }
    }
  }
}
