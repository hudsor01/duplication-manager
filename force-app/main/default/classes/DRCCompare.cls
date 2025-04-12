/**
 * Class for retrieving records for side-by-side comparison
 * @author Richard Hudson
 * @date 2025-04-11
 */
public class DRCCompare {
    /**
     * Static method for retrieving records for side-by-side comparison
     *
     * @param recordIds List of record IDs to compare
     * @param objectApiName API name of the object
     * @return Map containing records and metadata
     */
    @AuraEnabled
    public static Map<String, Object> getRecordsForComparison(List<String> recordIds, String objectApiName) {
        Map<String, Object> result = new Map<String, Object>();
        
        if (recordIds == null || recordIds.isEmpty()) {
            throw new AuraHandledException('Record IDs are required');
        }
        
        if (String.isBlank(objectApiName)) {
            // Try to determine object type from first ID
            try {
                Id firstId = Id.valueOf(recordIds[0]);
                objectApiName = String.valueOf(firstId.getSObjectType());
            } catch (Exception e) {
                throw new AuraHandledException('Object API name is required');
            }
        }
        
        try {
            // Get fields for the object
            Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
                .get(objectApiName).getDescribe().fields.getMap();
            
            // Build query
            Set<String> standardFields = new Set<String>{'Id', 'Name', 'CreatedDate', 'LastModifiedDate'};
            Set<String> fieldsToQuery = new Set<String>(standardFields);
            
            // Add all accessible fields (up to a limit)
            Integer fieldCount = 0;
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult describe = fieldMap.get(fieldName).getDescribe();
                if (describe.isAccessible()) {
                    fieldsToQuery.add(fieldName);
                    fieldCount++;
                    if (fieldCount > 100) {
                        break; // Limit to 100 fields to avoid query limits
                    }
                }
            }
            
            // Convert set to list for query
            List<String> fieldList = new List<String>(fieldsToQuery);
            
            // Build and execute query
            String query = 'SELECT ' + String.join(fieldList, ', ') + 
                          ' FROM ' + objectApiName + 
                          ' WHERE Id IN :recordIds';
            
            List<SObject> records = Database.query(query);
            
            // Return result
            result.put('records', records);
            result.put('objectApiName', objectApiName);
            result.put('fields', fieldList);
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error getting records for comparison: ' + e.getMessage());
        }
    }
}