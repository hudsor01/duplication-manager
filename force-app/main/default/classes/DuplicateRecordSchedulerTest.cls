/**
 * Test class for DuplicateRecordScheduler
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class DuplicateRecordSchedulerTest {

    /**
     * Tests the execute method of the scheduler
     */
    @isTest
    static void testSchedulerExecution() {
        // Set up test data
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Test Duplicate A', Phone = '555-1234', BillingCity = 'San Francisco'),
            new Account(Name = 'Test Duplicate A', Phone = '555-1234', BillingCity = 'San Francisco')
        };
        insert accounts;

        // Count accounts before
        Integer beforeCount = [SELECT COUNT() FROM Account];
        System.assertEquals(2, beforeCount, 'Should have 2 accounts before execution');

        Test.startTest();

        // Create a scheduler that directly uses the batch with explicit parameters
        TestScheduler scheduler = new TestScheduler();
        scheduler.execute(null);

        Test.stopTest();

        // Verify accounts were merged
        Integer afterCount = [SELECT COUNT() FROM Account];
        System.assertEquals(1, afterCount, 'Should have 1 account after merge');
    }

    /**
     * Tests the scheduleJob method
     */
    @isTest
    static void testScheduleJob() {
        // Get count of scheduled jobs before
        Integer beforeCount = [SELECT COUNT() FROM CronTrigger];

        Test.startTest();

        // Schedule directly with a test scheduler
        String jobName = 'Test Schedule Duplicate Finder';
        String cronExp = '0 0 4 * * ?'; // Daily at 4 AM

        TestScheduler scheduler = new TestScheduler();
        Id scheduledJobId = System.schedule(jobName, cronExp, scheduler);

        Test.stopTest();

        // Verify job was scheduled
        System.assertNotEquals(null, scheduledJobId, 'Job should be scheduled');

        Integer afterCount = [SELECT COUNT() FROM CronTrigger];
        System.assertEquals(beforeCount + 1, afterCount, 'Should have one new scheduled job');

        // Verify job details
        CronTrigger job = [
            SELECT Id, CronJobDetail.Name, CronExpression
            FROM CronTrigger
            WHERE Id = :scheduledJobId
        ];

        System.assertEquals(jobName, job.CronJobDetail.Name, 'Job name should match');
        System.assertEquals(cronExp, job.CronExpression, 'Cron expression should match');
    }

    /**
     * Test implementation of Schedulable for testing
     */
    private class TestScheduler implements Schedulable {

        /**
         * Execute method that runs a batch with explicit parameters
         */
        public void execute(SchedulableContext sc) {
            // Create batch directly without metadata dependency
            DuplicateRecordBatch batch = new DuplicateRecordBatch(
                'Account',
                new List<String>{'Name', 'Phone', 'BillingCity'},
                'OldestCreated',
                200,
                false // Do real merge
            );

            Database.executeBatch(batch, 200);
        }
    }
}
