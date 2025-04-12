/**
 * Specialized matcher for address fields
 *
 * @description A class to match address fields based on common naming patterns.
 * @author Richard Hudson
 * @date April 2025
 */
public class AddressMatcher {
    /**
     * @description Checks if this matcher can handle the specified field.
     * Checks if this matcher can handle the specified field
     *
     * @param fieldName API name of the field
     * @return True if this matcher can handle the field
     * @description Checks if this matcher can handle the specified field by checking if it contains "address" or ends with "address", as well as other common naming patterns related to addresses such as street, city, state, country and postal code.
     */
    public static Boolean canHandleField(String fieldName) {
        String normalizedFieldName = fieldName.toLowerCase();

        // Handle fields that are likely to contain addresses
        return normalizedFieldName.contains('address') ||
            normalizedFieldName.endsWith('address') ||
            normalizedFieldName.equals('street') ||
            normalizedFieldName.contains('street') ||
            normalizedFieldName.contains('city') ||
            normalizedFieldName.contains('state') ||
            normalizedFieldName.contains('country') ||
            normalizedFieldName.contains('postal') ||
            normalizedFieldName.contains('zip');
    }

    /**
     * Calculates match score between two address values
     *
     * @param address1 First address to compare
     * @param address2 Second address to compare
     * @return Match score (0-100)
     */
    /**
     * @description Calculates match score between two address values using normalized parts comparison.
     *
     * @param address1 First address to compare
     * @param address2 Second address to compare
     * @return Match score (0-100)
     */
    public static Decimal calculateMatchScore(String address1, String address2) {
        if (address1 == null || address2 == null) {
            return 0;
        }
        
        // Normalize the addresses for comparison
        String norm1 = normalizeAddress(address1);
        String norm2 = normalizeAddress(address2);
        
        if (norm1 == norm2) {
            return 100;
        }
        
        List<String> parts1 = norm1.split(' ');
        List<String> parts2 = norm2.split(' ');
        Integer commonParts = countCommonParts(parts1, parts2);
        Integer totalParts = parts1.size() + parts2.size() - commonParts;
        Decimal commonPartsScore = (totalParts != 0) ? 100.0 * commonParts / totalParts : 0;
        return commonPartsScore;
    }
    
    /**
     * @description Normalizes an address string by removing special characters and standardizing format
     * @param address The address to normalize
     * @return Normalized address
     */
    private static String normalizeAddress(String address) {
        if (String.isBlank(address)) {
            return '';
        }
        
        // Convert to lowercase
        String result = address.toLowerCase();
        
        // Replace special characters with spaces
        result = result.replaceAll('[^a-z0-9]', ' ');
        
        // Replace multiple spaces with a single space
        result = result.replaceAll('\\s+', ' ');
        
        // Trim leading and trailing spaces
        return result.trim();
    }

    /**
     * Counts the number of common parts between two string lists
     *
     * @param parts1 First list of string parts
     * @param parts2 Second list of string parts
     * @return Number of common parts
     * @description Counts how many string elements are common between two lists, ignoring case sensitivity
     */
    private static Integer countCommonParts(List<String> parts1, List<String> parts2) {
        Integer commonCount = 0;
        Set<String> uniqueParts = new Set<String>();

        // Convert all parts to lowercase for case-insensitive matching
        for (String part : parts1) {
            uniqueParts.add(part.toLowerCase());
        }

        // Count matches in the second list
        for (String part : parts2) {
            if (uniqueParts.contains(part.toLowerCase())) {
                commonCount++;
                uniqueParts.remove(part.toLowerCase()); // Remove to avoid double counting
            }
        }

        return commonCount;
    }
}
