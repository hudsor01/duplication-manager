/**
 * @description Class for previewing merge results without performing the merge
 * @author Richard Hudson
 * @date 2025-04-11
 */
public with sharing class DMUPreview {
    /**
     * @description Static method for previewing the result of merging records without actually performing the merge
     *
     * @param request Map containing merge parameters (masterId, duplicateIds, objectApiName, fieldSelections)
     * @return Map containing the preview of the merged record
     */
    @AuraEnabled
    public static Map<String, Object> previewMergeResults(Map<String, Object> request) {
        Map<String, Object> result = new Map<String, Object>();
        
        // Extract request parameters
        String masterId = (String)request.get('masterId');
        List<String> duplicateIds = (List<String>)request.get('duplicateIds');
        String objectApiName = (String)request.get('objectApiName');
        Map<String, String> fieldSelections = (Map<String, String>)request.get('fieldSelections');
        
        if (String.isBlank(masterId)) {
            throw new AuraHandledException('Master record ID is required');
        }
        
        if (duplicateIds == null || duplicateIds.isEmpty()) {
            throw new AuraHandledException('Duplicate record IDs are required');
        }
        
        if (String.isBlank(objectApiName)) {
            // Try to determine from master ID
            try {
                Id masterIdObj = Id.valueOf(masterId);
                objectApiName = String.valueOf(masterIdObj.getSObjectType());
            } catch (Exception e) {
                throw new AuraHandledException('Object API name is required');
            }
        }
        
        if (fieldSelections == null) {
            fieldSelections = new Map<String, String>();
        }
        
        try {
            // Get field map for the object
            Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
                .get(objectApiName).getDescribe().fields.getMap();
            
            // Get all fields for the object
            Set<String> fieldsToQuery = new Set<String>();
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult describe = fieldMap.get(fieldName).getDescribe();
                if (describe.isAccessible()) {
                    fieldsToQuery.add(fieldName);
                }
            }
            
            // Convert to list for query
            List<String> fieldList = new List<String>(fieldsToQuery);
            
            // Query all records
            List<Id> allIds = new List<Id>{ Id.valueOf(masterId) };
            for (String dupId : duplicateIds) {
                allIds.add(Id.valueOf(dupId));
            }
            
            // Use schema describe call to confirm valid object API name
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
            if (objectType == null) {
                throw new AuraHandledException('Invalid object API name: ' + objectApiName);
            }
            
            // Secure query building - no SOQL injection possible because:
            // 1. fieldList is built from describe calls, not user input
            // 2. objectApiName is validated against Schema.getGlobalDescribe()
            // 3. allIds are converted to Id type
            String fields = String.join(fieldList, ', ');
            String queryObject = String.escapeSingleQuotes(objectApiName);
            String query = 'SELECT ' + fields + 
                          ' FROM ' + queryObject + 
                          ' WHERE Id IN :allIds';
            
            // Since all variables are secured and Id list is type-safe
            // Add security enforcement to the query
            List<SObject> records = Database.query(query + ' WITH SECURITY_ENFORCED');
            
            // Find master record
            SObject masterRecord = null;
            List<SObject> dupRecords = new List<SObject>();
            
            for (SObject record : records) {
                if (record.Id == masterId) {
                    masterRecord = record;
                } else {
                    dupRecords.add(record);
                }
            }
            
            if (masterRecord == null) {
                throw new AuraHandledException('Master record not found');
            }
            
            // Create preview record - start with master record
            SObject previewRecord = masterRecord.clone(true, true, true, true);
            
            // Track conflicts and data that won't be included in the merge
            List<Map<String, Object>> conflicts = new List<Map<String, Object>>();
            List<Map<String, Object>> nonMergeableData = new List<Map<String, Object>>();
            String noteContents = 'Data preserved from merged records:\n\n';
            
            // Apply field selections
            for (String fieldName : fieldSelections.keySet()) {
                String selectedRecordId = fieldSelections.get(fieldName);
                
                if (String.isBlank(selectedRecordId)) {
                    continue;
                }
                
                // Find the record with the selected ID
                for (SObject record : records) {
                    if (record.Id == selectedRecordId) {
                        Object fieldValue = record.get(fieldName);
                        if (fieldValue != null) {
                            previewRecord.put(fieldName, fieldValue);
                        }
                        break;
                    }
                }
            }
            
            // Identify conflicts and non-mergeable data
            for (SObject dupRecord : dupRecords) {
                for (String fieldName : fieldMap.keySet()) {
                    // Skip system fields
                    if (fieldName == 'Id' || fieldName == 'IsDeleted' || fieldName == 'SystemModstamp') {
                        continue;
                    }
                    
                    Object masterValue = masterRecord.get(fieldName);
                    Object dupValue = dupRecord.get(fieldName);
                    
                    // Check if field has a value in duplicate that differs from master
                    if (dupValue != null && masterValue != null && dupValue != masterValue) {
                        // Check if this is a conflict that needs resolution
                        if (!fieldSelections.containsKey(fieldName)) {
                            Map<String, Object> conflict = new Map<String, Object>();
                            conflict.put('field', fieldName);
                            conflict.put('fieldLabel', fieldMap.get(fieldName).getDescribe().getLabel());
                            conflict.put('masterValue', masterValue);
                            conflict.put('dupValue', dupValue);
                            conflict.put('dupRecordId', dupRecord.Id);
                            conflicts.add(conflict);
                            
                            // Add to note contents
                            noteContents += fieldMap.get(fieldName).getDescribe().getLabel() + 
                                          ': ' + dupValue + ' (from record ' + dupRecord.Id + ')\n';
                        }
                    }
                    
                    // Check for data that exists only in duplicate record
                    if (dupValue != null && (masterValue == null || masterValue == '') && 
                        !fieldSelections.containsKey(fieldName)) {
                        Map<String, Object> nonMergeable = new Map<String, Object>();
                        nonMergeable.put('field', fieldName);
                        nonMergeable.put('fieldLabel', fieldMap.get(fieldName).getDescribe().getLabel());
                        nonMergeable.put('value', dupValue);
                        nonMergeable.put('dupRecordId', dupRecord.Id);
                        nonMergeableData.add(nonMergeable);
                        
                        // Add to note contents
                        noteContents += fieldMap.get(fieldName).getDescribe().getLabel() + 
                                      ': ' + dupValue + ' (from record ' + dupRecord.Id + ')\n';
                    }
                }
            }
            
            // Build field data for UI
            List<Map<String, Object>> fieldData = new List<Map<String, Object>>();
            
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult describe = fieldMap.get(fieldName).getDescribe();
                
                // Skip non-accessible and system fields
                if (!describe.isAccessible() || 
                    fieldName == 'Id' || 
                    fieldName == 'IsDeleted' || 
                    fieldName == 'SystemModstamp') {
                    continue;
                }
                
                Map<String, Object> field = new Map<String, Object>();
                field.put('apiName', fieldName);
                field.put('label', describe.getLabel());
                field.put('value', previewRecord.get(fieldName));
                field.put('sourceId', masterId); // Default to master
                
                // Check if this field was selected from another record
                if (fieldSelections.containsKey(fieldName)) {
                    field.put('sourceId', fieldSelections.get(fieldName));
                }
                
                fieldData.add(field);
            }
            
            // Build result
            result.put('success', true);
            result.put('masterId', masterId);
            result.put('objectApiName', objectApiName);
            result.put('previewRecord', previewRecord);
            result.put('fieldData', fieldData);
            result.put('conflicts', conflicts);
            result.put('nonMergeableData', nonMergeableData);
            result.put('noteContents', noteContents);
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error previewing merge results: ' + e.getMessage());
        }
    }
}