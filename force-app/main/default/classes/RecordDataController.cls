/**
 * Controller for retrieving record data
 *
 * @author Richard Hudson
 * @date 2025-04-11
 */
public with sharing class RecordDataController {

    /**
     * Get data for a specific record with field list
     * @param recordId ID of the record to retrieve
     * @param fields List of fields to retrieve (in format ObjectApiName.FieldName)
     * @return Map containing record data
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getRecordData(String recordId, List<String> fields) {
        try {
            // Validate parameters
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }

            if (fields == null || fields.isEmpty()) {
                throw new AuraHandledException('At least one field must be specified');
            }

            // Get the object type from the record ID
            String objectApiName = getObjectApiName(recordId);

            // Extract field names from fully qualified field names
            List<String> fieldNames = new List<String>();
            for (String field : fields) {
                // If the field contains a dot, extract the field name part
                if (field.contains('.')) {
                    fieldNames.add(field.substringAfter('.'));
                } else {
                    fieldNames.add(field);
                }
            }

            // Make sure ID is included
            if (!fieldNames.contains('Id')) {
                fieldNames.add('Id');
            }

            // Build and execute the query
            String query = 'SELECT ' + String.join(fieldNames, ', ') +
                          ' FROM ' + objectApiName +
                          ' WHERE Id = :recordId';

            // Improved error handling around query execution
            SObject record;
            try {
                List<SObject> records = Database.query(query);
                if (records.isEmpty()) {
                    throw new AuraHandledException('No record found with ID: ' + recordId);
                }
                record = records[0];
            } catch (QueryException qe) {
                throw new AuraHandledException('Query error: ' + qe.getMessage());
            } catch (Exception e) {
                throw new AuraHandledException('Error retrieving record: ' + e.getMessage());
            }

            // Convert to a map structure for LWC
            Map<String, Object> result = new Map<String, Object>();
            result.put('id', record.Id);

            // Add fields data
            Map<String, Object> fieldsMap = new Map<String, Object>();

            for (String fieldName : fieldNames) {
                // Skip system fields
                if (fieldName == 'Id') continue;

                Object fieldValue = record.get(fieldName);

                // Skip null values
                if (fieldValue == null) continue;

                // Add to fields map
                Map<String, Object> fieldData = new Map<String, Object>();
                fieldData.put('value', fieldValue);

                // For string values, display value is the same as value
                if (fieldValue instanceof String) {
                    fieldData.put('displayValue', fieldValue);
                } else {
                    // For other types, convert to string
                    fieldData.put('displayValue', String.valueOf(fieldValue));
                }

                fieldsMap.put(fieldName, fieldData);
            }

            result.put('fields', fieldsMap);

            return result;

        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving record data: ' + e.getMessage());
        }
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
}
