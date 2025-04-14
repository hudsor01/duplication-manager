/**
 * Specialized matcher for email fields with enhanced fuzzy matching capabilities
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
               normalizedFieldName.equals('email') ||
               normalizedFieldName.contains('e-mail');
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
        if (String.isBlank(email1) || String.isBlank(email2)) {
            return 0;
        }
        
        // Normalize emails
        email1 = normalizeEmail(email1);
        email2 = normalizeEmail(email2);
        
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
        
        // Domain must match exactly (case insensitive)
        if (domain1 != domain2) {
            return 0;
        }
        
        // Exact match on local part
        if (local1 == local2) {
            return 100;
        }
        
        // Check for common email prefix variations
        if (isCommonVariation(local1, local2)) {
            return 95;
        }
        
        // Check for period-separated versions of the same name
        // e.g., john.doe vs johndoe
        if (local1.replace('.', '') == local2.replace('.', '')) {
            return 95;
        }
        
        // Check for plus extensions (e.g., email+extension@domain.com)
        if (local1.contains('+') || local2.contains('+')) {
            String base1 = local1.contains('+') ? local1.substring(0, local1.indexOf('+')) : local1;
            String base2 = local2.contains('+') ? local2.substring(0, local2.indexOf('+')) : local2;
            
            if (base1 == base2) {
                return 95;
            }
        }
        
        // Calculate Levenshtein distance similarity
        Decimal distanceSimilarity = 100 - (100.0 * LevenshteinCalculator.distance(local1, local2) / Math.max(local1.length(), local2.length()));
        
        // If highly similar, consider it a possible match
        if (distanceSimilarity >= 80) {
            return distanceSimilarity;
        }
        
        // Calculate substring similarity
        if (isSubstringOrCommonPrefix(local1, local2)) {
            return 85;
        }
        
        return 0; // No match
    }
    
    /**
     * Normalizes an email address
     * 
     * @param email Email to normalize
     * @return Normalized email
     */
    private String normalizeEmail(String email) {
        if (String.isBlank(email)) {
            return '';
        }
        
        // Convert to lowercase
        String normalizedEmail = email.toLowerCase().trim();
        
        // Remove any whitespace
        normalizedEmail = normalizedEmail.replaceAll('\\s+', '');
        
        return normalizedEmail;
    }
    
    /**
     * Checks if two local parts are common variations of each other
     * 
     * @param local1 First local part
     * @param local2 Second local part
     * @return True if they are common variations
     */
    private Boolean isCommonVariation(String local1, String local2) {
        // Common variations like first initial + last name
        // e.g., jsmith and johnsmith
        if (local1.length() > 1 && local2.length() > 1) {
            // Check if one starts with the first letter of the other
            if ((local1.startsWith(local2.substring(0, 1)) && local1.endsWith(local2.substring(1))) || 
                (local2.startsWith(local1.substring(0, 1)) && local2.endsWith(local1.substring(1)))) {
                return true;
            }
            
            // Check for first.last vs firstlast
            if (local1.contains('.') || local2.contains('.')) {
                String noDots1 = local1.replace('.', '');
                String noDots2 = local2.replace('.', '');
                if (noDots1 == noDots2) {
                    return true;
                }
            }
        }
        
        return false;
    }
    
    /**
     * Checks if one local part is a substring of the other or they share a common prefix
     * 
     * @param local1 First local part
     * @param local2 Second local part
     * @return True if one is a substring of the other or they share a common prefix
     */
    private Boolean isSubstringOrCommonPrefix(String local1, String local2) {
        // Check if one is a substring of the other
        if (local1.contains(local2) || local2.contains(local1)) {
            return true;
        }
        
        // Check for common prefix (at least 4 chars)
        Integer minLength = Math.min(local1.length(), local2.length());
        if (minLength >= 4) {
            Integer commonPrefixLength = 0;
            for (Integer i = 0; i < minLength; i++) {
                if (local1.substring(i, i+1) == local2.substring(i, i+1)) {
                    commonPrefixLength++;
                } else {
                    break;
                }
            }
            
            // If at least 4 chars match at the beginning, consider it a possible match
            if (commonPrefixLength >= 4) {
                return true;
            }
        }
        
        return false;
    }
}