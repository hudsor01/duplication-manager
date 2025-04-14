/**
 * Generic matcher for any field type
 *
 * @author Richard Hudson
 * @date April 2025
 */
public class GenericMatcher implements FieldMatcherInterface {
  /**
   * Checks if this matcher can handle the specified field
   *
   * @param fieldName API name of the field
   * @return True if this matcher can handle the field (always true for generic matcher)
   */
  public Boolean canHandleField(String fieldName) {
    // Generic matcher can handle any field that other matchers don't
    return true;
  }

  /**
   * Calculates match score between two string values
   *
   * @param str1 First string to compare
   * @param str2 Second string to compare
   * @return Match score (0-100)
   */
  public Decimal calculateMatchScore(String str1, String str2) {
    // Handle null values
    if (str1 == null || str2 == null) {
      return 0;
    }

    // Normalize strings
    str1 = StringNormalizer.normalize(str1);
    str2 = StringNormalizer.normalize(str2);

    // Special case for exact match
    if (str1 == str2) {
      return 100;
    }

    // Special case for very short strings
    if (str1.length() < 3 || str2.length() < 3) {
      return str1 == str2 ? 100 : 0;
    }

    // Calculate Levenshtein distance-based score
    Decimal levenshteinScore =
      100 -
      (100.0 *
      LevenshteinCalculator.distance(str1, str2) /
      Math.max(str1.length(), str2.length()));

    return levenshteinScore;
  }
}
