/**
 * Test class for MatcherFactory
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class MatcherFactoryTest {
  /**
   * Test singleton pattern
   */
  @isTest
  static void testSingleton() {
    // Get instance twice and verify they are the same
    MatcherFactory instance1 = MatcherFactory.getInstance();
    MatcherFactory instance2 = MatcherFactory.getInstance();

    // Verify references point to the same instance
    System.assert(instance1 === instance2, 'Should return the same instance');
  }

  /**
   * Test matcher selection for different field types
   */
  @isTest
  static void testMatcherSelection() {
    MatcherFactory factory = MatcherFactory.getInstance();

    // Test with different field types

    // Name fields should use NameMatcher
    Decimal nameScore = factory.calculateFieldMatchScore(
      'John Smith',
      'John Smyth',
      'Name'
    );
    System.assert(
      nameScore >= 0 && nameScore <= 100,
      'Name score should be between 0 and 100'
    );

    // Email fields should use EmailMatcher
    Decimal emailScore = factory.calculateFieldMatchScore(
      'john.smith@example.com',
      'john.smith@gmail.com',
      'Email'
    );
    System.assert(
      emailScore >= 0 && emailScore <= 100,
      'Email score should be between 0 and 100'
    );

    // Address fields should use AddressMatcher
    Decimal addressScore = factory.calculateFieldMatchScore(
      '123 Main St',
      '123 Main Street',
      'BillingStreet'
    );
    System.assert(
      addressScore >= 0 && addressScore <= 100,
      'Address score should be between 0 and 100'
    );

    // Generic fields should use TextMatcher
    Decimal textScore = factory.calculateFieldMatchScore(
      'Description Text',
      'Description Txt',
      'Description'
    );
    System.assert(
      textScore >= 0 && textScore <= 100,
      'Text score should be between 0 and 100'
    );
  }

  /**
   * Test different field names for matcher selection
   */
  @isTest
  static void testFieldNameMatching() {
    MatcherFactory factory = MatcherFactory.getInstance();

    // Test with variations of field names

    // Name variations
    Decimal firstNameScore = factory.calculateFieldMatchScore(
      'John',
      'Jon',
      'FirstName'
    );
    Decimal lastNameScore = factory.calculateFieldMatchScore(
      'Johnson',
      'Johnsen',
      'LastName'
    );
    Decimal fullNameScore = factory.calculateFieldMatchScore(
      'John Smith',
      'John Smythe',
      'FullName'
    );

    // Email variations
    Decimal emailScore = factory.calculateFieldMatchScore(
      'test@example.com',
      'test@example.com',
      'Email'
    );
    Decimal workEmailScore = factory.calculateFieldMatchScore(
      'work@example.com',
      'work@example.com',
      'WorkEmail__c'
    );

    // Address variations
    Decimal streetScore = factory.calculateFieldMatchScore(
      '123 Main St',
      '123 Main Street',
      'Street'
    );
    Decimal billingStreetScore = factory.calculateFieldMatchScore(
      '456 Market St',
      '456 Market Street',
      'BillingStreet'
    );
    Decimal addressLineScore = factory.calculateFieldMatchScore(
      '789 Broadway',
      '789 Broadway Ave',
      'AddressLine1__c'
    );

    // Verify all scores are in valid range
    Decimal[] scores = new List<Decimal>{
      firstNameScore,
      lastNameScore,
      fullNameScore,
      emailScore,
      workEmailScore,
      streetScore,
      billingStreetScore,
      addressLineScore
    };

    for (Decimal score : scores) {
      System.assert(
        score >= 0 && score <= 100,
        'All scores should be between 0 and 100: ' + score
      );
    }
  }

  /**
   * Test exact matches
   */
  @isTest
  static void testExactMatches() {
    MatcherFactory factory = MatcherFactory.getInstance();

    // Test exact matches for different field types
    Decimal nameScore = factory.calculateFieldMatchScore(
      'John Smith',
      'John Smith',
      'Name'
    );
    Decimal emailScore = factory.calculateFieldMatchScore(
      'test@example.com',
      'test@example.com',
      'Email'
    );
    Decimal addressScore = factory.calculateFieldMatchScore(
      '123 Main St',
      '123 Main St',
      'BillingStreet'
    );
    Decimal phoneScore = factory.calculateFieldMatchScore(
      '555-123-4567',
      '555-123-4567',
      'Phone'
    );

    // All should have high match scores for exact matches
    System.assert(
      nameScore > 90,
      'Exact name match should have score > 90: ' + nameScore
    );
    System.assert(
      emailScore > 90,
      'Exact email match should have score > 90: ' + emailScore
    );
    System.assert(
      addressScore > 90,
      'Exact address match should have score > 90: ' + addressScore
    );
    System.assert(
      phoneScore > 90,
      'Exact phone match should have score > 90: ' + phoneScore
    );
  }

  /**
   * Test handling of case sensitivity
   */
  @isTest
  static void testCaseSensitivity() {
    MatcherFactory factory = MatcherFactory.getInstance();

    // Test case-insensitive matching
    Decimal nameScore = factory.calculateFieldMatchScore(
      'John Smith',
      'JOHN SMITH',
      'Name'
    );
    Decimal emailScore = factory.calculateFieldMatchScore(
      'test@example.com',
      'TEST@EXAMPLE.COM',
      'Email'
    );

    // Should still have high match scores despite case differences
    System.assert(
      nameScore > 90,
      'Case-insensitive name match should have score > 90: ' + nameScore
    );
    System.assert(
      emailScore > 90,
      'Case-insensitive email match should have score > 90: ' + emailScore
    );
  }
}
