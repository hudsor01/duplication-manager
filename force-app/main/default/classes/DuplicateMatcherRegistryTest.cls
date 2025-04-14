/**
 * Unit tests for duplicateMatcherRegistry class
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class DuplicateMatcherRegistryTest {

    @isTest
    static void testGetInstance() {
        // Verify singleton pattern works
        duplicateMatcherRegistry registry1 = duplicateMatcherRegistry.getInstance();
        duplicateMatcherRegistry registry2 = duplicateMatcherRegistry.getInstance();

        // Assert same instance is returned
        System.assertNotEquals(null, registry1);
        System.assertEquals(registry1, registry2);
    }

    @isTest
    static void testGetMatcherForEmailField() {
        // Get matcher for email field
        duplicateMatcherRegistry registry = duplicateMatcherRegistry.getInstance();
        FieldMatcherInterface matcher = registry.getMatcherForField('Email');

        // Assert correct matcher type returned
        System.assert(matcher instanceof EmailMatcher, 'Expected EmailMatcher for Email field');

        // Test matcher handles this field
        System.assert(matcher.canHandleField('Email'));
    }

    @isTest
    static void testGetMatcherForNameField() {
        // Get matcher for name field
        duplicateMatcherRegistry registry = duplicateMatcherRegistry.getInstance();
        FieldMatcherInterface matcher = registry.getMatcherForField('Name');

        // Assert correct matcher type returned
        System.assert(matcher instanceof NameMatcher, 'Expected NameMatcher for Name field');

        // Test matcher handles this field
        System.assert(matcher.canHandleField('Name'));
    }

    @isTest
    static void testGetMatcherForAddressField() {
        // Get matcher for address field
        duplicateMatcherRegistry registry = duplicateMatcherRegistry.getInstance();
        FieldMatcherInterface matcher = registry.getMatcherForField('BillingStreet');

        // Assert correct matcher type returned
        System.assert(matcher instanceof AddressMatcher, 'Expected AddressMatcher for BillingStreet field');

        // Test matcher handles this field
        System.assert(matcher.canHandleField('BillingStreet'));
    }

    @isTest
    static void testGetMatcherForGenericField() {
        // Get matcher for a generic field
        duplicateMatcherRegistry registry = duplicateMatcherRegistry.getInstance();
        FieldMatcherInterface matcher = registry.getMatcherForField('CustomField__c');

        // Assert generic matcher returned
        System.assert(matcher instanceof GenericMatcher, 'Expected GenericMatcher for CustomField__c field');
    }

    @isTest
    static void testCalculateMatchScore() {
        // Get registry
        duplicateMatcherRegistry registry = duplicateMatcherRegistry.getInstance();

        // Test exact match
        Decimal score1 = registry.calculateMatchScore('test@example.com', 'test@example.com', 'Email');
        System.assertEquals(100, score1, 'Expected 100% match for identical emails');

        // Test close match for name
        Decimal score2 = registry.calculateMatchScore('John Smith', 'Jon Smith', 'Name');
        System.assert(score2 > 70, 'Expected high match score for similar names');

        // Test no match
        Decimal score3 = registry.calculateMatchScore('ABC', 'XYZ', 'CustomField__c');
        System.assert(score3 < 50, 'Expected low match score for different values');
    }

    @isTest
    static void testClearCache() {
        // Get registry
        duplicateMatcherRegistry registry = duplicateMatcherRegistry.getInstance();

        // Get a matcher to populate cache
        FieldMatcherInterface matcher1 = registry.getMatcherForField('Email');

        // Clear cache
        registry.clearCache();

        // Get same matcher again
        FieldMatcherInterface matcher2 = registry.getMatcherForField('Email');

        // Can't test internal cache directly, so just verify both calls return EmailMatcher
        System.assert(matcher1 instanceof EmailMatcher);
        System.assert(matcher2 instanceof EmailMatcher);
    }

    @isTest
    static void testRegisterCustomMatcher() {
        // This test requires a mock implementation - just ensure method doesn't throw
        try {
            duplicateMatcherRegistry registry = duplicateMatcherRegistry.getInstance();
            registry.register('custom', EmailMatcher.class);
        } catch (Exception e) {
            System.assert(false, 'Should not throw exception: ' + e.getMessage());
        }
    }

    @isTest
    static void testRegisterInvalidMatcher() {
        // Attempt to register a non-matcher class
        duplicateMatcherRegistry registry = duplicateMatcherRegistry.getInstance();

        try {
            // Use a type that doesn't implement FieldMatcherInterface
            registry.register('invalid', duplicateMatcherRegistryTest.class);
            System.assert(false, 'Should have thrown exception for invalid matcher class');
        } catch (duplicateMatcherRegistry.duplicateException e) {
            // Expected exception
            System.assert(e.getMessage().contains('implement FieldMatcherInterface'),
                          'Exception should mention interface requirement');
        }
    }
}
