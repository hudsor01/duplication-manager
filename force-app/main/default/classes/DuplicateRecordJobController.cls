/**
 * Controller for duplicate job management and status tracking
 *
 * @author Richard Hudson
 * @since April 2025
 */
public with sharing class DuplicateRecordJobController {

    // Job status constants
    private static final String STATUS_QUEUED = 'Queued';
    private static final String STATUS_HOLDING = 'Holding';
    private static final String STATUS_PREPARING = 'Preparing';
    private static final String STATUS_PROCESSING = 'Processing';
    private static final String STATUS_COMPLETED = 'Completed';
    private static final String STATUS_FAILED = 'Failed';
    private static final String STATUS_ABORTED = 'Aborted';

    // Maximum error message length
    private static final Integer MAX_ERROR_MESSAGE_LENGTH = 100;

    // Default batch size if not specified
    private static final Integer DEFAULT_BATCH_SIZE = 200;

    // Default record limit for queries
    private static final Integer DEFAULT_RECORD_LIMIT = 10;

    /**
     * Custom exception class for job processing errors
     */
    public class CustomException extends Exception {}

    /**
     * JobStatusResult wrapper class to improve type safety
     */
    public class JobStatusResult {
        public Map<String, Object> data {get; private set;}

        public JobStatusResult() {
            this.data = new Map<String, Object>();
        }

        public void put(String key, Object value) {
            this.data.put(key, value);
        }

        public Object get(String key) {
            return this.data.get(key);
        }

        public Boolean containsKey(String key) {
            return this.data.containsKey(key);
        }

        public Map<String, Object> toMap() {
            return this.data;
        }
    }

    /**
     * Get status of a specific job
     * @param jobId ID of the batch job to check
     * @return Map of job status information
     */
    @AuraEnabled
    public static Map<String, Object> getJobStatus(String jobId) {
        try {
            if (String.isBlank(jobId)) {
                throw new AuraHandledException('Job ID is required');
            }

            // Check if this is a batch job ID or a custom job ID
            JobStatusResult result = new JobStatusResult();

            if (jobId.startsWith('707')) {
                // This is an AsyncApexJob ID
                AsyncApexJob job = [
                    SELECT Id, Status, JobItemsProcessed, TotalJobItems,
                           NumberOfErrors, ExtendedStatus, CreatedDate,
                           CompletedDate, MethodName
                    FROM AsyncApexJob
                    WHERE Id = :jobId
                    LIMIT 1
                ];

                result.put('jobId', jobId);
                result.put('status', job.Status);
                result.put('progress', job.TotalJobItems > 0 ? (job.JobItemsProcessed * 100 / job.TotalJobItems) : 0);
                result.put('jobType', job.MethodName);
                result.put('processedBatches', job.JobItemsProcessed);
                result.put('totalBatches', job.TotalJobItems);
                result.put('errorCount', job.NumberOfErrors);
                result.put('statusSummary', job.Status + (job.NumberOfErrors > 0 ? ' with ' + job.NumberOfErrors + ' errors' : ''));
                result.put('startTime', job.CreatedDate);
                result.put('endTime', job.CompletedDate);
            } else {
                // This is a custom job ID (DuplicateJobStatistic__c)
                DuplicateJobStatistic__c job = [
                    SELECT Id, Status__c, ObjectApiName__c, DuplicatesFound__c,
                           RecordsProcessed__c, RecordsMerged__c, JobStartTime__c,
                           JobCompletionTime__c, BatchJobId__c, ErrorMessage__c,
                           ConfigurationName__c
                    FROM DuplicateJobStatistic__c
                    WHERE Id = :jobId
                    LIMIT 1
                ];

                result.put('jobId', jobId);
                result.put('status', job.Status__c);
                result.put('objectApiName', job.ObjectApiName__c);
                result.put('duplicatesFound', job.DuplicatesFound__c);
                result.put('recordsProcessed', job.RecordsProcessed__c);
                result.put('recordsMerged', job.RecordsMerged__c);
                result.put('configName', job.ConfigurationName__c);

                // Get related batch job status if available
                if (String.isNotBlank(job.BatchJobId__c)) {
                    try {
                        AsyncApexJob batchJob = [
                            SELECT Status, JobItemsProcessed, TotalJobItems, NumberOfErrors
                            FROM AsyncApexJob
                            WHERE Id = :job.BatchJobId__c
                            LIMIT 1
                        ];

                        result.put('progress', batchJob.TotalJobItems > 0 ? (batchJob.JobItemsProcessed * 100 / batchJob.TotalJobItems) : 0);
                        result.put('processedBatches', batchJob.JobItemsProcessed);
                        result.put('totalBatches', batchJob.TotalJobItems);
                        result.put('errorCount', batchJob.NumberOfErrors);
                    } catch (Exception bex) {
                        // Batch job may have been deleted
                        result.put('progress', job.Status__c == STATUS_COMPLETED ? 100 : 0);
                    }
                } else {
                    // No batch job, set default progress
                    result.put('progress', job.Status__c == STATUS_COMPLETED ? 100 : 0);
                }

                result.put('startTime', job.JobStartTime__c);
                result.put('endTime', job.JobCompletionTime__c);
                result.put('errorMessages', job.ErrorMessage__c);
            }

            return result.toMap();

        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving job status: ' + e.getMessage());
        }
    }

    /**
     * Get list of recent jobs
     * @param recordLimit Maximum number of jobs to return
     * @return List of job status maps
     */
    @AuraEnabled
    public static List<Map<String, Object>> getRecentJobs(Integer recordLimit) {
        try {
            // Validate and normalize limit
            Integer queryLimit = normalizeRecordLimit(recordLimit);

            // Query for recent jobs
            List<DuplicateJobStatistic__c> recentJobs = [
                SELECT Id, Status__c, ObjectApiName__c, ConfigurationName__c,
                       DuplicatesFound__c, RecordsProcessed__c, RecordsMerged__c,
                       JobStartTime__c, JobCompletionTime__c, ProcessingTimeMs__c,
                       BatchJobId__c, IsDryRun__c, ErrorMessage__c
                FROM DuplicateJobStatistic__c
                ORDER BY JobStartTime__c DESC
                LIMIT :queryLimit
            ];

            // Convert to map format for LWC
            List<Map<String, Object>> results = new List<Map<String, Object>>();

            for (DuplicateJobStatistic__c job : recentJobs) {
                Map<String, Object> jobInfo = new Map<String, Object>();
                jobInfo.put('id', job.Id);
                jobInfo.put('objectApiName', job.ObjectApiName__c);
                jobInfo.put('status', job.Status__c);
                jobInfo.put('configName', job.ConfigurationName__c);
                jobInfo.put('duplicatesFound', job.DuplicatesFound__c);
                jobInfo.put('recordsProcessed', job.RecordsProcessed__c);
                jobInfo.put('recordsMerged', job.RecordsMerged__c);
                jobInfo.put('startTime', job.JobStartTime__c);
                jobInfo.put('endTime', job.JobCompletionTime__c);
                jobInfo.put('processingTimeMs', job.ProcessingTimeMs__c);
                jobInfo.put('batchJobId', job.BatchJobId__c);
                jobInfo.put('isDryRun', job.IsDryRun__c);

                // Calculate duration in seconds if we have start and end times
                if (job.JobStartTime__c != null && job.JobCompletionTime__c != null) {
                    Long durationMs = job.JobCompletionTime__c.getTime() - job.JobStartTime__c.getTime();
                    jobInfo.put('durationSeconds', durationMs / 1000);
                }

                // Add error messages if any
                if (String.isNotBlank(job.ErrorMessage__c)) {
                    jobInfo.put('errorMessages', job.ErrorMessage__c);
                }

                results.add(jobInfo);
            }

            return results;

        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving recent jobs: ' + e.getMessage());
        }
    }

    /**
     * Get list of scheduled jobs
     * @return List of scheduled job information
     */
    @AuraEnabled
    public static List<Map<String, Object>> getScheduledJobs() {
        try {
            // Query for scheduled jobs
            List<CronTrigger> scheduledJobs = [
                SELECT Id, CronJobDetail.Name, CronJobDetail.JobType,
                       CronExpression, State, NextFireTime, PreviousFireTime,
                       OwnerId, StartTime, EndTime, TimesTriggered
                FROM CronTrigger
                WHERE CronJobDetail.Name LIKE 'DuplicateRecord%'
                OR CronJobDetail.Name LIKE 'Deduplicate%'
                ORDER BY NextFireTime ASC
            ];

            // Convert to map format for LWC
            List<Map<String, Object>> results = new List<Map<String, Object>>();

            for (CronTrigger job : scheduledJobs) {
                Map<String, Object> jobInfo = new Map<String, Object>();
                jobInfo.put('id', job.Id);
                jobInfo.put('name', job.CronJobDetail.Name);
                jobInfo.put('cronExpression', job.CronExpression);
                jobInfo.put('state', job.State);
                jobInfo.put('nextFireTime', job.NextFireTime);
                jobInfo.put('previousFireTime', job.PreviousFireTime);
                jobInfo.put('startTime', job.StartTime);
                jobInfo.put('endTime', job.EndTime);
                jobInfo.put('timesTriggered', job.TimesTriggered);
                jobInfo.put('ownerId', job.OwnerId);
                jobInfo.put('jobType', job.CronJobDetail.JobType);

                // Parse configuration from name if possible
                if (job.CronJobDetail.Name.contains('_')) {
                    List<String> nameParts = job.CronJobDetail.Name.split('_');
                    if (nameParts.size() >= 2) {
                        jobInfo.put('objectApiName', nameParts[1]);
                    }
                    if (nameParts.size() >= 3) {
                        jobInfo.put('frequencyLabel', nameParts[2]);
                    }
                }

                results.add(jobInfo);
            }

            return results;

        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving scheduled jobs: ' + e.getMessage());
        }
    }

    /**
     * Delete a scheduled job
     * @param jobId ID of the scheduled job to delete
     * @return Success message
     */
    @AuraEnabled
    public static String deleteScheduledJob(Id jobId) {
        if (jobId == null) {
            throw new AuraHandledException('Job ID is required');
        }

        try {
            // Verify the job exists and is a CronTrigger
            CronTrigger job = [
                SELECT Id, CronJobDetail.Name
                FROM CronTrigger
                WHERE Id = :jobId
                LIMIT 1
            ];

            // Abort the scheduled job
            System.abortJob(jobId);

            return 'Scheduled job "' + job.CronJobDetail.Name + '" was deleted successfully';
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting job: ' + e.getMessage());
        }
    }

    /**
     * Schedule a new job
     * @param configId Configuration ID to use
     * @param cronExpression Cron expression for scheduling
     * @param isDryRun Whether to perform a dry run (find only, no merge)
     * @return ID of the scheduled job
     */
    @AuraEnabled
    public static Id scheduleJob(String configId, String cronExpression, Boolean isDryRun) {
        if (String.isBlank(configId)) {
            throw new AuraHandledException('Configuration ID is required');
        }

        if (String.isBlank(cronExpression)) {
            throw new AuraHandledException('Cron expression is required');
        }

        try {
            // Retrieve configuration details
            DuplicateFinderSettings__c config = [
                SELECT Id, Name, ObjectAPIName__c, IsActive__c
                FROM DuplicateFinderSettings__c
                WHERE Id = :configId
                LIMIT 1
            ];

            if (!config.IsActive__c) {
                throw new AuraHandledException('Cannot schedule using an inactive configuration.');
            }

            // Create a unique job name
            String jobName = 'DuplicateRecordScheduler_' + config.ObjectAPIName__c + '_' + System.now().getTime();

            // Create the scheduler with correct parameters
            DuplicateRecordScheduler scheduler = new DuplicateRecordScheduler(configId, isDryRun == true);

            // Schedule the job
            return System.schedule(jobName, cronExpression, scheduler);
        } catch (Exception e) {
            throw new AuraHandledException('Error scheduling job: ' + e.getMessage());
        }
    }

    /**
     * Run a duplicate finder batch job immediately
     * @param configId Configuration ID to use
     * @param isDryRun Whether to perform a dry run (find only, no merge)
     * @param batchSize Number of records per batch
     * @return ID of the started job
     */
    @AuraEnabled
    public static Id runDuplicateFinderBatch(String configId, Boolean isDryRun, Integer batchSize) {
        if (String.isBlank(configId)) {
            throw new AuraHandledException('Configuration ID is required');
        }

        try {
            // Normalize batch size
            if (batchSize == null || batchSize <= 0) {
                batchSize = DEFAULT_BATCH_SIZE;
            }

            // Retrieve configuration details
            DuplicateFinderSettings__c config = [
                SELECT Id, Name, ObjectAPIName__c, MatchFields__c, IsActive__c, BatchSize__c, MasterRecordStrategy__c
                FROM DuplicateFinderSettings__c
                WHERE Id = :configId
                LIMIT 1
            ];

            if (!config.IsActive__c) {
                throw new AuraHandledException('Cannot run job using an inactive configuration.');
            }

            // Extract match fields from the configuration
            List<String> matchFields = new List<String>();
            if (String.isNotBlank(config.MatchFields__c)) {
                matchFields = config.MatchFields__c.split(',');
            }

            // Create batch job with correct constructor parameters
            DuplicateRecordBatch batchJob = new DuplicateRecordBatch(configId, isDryRun == true);

            // Use configured batch size if available
            if (config.BatchSize__c != null && config.BatchSize__c > 0) {
                batchSize = Integer.valueOf(config.BatchSize__c);
            }

            // Create job statistic record
            DuplicateJobStatistic__c jobStat = new DuplicateJobStatistic__c(
                ObjectApiName__c = config.ObjectAPIName__c,
                Status__c = STATUS_QUEUED,
                ConfigurationName__c = config.Name,
                IsDryRun__c = isDryRun == true,
                JobStartTime__c = Datetime.now()
            );

            insert jobStat;

            // Start the batch job
            Id batchJobId = Database.executeBatch(batchJob, batchSize);

            // Update job statistic with batch job ID
            jobStat.BatchJobId__c = batchJobId;
            update jobStat;

            return jobStat.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error running batch job: ' + e.getMessage());
        }
    }

    /**
     * Normalizes record limit to ensure it's valid
     * @param recordLimit Requested limit
     * @return Normalized limit
     */
    private static Integer normalizeRecordLimit(Integer recordLimit) {
        Integer maxRecordLimit = 1000; // Define an upper limit for record limit
        if (recordLimit == null || recordLimit <= 0) {
            return DEFAULT_RECORD_LIMIT;
        }
        return Math.min(recordLimit, maxRecordLimit); // Enforce the maximum limit
    }

    /**
     * Get batch size options for the UI
     * @return List of batch size options
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getBatchSizeOptions() {
        List<Map<String, Object>> options = new List<Map<String, Object>>{
            new Map<String, Object>{'label' => 'Small (200 records)', 'value' => 200},
            new Map<String, Object>{'label' => 'Medium (500 records)', 'value' => 500},
            new Map<String, Object>{'label' => 'Large (1000 records)', 'value' => 1000},
            new Map<String, Object>{'label' => 'Very Large (2000 records)', 'value' => 2000}
        };

        return options;
    }

    /**
     * Run duplicate detection process
     * @param objectApiName API name of the object to process
     * @param fieldApiNames List of field API names to include in comparison
     * @param batchSize Number of records per batch
     * @return ID of the job that was started
     */
    @AuraEnabled
    public static String runDuplicateDetection(String objectApiName, List<String> fieldApiNames, Integer batchSize) {
        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException('Object API name is required');
        }

        try {
            // Normalize batch size
            if (batchSize == null || batchSize <= 0) {
                batchSize = DEFAULT_BATCH_SIZE;
            }

            // Create fields string from field API names
            String matchFields = '';
            if (fieldApiNames != null && !fieldApiNames.isEmpty()) {
                matchFields = String.join(fieldApiNames, ',');
            } else {
                // Use default fields based on object type
                if (objectApiName == 'Account') {
                    matchFields = 'Name,Phone,Website,BillingStreet,BillingCity,BillingState,BillingPostalCode';
                } else if (objectApiName == 'Contact') {
                    matchFields = 'FirstName,LastName,Email,Phone,MailingStreet,MailingCity,MailingState,MailingPostalCode';
                } else if (objectApiName == 'Lead') {
                    matchFields = 'FirstName,LastName,Email,Phone,Company,Street,City,State,PostalCode';
                } else {
                    matchFields = 'Name';
                }
            }

            // Create job statistic record
            DuplicateJobStatistic__c jobStat = new DuplicateJobStatistic__c(
                ObjectApiName__c = objectApiName,
                Status__c = STATUS_QUEUED,
                JobStartTime__c = Datetime.now(),
                IsDryRun__c = true
            );

            insert jobStat;

            // Create a basic batch job since we can't access the specialized methods
            // This is a temporary solution until the class references are fixed
            String configName = 'Test Config';
            DuplicateRecordBatch batchJob = new DuplicateRecordBatch(configName, true);
            Id batchJobId = Database.executeBatch(batchJob, batchSize);

            // Update job statistic with batch job ID
            jobStat.BatchJobId__c = batchJobId;
            update jobStat;

            return jobStat.Id;

        } catch (Exception e) {
            throw new AuraHandledException('Error starting duplicate detection job: ' + e.getMessage());
        }
    }
}
