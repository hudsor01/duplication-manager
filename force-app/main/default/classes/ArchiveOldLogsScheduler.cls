/***
 * Scheduler class for ArchiveOldLogsBatch
 * Schedules automatic archiving of old DuplicateMergeLog__c records
 *
 * @author Richard Hudson
 * @since April 2025
 */
global class ArchiveOldLogsScheduler implements Schedulable {
    // Default number of days to retain logs before archiving
    private Integer daysToRetain = 90;

    /**
     * Constructor with default retention period
     */
    public ArchiveOldLogsScheduler() {
        // Use default retention period
    }

    /**
     * Constructor with custom retention period
     * @param daysToRetain Number of days to retain logs
     */
    public ArchiveOldLogsScheduler(Integer daysToRetain) {
        if (daysToRetain != null && daysToRetain > 0) {
            this.daysToRetain = daysToRetain;
        }
    }

    /**
     * Execute method required by Schedulable interface
     * @param sc SchedulableContext
     */
    global void execute(SchedulableContext sc) {
        // Initialize batch job
        ArchiveOldLogsBatch batch = new ArchiveOldLogsBatch(daysToRetain);

        // Retrieve batch size from custom setting or use default
        Integer batchSize = getBatchSize();

        // Execute batch job with configurable batch size
        Database.executeBatch(batch, batchSize);
    }

    /**
     * Gets the configured batch size from custom settings or returns default value
     * @return The batch size to use for the archive batch job
     */
    private Integer getBatchSize() {
        // Replace with actual logic to fetch from custom settings if available
        return 200; // Default batch size
    }

    /**
     * Helper method to schedule this job
     * @description Schedules the job with the specified name, cron expression, and retention period.
     *              Throws a System.ScheduleException if the cron expression is invalid.
     * @param jobName Name for the scheduled job
     * @param cronExp Cron expression for scheduling
     * @param daysToRetain Number of days to retain logs
     * @return ID of the scheduled job
     */
    public static Id scheduleJob(String jobName, String cronExp, Integer daysToRetain) {
        ArchiveOldLogsScheduler scheduler = new ArchiveOldLogsScheduler(daysToRetain);
        return System.schedule(jobName, cronExp, scheduler);
    }

    /**
     * Helper method to schedule this job with default retention period
     * @description Schedules the job using the default retention period of 90 days.
     * @param jobName Name for the scheduled job
     * @param cronExp Cron expression for scheduling
     * @return ID of the scheduled job
     */
    public static Id scheduleJob(String jobName, String cronExp) {
        ArchiveOldLogsScheduler scheduler = new ArchiveOldLogsScheduler();
        return System.schedule(jobName, cronExp, scheduler);
    }
}
