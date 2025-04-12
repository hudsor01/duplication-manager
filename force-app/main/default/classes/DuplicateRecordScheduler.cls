/**
 * Scheduler class for scheduling duplicate record batch jobs
 * Allows configuring recurring jobs for duplicate detection and merging
 *
 * @description Handles scheduling and execution of duplicate record batch jobs
 * @author Richard Hudson
 * @since April 2025
 */
public class DuplicateRecordScheduler implements Schedulable {

    private String configId;
    private Boolean isDryRun;
    private Integer batchSize;
    /**
     * Constructor for scheduler
     * @description Initializes a new instance with specified configuration, dry run flag and batch size
     * @param configId ID of the configuration to use
     * @param isDryRun Whether to perform a dry run (find only, no merge)
     * @param batchSize Batch size to use (optional)
     */
    public DuplicateRecordScheduler(String configId, Boolean isDryRun, Integer batchSize) {
        this.configId = configId;
        this.isDryRun = isDryRun;
        this.batchSize = (batchSize != null && batchSize > 0) ? batchSize : 200;
    }
    /**
     * Constructor for scheduler with default batch size
     * @description Initializes a new instance with specified configuration and dry run flag using default batch size
     * @param configId ID of the configuration to use
     * @param isDryRun Whether to perform a dry run (find only, no merge)
     */
    public DuplicateRecordScheduler(String configId, Boolean isDryRun) {
        this(configId, isDryRun, 200);
    }
    /**
     * Execute method for the scheduler
     * @description Runs the batch job when the scheduled time is reached
     * @param context The SchedulableContext provided by the Salesforce scheduler
     */
    public void execute(SchedulableContext context) {
        try {
            initializeFromConfig();
            DuplicateRecordBatch batchJob = new DuplicateRecordBatch(configId, isDryRun);
            Database.executeBatch(batchJob, batchSize);
            logScheduledJobExecution(context.getTriggerId());
        } catch (Exception e) {
            logScheduleError(context.getTriggerId(), e);
        }
    }
    /**
     * Schedule a duplicate detection job
     * @description Creates and schedules a new duplicate detection job with the specified parameters
     * @param configId ID of the configuration to use
     * @param cronExpression Cron expression for the schedule
     * @param jobName Name to identify the job
     * @param isDryRun Whether to perform a dry run (find only, no merge)
     * @param batchSize Batch size to use
     * @return ID of the scheduled job
     */
    public static Id scheduleJob(String configId, String cronExpression, String jobName, Boolean isDryRun, Integer batchSize) {
        if (String.isBlank(configId)) {
            throw new DuplicateException('Configuration ID is required');
        }

        if (String.isBlank(cronExpression)) {
            throw new DuplicateException('Cron expression is required');
        }

        if (String.isBlank(jobName)) {
            // Generate a job name if not provided
            String jobType = isDryRun ? 'Find Only' : 'Merge';
            jobName = 'Duplicate ' + jobType + ' - ' + configId + ' - ' +
                        System.now().format('yyyy-MM-dd HH:mm');
        }

        try {
            // Create and schedule the job
            DuplicateRecordScheduler scheduler = new DuplicateRecordScheduler(configId, isDryRun, batchSize);
            Id jobId = System.schedule(jobName, cronExpression, scheduler);
            return jobId;
        } catch (Exception e) {
            throw new DuplicateException('Failed to schedule job: ' + e.getMessage());
        }
    }
    /**
     * Run a duplicate detection job immediately
     * @description Executes a duplicate detection batch job immediately without scheduling
     * @param configId ID of the configuration to use
     * @param isDryRun Whether to perform a dry run (find only, no merge)
     * @param batchSize Batch size to use
     * @return ID of the batch job
     */
    public static Id runJobNow(String configId, Boolean isDryRun, Integer batchSize) {
        if (String.isBlank(configId)) {
            throw new DuplicateException('Configuration ID is required');
        }

        try {
            // Start the batch job
            DuplicateRecordBatch batchJob = new DuplicateRecordBatch(configId, isDryRun);
            Id batchId = Database.executeBatch(batchJob, (batchSize != null && batchSize > 0) ? batchSize : 200);
            return batchId;
        } catch (Exception e) {
            throw new DuplicateException('Failed to run job: ' + e.getMessage());
        }
    }
    /**
     * Log the execution details of a scheduled job
     * @description Records details about a scheduled job execution for monitoring
     * @param triggerId ID of the scheduled job
     */
    private void logScheduledJobExecution(Id triggerId) {
        try {
            // Get the scheduled job with security enforcement
            CronTrigger scheduledJob = [
                SELECT Id, CronJobDetail.Name, State, NextFireTime, PreviousFireTime
                FROM CronTrigger
                WHERE Id = :triggerId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            // Log the execution (could be expanded to create a custom object record)
            String logMessage = 'Scheduled job executed - ' +
                                'Name: ' + scheduledJob.CronJobDetail.Name +
                                ', State: ' + scheduledJob.State +
                                ', Next Fire Time: ' + scheduledJob.NextFireTime +
                                ', Previous Fire Time: ' + scheduledJob.PreviousFireTime;
            System.debug(LoggingLevel.INFO, logMessage);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error logging job execution: ' + e.getMessage());
        }
    }
    
    /**
     * Log an error with a scheduled job execution
     * @description Records error details when a scheduled job fails
     * @param triggerId ID of the scheduled job
     * @param e Exception that occurred
     */
    private void logScheduleError(Id triggerId, Exception e) {
        try {
            // Get the scheduled job
            CronTrigger scheduledJob = [
                SELECT Id, CronJobDetail.Name, State
                FROM CronTrigger
                WHERE Id = :triggerId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            // Log the error
            String errorMessage = 'Error executing scheduled job - ' +
                                'Name: ' + scheduledJob.CronJobDetail.Name +
                                ', State: ' + scheduledJob.State +
                                ', Error: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, errorMessage);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Could not log scheduled job error: ' + ex.getMessage());
        }
    }

    /**
     * @description Creates a valid cron expression from human-readable schedule parameters
     * @param frequency Frequency type (HOURLY, DAILY, WEEKLY, MONTHLY)
     */
    /**
     * Build a cron expression from user-friendly parts
     * @description Creates a valid cron expression from human-readable schedule parameters
     * @param frequency Frequency type (HOURLY, DAILY, WEEKLY, MONTHLY)
     * @param hour Hour of day (0-23)
     * @param minute Minute of hour (0-59)
     * @param dayOfWeek Day of week (1-7, where 1=Sunday, 7=Saturday)
     * @param dayOfMonth Day of month (1-31)
     * @return Cron expression
     */
    public static String buildCronExpression(String frequency, Integer hour, Integer minute, Integer dayOfWeek, Integer dayOfMonth) {
        // Validate inputs
        if (String.isBlank(frequency)) {
            throw new DuplicateException('Frequency is required');
        }

        frequency = frequency.toUpperCase();
        hour = (hour != null) ? Math.min(Math.max(hour, 0), 23) : 0;
        minute = (minute != null) ? Math.min(Math.max(minute, 0), 59) : 0;

        // Build cron expression based on frequency
        String cronExpression;

        switch on frequency {
            when 'HOURLY' {
                cronExpression = '0 ' + minute + ' * * * ?';
            }
            when 'DAILY' {
                cronExpression = '0 ' + minute + ' ' + hour + ' * * ?';
            }
            when 'WEEKLY' {
                if (dayOfWeek == null || dayOfWeek < 1 || dayOfWeek > 7) {
                    dayOfWeek = 1; // Default to Sunday
                }
                cronExpression = '0 ' + minute + ' ' + hour + ' ? * ' + dayOfWeek;
            }
            when 'MONTHLY' {
                if (dayOfMonth == null || dayOfMonth < 1 || dayOfMonth > 31) {
                    dayOfMonth = 1; // Default to 1st of month
                }
                cronExpression = '0 ' + minute + ' ' + hour + ' ' + dayOfMonth + ' * ?';
            }
            when else {
                throw new DuplicateException('Unsupported frequency: ' + frequency);
            }
        }

        return cronExpression;
    }
    /**
     * Custom exception class for scheduling errors
     * @description Exception class for handling errors specific to duplicate record processing
     */
    public class DuplicateException extends Exception {}

    /**
     * Initialize production-ready configuration values
     * @description Sets default configuration values if none are provided
     */
    private void initializeFromConfig() {
        // Ensure that configId is set; if not, assign a default value.
        this.configId = (this.configId != null && !String.isBlank(this.configId)) ? this.configId : 'defaultConfig';
        System.debug(LoggingLevel.INFO, 'Default configuration initialized for configId: ' + this.configId);
    }
    
    /**
     * Run a duplicate finder batch job
     * @param objectApiName API name of the object to process
     * @param isDryRun Whether to perform a dry run (find only, no merge)
     * @param batchSize Batch size to use
     * @return ID of the batch job
     */
    public static Id runDuplicateFinderBatch(String objectApiName, Boolean isDryRun, Integer batchSize) {
        if (String.isBlank(objectApiName)) {
            throw new DuplicateException('Object API name is required');
        }
        
        try {
            // Default fields for matching if not specified
            List<String> defaultFields = new List<String>{'Name'};
            
            // Default master record strategy
            String masterStrategy = 'mostRecent';
            
            // Create and execute batch job
            DuplicateRecordBatch batchJob = new DuplicateRecordBatch(
                objectApiName, defaultFields, masterStrategy, batchSize, isDryRun
            );
            
            Id batchId = Database.executeBatch(batchJob, batchSize > 0 ? batchSize : 200);
            return batchId;
        } catch (Exception e) {
            throw new DuplicateException('Failed to run duplicate finder: ' + e.getMessage());
        }
    }
}
