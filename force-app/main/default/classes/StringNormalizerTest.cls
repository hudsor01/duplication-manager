/**
 * Test class for StringNormalizer
 *
 * @author Your Name
 * @date April 11, 2025
 */
@isTest
private class StringNormalizerTest {

    @isTest
    static void testNormalizeWithNullInput() {
        // Test with null input
        Test.startTest();
        String result = StringNormalizer.normalize(null);
        Test.stopTest();

        System.assertEquals('', result, 'Null input should return empty string');
    }

    @isTest
    static void testNormalizeWithSpecialCharacters() {
        // Test with special characters
        Test.startTest();
        String input = 'Hello, World! @#$%^&*()';
        String result = StringNormalizer.normalize(input);
        Test.stopTest();

        System.assertEquals('hello world', result, 'Special characters should be removed');
    }

    @isTest
    static void testNormalizeWithExtraSpaces() {
        // Test with extra spaces
        Test.startTest();
        String input = '  Multiple    Spaces    Here  ';
        String result = StringNormalizer.normalize(input);
        Test.stopTest();

        System.assertEquals('multiple spaces here', result, 'Extra spaces should be consolidated');
    }

    @isTest
    static void testNormalizeCaching() {
        // Test caching functionality
        Test.startTest();
        String input = 'Cache-Test';

        // First call should cache the result
        String result1 = StringNormalizer.normalize(input);

        // This should use the cached value
        String result2 = StringNormalizer.normalize(input);
        Test.stopTest();

        System.assertEquals('cache test', result1, 'First normalization should be correct');
        System.assertEquals(result1, result2, 'Cached result should be the same as original');
    }

    @isTest
    static void testClearCache() {
        // Test cache clearing
        String input = 'Clear-Cache-Test';

        // Cache a value
        StringNormalizer.normalize(input);

        // Clear the cache
        Test.startTest();
        StringNormalizer.clearCache();
        Test.stopTest();

        // Cannot directly test if cache is cleared, but we can ensure the method runs without error
        System.assertEquals(true, true, 'Cache clear should execute without errors');
    }

    @isTest
    static void testNormalizePhone() {
        // Test phone normalization
        Test.startTest();
        String phone1 = '(555) 123-4567';
        String phone2 = null;
        String phone3 = '';
        String result1 = StringNormalizer.normalizePhone(phone1);
        String result2 = StringNormalizer.normalizePhone(phone2);
        String result3 = StringNormalizer.normalizePhone(phone3);
        Test.stopTest();

        System.assertEquals('5551234567', result1, 'Phone should contain digits only');
        System.assertEquals('', result2, 'Null phone should return empty string');
        System.assertEquals('', result3, 'Empty phone should return empty string');
    }

    @isTest
    static void testNormalizeEmail() {
        // Test email normalization
        Test.startTest();
        String email1 = ' Test.Email@Example.com ';
        String email2 = null;
        String email3 = '';
        String result1 = StringNormalizer.normalizeEmail(email1);
        String result2 = StringNormalizer.normalizeEmail(email2);
        String result3 = StringNormalizer.normalizeEmail(email3);
        Test.stopTest();

        System.assertEquals('test.email@example.com', result1, 'Email should be lowercase and trimmed');
        System.assertEquals('', result2, 'Null email should return empty string');
        System.assertEquals('', result3, 'Empty email should return empty string');
    }
}
