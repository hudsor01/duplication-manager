/**
 * Test class for DuplicateRecordStatisticsController
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class DuplicateRecordStatisticsControllerTest {

    /**
     * Set up test data
     */
    @TestSetup
    static void setupTestData() {
        // Create test statistics records
        List<DuplicateJobStatistic__c> stats = new List<DuplicateJobStatistic__c>{
            new DuplicateJobStatistic__c(
                ConfigurationName__c = 'Account Configuration',
                ObjectApiName__c = 'Account',
                DuplicatesFound__c = 10,
                RecordsMerged__c = 5,
                RecordsProcessed__c = 100,
                IsDryRun__c = false,
                JobCompletionTime__c = System.now(),
                MatchScore__c = 80.5
            ),
            new DuplicateJobStatistic__c(
                ConfigurationName__c = 'Contact Configuration',
                ObjectApiName__c = 'Contact',
                DuplicatesFound__c = 15,
                RecordsMerged__c = 8,
                RecordsProcessed__c = 200,
                IsDryRun__c = false,
                JobCompletionTime__c = System.now().addDays(-1),
                MatchScore__c = 75.2
            ),
            new DuplicateJobStatistic__c(
                ConfigurationName__c = 'Lead Configuration',
                ObjectApiName__c = 'Lead',
                DuplicatesFound__c = 7,
                RecordsMerged__c = 0,
                RecordsProcessed__c = 50,
                IsDryRun__c = true,
                JobCompletionTime__c = System.now().addDays(-2),
                MatchScore__c = 90.0
            )
        };

        insert stats;
    }

    /**
     * Tests the getDuplicateStatistics method
     */
    @isTest
    static void testGetDuplicateStatistics() {
        Test.startTest();

        // Get statistics
        Map<String, Object> stats = DuplicateRecordStatisticsController.getDuplicateStatistics();

        Test.stopTest();

        // Verify results
        System.assertNotEquals(null, stats, 'Statistics should not be null');

        // Check totals
        Decimal totalDuplicates = (Decimal)stats.get('totalDuplicates');
        Decimal totalMerged = (Decimal)stats.get('totalMerged');
        Integer totalJobs = (Integer)stats.get('totalJobs');

        System.assertEquals(32, totalDuplicates, 'Total duplicates should be 32 (10+15+7)');
        System.assertEquals(13, totalMerged, 'Total merged should be 13 (5+8+0)');
        System.assertEquals(3, totalJobs, 'Total jobs should be 3');

        // Check by object
        Map<String, Map<String, Object>> byObject = (Map<String, Map<String, Object>>)stats.get('byObject');
        System.assertEquals(3, byObject.size(), 'Should have statistics for 3 objects');

        // Check recent merges
        List<Map<String, Object>> recentMerges = (List<Map<String, Object>>)stats.get('recentMerges');
        System.assertEquals(3, recentMerges.size(), 'Should have 3 recent merges');
    }

    /**
     * Tests the getPaginatedJobStatistics method
     */
    @isTest
    static void testGetPaginatedJobStatistics() {
        Test.startTest();

        // Get paginated statistics
        Map<String, Object> result = DuplicateRecordStatisticsController.getPaginatedJobStatistics(2, 1);

        Test.stopTest();

        // Verify results
        System.assertNotEquals(null, result, 'Result should not be null');

        // Check records
        List<Map<String, Object>> records = (List<Map<String, Object>>)result.get('records');
        System.assertEquals(2, records.size(), 'Should have 2 records per page');

        // Check pagination
        Integer totalRecords = (Integer)result.get('totalRecords');
        Integer totalPages = (Integer)result.get('totalPages');
        Integer pageSize = (Integer)result.get('pageSize');
        Integer pageNumber = (Integer)result.get('pageNumber');

        System.assertEquals(3, totalRecords, 'Total records should be 3');
        System.assertEquals(2, totalPages, 'Total pages should be 2');
        System.assertEquals(2, pageSize, 'Page size should be 2');
        System.assertEquals(1, pageNumber, 'Page number should be 1');

        // Test second page
        result = DuplicateRecordStatisticsController.getPaginatedJobStatistics(2, 2);
        records = (List<Map<String, Object>>)result.get('records');
        System.assertEquals(1, records.size(), 'Should have 1 record on the second page');
    }

    /**
     * Tests the clearAllJobStatistics method
     */
    @isTest
    static void testClearAllJobStatistics() {
        // Verify test data exists
        Integer beforeCount = [SELECT COUNT() FROM DuplicateJobStatistic__c];
        System.assertEquals(3, beforeCount, 'Should have 3 job statistics records before test');

        Test.startTest();

        // Clear statistics
        Integer deletedCount = DuplicateRecordStatisticsController.clearAllJobStatistics();

        Test.stopTest();

        // Verify results
        System.assertEquals(3, deletedCount, 'Should report 3 deleted records');

        // Verify records were deleted
        Integer afterCount = [SELECT COUNT() FROM DuplicateJobStatistic__c];
        System.assertEquals(0, afterCount, 'Should have 0 job statistics records after deletion');
    }
}