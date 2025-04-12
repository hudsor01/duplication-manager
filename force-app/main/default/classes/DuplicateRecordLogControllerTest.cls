/**
 * Test class for DuplicateRecordLogController
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class DuplicateRecordLogControllerTest {

    /**
     * Set up test data
     */
    @TestSetup
    static void setupTestData() {
        // Create test merge job logs
        List<MergeJobLog__c> logs = new List<MergeJobLog__c>{
            new MergeJobLog__c(
                BatchJobId__c = 'batch-001',
                ConfigurationName__c = 'Account Merge',
                ConfigurationId__c = 'cfg-001',
                ObjectApiName__c = 'Account',
                RecordsMerged__c = 5,
                RecordIdsJSON__c = '{"group1":["001000000001","001000000002","001000000003"]}',
                IsScheduledJob__c = true,
                ExecutionTime__c = System.now(),
                InitiatedBy__c = UserInfo.getUserId()
            ),
            new MergeJobLog__c(
                BatchJobId__c = 'batch-002',
                ConfigurationName__c = 'Contact Merge',
                ConfigurationId__c = 'cfg-002',
                ObjectApiName__c = 'Contact',
                RecordsMerged__c = 8,
                RecordIdsJSON__c = '{"group1":["003000000001","003000000002"]}',
                IsScheduledJob__c = false,
                ExecutionTime__c = System.now().addDays(-1),
                InitiatedBy__c = UserInfo.getUserId()
            ),
            new MergeJobLog__c(
                BatchJobId__c = 'batch-003',
                ConfigurationName__c = 'Lead Merge',
                ConfigurationId__c = 'cfg-003',
                ObjectApiName__c = 'Lead',
                RecordsMerged__c = 3,
                RecordIdsJSON__c = '{"group1":["00Q000000001","00Q000000002"]}',
                IsScheduledJob__c = true,
                ExecutionTime__c = System.now().addDays(-2),
                InitiatedBy__c = UserInfo.getUserId()
            )
        };

        insert logs;
    }

    /**
     * Tests the createMergeJobLog method
     */
    @isTest
    static void testCreateMergeJobLog() {
        Test.startTest();

        // Create a new log
        Id logId = DuplicateRecordLogController.createMergeJobLog(
            'batch-test',
            'Test Configuration',
            'cfg-test',
            'Opportunity',
            7,
            '{"group1":["006000000001","006000000002"]}',
            false
        );

        Test.stopTest();

        // Verify log was created
        System.assertNotEquals(null, logId, 'Log ID should not be null');

        // Verify log details
        MergeJobLog__c log = [
            SELECT BatchJobId__c, ConfigurationName__c, ConfigurationId__c,
                   ObjectApiName__c, RecordsMerged__c, IsScheduledJob__c
            FROM MergeJobLog__c
            WHERE Id = :logId
        ];

        System.assertEquals('batch-test', log.BatchJobId__c, 'Batch job ID should match');
        System.assertEquals('Test Configuration', log.ConfigurationName__c, 'Configuration name should match');
        System.assertEquals('cfg-test', log.ConfigurationId__c, 'Configuration ID should match');
        System.assertEquals('Opportunity', log.ObjectApiName__c, 'Object API name should match');
        System.assertEquals(7, log.RecordsMerged__c, 'Records merged count should match');
        System.assertEquals(false, log.IsScheduledJob__c, 'Is scheduled job flag should match');
    }

    /**
     * Tests the getMergeJobLogs method with no filters
     */
    @isTest
    static void testGetMergeJobLogsNoFilters() {
        Test.startTest();

        // Get logs without filters
        Map<String, Object> result = DuplicateRecordLogController.getMergeJobLogs(
            null, null, 10, 1, null
        );

        Test.stopTest();

        // Verify results
        System.assertNotEquals(null, result, 'Result should not be null');

        // Check records
        List<Map<String, Object>> records = (List<Map<String, Object>>)result.get('records');
        System.assertEquals(3, records.size(), 'Should have 3 log records');

        // Check pagination
        Map<String, Object> pagination = (Map<String, Object>)result.get('pagination');
        System.assertEquals(10, pagination.get('pageSize'), 'Page size should be 10');
        System.assertEquals(1, pagination.get('pageNumber'), 'Page number should be 1');
        System.assertEquals(3, pagination.get('totalRecords'), 'Total records should be 3');
        System.assertEquals(1, pagination.get('totalPages'), 'Total pages should be 1');
    }

    /**
     * Tests the getMergeJobLogs method with object filter
     */
    @isTest
    static void testGetMergeJobLogsWithObjectFilter() {
        Test.startTest();

        // Get logs with object filter
        Map<String, Object> result = DuplicateRecordLogController.getMergeJobLogs(
            'Account', null, 10, 1, null
        );

        Test.stopTest();

        // Verify results
        System.assertNotEquals(null, result, 'Result should not be null');

        // Check records
        List<Map<String, Object>> records = (List<Map<String, Object>>)result.get('records');
        System.assertEquals(1, records.size(), 'Should have 1 log record for Account');

        // Verify record is for Account
        Map<String, Object> record = records[0];
        System.assertEquals('Account', record.get('objectApiName'), 'Object API name should be Account');
    }

    /**
     * Tests the getMergeJobLogs method with configuration filter
     */
    @isTest
    static void testGetMergeJobLogsWithConfigFilter() {
        Test.startTest();

        // Get logs with config filter
        Map<String, Object> result = DuplicateRecordLogController.getMergeJobLogs(
            null, 'cfg-002', 10, 1, null
        );

        Test.stopTest();

        // Verify results
        System.assertNotEquals(null, result, 'Result should not be null');

        // Check records
        List<Map<String, Object>> records = (List<Map<String, Object>>)result.get('records');
        System.assertEquals(1, records.size(), 'Should have 1 log record for config cfg-002');

        // Verify record is for Contact Merge
        Map<String, Object> record = records[0];
        System.assertEquals('Contact Merge', record.get('configName'), 'Config name should be Contact Merge');
    }

    /**
     * Tests the getMergeJobLogs method with date range filter
     */
    @isTest
    static void testGetMergeJobLogsWithDateFilter() {
        Test.startTest();

        // Create filter JSON with date range
        String filters = '{"dateRange": "TODAY"}';

        // Get logs with date filter
        Map<String, Object> result = DuplicateRecordLogController.getMergeJobLogs(
            null, null, 10, 1, filters
        );

        Test.stopTest();

        // Verify results
        System.assertNotEquals(null, result, 'Result should not be null');

        // Check records - should only get logs from today
        List<Map<String, Object>> records = (List<Map<String, Object>>)result.get('records');

        // At least one record is from today (the first one inserted in setup)
        System.assert(records.size() > 0, 'Should have at least one log from today');

        // All records should be from today
        for (Map<String, Object> record : records) {
            Datetime executionTime = (Datetime)record.get('executionTime');
            System.assertEquals(Date.today(), executionTime.date(), 'Execution date should be today');
        }
    }

    /**
     * Tests the getMergeJobLogs method with pagination
     */
    @isTest
    static void testGetMergeJobLogsWithPagination() {
        Test.startTest();

        // Get logs with pagination
        Map<String, Object> result = DuplicateRecordLogController.getMergeJobLogs(
            null, null, 2, 1, null
        );

        Test.stopTest();

        // Verify results
        System.assertNotEquals(null, result, 'Result should not be null');

        // Check records
        List<Map<String, Object>> records = (List<Map<String, Object>>)result.get('records');
        System.assertEquals(2, records.size(), 'Should have 2 records on first page');

        // Check pagination
        Map<String, Object> pagination = (Map<String, Object>)result.get('pagination');
        System.assertEquals(2, pagination.get('pageSize'), 'Page size should be 2');
        System.assertEquals(1, pagination.get('pageNumber'), 'Page number should be 1');
        System.assertEquals(3, pagination.get('totalRecords'), 'Total records should be 3');
        System.assertEquals(2, pagination.get('totalPages'), 'Total pages should be 2');

        // Get second page
        result = DuplicateRecordLogController.getMergeJobLogs(
            null, null, 2, 2, null
        );

        // Verify second page
        records = (List<Map<String, Object>>)result.get('records');
        System.assertEquals(1, records.size(), 'Should have 1 record on second page');
    }
}
