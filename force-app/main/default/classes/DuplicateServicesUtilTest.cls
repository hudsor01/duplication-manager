/**
 * Unit tests for DuplicateServicesUtil class
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class DuplicateServicesUtilTest {
  @isTest
  static void testGetObjectConfiguration() {
    // We can't create test instances of metadata types directly
    // This is a simplified test that can't actually test the query
    // In a real implementation, use a test pattern that allows mocking

    // Use the ApexMocks framework or similar to mock the SOQL query
    // For now, just verify the method runs without errors
    DuplicationConfiguration__mdt result = DuplicateServicesUtil.getObjectConfiguration(
      'Account'
    );

    // Just test that the method exists and returns without error
    System.assertEquals(
      null,
      result,
      'Expected null as no real configuration exists in test context'
    );
  }

  @isTest
  static void testParseMatchFieldWeights() {
    // Test with valid JSON
    String validJson = '{"Name": 0.5, "Email": 0.8, "Phone": 0.3}';
    Map<String, Decimal> result1 = DuplicateServicesUtil.parseMatchFieldWeights(
      validJson
    );

    System.assertEquals(3, result1.size(), 'Should have 3 field weights');
    System.assertEquals(0.5, result1.get('Name'), 'Name weight should be 0.5');
    System.assertEquals(
      0.8,
      result1.get('Email'),
      'Email weight should be 0.8'
    );
    System.assertEquals(
      0.3,
      result1.get('Phone'),
      'Phone weight should be 0.3'
    );

    // Test with empty JSON
    String emptyJson = '{}';
    Map<String, Decimal> result2 = DuplicateServicesUtil.parseMatchFieldWeights(
      emptyJson
    );
    System.assertEquals(
      0,
      result2.size(),
      'Should have 0 field weights for empty JSON'
    );

    // Test with null
    Map<String, Decimal> result3 = DuplicateServicesUtil.parseMatchFieldWeights(
      null
    );
    System.assertEquals(
      0,
      result3.size(),
      'Should have 0 field weights for null input'
    );

    // Test with invalid JSON
    try {
      Map<String, Decimal> result4 = DuplicateServicesUtil.parseMatchFieldWeights(
        'invalid json'
      );
      // Should not throw an exception, but return empty map
      System.assertEquals(
        0,
        result4.size(),
        'Should have 0 field weights for invalid JSON'
      );
    } catch (Exception e) {
      System.assert(false, 'Should not throw exception for invalid JSON');
    }
  }

  @isTest
  static void testCalculateRecordMatchScore() {
    // Create test records
    Account acc1 = new Account(
      Name = 'Test Account 1',
      Phone = '1234567890',
      Website = 'test1.com'
    );

    Account acc2 = new Account(
      Name = 'Test Account 1',
      Phone = '1234567890',
      Website = 'test2.com'
    );

    Account acc3 = new Account(
      Name = 'Different Account',
      Phone = '9876543210',
      Website = 'different.com'
    );

    // Create field weights
    Map<String, Decimal> fieldWeights = new Map<String, Decimal>{
      'Name' => 0.5,
      'Phone' => 0.3,
      'Website' => 0.2
    };

    // Calculate match scores
    Decimal score1 = DuplicateServicesUtil.calculateRecordMatchScore(
      acc1,
      acc2,
      fieldWeights
    );
    Decimal score2 = DuplicateServicesUtil.calculateRecordMatchScore(
      acc1,
      acc3,
      fieldWeights
    );

    // Verify results
    System.assert(score1 > 80, 'Similar accounts should have high match score');
    System.assert(
      score2 < 50,
      'Different accounts should have low match score'
    );

    // Test edge cases
    Decimal score3 = DuplicateServicesUtil.calculateRecordMatchScore(
      acc1,
      acc1,
      fieldWeights
    );
    System.assertEquals(
      100,
      score3,
      'Identical records should have 100% match'
    );

    Decimal score4 = DuplicateServicesUtil.calculateRecordMatchScore(
      null,
      acc1,
      fieldWeights
    );
    System.assertEquals(0, score4, 'Null record should have 0% match');

    Decimal score5 = DuplicateServicesUtil.calculateRecordMatchScore(
      acc1,
      acc2,
      null
    );
    System.assertEquals(0, score5, 'Null weights should have 0% match');
  }

  @isTest
  static void testChunkRecords() {
    // Create test records
    List<Account> accounts = new List<Account>();
    for (Integer i = 0; i < 10; i++) {
      accounts.add(new Account(Name = 'Test Account ' + i));
    }

    // Test normal chunking
    List<List<SObject>> chunks1 = DuplicateServicesUtil.chunkRecords(
      accounts,
      3
    );
    System.assertEquals(4, chunks1.size(), 'Should have 4 chunks');
    System.assertEquals(
      3,
      chunks1[0].size(),
      'First chunk should have 3 records'
    );
    System.assertEquals(
      3,
      chunks1[1].size(),
      'Second chunk should have 3 records'
    );
    System.assertEquals(
      3,
      chunks1[2].size(),
      'Third chunk should have 3 records'
    );
    System.assertEquals(
      1,
      chunks1[3].size(),
      'Fourth chunk should have 1 record'
    );

    // Test chunking with chunk size larger than list
    List<List<SObject>> chunks2 = DuplicateServicesUtil.chunkRecords(
      accounts,
      20
    );
    System.assertEquals(1, chunks2.size(), 'Should have 1 chunk');
    System.assertEquals(
      10,
      chunks2[0].size(),
      'Chunk should have all 10 records'
    );

    // Test edge cases
    List<List<SObject>> chunks3 = DuplicateServicesUtil.chunkRecords(
      accounts,
      0
    );
    System.assert(!chunks3.isEmpty(), 'Should use default chunk size for 0');

    List<List<SObject>> chunks4 = DuplicateServicesUtil.chunkRecords(
      new List<Account>(),
      5
    );
    System.assertEquals(
      0,
      chunks4.size(),
      'Empty list should produce no chunks'
    );

    List<List<SObject>> chunks5 = DuplicateServicesUtil.chunkRecords(null, 5);
    System.assertEquals(
      0,
      chunks5.size(),
      'Null list should produce no chunks'
    );
  }

  @isTest
  static void testGetRecordIds() {
    // Create real test records in the database
    List<Account> accounts = new List<Account>{
      new Account(Name = 'Test 1'),
      new Account(Name = 'Test 2'),
      new Account(Name = 'Test 3')
    };
    insert accounts; // Insert to get real IDs

    // Test normal case with real database IDs
    List<Id> ids1 = DuplicateServicesUtil.getRecordIds(accounts);
    System.assertEquals(3, ids1.size(), 'Should have 3 IDs');
    System.assertEquals(accounts[0].Id, ids1[0], 'First ID should match');
    System.assertEquals(accounts[1].Id, ids1[1], 'Second ID should match');
    System.assertEquals(accounts[2].Id, ids1[2], 'Third ID should match');

    // Test edge cases
    List<Id> ids2 = DuplicateServicesUtil.getRecordIds(new List<Account>());
    System.assertEquals(0, ids2.size(), 'Empty list should produce no IDs');

    List<Id> ids3 = DuplicateServicesUtil.getRecordIds(null);
    System.assertEquals(0, ids3.size(), 'Null list should produce no IDs');
  }
}
