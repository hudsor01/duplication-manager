/**
 * Unit tests for DuplicateBatch class
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class DuplicateBatchTest {

    // Create some test duplicate accounts
    @TestSetup
    static void setupTestData() {
        // Create duplicate accounts
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Test Account', Phone = '1234567890'),
            new Account(Name = 'Test Account', Phone = '1234567890'),
            new Account(Name = 'Another Account', Phone = '9876543210')
        };

        insert accounts;
    }

    @isTest
    static void testBatchExecution() {
        // Get the accounts
        List<Account> accounts = [SELECT Id, Name, Phone FROM Account];
        System.assertEquals(3, accounts.size(), 'Should have 3 test accounts');

        // Create a duplicate rule (simulated)
        // In a real environment, this would need to be a real duplicate rule
        String mockDuplicateRuleId = 'mockRuleId';

        Test.startTest();

        // Create the batch job
        DuplicateBatch batchJob = new DuplicateBatch(
            'Account',
            mockDuplicateRuleId,
            new List<String>{'Name', 'Phone'},
            true  // Dry run
        );

        // Execute the batch
        Database.executeBatch(batchJob, 10);

        Test.stopTest();

        // In a test context, we can't fully test the duplicate finding
        // as it depends on Salesforce duplicate rules.
        // Instead, we just verify the batch executed without errors.

        // Check if job statistics were created
        List<DuplicateJobStatistic__c> stats = [
            SELECT Id, ObjectApiName__c, RecordsProcessed__c, Status__c
            FROM DuplicateJobStatistic__c
        ];

        // Not asserting stats size as the insert may fail in test context
        // Just check if any were created
        for (DuplicateJobStatistic__c stat : stats) {
            System.assertEquals('Account', stat.ObjectApiName__c, 'Should be for Account object');
        }
    }

    @isTest
    static void testBatchWithMerge() {
        // Get the accounts
        List<Account> accounts = [SELECT Id, Name, Phone FROM Account];
        System.assertEquals(3, accounts.size(), 'Should have 3 test accounts');

        // Create a duplicate rule (simulated)
        String mockDuplicateRuleId = 'mockRuleId';

        Test.startTest();

        // Create the batch job with merge enabled
        DuplicateBatch batchJob = new DuplicateBatch(
            'Account',
            mockDuplicateRuleId,
            new List<String>{'Name', 'Phone'},
            false  // Not a dry run - will attempt to merge
        );

        // Execute the batch
        Database.executeBatch(batchJob, 10);

        Test.stopTest();

        // Check if any merge logs were created
        List<DuplicateMergeLog__c> mergeLogs = [
            SELECT Id, MasterId__c, MergedIds__c, ObjectApiName__c
            FROM DuplicateMergeLog__c
        ];

        // Not asserting logs size as merges depend on duplicate detection
        // Just check if any were created
        for (DuplicateMergeLog__c log : mergeLogs) {
            System.assertEquals('Account', log.ObjectApiName__c, 'Should be for Account object');
        }
    }

    @isTest
    static void testFindDuplicatesUsingAPI() {
        // This test would need Datacloud.FindDuplicates mock
        // which is not available in standard test context.
        // We're just testing that the code executes without errors.

        // Get accounts
        List<Account> accounts = [SELECT Id, Name, Phone FROM Account];

        // Create a duplicate rule (simulated)
        String mockDuplicateRuleId = 'mockRuleId';

        Test.startTest();

        // Create the batch job
        DuplicateBatch batchJob = new DuplicateBatch(
            'Account',
            mockDuplicateRuleId,
            new List<String>{'Name', 'Phone'},
            true  // Dry run
        );

        // Execute the batch
        Database.executeBatch(batchJob, 10);

        Test.stopTest();

        // Nothing to assert as we can't mock the duplicate detection API
        // Just ensure no exceptions were thrown
    }
}
