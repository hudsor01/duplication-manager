/**
 * Unified controller for the duplicate Manager application
 * Provides centralized access points for all LWC components
 *
 * @author Richard Hudson
 * @date April 2025
 */
public with sharing class DuplicateController {

    /**
     * Get available duplicate rules for an object
     * @param objectName API name of the object
     * @return List of duplicate rules
     */
    @AuraEnabled(cacheable=true)
    public static List<DuplicateRuleInfo> getDuplicateRules(String objectName) {
        try {
            List<DuplicateRuleInfo> result = new List<DuplicateRuleInfo>();

            // Query active duplicate rules for this object
            List<DuplicateRule> rules = [
                SELECT Id, DeveloperName, MasterLabel, SobjectType, IsActive
                FROM DuplicateRule
                WHERE SobjectType = :objectName
                AND IsActive = true
                ORDER BY MasterLabel
            ];

            // Convert to info objects
            for (DuplicateRule rule : rules) {
                result.add(new DuplicateRuleInfo(
                    rule.Id,
                    rule.MasterLabel,
                    rule.DeveloperName,
                    rule.SobjectType
                ));
            }

            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error getting duplicate rules: ' + e.getMessage());
        }
    }

    /**
     * Get recent job logs
     * @return List of recent job logs
     */
    @AuraEnabled
    public static List<DuplicateJobStatistic__c> getRecentJobs() {
        try {
            return [
                SELECT Id, ObjectApiName__c, JobStartTime__c, JobCompletionTime__c,
                       DuplicatesFound__c, RecordsMerged__c, RecordsProcessed__c,
                       Status__c, IsDryRun__c, BatchJobId__c, ConfigurationName__c,
                       MatchScore__c, ProcessingTimeMs__c, ErrorMessage__c
                FROM DuplicateJobStatistic__c
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error getting recent jobs: ' + e.getMessage());
        }
    }

    /**
     * Get detailed statistics for the dashboard
     * @param timeRange Time range to query (LAST_7_DAYS, LAST_30_DAYS, etc.)
     * @return Statistics data
     */
    @AuraEnabled
    public static Map<String, Object> getDetailedStatistics(String timeRange) {
        try {
            // Return statistics from specialized class
            return DuplicateStatisticsService.getDetailedStatistics(timeRange);
        } catch (Exception e) {
            throw new AuraHandledException('Error getting statistics: ' + e.getMessage());
        }
    }

    /**
     * Start a duplicate job
     * @param objectName API name of object to process
     * @param duplicateRuleId ID of duplicate rule to use
     * @param additionalFields Additional fields to preserve
     * @param batchSize Batch size for processing
     * @param isDryRun Whether to perform a dry run (no merges)
     * @return ID of the batch job
     */
    @AuraEnabled
    public static String runDuplicateJob(
        String objectName,
        String duplicateRuleId,
        List<String> additionalFields,
        Integer batchSize,
        Boolean isDryRun
    ) {
        try {
            // Create and execute batch job
            DuplicateBatch batchJob = new DuplicateBatch(
                objectName,
                duplicateRuleId,
                additionalFields,
                isDryRun
            );

            // Use provided batch size or default
            Integer finalBatchSize = (batchSize != null && batchSize > 0) ? batchSize : 200;
            ID jobId = Database.executeBatch(batchJob, finalBatchSize);

            // Log is created in the batch, no need to create here

            return jobId;
        } catch (Exception e) {
            throw new AuraHandledException('Error starting duplicate job: ' + e.getMessage());
        }
    }

    /**
     * Get status of a job
     * @param jobId ID of the batch job
     * @return Job status information
     */
    @AuraEnabled
    public static JobStatus getJobStatus(String jobId) {
        try {
            // Query AsyncApexJob for basic status
            AsyncApexJob job = [
                SELECT Id, Status, JobItemsProcessed, TotalJobItems,
                       NumberOfErrors, CompletedDate, CreatedDate
                FROM AsyncApexJob
                WHERE Id = :jobId
            ];

            // Query job statistics for detailed info
            List<DuplicateJobStatistic__c> stats = [
                SELECT Id, ObjectApiName__c, JobStartTime__c, JobCompletionTime__c,
                       DuplicatesFound__c, RecordsMerged__c, RecordsProcessed__c,
                       Status__c, IsDryRun__c, ErrorMessage__c
                FROM DuplicateJobStatistic__c
                WHERE BatchJobId__c = :jobId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            // Create status object
            JobStatus status = new JobStatus();
            status.jobId = jobId;
            status.status = job.Status;
            status.itemsProcessed = job.JobItemsProcessed;
            status.totalItems = job.TotalJobItems;
            status.errors = job.NumberOfErrors;

            // Add statistics if available
            if (!stats.isEmpty()) {
                DuplicateJobStatistic__c stat = stats[0];
                status.isDryRun = stat.IsDryRun__c;
                status.recordsProcessed = Integer.valueOf(stat.RecordsProcessed__c);
                status.duplicatesFound = Integer.valueOf(stat.DuplicatesFound__c);
                status.recordsMerged = Integer.valueOf(stat.RecordsMerged__c);
                status.errorMessages = stat.ErrorMessage__c;
            }

            return status;
        } catch (Exception e) {
            throw new AuraHandledException('Error getting job status: ' + e.getMessage());
        }
    }

    /**
     * Get fields for an object that can be preserved during merges
     * @param objectName API name of the object
     * @return List of field info
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldInfo> getPreservableFields(String objectName) {
        try {
            List<FieldInfo> result = new List<FieldInfo>();

            // Get object metadata
            SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
            if (objectType == null) {
                throw new AuraHandledException('Invalid object type: ' + objectName);
            }

            Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();

            // Filter for preservable field types
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                Schema.DisplayType fieldType = fieldDescribe.getType();

                // Only include writable, non-system fields
                if (isPreservableType(fieldType) &&
                    fieldDescribe.isUpdateable() &&
                    fieldDescribe.isAccessible() &&
                    !isSystemField(fieldName)) {

                    result.add(new FieldInfo(
                        fieldName,
                        fieldDescribe.getLabel(),
                        fieldType.name()
                    ));
                }
            }

            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error getting preservable fields: ' + e.getMessage());
        }
    }

    /**
     * Get duplicate groups for a run result
     * @param runResultId ID of the run result
     * @return List of duplicate groups
     */
    @AuraEnabled
    public static List<DuplicateGroupService.DuplicateGroupInfo> getDuplicateGroups(String runResultId) {
        try {
            // Get duplicate groups from specialized service
            return DuplicateGroupService.getDuplicateGroupsForResult(runResultId);
        } catch (Exception e) {
            throw new AuraHandledException('Error getting duplicate groups: ' + e.getMessage());
        }
    }

    /**
     * Get merge conflicts between records
     * @param masterId ID of master record
     * @param duplicateIds IDs of duplicate records
     * @return Map of field name to conflict info
     */
    @AuraEnabled
    public static Map<String, Object> getMergeConflicts(Id masterId, List<Id> duplicateIds) {
        try {
            // Get conflicts from specialized service
            return DuplicateMergeService.getMergeConflicts(masterId, duplicateIds);
        } catch (Exception e) {
            throw new AuraHandledException('Error getting merge conflicts: ' + e.getMessage());
        }
    }

    /**
     * Merge duplicate records
     * @param masterId ID of master record
     * @param duplicateIds IDs of duplicate records
     * @param fieldSelections Map of field name to selected record ID for conflicts
     * @return Result of merge operation
     */
    @AuraEnabled
    public static Map<String, Object> mergeDuplicates(
        Id masterId,
        List<Id> duplicateIds,
        Map<String, String> fieldSelections
    ) {
        try {
            // Perform merge using specialized service
            return DuplicateMergeService.mergeRecords(masterId, duplicateIds, fieldSelections);
        } catch (Exception e) {
            throw new AuraHandledException('Error merging duplicates: ' + e.getMessage());
        }
    }

    /**
     * Check if a field type can be preserved during merges
     */
    private static Boolean isPreservableType(Schema.DisplayType fieldType) {
        return fieldType != Schema.DisplayType.ID &&
               fieldType != Schema.DisplayType.REFERENCE &&
               fieldType != Schema.DisplayType.BASE64;
    }

    /**
     * Check if a field is a system field
     */
    private static Boolean isSystemField(String fieldName) {
        return (fieldName == 'Id' || fieldName == 'IsDeleted' ||
               fieldName == 'CreatedDate' || fieldName == 'CreatedById' ||
               fieldName == 'LastModifiedDate' || fieldName == 'LastModifiedById' ||
               fieldName == 'SystemModstamp');
    }

    /**
     * Field information class
     */
    public class FieldInfo {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String type;

        public FieldInfo(String apiName, String label, String type) {
            this.apiName = apiName;
            this.label = label;
            this.type = type;
        }
    }

    /**
     * Duplicate rule information class
     */
    public class DuplicateRuleInfo {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public String developerName;
        @AuraEnabled public String objectName;

        public DuplicateRuleInfo(String id, String label, String developerName, String objectName) {
            this.id = id;
            this.label = label;
            this.developerName = developerName;
            this.objectName = objectName;
        }
    }

    /**
     * Job status class
     */
    public class JobStatus {
        @AuraEnabled public String jobId;
        @AuraEnabled public String status;
        @AuraEnabled public Integer itemsProcessed;
        @AuraEnabled public Integer totalItems;
        @AuraEnabled public Integer errors;
        @AuraEnabled public Integer recordsProcessed;
        @AuraEnabled public Integer duplicatesFound;
        @AuraEnabled public Integer recordsMerged;
        @AuraEnabled public Boolean isDryRun;
        @AuraEnabled public String errorMessages;
    }
}
