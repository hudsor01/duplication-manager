/**
 * Utility class for duplicate management
 * Provides common utility methods for duplicate processing
 *
 * @author Richard Hudson
 * @date April 2025
 */
public class DuplicateUtil {
  /**
   * Format a list of IDs as a comma-separated string
   * @param recordIds List of record IDs to format
   * @return Comma-separated string of IDs
   */
  public static String formatIdList(List<Id> recordIds) {
    if (recordIds == null || recordIds.isEmpty()) {
      return '';
    }
    return String.join(recordIds, ',');
  }

  /**
   * Parse a comma-separated string of IDs into a list
   * @param idString Comma-separated string of IDs
   * @return List of record IDs
   */
  public static List<Id> parseIdList(String idString) {
    List<Id> result = new List<Id>();
    if (String.isBlank(idString)) {
      return result;
    }

    for (String idStr : idString.split(',')) {
      if (String.isNotBlank(idStr) && idStr.length() >= 15) {
        try {
          result.add(Id.valueOf(idStr));
        } catch (Exception e) {
          // Skip invalid IDs
        }
      }
    }
    return result;
  }

  /**
   * Truncate a string to a maximum length
   * @param input Input string to truncate
   * @param maxLength Maximum length
   * @return Truncated string
   */
  public static String truncateString(String input, Integer maxLength) {
    if (String.isBlank(input) || input.length() <= maxLength) {
      return input;
    }
    return input.substring(0, maxLength);
  }

  /**
   * Get field value as string from an SObject
   * @param record SObject record
   * @param fieldName Field API name
   * @return String representation of the field value
   */
  public static String getFieldValueAsString(SObject record, String fieldName) {
    if (record == null || String.isBlank(fieldName)) {
      return '';
    }

    Object value = record.get(fieldName);
    if (value == null) {
      return '';
    }
    return String.valueOf(value);
  }
}
