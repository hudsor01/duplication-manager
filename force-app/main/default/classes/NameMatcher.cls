/**
 * Specialized matcher for name fields
 * 
 * @author Richard Hudson
 * @date April 2025
 */
public class NameMatcher implements FieldMatcherInterface {
    /**
     * Checks if this matcher can handle the specified field
     * 
     * @param fieldName API name of the field
     * @return True if this matcher can handle the field
     */
    public Boolean canHandleField(String fieldName) {
        String normalizedFieldName = fieldName.toLowerCase();
        
        // Handle fields that are likely to contain names
        return normalizedFieldName.contains('name') ||
               normalizedFieldName.endsWith('name') ||
               normalizedFieldName.equals('firstname') ||
               normalizedFieldName.equals('lastname') ||
               normalizedFieldName.equals('middlename');
    }
    
    /**
     * Calculates match score between two name values
     * 
     * @param name1 First name to compare
     * @param name2 Second name to compare
     * @return Match score (0-100)
     */
    public Decimal calculateMatchScore(String name1, String name2) {
        // Handle null values
        if (name1 == null || name2 == null) {
            return 0;
        }
        
        // Normalize names
        name1 = StringNormalizer.normalize(name1);
        name2 = StringNormalizer.normalize(name2);
        
        // Split names into parts
        List<String> parts1 = name1.split(' ');
        List<String> parts2 = name2.split(' ');
        
        // Special case for exact match
        if (name1 == name2) {
            return 100;
        }
        
        // Special case for very short strings
        if (name1.length() < 3 || name2.length() < 3) {
            return name1 == name2 ? 100 : 0;
        }
        
        // Calculate Levenshtein distance-based score
        Decimal levenshteinScore = 100 - (100.0 * LevenshteinCalculator.distance(name1, name2) / Math.max(name1.length(), name2.length()));
        
        // Calculate common parts score
        Decimal commonPartsScore = 0;
        if (!parts1.isEmpty() && !parts2.isEmpty()) {
            Integer commonParts = 0;
            
            // Count common parts
            for (String part1 : parts1) {
                for (String part2 : parts2) {
                    if (part1 == part2 && part1.length() > 1) {
                        commonParts++;
                        break;
                    }
                }
            }
            
            // Calculate score
            commonPartsScore = 100.0 * commonParts / Math.max(parts1.size(), parts2.size());
        }
        
        // For names, we weigh common parts more heavily
        return (levenshteinScore * 0.4) + (commonPartsScore * 0.6);
    }
}