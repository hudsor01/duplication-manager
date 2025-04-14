/**
 * Factory class for creating field matchers based on field type
 *
 * @author Richard Hudson
 * @date April 2025
 */
public class MatcherFactory {
  // Singleton instance
  private static MatcherFactory instance;

  /**
   * Private constructor for singleton pattern
   */
  private MatcherFactory() {
    // Initialize with empty constructor
  }

  /**
   * Gets the singleton instance of the factory
   * @return MatcherFactory instance
   */
  public static MatcherFactory getInstance() {
    if (instance == null) {
      instance = new MatcherFactory();
    }
    return instance;
  }

  /**
   * Calculates match score between two field values using the appropriate matcher
   *
   * @param value1 First value to compare
   * @param value2 Second value to compare
   * @param fieldName API name of the field
   * @return Match score (0-100)
   */
  public Decimal calculateFieldMatchScore(
    String value1,
    String value2,
    String fieldName
  ) {
    // If null values, return 0
    if (value1 == null || value2 == null) {
      return 0;
    }

    // Normalize strings for comparison
    String normalizedValue1 = value1.toLowerCase().trim();
    String normalizedValue2 = value2.toLowerCase().trim();

    // Exact match after normalization
    if (normalizedValue1 == normalizedValue2) {
      return 100;
    }

    // Use different matching strategies based on field name
    String normalizedFieldName = fieldName.toLowerCase();

    // Check field type and use appropriate matcher
    if (isEmailField(normalizedFieldName)) {
      return calculateEmailMatchScore(normalizedValue1, normalizedValue2);
    } else if (isNameField(normalizedFieldName)) {
      return calculateNameMatchScore(normalizedValue1, normalizedValue2);
    } else if (isAddressField(normalizedFieldName)) {
      return calculateAddressMatchScore(normalizedValue1, normalizedValue2);
    } else {
      return calculateGenericMatchScore(normalizedValue1, normalizedValue2);
    }
  }

  /**
   * Checks if field is an email field
   * @param fieldName Normalized field name
   * @return True if it's an email field
   */
  private Boolean isEmailField(String fieldName) {
    return fieldName.contains('email') || fieldName.endsWith('email');
  }

  /**
   * Checks if field is a name field
   * @param fieldName Normalized field name
   * @return True if it's a name field
   */
  private Boolean isNameField(String fieldName) {
    return fieldName.contains('name') ||
      fieldName.endsWith('name') ||
      fieldName.equals('firstname') ||
      fieldName.equals('lastname') ||
      fieldName.equals('middlename');
  }

  /**
   * Checks if field is an address field
   * @param fieldName Normalized field name
   * @return True if it's an address field
   */
  private Boolean isAddressField(String fieldName) {
    return fieldName.contains('address') ||
      fieldName.endsWith('address') ||
      fieldName.equals('street') ||
      fieldName.contains('street') ||
      fieldName.contains('city') ||
      fieldName.contains('state') ||
      fieldName.contains('country') ||
      fieldName.contains('postal') ||
      fieldName.contains('zip');
  }

  /**
   * Calculates match score for email fields
   * @param email1 First email
   * @param email2 Second email
   * @return Match score (0-100)
   */
  private Decimal calculateEmailMatchScore(String email1, String email2) {
    // Exact match
    if (email1 == email2) {
      return 100;
    }

    // Split emails into local part and domain
    List<String> parts1 = email1.split('@');
    List<String> parts2 = email2.split('@');

    // Invalid email format
    if (parts1.size() != 2 || parts2.size() != 2) {
      // Fall back to generic matching
      return calculateGenericMatchScore(email1, email2);
    }

    String local1 = parts1[0];
    String domain1 = parts1[1];
    String local2 = parts2[0];
    String domain2 = parts2[1];

    // Domain must match exactly
    if (domain1 != domain2) {
      return 0;
    }

    // For local part, use Levenshtein distance
    Decimal localPartScore = calculateStringSimilarity(local1, local2);
    return localPartScore;
  }

  /**
   * Calculates match score for name fields
   * @param name1 First name
   * @param name2 Second name
   * @return Match score (0-100)
   */
  private Decimal calculateNameMatchScore(String name1, String name2) {
    // Special case for exact match
    if (name1 == name2) {
      return 100;
    }

    // Special case for very short strings
    if (name1.length() < 3 || name2.length() < 3) {
      return name1 == name2 ? 100 : 0;
    }

    // Calculate similarity score
    Decimal similarityScore = calculateStringSimilarity(name1, name2);

    // Calculate common parts score
    List<String> parts1 = name1.split(' ');
    List<String> parts2 = name2.split(' ');
    Decimal commonPartsScore = calculateCommonPartsScore(parts1, parts2);

    // For names, we weigh common parts more heavily
    return (similarityScore * 0.4) + (commonPartsScore * 0.6);
  }

  /**
   * Calculates match score for address fields
   * @param address1 First address
   * @param address2 Second address
   * @return Match score (0-100)
   */
  private Decimal calculateAddressMatchScore(String address1, String address2) {
    // Special case for exact match
    if (address1 == address2) {
      return 100;
    }

    // Split addresses into parts
    List<String> parts1 = address1.split(' ');
    List<String> parts2 = address2.split(' ');

    // Calculate common parts score
    return calculateCommonPartsScore(parts1, parts2);
  }

  /**
   * Calculates match score for generic fields
   * @param value1 First value
   * @param value2 Second value
   * @return Match score (0-100)
   */
  private Decimal calculateGenericMatchScore(String value1, String value2) {
    // Exact match
    if (value1 == value2) {
      return 100;
    }

    // Calculate similarity score based on string length and common characters
    return calculateStringSimilarity(value1, value2);
  }

  /**
   * Calculates common parts score between two lists of string parts
   * @param parts1 First list of parts
   * @param parts2 Second list of parts
   * @return Common parts score (0-100)
   */
  private Decimal calculateCommonPartsScore(
    List<String> parts1,
    List<String> parts2
  ) {
    if (parts1.isEmpty() || parts2.isEmpty()) {
      return 0;
    }

    Integer commonParts = 0;
    Set<String> uniqueParts = new Set<String>();

    // Convert all parts to lowercase for case-insensitive matching
    for (String part : parts1) {
      uniqueParts.add(part.toLowerCase());
    }

    // Count matches in the second list
    for (String part : parts2) {
      if (uniqueParts.contains(part.toLowerCase())) {
        commonParts++;
        uniqueParts.remove(part.toLowerCase()); // Remove to avoid double counting
      }
    }

    // Calculate score
    Integer totalParts = parts1.size() + parts2.size() - commonParts;
    return (totalParts > 0) ? (Decimal) commonParts / totalParts * 100 : 0;
  }

  /**
   * Calculates string similarity between two strings
   * @param s1 First string
   * @param s2 Second string
   * @return Similarity score (0-100)
   */
  private Decimal calculateStringSimilarity(String s1, String s2) {
    // Length based similarity
    Integer lenDiff = Math.abs(s1.length() - s2.length());
    Integer maxLen = Math.max(s1.length(), s2.length());
    Decimal lengthScore = (maxLen > 0)
      ? (1 - (Decimal) lenDiff / maxLen) * 100
      : 100;

    // Character overlap similarity
    Set<String> chars1 = new Set<String>();
    for (Integer i = 0; i < s1.length(); i++) {
      chars1.add(s1.substring(i, i + 1));
    }

    Integer commonChars = 0;
    for (Integer i = 0; i < s2.length(); i++) {
      if (chars1.contains(s2.substring(i, i + 1))) {
        commonChars++;
      }
    }

    Decimal overlapScore = (maxLen > 0)
      ? (Decimal) commonChars / maxLen * 100
      : 0;

    // Combined score (weigh overlap more heavily)
    return (lengthScore * 0.3 + overlapScore * 0.7).setScale(2);
  }
}
