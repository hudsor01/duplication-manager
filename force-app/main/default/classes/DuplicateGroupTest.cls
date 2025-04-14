/**
 * Test class for DuplicateGroup
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class DuplicateGroupTest {
  /**
   * Test basic functionality of the DuplicateGroup class
   */
  @isTest
  static void testBasicFunctionality() {
    // Create test data
    List<Account> accounts = new List<Account>();

    Account account1 = new Account(
      Name = 'Test Account 1',
      BillingStreet = '123 Main St',
      Phone = '555-123-4567'
    );

    Account account2 = new Account(
      Name = 'Test Account 2',
      BillingStreet = '456 Market St',
      Phone = '555-987-6543'
    );

    // Insert accounts to generate IDs
    insert new List<Account>{ account1, account2 };

    // Refresh account records to get all fields
    account1 = [
      SELECT Id, Name, BillingStreet, Phone, CreatedDate
      FROM Account
      WHERE Id = :account1.Id
    ];
    account2 = [
      SELECT Id, Name, BillingStreet, Phone, CreatedDate
      FROM Account
      WHERE Id = :account2.Id
    ];

    // Create a duplicate group
    DuplicateGroup dupGroup = new DuplicateGroup(
      new List<SObject>{ account1, account2 },
      85.5,
      'test-group-key',
      false
    );

    // Verify group properties
    System.assertEquals(
      2,
      dupGroup.getRecordCount(),
      'Record count should be 2'
    );
    System.assertEquals(
      85.5,
      dupGroup.matchScore,
      'Match score should be 85.5'
    );
    System.assertEquals(
      'test-group-key',
      dupGroup.groupKey,
      'Group key should match'
    );
    System.assertEquals(
      false,
      dupGroup.isExactMatch,
      'Should not be an exact match'
    );
    System.assertEquals(
      true,
      dupGroup.hasDuplicates(),
      'Should have duplicates'
    );

    // Test getDuplicateIds with account1 as master
    List<Id> duplicateIds = dupGroup.getDuplicateIds(account1);
    System.assertEquals(1, duplicateIds.size(), 'Should have 1 duplicate ID');
    System.assertEquals(
      account2.Id,
      duplicateIds[0],
      'Duplicate ID should match account2'
    );
  }

  /**
   * Test getMasterRecord with different strategies
   */
  @isTest
  static void testGetMasterRecordStrategies() {
    // Create test data with different created dates
    List<Account> accounts = new List<Account>();

    Account oldestAccount = new Account(
      Name = 'Oldest Account',
      BillingStreet = '123 Main St',
      Phone = '555-123-4567'
    );

    Account newestAccount = new Account(
      Name = 'Newest Account',
      BillingStreet = '456 Market St',
      Phone = '555-987-6543'
    );

    // Complete account with more fields populated
    Account completeAccount = new Account(
      Name = 'Complete Account',
      BillingStreet = '789 Broadway',
      BillingCity = 'San Francisco',
      BillingState = 'CA',
      BillingPostalCode = '94105',
      BillingCountry = 'USA',
      Phone = '555-555-5555',
      Website = 'www.example.com',
      Industry = 'Technology'
    );

    // Insert accounts to generate IDs
    insert new List<Account>{ oldestAccount };

    // Sleep to ensure different created dates
    Test.startTest();
    // Sleep for 1 second
    Long startTime = System.now().getTime();
    while (System.now().getTime() - startTime < 1000) {
      // Wait for at least 1 second
    }

    insert new List<Account>{ newestAccount, completeAccount };
    Test.stopTest();

    // Refresh account records to get all fields including CreatedDate
    oldestAccount = [
      SELECT
        Id,
        Name,
        BillingStreet,
        BillingCity,
        BillingState,
        BillingPostalCode,
        BillingCountry,
        Phone,
        Website,
        Industry,
        CreatedDate
      FROM Account
      WHERE Id = :oldestAccount.Id
    ];

    newestAccount = [
      SELECT
        Id,
        Name,
        BillingStreet,
        BillingCity,
        BillingState,
        BillingPostalCode,
        BillingCountry,
        Phone,
        Website,
        Industry,
        CreatedDate
      FROM Account
      WHERE Id = :newestAccount.Id
    ];

    completeAccount = [
      SELECT
        Id,
        Name,
        BillingStreet,
        BillingCity,
        BillingState,
        BillingPostalCode,
        BillingCountry,
        Phone,
        Website,
        Industry,
        CreatedDate
      FROM Account
      WHERE Id = :completeAccount.Id
    ];

    // Create a duplicate group
    DuplicateGroup dupGroup = new DuplicateGroup(
      new List<SObject>{ oldestAccount, newestAccount, completeAccount },
      90.0,
      'test-strategy-group',
      false
    );

    // Test OldestCreated strategy
    SObject masterRecord = dupGroup.getMasterRecord('OldestCreated');
    System.assertEquals(
      oldestAccount.Id,
      masterRecord.Id,
      'Oldest account should be selected'
    );

    // Test NewestCreated strategy
    masterRecord = dupGroup.getMasterRecord('NewestCreated');
    System.assertEquals(
      newestAccount.Id,
      masterRecord.Id,
      'Newest account should be selected'
    );

    // Test MostComplete strategy
    masterRecord = dupGroup.getMasterRecord('MostComplete');
    System.assertEquals(
      completeAccount.Id,
      masterRecord.Id,
      'Most complete account should be selected'
    );

    // Test default strategy (should default to OldestCreated)
    masterRecord = dupGroup.getMasterRecord('UnknownStrategy');
    System.assertEquals(
      oldestAccount.Id,
      masterRecord.Id,
      'Default should select oldest account'
    );
  }

  /**
   * Test edge cases and null handling
   */
  @isTest
  static void testEdgeCases() {
    // Test empty group
    DuplicateGroup emptyGroup = new DuplicateGroup(
      new List<SObject>(),
      0.0,
      'empty-group',
      true
    );

    System.assertEquals(
      0,
      emptyGroup.getRecordCount(),
      'Record count should be 0'
    );
    System.assertEquals(
      false,
      emptyGroup.hasDuplicates(),
      'Empty group should not have duplicates'
    );
    System.assertEquals(
      null,
      emptyGroup.getMasterRecord('OldestCreated'),
      'Master record should be null for empty group'
    );
    System.assertEquals(
      0,
      emptyGroup.getDuplicateIds(null).size(),
      'No duplicate IDs for empty group'
    );

    // Test single record group
    Account singleAccount = new Account(Name = 'Single Account');
    insert singleAccount;

    DuplicateGroup singleGroup = new DuplicateGroup(
      new List<SObject>{ singleAccount },
      100.0,
      'single-group',
      true
    );

    System.assertEquals(
      1,
      singleGroup.getRecordCount(),
      'Record count should be 1'
    );
    System.assertEquals(
      false,
      singleGroup.hasDuplicates(),
      'Single record group should not have duplicates'
    );
    System.assertEquals(
      singleAccount.Id,
      singleGroup.getMasterRecord('OldestCreated').Id,
      'Master record should be the single account'
    );
    System.assertEquals(
      0,
      singleGroup.getDuplicateIds(singleAccount).size(),
      'No duplicate IDs for single record group'
    );

    // Test null master record for getDuplicateIds
    Account account1 = new Account(Name = 'Test Account 1');
    Account account2 = new Account(Name = 'Test Account 2');
    insert new List<Account>{ account1, account2 };

    DuplicateGroup normalGroup = new DuplicateGroup(
      new List<SObject>{ account1, account2 },
      90.0,
      'normal-group',
      false
    );

    List<Id> duplicateIds = normalGroup.getDuplicateIds(null);
    System.assertEquals(
      0,
      duplicateIds.size(),
      'Should handle null master record gracefully'
    );
  }
}
