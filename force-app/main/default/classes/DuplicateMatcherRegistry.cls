/**
 * Registry class for field matchers with proper factory pattern
 * Centralizes matcher registration and lookup, eliminating duplicate code
 *
 * @author Richard Hudson
 * @date April 2025
 */
public class DuplicateMatcherRegistry {
  // Singleton instance
  private static DuplicateMatcherRegistry instance;

  // Map of field patterns to matcher class types
  private Map<String, Type> matchersByPattern;

  // Map of exact field names to matcher instances for caching
  private Map<String, FieldMatcherInterface> matcherCache;

  /**
   * Private constructor for singleton pattern
   */
  private DuplicateMatcherRegistry() {
    matchersByPattern = new Map<String, Type>();
    matcherCache = new Map<String, FieldMatcherInterface>();

    // Register standard matchers
    register('email', EmailMatcher.class);
    register('name', NameMatcher.class);
    register('address', AddressMatcher.class);
    register('street', AddressMatcher.class);
    register('city', AddressMatcher.class);
    register('state', AddressMatcher.class);
    register('country', AddressMatcher.class);
    register('zip', AddressMatcher.class);
    register('postal', AddressMatcher.class);
    register('phone', PhoneMatcher.class);
    register('tel', PhoneMatcher.class);
    register('fax', PhoneMatcher.class);
    register('mobile', PhoneMatcher.class);
    register('cell', PhoneMatcher.class);
  }

  /**
   * Get singleton instance
   */
  public static DuplicateMatcherRegistry getInstance() {
    if (instance == null) {
      instance = new DuplicateMatcherRegistry();
    }
    return instance;
  }

  /**
   * Register a matcher for a field pattern
   */
  public void register(String fieldPattern, Type matcherClass) {
    // Validate parameters
    if (String.isBlank(fieldPattern) || matcherClass == null) {
      throw new DuplicateException(
        'Field pattern and matcher class must be specified'
      );
    }

    // Verify the class implements the matcher interface
    if (!isValidMatcherClass(matcherClass)) {
      throw new DuplicateException(
        'Class must implement FieldMatcherInterface: ' + matcherClass.getName()
      );
    }

    matchersByPattern.put(fieldPattern.toLowerCase(), matcherClass);
  }

  /**
   * Check if a class implements FieldMatcherInterface
   */
  private Boolean isValidMatcherClass(Type matcherClass) {
    try {
      // Attempt to create an instance and check if it implements the interface
      Object obj = matcherClass.newInstance();
      return obj instanceof FieldMatcherInterface;
    } catch (Exception e) {
      return false;
    }
  }

  /**
   * Get appropriate matcher for a field
   */
  public FieldMatcherInterface getMatcherForField(String fieldName) {
    if (String.isBlank(fieldName)) {
      return new GenericMatcher();
    }

    // Check cache first
    String normalizedFieldName = fieldName.toLowerCase();
    if (matcherCache.containsKey(normalizedFieldName)) {
      return matcherCache.get(normalizedFieldName);
    }

    // Find matcher based on field name pattern
    for (String pattern : matchersByPattern.keySet()) {
      if (normalizedFieldName.contains(pattern)) {
        Type matcherClass = matchersByPattern.get(pattern);
        FieldMatcherInterface matcher = (FieldMatcherInterface) matcherClass.newInstance();

        // Only use this matcher if it can handle the field
        if (matcher.canHandleField(fieldName)) {
          // Cache the matcher for this field
          matcherCache.put(normalizedFieldName, matcher);
          return matcher;
        }
      }
    }

    // Default to generic matcher if no specific matcher found
    FieldMatcherInterface defaultMatcher = new GenericMatcher();
    matcherCache.put(normalizedFieldName, defaultMatcher);
    return defaultMatcher;
  }

  /**
   * Calculate match score between two field values
   */
  public Decimal calculateMatchScore(
    String value1,
    String value2,
    String fieldName
  ) {
    // Get appropriate matcher for this field
    FieldMatcherInterface matcher = getMatcherForField(fieldName);

    // Use matcher to calculate match score
    return matcher.calculateMatchScore(value1, value2);
  }

  /**
   * Clear the matcher cache
   */
  public void clearCache() {
    matcherCache.clear();
  }

  /**
   * Custom exception class
   */
  public class DuplicateException extends Exception {
  }
}
