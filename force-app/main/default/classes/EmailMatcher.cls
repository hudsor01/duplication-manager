/**
 * Specialized matcher for email fields
 * 
 * @author Richard Hudson
 * @date April 2025
 */
public class EmailMatcher implements FieldMatcherInterface {
    /**
     * Checks if this matcher can handle the specified field
     * 
     * @param fieldName API name of the field
     * @return True if this matcher can handle the field
     */
    public Boolean canHandleField(String fieldName) {
        String normalizedFieldName = fieldName.toLowerCase();
        
        // Handle fields that are likely to contain emails
        return normalizedFieldName.contains('email') ||
               normalizedFieldName.endsWith('email') ||
               normalizedFieldName.equals('email');
    }
    
    /**
     * Calculates match score between two email values
     * 
     * @param email1 First email to compare
     * @param email2 Second email to compare
     * @return Match score (0-100)
     */
    public Decimal calculateMatchScore(String email1, String email2) {
        // Handle null values
        if (email1 == null || email2 == null) {
            return 0;
        }
        
        // Normalize emails (lowercase only, no other normalization)
        email1 = email1.toLowerCase().trim();
        email2 = email2.toLowerCase().trim();
        
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
            return new GenericMatcher().calculateMatchScore(email1, email2);
        }
        
        String local1 = parts1[0];
        String domain1 = parts1[1];
        String local2 = parts2[0];
        String domain2 = parts2[1];
        
        // Domain must match exactly
        if (domain1 != domain2) {
            return 0;
        }
        
        // Calculate local part similarity
        Decimal localPartScore = 100 - (100.0 * LevenshteinCalculator.distance(local1, local2) / Math.max(local1.length(), local2.length()));
        
        // Email username similarity is crucial, so we return the local part score
        return localPartScore;
    }
}