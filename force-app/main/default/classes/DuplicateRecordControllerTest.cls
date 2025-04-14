/**
 * Test class for DuplicateRecordController
 * @description This test class validates the functionality of DuplicateRecordController.
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class DuplicateRecordControllerTest {
  /**
   * Set up test data
   * @description Creates test accounts and duplicate records for testing purposes.
   */
  @TestSetup
  static void setupTestData() {
    // Create test accounts with duplicates
    List<Account> accounts = new List<Account>{
      new Account(
        Name = 'Test Company A',
        Phone = '555-1234',
        BillingCity = 'San Francisco'
      ),
      new Account(
        Name = 'Test Company A',
        Phone = '555-1234',
        BillingCity = 'San Francisco'
      ),
      new Account(
        Name = 'Unique Company',
        Phone = '555-3456',
        BillingCity = 'Boston'
      )
    };

    insert accounts;

    // Create a mock duplicate run result
    DuplicateRunResult__c runResult = new DuplicateRunResult__c(
      BatchJobId__c = 'batch-001',
      ConfigurationName__c = 'Test Configuration',
      ObjectApiName__c = 'Account',
      IsDryRun__c = true,
      DuplicatesFound__c = 1,
      RecordsProcessed__c = 3,
      RecordsMerged__c = 0,
      ProcessingTimeMs__c = 1500,
      AverageMatchScore__c = 90.5,
      Status__c = 'Completed'
    );

    insert runResult;

    // Create a duplicate group detail
    DuplicateGroupDetail__c duplicateGroup = new DuplicateGroupDetail__c(
      DuplicateRunResult__c = runResult.Id,
      GroupKey__c = 'key-001',
      RecordCount__c = 2,
      MatchScore__c = 90.5,
      FieldValues__c = '{"Name":"Test Company A","Phone":"555-1234"}',
      MasterRecordId__c = accounts[0].Id,
      DuplicateRecordIds__c = accounts[1].Id,
      ObjectName__c = 'Account'
    );

    insert duplicateGroup;
  }

  /**
   * Test implementation of getActiveSettings method
   */
  @isTest
  static void testGetActiveSettings() {
    Test.startTest();

    // Get settings - will return empty list in test context
    List<Map<String, Object>> settings = DuplicateRecordController.getActiveSettings();

    Test.stopTest();

    // No settings in test context (since metadata doesn't exist)
    System.assertNotEquals(null, settings, 'Settings should not be null');
  }

  /**
   * Tests the getDuplicateRunResults method
   */
  @isTest
  static void testGetDuplicateRunResults() {
    // Get the batch job ID
    DuplicateRunResult__c runResult = [
      SELECT BatchJobId__c
      FROM DuplicateRunResult__c
      LIMIT 1
    ];
    String batchJobId = runResult.BatchJobId__c;

    Test.startTest();

    // Get results
    Map<String, Object> results = DuplicateRecordController.getDuplicateRunResults(
      batchJobId,
      10, // pageSize
      1, // pageNumber
      null // filters - optional parameter
    );

    Test.stopTest();

    // Verify results
    System.assertNotEquals(null, results, 'Results should not be null');

    // Check summary
    Map<String, Object> summary = (Map<String, Object>) results.get('summary');
    System.assertEquals(
      batchJobId,
      summary.get('batchJobId'),
      'Batch job ID should match'
    );
    System.assertEquals(
      'Test Configuration',
      summary.get('configName'),
      'Configuration name should match'
    );
    System.assertEquals(
      'Account',
      summary.get('objectApiName'),
      'Object API name should match'
    );
    System.assertEquals(
      true,
      summary.get('isDryRun'),
      'Is dry run flag should match'
    );
    System.assertEquals(
      1,
      summary.get('duplicatesFound'),
      'Duplicates found count should match'
    );

    // Check groups
    List<Map<String, Object>> groups = (List<Map<String, Object>>) results.get(
      'groups'
    );
    System.assertEquals(1, groups.size(), 'Should have 1 duplicate group');

    // Check pagination
    Map<String, Object> pagination = (Map<String, Object>) results.get(
      'pagination'
    );
    System.assertEquals(
      10,
      pagination.get('pageSize'),
      'Page size should match'
    );
    System.assertEquals(
      1,
      pagination.get('pageNumber'),
      'Page number should match'
    );
    System.assertEquals(
      1,
      pagination.get('totalRecords'),
      'Total records should match'
    );
    System.assertEquals(
      1,
      pagination.get('totalPages'),
      'Total pages should match'
    );
  }

  /**
   * Tests the mergeDuplicateRecords method
   */
  @isTest
  static void testMergeDuplicateRecords() {
    // Get test accounts
    List<Account> accounts = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Company A'
    ];

    // Ensure we have at least 2 duplicate accounts
    System.assertEquals(2, accounts.size(), 'Should have 2 duplicate accounts');

    Id masterId = accounts[0].Id;
    List<String> dupeIds = new List<String>{ accounts[1].Id };
    String objectApiName = 'Account';

    Test.startTest();

    // Merge the accounts
    // Using a map to match the mergeDuplicateRecords method signature
    Map<String, Object> request = new Map<String, Object>{
      'masterRecordId' => masterId,
      'duplicateRecordIds' => dupeIds,
      'objectApiName' => objectApiName
    };

    Map<String, Object> result = DuplicateRecordController.mergeDuplicateRecords(
      request
    );

    Test.stopTest();

    // Verify result
    System.assertNotEquals(null, result, 'Result should not be null');
    System.assertEquals(
      true,
      result.get('success'),
      'Merge should be successful'
    );

    // Check that records were merged
    Integer accountCount = [SELECT COUNT() FROM Account];
    System.assertEquals(
      2,
      accountCount,
      'Should have 2 accounts after merge (1 merged, 1 unique)'
    );
  }

  /**
   * Tests the checkForDuplicates method
   */
  @isTest
  static void testCheckForDuplicates() {
    // Get a test account
    Account account = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Company A'
      LIMIT 1
    ];

    Test.startTest();

    // Check for duplicates
    Map<String, Object> request = new Map<String, Object>{
      'objectApiName' => 'Account',
      'recordId' => account.Id,
      'matchFields' => new List<String>{ 'Name', 'Phone', 'BillingCity' }
    };

    Map<String, Object> result = DuplicateRecordController.checkForDuplicates(
      request
    );

    Test.stopTest();

    // Verify result
    System.assertNotEquals(null, result, 'Result should not be null');

    // Check duplicates found
    Integer duplicatesFound = (Integer) result.get('duplicatesFound');
    List<Map<String, Object>> duplicates = (List<Map<String, Object>>) result.get(
      'duplicates'
    );

    System.assertEquals(1, duplicatesFound, 'Should find 1 duplicate');
    System.assertEquals(
      1,
      duplicates.size(),
      'Should have 1 duplicate in list'
    );

    // Verify duplicate details
    Map<String, Object> dupe = duplicates[0];
    System.assertNotEquals(
      null,
      dupe.get('id'),
      'Duplicate ID should not be null'
    );
    System.assertNotEquals(
      null,
      dupe.get('matchScore'),
      'Match score should not be null'
    );
  }
}
