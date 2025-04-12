/**
 * Extension class for DuplicateRecordController to handle merge job logs
 * Provides functionality for tracking and managing merge operations
 *
 * @author Richard Hudson
 * @since April 2025
 */
public with sharing class DuplicateRecordController_MergeJobLogs {

    /**
     * Get recent merge logs
     * @param limit Maximum number of logs to return
     * @return List of merge logs
     */
    @AuraEnabled
    public static List<DuplicateMergeLog__c> getRecentMergeLogs(Integer limitParam) {
        if (limitParam == null || limitParam <= 0) {
            limitParam = 50;
        }

        return [
            SELECT Id, MasterId__c, MergedIds__c, ObjectApiName__c,
                   MergeTime__c, JobId__c, UserId__c,
                   FieldMergeDetails__c, ErrorMessages__c
            FROM DuplicateMergeLog__c
            ORDER BY MergeTime__c DESC
            LIMIT :limitParam
        ];
    }

    /**
     * Get merge logs for a specific job
     * @param jobId Batch job ID
     * @return List of merge logs
     */
    @AuraEnabled
    public static List<DuplicateMergeLog__c> getMergeLogsForJob(Id jobId) {
        if (jobId == null) {
            throw new AuraHandledException('Job ID is required');
        }

        return [
            SELECT Id, MasterId__c, MergedIds__c, ObjectApiName__c,
                   MergeTime__c, JobId__c, UserId__c,
                   FieldMergeDetails__c, ErrorMessages__c
            FROM DuplicateMergeLog__c
            WHERE JobId__c = :jobId
            ORDER BY MergeTime__c DESC
        ];
    }

    /**
     * Get merge logs for a specific master record
     * @param masterId Master record ID
     * @return List of merge logs
     */
    @AuraEnabled
    public static List<DuplicateMergeLog__c> getMergeLogsForMaster(Id masterId) {
        if (masterId == null) {
            throw new AuraHandledException('Master record ID is required');
        }

        return [
            SELECT Id, MasterId__c, MergedIds__c, ObjectApiName__c,
                   MergeTime__c, JobId__c, UserId__c,
                   FieldMergeDetails__c, ErrorMessages__c
            FROM DuplicateMergeLog__c
            WHERE MasterId__c = :masterId
            ORDER BY MergeTime__c DESC
        ];
    }

    /**
     * Get merge log details including record information
     * @param logId Merge log ID
     * @return Map with merge log details
     */
    @AuraEnabled
    public static Map<String, Object> getMergeLogDetails(Id logId) {
        if (logId == null) {
            throw new AuraHandledException('Log ID is required');
        }

        Map<String, Object> result = new Map<String, Object>();

        try {
            // Get the merge log
            DuplicateMergeLog__c log = [
                SELECT Id, MasterId__c, MergedIds__c, ObjectApiName__c,
                       MergeTime__c, JobId__c, UserId__c,
                       FieldMergeDetails__c, ErrorMessages__c
                FROM DuplicateMergeLog__c
                WHERE Id = :logId
                LIMIT 1
            ];

            result.put('log', log);

            // Get master record info if available
            if (log.MasterId__c != null) {
                String objectApiName = log.ObjectApiName__c;
                Id masterId = log.MasterId__c;

                if (String.isNotBlank(objectApiName)) {
                    // Query basic fields for the master record
                    String soql = 'SELECT Id, Name FROM ' + objectApiName + ' WHERE Id = :masterId LIMIT 1';
                    List<SObject> masterRecords = Database.query(soql);

                    if (!masterRecords.isEmpty()) {
                        result.put('masterRecord', masterRecords[0]);
                    }
                }
            }

            // Parse merged record IDs
            if (String.isNotBlank(log.MergedIds__c)) {
                try {
                    List<Id> mergedIds = (List<Id>)JSON.deserialize(log.MergedIds__c, List<Id>.class);
                    result.put('mergedRecordIds', mergedIds);
                    result.put('mergedRecordCount', mergedIds.size());
                } catch (Exception e) {
                    result.put('mergedRecordError', 'Error parsing merged record IDs: ' + e.getMessage());
                }
            }

            // Parse field merge details
            if (String.isNotBlank(log.FieldMergeDetails__c)) {
                try {
                    Map<String, List<Object>> fieldDetails =
                        (Map<String, List<Object>>)JSON.deserializeUntyped(log.FieldMergeDetails__c);

                    result.put('fieldDetails', fieldDetails);
                    result.put('conflictCount', fieldDetails.size());
                } catch (Exception e) {
                    result.put('fieldDetailsError', 'Error parsing field details: ' + e.getMessage());
                }
            }

            // Add user info
            if (log.UserId__c != null) {
                try {
                    User user = [
                        SELECT Id, Name, Username
                        FROM User
                        WHERE Id = :log.UserId__c
                        LIMIT 1
                    ];
                    result.put('user', user);
                } catch (Exception e) {
                    result.put('userError', 'Error retrieving user info: ' + e.getMessage());
                }
            }

        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving merge log details: ' + e.getMessage());
        }

        return result;
    }

    /**
     * Create a manual merge log entry
     * @param masterId Master record ID
     * @param mergedIds List of merged record IDs
     * @param objectApiName API name of the object
     * @param fieldDetails Field merge details (JSON string)
     * @return ID of the created log
     */
    @AuraEnabled
    public static Id createMergeLog(Id masterId, List<Id> mergedIds, String objectApiName, String fieldDetails) {
        if (masterId == null) {
            throw new AuraHandledException('Master record ID is required');
        }

        if (mergedIds == null || mergedIds.isEmpty()) {
            throw new AuraHandledException('Merged record IDs are required');
        }

        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException('Object API name is required');
        }

        try {
            // Create merge log record
            DuplicateMergeLog__c log = new DuplicateMergeLog__c(
                MasterId__c = masterId,
                MergedIds__c = JSON.serialize(mergedIds),
                ObjectApiName__c = objectApiName,
                MergeTime__c = System.now(),
                UserId__c = UserInfo.getUserId(),
                // MatchScore__c field doesn't exist
                FieldMergeDetails__c = fieldDetails
            );

            insert log;
            return log.Id;

        } catch (Exception e) {
            throw new AuraHandledException('Error creating merge log: ' + e.getMessage());
        }
    }

    /**
     * Delete a merge log
     * @param logId Log ID to delete
     * @return Success message
     */
    @AuraEnabled
    public static String deleteMergeLog(Id logId) {
        if (logId == null) {
            throw new AuraHandledException('Log ID is required');
        }

        try {
            DuplicateMergeLog__c log = [SELECT Id FROM DuplicateMergeLog__c WHERE Id = :logId LIMIT 1];
            delete log;
            return 'Merge log deleted successfully';
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting merge log: ' + e.getMessage());
        }
    }
}
