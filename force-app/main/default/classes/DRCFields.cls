/**
 * @description Class for retrieving field metadata for an object
 * @author Richard Hudson
 * @date 2025-04-11
 */
public class DRCFields {
    /**
     * @description Static method for getting field metadata for an object organized into groups
     *
     * @param objectApiName API name of the object
     * @return Map containing field groups and metadata
     */
    @AuraEnabled
    public static Map<String, Object> getFieldsForObject(String objectApiName) {
        Map<String, Object> result = new Map<String, Object>();
        
        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException('Object API name is required');
        }
        
        try {
            // Get field map for the object
            Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
                .get(objectApiName).getDescribe().fields.getMap();
            
            // Define field groups
            List<Map<String, Object>> fieldGroups = new List<Map<String, Object>>();
            
            // Standard fields group
            Map<String, Object> standardGroup = new Map<String, Object>();
            standardGroup.put('label', 'Standard Fields');
            List<Map<String, Object>> standardFields = new List<Map<String, Object>>();
            
            // System fields group
            Map<String, Object> systemGroup = new Map<String, Object>();
            systemGroup.put('label', 'System Fields');
            List<Map<String, Object>> systemFields = new List<Map<String, Object>>();
            
            // Custom fields group
            Map<String, Object> customGroup = new Map<String, Object>();
            customGroup.put('label', 'Custom Fields');
            List<Map<String, Object>> customFields = new List<Map<String, Object>>();
            
            // Process each field
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                
                // Skip non-accessible fields
                if (!fieldDescribe.isAccessible()) {
                    continue;
                }
                
                // Create field info map
                Map<String, Object> fieldInfo = new Map<String, Object>();
                fieldInfo.put('apiName', fieldName);
                fieldInfo.put('label', fieldDescribe.getLabel());
                fieldInfo.put('type', fieldDescribe.getType().name());
                fieldInfo.put('isCustom', fieldDescribe.isCustom());
                
                // Categorize field
                if (fieldName.toLowerCase().endsWith('__c')) {
                    customFields.add(fieldInfo);
                } else if (fieldName.equals('Id') || fieldName.equals('CreatedDate') || 
                          fieldName.equals('LastModifiedDate') || fieldName.equals('CreatedById') || 
                          fieldName.equals('LastModifiedById') || fieldName.equals('SystemModstamp') || 
                          fieldName.equals('IsDeleted')) {
                    systemFields.add(fieldInfo);
                } else {
                    standardFields.add(fieldInfo);
                }
            }
            
            // Set fields in groups
            standardGroup.put('fields', standardFields);
            systemGroup.put('fields', systemFields);
            customGroup.put('fields', customFields);
            
            // Add groups to result
            fieldGroups.add(standardGroup);
            fieldGroups.add(customGroup);
            fieldGroups.add(systemGroup);
            
            // Set result
            result.put('objectApiName', objectApiName);
            result.put('fieldGroups', fieldGroups);
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error getting fields for object: ' + e.getMessage());
        }
    }
}