/**
 * Controller for retrieving metadata about objects and fields
 * @author Richard Hudson
 * @date 2025-04-11
 */
public with sharing class MetadataController {
    
    /**
     * Get object info including fields and relationships
     * @param objectApiName API name of the object
     * @return Map containing object metadata information
     */
    @AuraEnabled
    public static Map<String, Object> getObjectInfo(String objectApiName) {
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            // Get global describe to get the object info
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            Schema.SObjectType objectType = globalDescribe.get(objectApiName);
            
            if (objectType == null) {
                throw new AuraHandledException('Object not found: ' + objectApiName);
            }
            
            // Get object describe
            Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
            
            // Build object info
            result.put('apiName', objectApiName);
            result.put('label', objectDescribe.getLabel());
            result.put('labelPlural', objectDescribe.getLabelPlural());
            result.put('isCustom', objectDescribe.isCustom());
            
            // Get fields
            Map<String, Object> fieldsMap = new Map<String, Object>();
            Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
            
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                
                Map<String, Object> fieldInfo = new Map<String, Object>();
                fieldInfo.put('apiName', fieldName);
                fieldInfo.put('label', fieldDescribe.getLabel());
                fieldInfo.put('type', fieldDescribe.getType().name());
                fieldInfo.put('isCustom', fieldDescribe.isCustom());
                fieldInfo.put('required', !fieldDescribe.isNillable() && !fieldDescribe.isDefaultedOnCreate());
                fieldInfo.put('updateable', fieldDescribe.isUpdateable());
                
                fieldsMap.put(fieldName, fieldInfo);
            }
            
            result.put('fields', fieldsMap);
            
            // Get child relationships
            List<Map<String, Object>> childRelationships = new List<Map<String, Object>>();
            for (Schema.ChildRelationship rel : objectDescribe.getChildRelationships()) {
                if (rel.getRelationshipName() != null) {
                    Map<String, Object> relInfo = new Map<String, Object>();
                    relInfo.put('relationshipName', rel.getRelationshipName());
                    relInfo.put('childObject', String.valueOf(rel.getChildSObject()));
                    relInfo.put('childObjectLabel', rel.getChildSObject().getDescribe().getLabel());
                    relInfo.put('field', String.valueOf(rel.getField()));
                    
                    childRelationships.add(relInfo);
                }
            }
            
            result.put('childRelationships', childRelationships);
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving object info: ' + e.getMessage());
        }
    }
}