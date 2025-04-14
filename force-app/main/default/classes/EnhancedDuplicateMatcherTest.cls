/**
 * Test class for EnhancedDuplicateMatcher
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class EnhancedDuplicateMatcherTest {
  /**
   * Test exact email matches
   */
  @isTest
  static void testExactEmailMatches() {
    // Test exact matches
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchEmails(
        'test@example.com',
        'test@example.com'
      ),
      'Identical emails should match 100%'
    );
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchEmails(
        'user@domain.com',
        'user@domain.com'
      ),
      'Identical emails should match 100%'
    );
  }

  /**
   * Test case insensitivity for emails
   */
  @isTest
  static void testEmailCaseInsensitivity() {
    // Test case insensitivity
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchEmails(
        'Test@Example.com',
        'test@example.com'
      ),
      'Case should be ignored'
    );
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchEmails(
        'USER@DOMAIN.COM',
        'user@domain.com'
      ),
      'Case should be ignored'
    );
  }

  /**
   * Test whitespace handling in emails
   */
  @isTest
  static void testEmailWhitespaceHandling() {
    // Test whitespace handling
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchEmails(
        ' test@example.com ',
        'test@example.com'
      ),
      'Whitespace should be trimmed'
    );
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchEmails(
        'test@example.com',
        ' test@example.com '
      ),
      'Whitespace should be trimmed'
    );
  }

  /**
   * Test common email variations
   */
  @isTest
  static void testEmailCommonVariations() {
    // Test period-separated variations
    System.assertEquals(
      95,
      EnhancedDuplicateMatcher.matchEmails(
        'john.doe@example.com',
        'johndoe@example.com'
      ),
      'Period-separated should match'
    );

    // Test plus extensions
    System.assertEquals(
      95,
      EnhancedDuplicateMatcher.matchEmails(
        'test+spam@example.com',
        'test@example.com'
      ),
      'Plus extensions should match'
    );
    System.assertEquals(
      95,
      EnhancedDuplicateMatcher.matchEmails(
        'test+123@example.com',
        'test+abc@example.com'
      ),
      'Different plus extensions should match'
    );

    // Test common variations (e.g., first initial + last name)
    System.assertEquals(
      95,
      EnhancedDuplicateMatcher.matchEmails(
        'jdoe@example.com',
        'johndoe@example.com'
      ),
      'First initial + last name should match with high score'
    );
  }

  /**
   * Test email fuzzy matching
   */
  @isTest
  static void testEmailFuzzyMatching() {
    // Test substring matches
    System.assertEquals(
      85,
      EnhancedDuplicateMatcher.matchEmails(
        'john@example.com',
        'johndoe@example.com'
      ),
      'Substring should match'
    );

    // Test common prefix (these cases are somewhat dependent on Levenshtein implementation)
    Decimal score = EnhancedDuplicateMatcher.matchEmails(
      'john1234@example.com',
      'john5678@example.com'
    );
    System.assert(score > 0, 'Common prefix should match with some score');
  }

  /**
   * Test email domain mismatch
   */
  @isTest
  static void testEmailDomainMismatch() {
    // Test domain mismatch (should not match)
    System.assertEquals(
      0,
      EnhancedDuplicateMatcher.matchEmails(
        'test@example.com',
        'test@different.com'
      ),
      'Different domains should not match'
    );
    System.assertEquals(
      0,
      EnhancedDuplicateMatcher.matchEmails('john@gmail.com', 'john@yahoo.com'),
      'Different domains should not match'
    );
  }

  /**
   * Test null and empty email values
   */
  @isTest
  static void testEmailNullAndEmpty() {
    // Test null and empty values
    System.assertEquals(
      0,
      EnhancedDuplicateMatcher.matchEmails(null, 'test@example.com'),
      'Null value should not match'
    );
    System.assertEquals(
      0,
      EnhancedDuplicateMatcher.matchEmails('test@example.com', null),
      'Null value should not match'
    );
    System.assertEquals(
      0,
      EnhancedDuplicateMatcher.matchEmails('', 'test@example.com'),
      'Empty value should not match'
    );
    System.assertEquals(
      0,
      EnhancedDuplicateMatcher.matchEmails('test@example.com', ''),
      'Empty value should not match'
    );
  }

  /**
   * Test exact phone matches
   */
  @isTest
  static void testExactPhoneMatches() {
    // Test exact matches
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchPhones('(555) 123-4567', '(555) 123-4567'),
      'Identical phone numbers should match 100%'
    );
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchPhones('555-123-4567', '555-123-4567'),
      'Identical phone numbers should match 100%'
    );
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchPhones('5551234567', '5551234567'),
      'Identical phone numbers should match 100%'
    );
  }

  /**
   * Test different phone formats
   */
  @isTest
  static void testPhoneDifferentFormats() {
    // Test different formats of the same number
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchPhones('(555) 123-4567', '555-123-4567'),
      'Different formats should match 100%'
    );
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchPhones('(555) 123-4567', '5551234567'),
      'Different formats should match 100%'
    );
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchPhones('555.123.4567', '5551234567'),
      'Different formats should match 100%'
    );
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchPhones('555 123 4567', '5551234567'),
      'Different formats should match 100%'
    );
  }

  /**
   * Test international phone prefixes
   */
  @isTest
  static void testPhoneInternationalPrefixes() {
    // Test with international prefixes
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchPhones('1-555-123-4567', '5551234567'),
      'Should match with US country code'
    );
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchPhones('+1 (555) 123-4567', '5551234567'),
      'Should match with + prefix'
    );
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchPhones('001-555-123-4567', '5551234567'),
      'Should match with 00 prefix'
    );
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchPhones('011-555-123-4567', '5551234567'),
      'Should match with 011 prefix'
    );
  }

  /**
   * Test partial phone matches
   */
  @isTest
  static void testPhonePartialMatches() {
    // Test partial matches (last 10, 7, or 4 digits)
    System.assertEquals(
      100,
      EnhancedDuplicateMatcher.matchPhones('5551234567', '5551234567'),
      'Last 10 digits match'
    );
    System.assertEquals(
      90,
      EnhancedDuplicateMatcher.matchPhones('4441234567', '9991234567'),
      'Last 7 digits match'
    );
    System.assertEquals(
      75,
      EnhancedDuplicateMatcher.matchPhones('5559994567', '1234567'),
      'Last 4 digits match'
    );

    // Different area codes
    System.assertEquals(
      90,
      EnhancedDuplicateMatcher.matchPhones('(555) 123-4567', '(444) 123-4567'),
      'Different area codes should match with high score'
    );
  }

  /**
   * Test non-matching phones
   */
  @isTest
  static void testPhoneNonMatches() {
    // Test non-matching phone numbers
    System.assertEquals(
      0,
      EnhancedDuplicateMatcher.matchPhones('(555) 123-4567', '(555) 987-6543'),
      'Different numbers should not match'
    );
    System.assertEquals(
      0,
      EnhancedDuplicateMatcher.matchPhones('(555) 123-4567', null),
      'Null comparison should not match'
    );
    System.assertEquals(
      0,
      EnhancedDuplicateMatcher.matchPhones(null, '(555) 123-4567'),
      'Null comparison should not match'
    );
    System.assertEquals(
      0,
      EnhancedDuplicateMatcher.matchPhones('', '(555) 123-4567'),
      'Empty comparison should not match'
    );
    System.assertEquals(
      0,
      EnhancedDuplicateMatcher.matchPhones('(555) 123-4567', ''),
      'Empty comparison should not match'
    );
  }

  /**
   * Test very short phone numbers
   */
  @isTest
  static void testPhoneShortNumbers() {
    // Test very short numbers (should not match to avoid false positives)
    System.assertEquals(
      0,
      EnhancedDuplicateMatcher.matchPhones('1234', '1234'),
      'Very short numbers should not match'
    );
    System.assertEquals(
      0,
      EnhancedDuplicateMatcher.matchPhones('123', '123'),
      'Very short numbers should not match'
    );
  }
}
