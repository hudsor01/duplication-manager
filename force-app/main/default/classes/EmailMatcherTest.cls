/**
 * Test class for EmailMatcher
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class EmailMatcherTest {
  /**
   * Test field type detection
   */
  @isTest
  static void testCanHandleField() {
    // Create instance of matcher
    EmailMatcher matcher = new EmailMatcher();

    // Test various field names
    System.assertEquals(
      true,
      matcher.canHandleField('Email'),
      'Should handle Email field'
    );
    System.assertEquals(
      true,
      matcher.canHandleField('EmailAddress'),
      'Should handle EmailAddress field'
    );
    System.assertEquals(
      true,
      matcher.canHandleField('SecondaryEmail'),
      'Should handle SecondaryEmail field'
    );
    System.assertEquals(
      true,
      matcher.canHandleField('WorkEmail'),
      'Should handle WorkEmail field'
    );
    System.assertEquals(
      true,
      matcher.canHandleField('PersonalEmail'),
      'Should handle PersonalEmail field'
    );
    System.assertEquals(
      true,
      matcher.canHandleField('E-mail'),
      'Should handle E-mail field'
    );

    System.assertEquals(
      false,
      matcher.canHandleField('Phone'),
      'Should not handle Phone field'
    );
    System.assertEquals(
      false,
      matcher.canHandleField('Address'),
      'Should not handle Address field'
    );
    System.assertEquals(
      false,
      matcher.canHandleField('Name'),
      'Should not handle Name field'
    );
    System.assertEquals(
      false,
      matcher.canHandleField(null),
      'Should not handle null field'
    );
    System.assertEquals(
      false,
      matcher.canHandleField(''),
      'Should not handle empty field'
    );
  }

  /**
   * Test exact email matches
   */
  @isTest
  static void testExactEmailMatches() {
    // Create instance of matcher
    EmailMatcher matcher = new EmailMatcher();

    // Test exact matches
    System.assertEquals(
      100,
      matcher.calculateMatchScore('test@example.com', 'test@example.com'),
      'Identical emails should match 100%'
    );
    System.assertEquals(
      100,
      matcher.calculateMatchScore('user@domain.com', 'user@domain.com'),
      'Identical emails should match 100%'
    );
  }

  /**
   * Test case insensitivity
   */
  @isTest
  static void testCaseInsensitivity() {
    // Create instance of matcher
    EmailMatcher matcher = new EmailMatcher();

    // Test case insensitivity
    System.assertEquals(
      100,
      matcher.calculateMatchScore('Test@Example.com', 'test@example.com'),
      'Case should be ignored'
    );
    System.assertEquals(
      100,
      matcher.calculateMatchScore('USER@DOMAIN.COM', 'user@domain.com'),
      'Case should be ignored'
    );
  }

  /**
   * Test whitespace handling
   */
  @isTest
  static void testWhitespaceHandling() {
    // Create instance of matcher
    EmailMatcher matcher = new EmailMatcher();

    // Test whitespace handling
    System.assertEquals(
      100,
      matcher.calculateMatchScore(' test@example.com ', 'test@example.com'),
      'Whitespace should be trimmed'
    );
    System.assertEquals(
      100,
      matcher.calculateMatchScore('test@example.com', ' test@example.com '),
      'Whitespace should be trimmed'
    );
  }

  /**
   * Test common email variations
   */
  @isTest
  static void testCommonVariations() {
    // Create instance of matcher
    EmailMatcher matcher = new EmailMatcher();

    // Test period-separated variations
    System.assertEquals(
      95,
      matcher.calculateMatchScore(
        'john.doe@example.com',
        'johndoe@example.com'
      ),
      'Period-separated should match'
    );

    // Test plus extensions
    System.assertEquals(
      95,
      matcher.calculateMatchScore('test+spam@example.com', 'test@example.com'),
      'Plus extensions should match'
    );
    System.assertEquals(
      95,
      matcher.calculateMatchScore(
        'test+123@example.com',
        'test+abc@example.com'
      ),
      'Different plus extensions should match'
    );

    // Test common variations (e.g., first initial + last name)
    System.assertEquals(
      95,
      matcher.calculateMatchScore('jdoe@example.com', 'johndoe@example.com'),
      'First initial + last name should match'
    );
  }

  /**
   * Test fuzzy matching
   */
  @isTest
  static void testFuzzyMatching() {
    // Create instance of matcher
    EmailMatcher matcher = new EmailMatcher();

    // Test Levenshtein distance similarity
    System.assert(
      matcher.calculateMatchScore('john@example.com', 'jhon@example.com') >= 80,
      'Typos should match with high score'
    );

    // Test substring matches
    System.assertEquals(
      85,
      matcher.calculateMatchScore('john@example.com', 'johndoe@example.com'),
      'Substring should match'
    );

    // Test common prefix
    System.assert(
      matcher.calculateMatchScore(
        'john1234@example.com',
        'john5678@example.com'
      ) >= 80,
      'Common prefix should match'
    );
  }

  /**
   * Test domain mismatch
   */
  @isTest
  static void testDomainMismatch() {
    // Create instance of matcher
    EmailMatcher matcher = new EmailMatcher();

    // Test domain mismatch (should not match)
    System.assertEquals(
      0,
      matcher.calculateMatchScore('test@example.com', 'test@different.com'),
      'Different domains should not match'
    );
    System.assertEquals(
      0,
      matcher.calculateMatchScore('john@gmail.com', 'john@yahoo.com'),
      'Different domains should not match'
    );
  }

  /**
   * Test null and empty values
   */
  @isTest
  static void testNullAndEmpty() {
    // Create instance of matcher
    EmailMatcher matcher = new EmailMatcher();

    // Test null and empty values
    System.assertEquals(
      0,
      matcher.calculateMatchScore(null, 'test@example.com'),
      'Null value should not match'
    );
    System.assertEquals(
      0,
      matcher.calculateMatchScore('test@example.com', null),
      'Null value should not match'
    );
    System.assertEquals(
      0,
      matcher.calculateMatchScore('', 'test@example.com'),
      'Empty value should not match'
    );
    System.assertEquals(
      0,
      matcher.calculateMatchScore('test@example.com', ''),
      'Empty value should not match'
    );
  }

  /**
   * Test invalid email formats
   */
  @isTest
  static void testInvalidFormat() {
    // Create instance of matcher
    EmailMatcher matcher = new EmailMatcher();

    // Test invalid email formats
    Decimal score = matcher.calculateMatchScore(
      'not-an-email',
      'also-not-an-email'
    );
    System.assert(
      score >= 0 && score <= 100,
      'Invalid emails should return a score between 0 and 100'
    );

    // Test valid vs invalid
    score = matcher.calculateMatchScore('test@example.com', 'not-an-email');
    System.assert(
      score >= 0 && score <= 100,
      'Valid vs invalid should return a score between 0 and 100'
    );
  }
}
