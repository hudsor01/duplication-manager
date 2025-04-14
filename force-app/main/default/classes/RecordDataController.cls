/**
 * Controller for retrieving record data
 *
 * @author Richard Hudson
 * @date 2025-04-11
 */
public with sharing class RecordDataController {
  /**
   * @description Retrieves record data as a map structure for LWC.
   * @param recordId ID of the record to retrieve
   * @param requestedFields List of fields to retrieve (in format ObjectApiName.FieldName)
   * @return Map containing record data
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getRecordData(
    String recordId,
    List<String> requestedFields
  ) {
    if (String.isBlank(recordId)) {
      throw new AuraHandledException('Record ID is required');
    }
    if (requestedFields == null || requestedFields.isEmpty()) {
      throw new AuraHandledException('At least one field must be specified');
    }

    String objectApiName = getObjectApiName(recordId);

    List<String> fieldNames = new List<String>();
    for (String field : requestedFields) {
      if (field.contains('.')) {
        fieldNames.add(field.substringAfter('.'));
      } else {
        fieldNames.add(field);
      }
    }
    if (!fieldNames.contains('Id')) {
      fieldNames.add('Id');
    }

    List<String> safeFieldNames = getSafeFieldNames(objectApiName, fieldNames);

    String query =
      'SELECT ' +
      String.join(safeFieldNames, ', ') +
      ' FROM ' +
      objectApiName +
      ' WHERE Id = :recordId';

    SObject record = queryRecord(query, recordId);

    return buildResultMap(record, safeFieldNames);
  }

  /**
   * Get object API name from record ID
   * @param recordId ID of the record
   * @return API name of the object
   */
  private static String getObjectApiName(String recordId) {
    Id recordIdObj = Id.valueOf(recordId);
    return recordIdObj.getSObjectType().getDescribe().getName();
  }

  private static List<String> getSafeFieldNames(
    String objectApiName,
    List<String> fieldNames
  ) {
    Schema.SObjectType sobjectType = Schema.getGlobalDescribe()
      .get(objectApiName);
    Map<String, Schema.SObjectField> validFieldMap = sobjectType.getDescribe()
      .fields.getMap();
    List<String> safeNames = new List<String>();
    for (String fieldName : fieldNames) {
      if (validFieldMap.containsKey(fieldName)) {
        safeNames.add(fieldName);
      }
    }
    if (safeNames.isEmpty()) {
      throw new AuraHandledException('No valid fields specified.');
    }
    return safeNames;
  }

  private static SObject queryRecord(String query, String recordId) {
    try {
      List<SObject> records = Database.query(query);
      if (records.isEmpty()) {
        throw new AuraHandledException('No record found with ID: ' + recordId);
      }
      return records[0];
    } catch (QueryException qe) {
      throw new AuraHandledException('Query error: ' + qe.getMessage());
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error retrieving record: ' + e.getMessage()
      );
    }
  }

  private static Map<String, Object> buildResultMap(
    SObject record,
    List<String> safeFieldNames
  ) {
    Map<String, Object> result = new Map<String, Object>();
    result.put('id', record.get('Id'));
    Map<String, Object> fieldsMap = new Map<String, Object>();
    for (String fieldName : safeFieldNames) {
      if (fieldName == 'Id') {
        continue;
      }
      Object fieldValue = record.get(fieldName);
      if (fieldValue == null) {
        continue;
      }
      Map<String, Object> fieldData = new Map<String, Object>();
      fieldData.put('value', fieldValue);
      if (fieldValue instanceof String) {
        fieldData.put('displayValue', fieldValue);
      } else {
        fieldData.put('displayValue', String.valueOf(fieldValue));
      }
      fieldsMap.put(fieldName, fieldData);
    }
    result.put('fields', fieldsMap);
    return result;
  }
}
