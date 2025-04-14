/**
 * @description Test class for ArchiveOldLogsScheduler
 *
 * @author Richard Hudson
 * @since April 2025
 */
@isTest
private class ArchiveOldLogsSchedulerTest {

    @isTest
    static void testSchedulerWithDefaultRetention() {
        Test.startTest();

        // Schedule the job
        String cronExp = '0 0 0 ? * SUN'; // Weekly at midnight on Sunday
        String jobName = 'Test Archive Old Logs Job';

        Id jobId = ArchiveOldLogsScheduler.scheduleJob(jobName, cronExp);

        // Verify the job was scheduled
        CronTrigger ct = [
            SELECT Id, CronExpression, TimesTriggered, NextFireTime
            FROM CronTrigger
            WHERE Id = :jobId
        ];

        System.assertEquals(cronExp, ct.CronExpression, 'Cron expression does not match expected value');
        System.assertEquals(0, ct.TimesTriggered, 'Job should not have triggered yet');

        // Execute the job
        ArchiveOldLogsScheduler scheduler = new ArchiveOldLogsScheduler();
        scheduler.execute(null);

        Test.stopTest();

        // Verify that a batch job was executed (indirectly through AsyncApexJob)
        List<AsyncApexJob> jobs = [
            SELECT Id, ApexClassId, Status, JobType
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'ArchiveOldLogsBatch'
        ];

        System.assertNotEquals(0, jobs.size(), 'Expected a batch job to be executed');
    }

    @isTest
    static void testSchedulerWithCustomRetention() {
        Test.startTest();

        // Schedule the job with custom retention period
        String cronExp = '0 0 0 ? * MON-FRI'; // Weekdays at midnight
        String jobName = 'Test Custom Retention Job';
        Integer customDaysToRetain = 30; // 30 days retention

        Id jobId = ArchiveOldLogsScheduler.scheduleJob(jobName, cronExp, customDaysToRetain);

        // Verify the job was scheduled
        CronTrigger ct = [
            SELECT Id, CronExpression, TimesTriggered
            FROM CronTrigger
            WHERE Id = :jobId
        ];

        System.assertEquals(cronExp, ct.CronExpression, 'Cron expression does not match expected value');
        System.assertEquals(0, ct.TimesTriggered, 'Job should not have triggered yet');

        // Execute the job with custom retention period
        ArchiveOldLogsScheduler scheduler = new ArchiveOldLogsScheduler(customDaysToRetain);
        scheduler.execute(null);

        Test.stopTest();

        // Verify that a batch job was executed
        List<AsyncApexJob> jobs = [
            SELECT Id, ApexClassId, Status, JobType
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'ArchiveOldLogsBatch'
        ];

        System.assertNotEquals(0, jobs.size(), 'Expected a batch job to be executed');
    }

    @isTest
    static void testSchedulerWithInvalidRetention() {
        Test.startTest();

        // Create scheduler with invalid retention period (negative number)
        ArchiveOldLogsScheduler scheduler = new ArchiveOldLogsScheduler(-10);
        scheduler.execute(null);

        Test.stopTest();

        // Verify that a batch job was executed with default retention
        List<AsyncApexJob> jobs = [
            SELECT Id, ApexClassId, Status, JobType
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'ArchiveOldLogsBatch'
        ];

        System.assertNotEquals(0, jobs.size(), 'Expected a batch job to be executed');
    }
}
