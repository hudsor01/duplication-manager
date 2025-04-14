/**
 * Controller for checking the health of duplicate system
 * Performs various health checks on settings, permissions, and data
 *
 * @author Richard Hudson
 * @date 2025-04-11
 */
public with sharing class DuplicateHealthController {

    /**
     * Check health of duplicate system components
     * @return List of health issue objects with details
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> checkHealth() {
        try {
            List<Map<String, Object>> healthIssues = new List<Map<String, Object>>();

            // Add object and field permission checks
            checkObjectPermissions(healthIssues);

            // Check custom settings
            checkDuplicateSettings(healthIssues);

            // Check recent job metrics
            checkJobMetrics(healthIssues);

            // Check for scheduled jobs
            checkScheduledJobs(healthIssues);

            return healthIssues;
        } catch (Exception e) {
            throw new AuraHandledException('Error performing health check: ' + e.getMessage());
        }
    }

    /**
     * Check object permissions for key objects
     * @param healthIssues List to add any issues to
     */
    private static void checkObjectPermissions(List<Map<String, Object>> healthIssues) {
        // List of objects to check
        List<String> objectsToCheck = new List<String>{
            'MergeJobLog__c',
            'DuplicateRunResult__c',
            'DuplicateGroupDetail__c',
            'DuplicateJobStatistic__c'
        };

        // Get current user ID
        Id userId = UserInfo.getUserId();

        for (String objectName : objectsToCheck) {
            try {
                // Check if the object is accessible to the current user
                Schema.DescribeSObjectResult describe = Schema.getGlobalDescribe().get(objectName).getDescribe();

                if (!describe.isAccessible()) {
                    // Add health issue for object permission
                    Map<String, Object> issue = new Map<String, Object>();
                    issue.put('id', 'obj_permission_' + objectName);
                    issue.put('title', 'Missing Object Permissions');
                    issue.put('description', 'User does not have read access to the ' + describe.getLabel() + ' object.');
                    issue.put('severity', 'error');
                    issue.put('category', 'Permissions');
                    issue.put('resolution', 'Grant read access to the ' + describe.getLabel() + ' object through permission sets or profiles.');

                    healthIssues.add(issue);
                }

                // Check if the object is createable
                if (!describe.isCreateable()) {
                    Map<String, Object> issue = new Map<String, Object>();
                    issue.put('id', 'obj_create_' + objectName);
                    issue.put('title', 'Missing Create Permissions');
                    issue.put('description', 'User does not have create access to the ' + describe.getLabel() + ' object.');
                    issue.put('severity', 'warning');
                    issue.put('category', 'Permissions');
                    issue.put('resolution', 'Grant create access to the ' + describe.getLabel() + ' object through permission sets or profiles.');

                    healthIssues.add(issue);
                }
            } catch (Exception e) {
                // Object doesn't exist or can't be accessed
                Map<String, Object> issue = new Map<String, Object>();
                issue.put('id', 'obj_missing_' + objectName);
                issue.put('title', 'Missing Object');
                issue.put('description', 'The ' + objectName + ' object is missing or cannot be accessed.');
                issue.put('severity', 'error');
                issue.put('category', 'Configuration');
                issue.put('resolution', 'Ensure the ' + objectName + ' object is properly deployed and accessible.');

                healthIssues.add(issue);
            }
        }
    }

    /**
     * Check duplicate settings configuration
     * @param healthIssues List to add any issues to
     */
    private static void checkDuplicateSettings(List<Map<String, Object>> healthIssues) {
        try {
            // Check for active duplicate finder settings
            List<DuplicateFinderSetting__mdt> activeSettings = [
                SELECT Id, MasterLabel, SObject_API_Name__c
                FROM DuplicateFinderSetting__mdt
                WHERE IsActive__c = true
                LIMIT 100
            ];

            if (activeSettings.isEmpty()) {
                // Add health issue for missing active settings
                Map<String, Object> issue = new Map<String, Object>();
                issue.put('id', 'no_active_settings');
                issue.put('title', 'No Active Duplicate Settings');
                issue.put('description', 'There are no active duplicate finder settings configured.');
                issue.put('severity', 'warning');
                issue.put('category', 'Configuration');
                issue.put('resolution', 'Configure at least one active duplicate finder setting for objects you want to deduplicate.');

                healthIssues.add(issue);
            }

            // Check specific object types that should have settings
            Set<String> configuredObjects = new Set<String>();
            for (DuplicateFinderSetting__mdt setting : activeSettings) {
                configuredObjects.add(setting.SObject_API_Name__c);
            }

            // List of recommended objects to check
            List<String> recommendedObjects = new List<String>{
                'Account',
                'Contact',
                'Lead'
            };

            for (String objectName : recommendedObjects) {
                if (!configuredObjects.contains(objectName)) {
                    // Add recommendation for common object
                    Map<String, Object> issue = new Map<String, Object>();
                    issue.put('id', 'recommended_' + objectName);
                    issue.put('title', 'Recommended Setting Missing');
                    issue.put('description', 'No active duplicate finder setting for ' + objectName + ' objects.');
                    issue.put('severity', 'info');
                    issue.put('category', 'Recommendation');
                    issue.put('resolution', 'Consider creating a duplicate finder setting for ' + objectName + ' objects.');

                    healthIssues.add(issue);
                }
            }
        } catch (Exception e) {
            // Add error for settings access
            Map<String, Object> issue = new Map<String, Object>();
            issue.put('id', 'settings_access_error');
            issue.put('title', 'Settings Access Error');
            issue.put('description', 'Error accessing duplicate finder settings: ' + e.getMessage());
            issue.put('severity', 'error');
            issue.put('category', 'Access');
            issue.put('resolution', 'Ensure you have access to the DuplicateFinderSetting__mdt metadata.');

            healthIssues.add(issue);
        }
    }

    /**
     * Check job metrics from recent duplicate jobs
     * @param healthIssues List to add any issues to
     */
    private static void checkJobMetrics(List<Map<String, Object>> healthIssues) {
        try {
            // Query recent job metrics
            List<DuplicateJobStatistic__c> recentJobs = [
                SELECT Id, JobStartTime__c, JobCompletionTime__c, Status__c, 
                       RecordsProcessed__c, DuplicatesFound__c, RecordsMerged__c,
                       ObjectApiName__c, ProcessingTimeMs__c, ErrorMessage__c
                FROM DuplicateJobStatistic__c
                WHERE JobStartTime__c >= LAST_N_DAYS:30
                ORDER BY JobStartTime__c DESC
                LIMIT 10
            ];
            
            // Check for failed jobs
            for (DuplicateJobStatistic__c job : recentJobs) {
                if (job.Status__c == 'Failed' || job.Status__c == 'Error') {
                    Map<String, Object> issue = new Map<String, Object>();
                    issue.put('id', 'failed_job_' + job.Id);
                    issue.put('title', 'Failed Duplicate Job');
                    issue.put('description', 'A duplicate job failed on ' + 
                              job.JobStartTime__c.format() + ' for object ' + job.ObjectApiName__c);
                    issue.put('severity', 'warning');
                    issue.put('category', 'Jobs');
                    issue.put('resolution', 'Review error message: ' + 
                              (String.isBlank(job.ErrorMessage__c) ? 'No error details available' : job.ErrorMessage__c));
                    
                    healthIssues.add(issue);
                }
            }
            
            // Check for long-running jobs
            for (DuplicateJobStatistic__c job : recentJobs) {
                if (job.ProcessingTimeMs__c > 300000) { // 5+ minutes
                    Map<String, Object> issue = new Map<String, Object>();
                    issue.put('id', 'slow_job_' + job.Id);
                    issue.put('title', 'Slow Duplicate Job');
                    issue.put('description', 'A duplicate job took ' + 
                              (job.ProcessingTimeMs__c/1000) + ' seconds to process ' + 
                              job.RecordsProcessed__c + ' records');
                    issue.put('severity', 'info');
                    issue.put('category', 'Performance');
                    issue.put('resolution', 'Consider optimizing duplicate job settings or increasing batch size');
                    
                    healthIssues.add(issue);
                }
            }
            
            // Add a recommended notice about reviewing metrics regularly
            Map<String, Object> issue = new Map<String, Object>();
            issue.put('id', 'job_metrics_review');
            issue.put('title', 'Review Job Metrics Regularly');
            issue.put('description', 'Regular review of duplicate job metrics is recommended to ensure optimal performance.');
            issue.put('severity', 'info');
            issue.put('category', 'Best Practice');
            issue.put('resolution', 'Schedule time to review duplicate job metrics on a monthly basis.');

            healthIssues.add(issue);

        } catch (Exception e) {
            // Add error for job metrics access
            Map<String, Object> issue = new Map<String, Object>();
            issue.put('id', 'job_metrics_error');
            issue.put('title', 'Job Metrics Access Error');
            issue.put('description', 'Error accessing job metrics: ' + e.getMessage());
            issue.put('severity', 'warning');
            issue.put('category', 'Access');
            issue.put('resolution', 'Ensure you have access to job statistics records.');

            healthIssues.add(issue);
        }
    }

    /**
     * Check scheduled jobs for duplicate
     * @param healthIssues List to add any issues to
     */
    private static void checkScheduledJobs(List<Map<String, Object>> healthIssues) {
        try {
            // Query for scheduled jobs related to duplicate
            List<CronTrigger> scheduledJobs = [
                SELECT Id, CronJobDetail.Name, NextFireTime
                FROM CronTrigger
                WHERE CronJobDetail.Name LIKE '%Duplicate%'
                AND State = 'WAITING'
                ORDER BY NextFireTime
                LIMIT 10
            ];

            if (scheduledJobs.isEmpty()) {
                // Add recommendation for scheduled jobs
                Map<String, Object> issue = new Map<String, Object>();
                issue.put('id', 'no_scheduled_jobs');
                issue.put('title', 'No Scheduled Duplicate Jobs');
                issue.put('description', 'There are no scheduled duplicate jobs configured.');
                issue.put('severity', 'info');
                issue.put('category', 'Automation');
                issue.put('resolution', 'Consider scheduling recurring duplicate jobs for automated cleanup.');

                healthIssues.add(issue);
            }

        } catch (Exception e) {
            // Add error for scheduled jobs access
            Map<String, Object> issue = new Map<String, Object>();
            issue.put('id', 'scheduled_jobs_error');
            issue.put('title', 'Scheduled Jobs Access Error');
            issue.put('description', 'Error accessing scheduled jobs: ' + e.getMessage());
            issue.put('severity', 'warning');
            issue.put('category', 'Access');
            issue.put('resolution', 'Ensure you have access to CronTrigger objects.');

            healthIssues.add(issue);
        }
    }
}
