/**
 * Test class for DuplicateRecordUtility
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class DuplicateRecordUtilityTest {
  /**
   * Tests the createCompositeKey method
   */
  @isTest
  static void testCreateCompositeKey() {
    // Create test account
    Account testAccount = new Account(
      Name = 'Test Account',
      Phone = '555-1234',
      BillingCity = 'San Francisco'
    );

    // Test composite key creation
    List<String> fields = new List<String>{ 'Name', 'Phone', 'BillingCity' };
    String key = DuplicateRecordUtility.createCompositeKey(testAccount, fields);

    // Verify key format
    List<String> keyParts = key.split('\\|#\\|');
    System.assertEquals(3, keyParts.size(), 'Key should have 3 parts');
    System.assertEquals(
      'test account',
      keyParts[0],
      'First part should be lowercase name'
    );
    System.assertEquals('555-1234', keyParts[1], 'Second part should be phone');
    System.assertEquals(
      'san francisco',
      keyParts[2],
      'Third part should be lowercase city'
    );

    // Test with null values
    testAccount.Phone = null;
    key = DuplicateRecordUtility.createCompositeKey(testAccount, fields);
    keyParts = key.split('\\|#\\|');
    System.assertEquals(3, keyParts.size(), 'Key should still have 3 parts');
    System.assertEquals('', keyParts[1], 'Null value should be empty string');
  }

  /**
   * Tests the groupDuplicates method
   */
  @isTest
  static void testGroupDuplicates() {
    // Create test records
    List<Account> accounts = new List<Account>{
      new Account(
        Name = 'Duplicate Account',
        Phone = '555-1234',
        BillingCity = 'San Francisco'
      ),
      new Account(
        Name = 'Duplicate Account',
        Phone = '555-1234',
        BillingCity = 'San Francisco'
      ),
      new Account(
        Name = 'Different Account',
        Phone = '555-9876',
        BillingCity = 'New York'
      ),
      new Account(
        Name = 'Duplicate Account',
        Phone = '555-1234',
        BillingCity = 'San Francisco'
      ),
      new Account(
        Name = 'Another Account',
        Phone = '555-4321',
        BillingCity = 'Chicago'
      )
    };

    // Insert test records to get IDs
    insert accounts;

    // Refresh the records
    accounts = [
      SELECT Id, Name, Phone, BillingCity
      FROM Account
      WHERE Id IN :accounts
      ORDER BY Name
    ];

    // Group duplicates
    List<String> fields = new List<String>{ 'Name', 'Phone', 'BillingCity' };
    Map<String, List<SObject>> duplicateGroups = DuplicateRecordUtility.groupDuplicates(
      accounts,
      fields
    );

    // Verify grouping
    System.assertEquals(
      1,
      duplicateGroups.size(),
      'Should find one group of duplicates'
    );

    String duplicateKey = null;
    for (String key : duplicateGroups.keySet()) {
      duplicateKey = key;
      break;
    }

    System.assertNotEquals(null, duplicateKey, 'Should have a duplicate key');
    System.assertEquals(
      3,
      duplicateGroups.get(duplicateKey).size(),
      'Should have 3 records in the duplicate group'
    );
  }

  /**
   * Tests the determineMasterRecord method with OldestCreated strategy
   */
  @isTest
  static void testDetermineMasterRecordOldest() {
    // Create test records with different created dates
    Account oldest = new Account(Name = 'Oldest Account');
    Account middle = new Account(Name = 'Middle Account');
    Account newest = new Account(Name = 'Newest Account');

    // Insert in reverse order to control CreatedDate
    insert newest;
    System.Test.setCreatedDate(newest.Id, Datetime.now());

    insert middle;
    System.Test.setCreatedDate(middle.Id, Datetime.now().addDays(-5));

    insert oldest;
    System.Test.setCreatedDate(oldest.Id, Datetime.now().addDays(-10));

    // Refresh the records to get the CreatedDate field
    List<Account> accounts = [
      SELECT Id, Name, CreatedDate
      FROM Account
      WHERE Id IN (:oldest.Id, :middle.Id, :newest.Id)
      ORDER BY CreatedDate
    ];

    // Determine master with OldestCreated strategy
    SObject masterRecord = DuplicateRecordUtility.determineMasterRecord(
      accounts,
      'OldestCreated'
    );

    // Verify result
    System.assertEquals(
      oldest.Id,
      masterRecord.Id,
      'Oldest record should be selected as master'
    );
  }

  /**
   * Tests the determineMasterRecord method with NewestCreated strategy
   */
  @isTest
  static void testDetermineMasterRecordNewest() {
    // Create test records with different created dates
    Account oldest = new Account(Name = 'Oldest Account');
    Account middle = new Account(Name = 'Middle Account');
    Account newest = new Account(Name = 'Newest Account');

    // Insert in reverse order to control CreatedDate
    insert newest;
    System.Test.setCreatedDate(newest.Id, Datetime.now());

    insert middle;
    System.Test.setCreatedDate(middle.Id, Datetime.now().addDays(-5));

    insert oldest;
    System.Test.setCreatedDate(oldest.Id, Datetime.now().addDays(-10));

    // Refresh the records to get the CreatedDate field
    List<Account> accounts = [
      SELECT Id, Name, CreatedDate
      FROM Account
      WHERE Id IN (:oldest.Id, :middle.Id, :newest.Id)
      ORDER BY CreatedDate
    ];

    // Determine master with NewestCreated strategy
    SObject masterRecord = DuplicateRecordUtility.determineMasterRecord(
      accounts,
      'NewestCreated'
    );

    // Verify result
    System.assertEquals(
      newest.Id,
      masterRecord.Id,
      'Newest record should be selected as master'
    );
  }

  /**
   * Tests the determineMasterRecord method with MostComplete strategy
   */
  @isTest
  static void testDetermineMasterRecordMostComplete() {
    // Create test records with varying completeness
    Account least = new Account(Name = 'Least Complete');
    Account most = new Account(
      Name = 'Most Complete',
      Phone = '555-1234',
      Website = 'https://example.com',
      BillingStreet = '123 Main St',
      BillingCity = 'San Francisco',
      BillingState = 'CA',
      BillingPostalCode = '94105',
      BillingCountry = 'USA'
    );
    Account medium = new Account(
      Name = 'Medium Complete',
      Phone = '555-5678',
      Website = 'https://medium.com'
    );

    insert new List<Account>{ least, most, medium };

    // Refresh the records to get all fields
    List<Account> accounts = [
      SELECT
        Id,
        Name,
        Phone,
        Website,
        BillingStreet,
        BillingCity,
        BillingState,
        BillingPostalCode,
        BillingCountry
      FROM Account
      WHERE Id IN (:least.Id, :most.Id, :medium.Id)
    ];

    // Determine master with MostComplete strategy
    SObject masterRecord = DuplicateRecordUtility.determineMasterRecord(
      accounts,
      'MostComplete'
    );

    // Verify result
    System.assertEquals(
      most.Id,
      masterRecord.Id,
      'Most complete record should be selected as master'
    );
  }

  /**
   * Tests the createMergeDocumentationNote method
   */
  @isTest
  static void testCreateMergeDocumentationNote() {
    // Create a master record
    Account master = new Account(Name = 'Master Account');
    insert master;

    // Create duplicate records
    List<Account> dupes = new List<Account>{
      new Account(Name = 'Dupe 1'),
      new Account(Name = 'Dupe 2')
    };
    insert dupes;

    // Create the documentation note
    List<Id> dupeIds = new List<Id>{ dupes[0].Id, dupes[1].Id };
    Test.startTest();
    Id noteId = DuplicateRecordUtility.createMergeDocumentationNote(
      master.Id,
      dupeIds
    );
    Test.stopTest();

    // Verify note was created
    System.assertNotEquals(null, noteId, 'Note should be created');

    // Verify the standard Note was created with the right parent
    List<Note> notes = [
      SELECT Id, ParentId, Title, Body
      FROM Note
      WHERE ParentId = :master.Id
    ];

    System.assertEquals(
      1,
      notes.size(),
      'Note should be created and linked to master record'
    );
    System.assertEquals(
      'Record Merge Documentation',
      notes[0].Title,
      'Note title should match'
    );
    System.assert(
      notes[0].Body.contains(dupeIds[0]),
      'Note body should contain first duplicate ID'
    );
    System.assert(
      notes[0].Body.contains(dupeIds[1]),
      'Note body should contain second duplicate ID'
    );
  }

  /**
   * Tests the mergeRecords method
   */
  @isTest
  static void testMergeRecords() {
    // Create a master record
    Account master = new Account(Name = 'Master Account', Phone = '555-1234');
    insert master;

    // Create duplicate records
    List<Account> dupes = new List<Account>{
      new Account(Name = 'Dupe 1', Description = 'First duplicate'),
      new Account(Name = 'Dupe 2', Website = 'https://example.com')
    };
    insert dupes;

    // Perform merge
    Test.startTest();
    Integer mergeCount = DuplicateRecordUtility.mergeRecords(
      master.Id,
      new List<Id>{ dupes[0].Id, dupes[1].Id }
    );
    Test.stopTest();

    // Verify merge count
    System.assertEquals(2, mergeCount, 'Should have merged 2 records');

    // Verify duplicates no longer exist
    List<Account> remainingDupes = [SELECT Id FROM Account WHERE Id IN :dupes];
    System.assertEquals(
      0,
      remainingDupes.size(),
      'Duplicates should be merged'
    );
  }

  /**
   * Tests error handling in the mergeRecords method
   */
  @isTest
  static void testMergeRecordsErrorHandling() {
    // Create a master record
    Account master = new Account(Name = 'Master Account', Phone = '555-1234');
    insert master;

    // Create test with invalid ID
    Test.startTest();
    Integer mergeCount = DuplicateRecordUtility.mergeRecords(
      master.Id,
      new List<Id>{ null }
    );
    Test.stopTest();

    // Verify merge count - should be 0 since we had an invalid ID
    System.assertEquals(
      0,
      mergeCount,
      'Should have merged 0 records with invalid ID'
    );

    // Test with empty list
    mergeCount = DuplicateRecordUtility.mergeRecords(master.Id, new List<Id>());
    System.assertEquals(0, mergeCount, 'Should handle empty list gracefully');

    // Test with null list
    mergeCount = DuplicateRecordUtility.mergeRecords(master.Id, null);
    System.assertEquals(0, mergeCount, 'Should handle null list gracefully');
  }

  /**
   * Tests the edge case of an empty list for determineMasterRecord
   */
  @isTest
  static void testDetermineMasterRecordEmptyList() {
    // Test with empty list
    SObject masterRecord = DuplicateRecordUtility.determineMasterRecord(
      new List<SObject>(),
      'OldestCreated'
    );
    System.assertEquals(
      null,
      masterRecord,
      'Should return null for empty list'
    );

    // Test with null list
    masterRecord = DuplicateRecordUtility.determineMasterRecord(
      null,
      'OldestCreated'
    );
    System.assertEquals(null, masterRecord, 'Should return null for null list');
  }
}
