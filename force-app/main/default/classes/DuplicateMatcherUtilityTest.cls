/**
 * Test class for DuplicateMatcherUtility
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class DuplicateMatcherUtilityTest {
  /**
   * Test finding exact duplicate groups
   */
  @isTest
  static void testFindExactDuplicates() {
    // Create test data
    List<Account> accounts = new List<Account>();

    // Add duplicate records with the same name
    accounts.add(
      new Account(
        Name = 'Test Account',
        BillingStreet = '123 Main St',
        BillingCity = 'San Francisco',
        BillingState = 'CA',
        BillingPostalCode = '94105',
        Phone = '(555) 123-4567'
      )
    );

    accounts.add(
      new Account(
        Name = 'Test Account',
        BillingStreet = '123 Main St',
        BillingCity = 'San Francisco',
        BillingState = 'CA',
        BillingPostalCode = '94105',
        Phone = '(555) 123-4567'
      )
    );

    // Add unique record
    accounts.add(
      new Account(
        Name = 'Unique Account',
        BillingStreet = '456 Market St',
        BillingCity = 'Los Angeles',
        BillingState = 'CA',
        BillingPostalCode = '90001',
        Phone = '(555) 987-6543'
      )
    );

    // Insert accounts
    insert accounts;

    // Define fields to match on
    List<String> fields = new List<String>{ 'Name', 'BillingStreet', 'Phone' };

    Test.startTest();

    // Find duplicates
    Map<String, DuplicateGroup> duplicateGroups = DuplicateMatcherUtility.findDuplicateGroups(
      accounts,
      fields
    );

    Test.stopTest();

    // Verify exact match group was found
    System.assertEquals(
      1,
      duplicateGroups.size(),
      'Should find 1 duplicate group'
    );

    // Verify the duplicate group
    DuplicateGroup dupGroup = duplicateGroups.values()[0];
    System.assertEquals(
      2,
      dupGroup.getRecordCount(),
      'Group should have 2 records'
    );
    System.assertEquals(
      100,
      dupGroup.matchScore,
      'Exact match score should be 100'
    );
    System.assertEquals(
      true,
      dupGroup.isExactMatch,
      'Should be an exact match'
    );
  }

  /**
   * Test finding fuzzy duplicate groups
   */
  @isTest
  static void testFindFuzzyDuplicates() {
    // Create test data
    List<Account> accounts = new List<Account>();

    // Add similar records with slight variations
    accounts.add(
      new Account(
        Name = 'Acme Corporation',
        BillingStreet = '100 Pine Street',
        BillingCity = 'San Francisco',
        BillingState = 'CA',
        BillingPostalCode = '94111',
        Phone = '(415) 555-1234'
      )
    );

    accounts.add(
      new Account(
        Name = 'Acme Corp.',
        BillingStreet = '100 Pine St',
        BillingCity = 'San Francisco',
        BillingState = 'CA',
        BillingPostalCode = '94111',
        Phone = '415-555-1234'
      )
    );

    // Add unique record
    accounts.add(
      new Account(
        Name = 'Totally Different Inc',
        BillingStreet = '200 Broadway',
        BillingCity = 'New York',
        BillingState = 'NY',
        BillingPostalCode = '10007',
        Phone = '(212) 555-6789'
      )
    );

    // Insert accounts
    insert accounts;

    // Define fields to match on
    List<String> fields = new List<String>{ 'Name', 'BillingStreet', 'Phone' };

    Test.startTest();

    // Find duplicates
    Map<String, DuplicateGroup> duplicateGroups = DuplicateMatcherUtility.findDuplicateGroups(
      accounts,
      fields
    );

    Test.stopTest();

    // Verify fuzzy match was found
    System.assertNotEquals(
      0,
      duplicateGroups.size(),
      'Should find at least one duplicate group'
    );

    // Loop through groups to find the fuzzy match
    Boolean foundFuzzyMatch = false;
    for (DuplicateGroup dupGroup : duplicateGroups.values()) {
      if (!dupGroup.isExactMatch && dupGroup.getRecordCount() > 1) {
        foundFuzzyMatch = true;
        System.assertNotEquals(
          100,
          dupGroup.matchScore,
          'Fuzzy match score should be less than 100'
        );
        System.assertEquals(
          2,
          dupGroup.getRecordCount(),
          'Group should have 2 records'
        );
      }
    }

    System.assertEquals(
      true,
      foundFuzzyMatch,
      'Should find a fuzzy match group'
    );
  }

  /**
   * Test finding no duplicates
   */
  @isTest
  static void testFindNoDuplicates() {
    // Create test data
    List<Account> accounts = new List<Account>();

    // Add unique records
    accounts.add(
      new Account(
        Name = 'Unique Account 1',
        BillingStreet = '123 Main St',
        BillingCity = 'San Francisco',
        BillingState = 'CA',
        BillingPostalCode = '94105',
        Phone = '(555) 123-4567'
      )
    );

    accounts.add(
      new Account(
        Name = 'Unique Account 2',
        BillingStreet = '456 Market St',
        BillingCity = 'Los Angeles',
        BillingState = 'CA',
        BillingPostalCode = '90001',
        Phone = '(555) 987-6543'
      )
    );

    // Insert accounts
    insert accounts;

    // Define fields to match on
    List<String> fields = new List<String>{ 'Name', 'BillingStreet', 'Phone' };

    Test.startTest();

    // Find duplicates
    Map<String, DuplicateGroup> duplicateGroups = DuplicateMatcherUtility.findDuplicateGroups(
      accounts,
      fields
    );

    Test.stopTest();

    // Verify no duplicate groups were found
    System.assertEquals(
      0,
      duplicateGroups.size(),
      'Should not find any duplicate groups'
    );
  }

  /**
   * Test with empty or null values
   */
  @isTest
  static void testWithEmptyValues() {
    // Create test data
    List<Account> accounts = new List<Account>();

    // Add records with some null fields
    accounts.add(
      new Account(
        Name = 'Test Account',
        BillingStreet = null,
        BillingCity = 'San Francisco',
        BillingState = 'CA',
        BillingPostalCode = '94105',
        Phone = '(555) 123-4567'
      )
    );

    accounts.add(
      new Account(
        Name = 'Test Account',
        BillingStreet = null,
        BillingCity = 'San Francisco',
        BillingState = 'CA',
        BillingPostalCode = '94105',
        Phone = '(555) 123-4567'
      )
    );

    // Insert accounts
    insert accounts;

    // Define fields to match on, including some null fields
    List<String> fields = new List<String>{ 'Name', 'BillingStreet', 'Phone' };

    Test.startTest();

    // Find duplicates
    Map<String, DuplicateGroup> duplicateGroups = DuplicateMatcherUtility.findDuplicateGroups(
      accounts,
      fields
    );

    Test.stopTest();

    // Verify match found even with null fields
    System.assertEquals(
      1,
      duplicateGroups.size(),
      'Should find 1 duplicate group'
    );
  }

  /**
   * Test with a single field
   */
  @isTest
  static void testWithSingleField() {
    // Create test data
    List<Account> accounts = new List<Account>();

    // Add records with the same name
    accounts.add(
      new Account(
        Name = 'Same Name Corp',
        BillingStreet = '123 Main St',
        BillingCity = 'San Francisco',
        Phone = '(555) 123-4567'
      )
    );

    accounts.add(
      new Account(
        Name = 'Same Name Corp',
        BillingStreet = '456 Different St',
        BillingCity = 'Los Angeles',
        Phone = '(555) 987-6543'
      )
    );

    // Insert accounts
    insert accounts;

    // Define fields to match on - just the name
    List<String> fields = new List<String>{ 'Name' };

    Test.startTest();

    // Find duplicates based only on name
    Map<String, DuplicateGroup> duplicateGroups = DuplicateMatcherUtility.findDuplicateGroups(
      accounts,
      fields
    );

    Test.stopTest();

    // Verify exact match found based on single field
    System.assertEquals(
      1,
      duplicateGroups.size(),
      'Should find 1 duplicate group'
    );

    // Verify the duplicate group
    DuplicateGroup dupGroup = duplicateGroups.values()[0];
    System.assertEquals(
      2,
      dupGroup.getRecordCount(),
      'Group should have 2 records'
    );
    System.assertEquals(
      100,
      dupGroup.matchScore,
      'Exact match score should be 100'
    );
    System.assertEquals(
      true,
      dupGroup.isExactMatch,
      'Should be an exact match'
    );
  }
}
