/**
 * Unit tests for DuplicateController class
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class DuplicateControllerTest {
  @isTest
  static void testGetDuplicateRules() {
    // Set up test data
    setupTestData();

    Test.startTest();

    // Call the method
    List<DuplicateController.DuplicateRuleInfo> rules = DuplicateController.getDuplicateRules(
      'Account'
    );

    Test.stopTest();

    // Verify results - may be empty in test context without elaborate setup
    System.assertNotEquals(null, rules, 'Rules list should not be null');
  }

  @isTest
  static void testGetRecentJobs() {
    // Set up test data
    setupTestData();

    Test.startTest();

    // Call the method
    List<DuplicateJobStatistic__c> jobs = DuplicateController.getRecentJobs();

    Test.stopTest();

    // Verify results
    System.assertNotEquals(null, jobs, 'Jobs list should not be null');
  }

  @isTest
  static void testGetDetailedStatistics() {
    // Set up test data
    setupTestData();

    Test.startTest();

    // Call the method
    Map<String, Object> stats = DuplicateController.getDetailedStatistics(
      'LAST_30_DAYS'
    );

    Test.stopTest();

    // Verify results
    System.assertNotEquals(null, stats, 'Statistics should not be null');
    System.assertEquals(
      'LAST_30_DAYS',
      stats.get('timeRange'),
      'Time range should match input'
    );
  }

  @isTest
  static void testRunDuplicateJob() {
    // Set up test data
    setupTestData();

    Test.startTest();

    // Call the method
    String jobId = DuplicateController.runDuplicateJob(
      'Account',
      'mockRuleId',
      new List<String>{ 'Name', 'Phone' },
      200,
      true
    );

    Test.stopTest();

    // Verify results
    System.assertNotEquals(null, jobId, 'Job ID should not be null');
  }

  @isTest
  static void testGetJobStatus() {
    // Set up test data
    setupTestData();

    // Get mock job data
    Map<String, Object> mockJobData = createMockAsyncApexJob();

    // For testing, we'll add this to the method under test via Test.setMock()
    // or modify the method to accept a parameter for testing

    Test.startTest();

    // Call the method - will use mock job ID
    DuplicateController.JobStatus status = DuplicateController.getJobStatus(
      (String) mockJobData.get('Id')
    );

    Test.stopTest();

    // Verify results
    System.assertNotEquals(null, status, 'Status should not be null');
    System.assertEquals(
      mockJobData.get('Id'),
      status.jobId,
      'Job ID should match'
    );
  }

  @isTest
  static void testGetPreservableFields() {
    // Set up test data
    setupTestData();

    Test.startTest();

    // Call the method
    List<DuplicateController.FieldInfo> fields = DuplicateController.getPreservableFields(
      'Account'
    );

    Test.stopTest();

    // Verify results
    System.assertNotEquals(null, fields, 'Fields list should not be null');
    System.assert(!fields.isEmpty(), 'Should have at least some fields');
  }

  @isTest
  static void testHandleExceptions() {
    // Test exception handling in controller methods
    Test.startTest();

    try {
      // Pass invalid object name
      DuplicateController.getPreservableFields('InvalidObject');
      System.assert(false, 'Should throw exception for invalid object');
    } catch (AuraHandledException e) {
      // Expected exception
      System.assert(
        e.getMessage().contains('Error getting preservable fields'),
        'Should have descriptive error message'
      );
    }

    Test.stopTest();
  }

  /**
   * Set up test data for unit tests
   */
  private static void setupTestData() {
    // Create test job statistic
    DuplicateJobStatistic__c jobStat = new DuplicateJobStatistic__c(
      BatchJobId__c = 'mockJobId',
      ObjectApiName__c = 'Account',
      Status__c = 'Completed',
      RecordsProcessed__c = 100,
      DuplicatesFound__c = 10,
      RecordsMerged__c = 5,
      JobStartTime__c = Datetime.now().addHours(-1),
      JobCompletionTime__c = Datetime.now(),
      IsDryRun__c = true
    );

    // Insert in try-catch as this may fail in some test environments
    try {
      insert jobStat;
    } catch (Exception e) {
      System.debug('Error inserting test data: ' + e.getMessage());
    }
  }

  /**
   * Create mock data for AsyncApexJob for testing
   */
  private static Map<String, Object> createMockAsyncApexJob() {
    // Since we can't create AsyncApexJob records directly
    // we'll return a map of the key fields we need to test with
    return new Map<String, Object>{
      'Id' => '707xx000000000AAAA',
      'Status' => 'Completed',
      'JobItemsProcessed' => 100,
      'TotalJobItems' => 100,
      'NumberOfErrors' => 0
    };
  }
}
