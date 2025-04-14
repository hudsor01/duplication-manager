/**
 * Test class for PhoneMatcher
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class PhoneMatcherTest {
    
    /**
     * Test field type detection
     */
    @isTest
    static void testCanHandleField() {
        // Create instance of matcher
        PhoneMatcher matcher = new PhoneMatcher();
        
        // Test various field names
        System.assertEquals(true, matcher.canHandleField('Phone'), 'Should handle Phone field');
        System.assertEquals(true, matcher.canHandleField('MobilePhone'), 'Should handle MobilePhone field');
        System.assertEquals(true, matcher.canHandleField('HomePhone'), 'Should handle HomePhone field');
        System.assertEquals(true, matcher.canHandleField('WorkPhone'), 'Should handle WorkPhone field');
        System.assertEquals(true, matcher.canHandleField('CellPhone'), 'Should handle CellPhone field');
        System.assertEquals(true, matcher.canHandleField('TelephoneNumber'), 'Should handle TelephoneNumber field');
        System.assertEquals(true, matcher.canHandleField('Fax'), 'Should handle Fax field');
        
        System.assertEquals(false, matcher.canHandleField('Email'), 'Should not handle Email field');
        System.assertEquals(false, matcher.canHandleField('Address'), 'Should not handle Address field');
        System.assertEquals(false, matcher.canHandleField('Name'), 'Should not handle Name field');
        System.assertEquals(false, matcher.canHandleField(null), 'Should not handle null field');
        System.assertEquals(false, matcher.canHandleField(''), 'Should not handle empty field');
    }
    
    /**
     * Test exact phone matches
     */
    @isTest
    static void testExactPhoneMatches() {
        // Create instance of matcher
        PhoneMatcher matcher = new PhoneMatcher();
        
        // Test exact matches
        System.assertEquals(100, matcher.calculateMatchScore('(555) 123-4567', '(555) 123-4567'), 'Identical phone numbers should match 100%');
        System.assertEquals(100, matcher.calculateMatchScore('555-123-4567', '555-123-4567'), 'Identical phone numbers should match 100%');
        System.assertEquals(100, matcher.calculateMatchScore('5551234567', '5551234567'), 'Identical phone numbers should match 100%');
    }
    
    /**
     * Test different phone formats
     */
    @isTest
    static void testDifferentFormats() {
        // Create instance of matcher
        PhoneMatcher matcher = new PhoneMatcher();
        
        // Test different formats of the same number
        System.assertEquals(100, matcher.calculateMatchScore('(555) 123-4567', '555-123-4567'), 'Different formats should match 100%');
        System.assertEquals(100, matcher.calculateMatchScore('(555) 123-4567', '5551234567'), 'Different formats should match 100%');
        System.assertEquals(100, matcher.calculateMatchScore('555.123.4567', '5551234567'), 'Different formats should match 100%');
        System.assertEquals(100, matcher.calculateMatchScore('555 123 4567', '5551234567'), 'Different formats should match 100%');
    }
    
    /**
     * Test international prefixes
     */
    @isTest
    static void testInternationalPrefixes() {
        // Create instance of matcher
        PhoneMatcher matcher = new PhoneMatcher();
        
        // Test with international prefixes
        System.assertEquals(100, matcher.calculateMatchScore('1-555-123-4567', '5551234567'), 'Should match with US country code');
        System.assertEquals(100, matcher.calculateMatchScore('+1 (555) 123-4567', '5551234567'), 'Should match with + prefix');
        System.assertEquals(100, matcher.calculateMatchScore('001-555-123-4567', '5551234567'), 'Should match with 00 prefix');
        System.assertEquals(100, matcher.calculateMatchScore('011-555-123-4567', '5551234567'), 'Should match with 011 prefix');
    }
    
    /**
     * Test partial matches
     */
    @isTest
    static void testPartialMatches() {
        // Create instance of matcher
        PhoneMatcher matcher = new PhoneMatcher();
        
        // Test partial matches (last 10, 7, or 4 digits)
        System.assertEquals(100, matcher.calculateMatchScore('5551234567', '5551234567'), 'Last 10 digits match');
        System.assertEquals(90, matcher.calculateMatchScore('4441234567', '9991234567'), 'Last 7 digits match');
        System.assertEquals(75, matcher.calculateMatchScore('5559994567', '1234567'), 'Last 4 digits match');
        
        // Different area codes
        System.assertEquals(90, matcher.calculateMatchScore('(555) 123-4567', '(444) 123-4567'), 'Different area codes should match 90%');
    }
    
    /**
     * Test non-matches
     */
    @isTest
    static void testNonMatches() {
        // Create instance of matcher
        PhoneMatcher matcher = new PhoneMatcher();
        
        // Test non-matching phone numbers
        System.assertEquals(0, matcher.calculateMatchScore('(555) 123-4567', '(555) 987-6543'), 'Different numbers should not match');
        System.assertEquals(0, matcher.calculateMatchScore('(555) 123-4567', null), 'Null comparison should not match');
        System.assertEquals(0, matcher.calculateMatchScore(null, '(555) 123-4567'), 'Null comparison should not match');
        System.assertEquals(0, matcher.calculateMatchScore('', '(555) 123-4567'), 'Empty comparison should not match');
        System.assertEquals(0, matcher.calculateMatchScore('(555) 123-4567', ''), 'Empty comparison should not match');
    }
    
    /**
     * Test very short numbers
     */
    @isTest
    static void testShortNumbers() {
        // Create instance of matcher
        PhoneMatcher matcher = new PhoneMatcher();
        
        // Test very short numbers (should not match to avoid false positives)
        System.assertEquals(0, matcher.calculateMatchScore('1234', '1234'), 'Very short numbers should not match');
        System.assertEquals(0, matcher.calculateMatchScore('123', '123'), 'Very short numbers should not match');
    }
}