/**
 * Interface for field matchers to calculate similarity between field values
 *
 * @author Richard Hudson
 * @date April 2025
 */
public interface FieldMatcherInterface {
  /**
   * Calculates match score between two field values
   *
   * @param value1 First value to compare
   * @param value2 Second value to compare
   * @return Match score (0-100)
   */
  Decimal calculateMatchScore(String value1, String value2);

  /**
   * Checks if this matcher can handle the specified field
   *
   * @param fieldName API name of the field
   * @return True if this matcher can handle the field
   */
  Boolean canHandleField(String fieldName);
}
