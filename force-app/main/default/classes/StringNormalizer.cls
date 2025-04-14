/**
 * Utility for string normalization
 *
 * @description A utility class for normalizing strings to make them comparable
 * @author Richard Hudson
 * @date April 2025
 */
public class StringNormalizer {
  // Cache of normalized strings
  private static Map<String, String> normalizationCache = new Map<String, String>();

  /**
   * Normalizes a string for comparison
   *
   * @param input String to normalize
   * @return Normalized string
   * @description Removes special characters, extra spaces, and converts to lowercase
   */
  public static String normalize(String input) {
    if (input == null) {
      return '';
    }

    // Check cache first
    String cacheKey = input;
    if (normalizationCache.containsKey(cacheKey)) {
      return normalizationCache.get(cacheKey);
    }

    // Convert to lowercase
    input = input.toLowerCase();

    // Replace special characters with spaces
    input = input.replaceAll('[^a-z0-9]', ' ');

    // Replace multiple spaces with a single space
    input = input.replaceAll('\\s+', ' ');

    // Trim leading and trailing spaces
    input = input.trim();

    // Cache the result
    normalizationCache.put(cacheKey, input);

    return input;
  }

  /**
   * Clears the normalization cache
   */
  public static void clearCache() {
    normalizationCache.clear();
  }

  /**
   * Normalizes a text field for phone comparison
   *
   * @param phoneNumber Phone number to normalize
   * @return Normalized phone number (digits only)
   */
  public static String normalizePhone(String phoneNumber) {
    if (String.isBlank(phoneNumber)) {
      return '';
    }

    // Remove all non-digit characters
    return phoneNumber.replaceAll('[^0-9]', '');
  }

  /**
   * Normalizes an email address
   *
   * @param email Email to normalize
   * @return Normalized email (lowercase)
   */
  public static String normalizeEmail(String email) {
    if (String.isBlank(email)) {
      return '';
    }

    // Convert to lowercase and trim
    return email.toLowerCase().trim();
  }
}
