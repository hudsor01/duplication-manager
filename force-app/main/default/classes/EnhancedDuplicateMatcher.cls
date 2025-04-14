/**
 * Enhanced matcher utility for duplicate detection
 * Provides improved matching algorithms for emails and phone numbers
 *
 * @author Richard Hudson
 * @date April 2025
 */
public class EnhancedDuplicateMatcher {
    
    /**
     * Matches emails with enhanced algorithm that handles common variations
     * 
     * @param email1 First email to compare
     * @param email2 Second email to compare
     * @return Match score from 0-100
     */
    public static Decimal matchEmails(String email1, String email2) {
        // Handle null values
        if (String.isBlank(email1) || String.isBlank(email2)) {
            return 0;
        }
        
        // Normalize emails
        String normalizedEmail1 = normalizeEmail(email1);
        String normalizedEmail2 = normalizeEmail(email2);
        
        // Exact match
        if (normalizedEmail1 == normalizedEmail2) {
            return 100;
        }
        
        // Split emails into local part and domain
        List<String> parts1 = normalizedEmail1.split('@');
        List<String> parts2 = normalizedEmail2.split('@');
        
        // Invalid email format
        if (parts1.size() != 2 || parts2.size() != 2) {
            return 0;
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
        Decimal distanceSimilarity = 100;
        if (local1.length() > 0 && local2.length() > 0) {
            Integer distance = LevenshteinCalculator.distance(local1, local2);
            distanceSimilarity = 100 - (100.0 * distance / Math.max(local1.length(), local2.length()));
        }
        
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
     * Matches phone numbers with enhanced algorithm that handles formatting differences
     * 
     * @param phone1 First phone number
     * @param phone2 Second phone number
     * @return Match score from 0-100
     */
    public static Decimal matchPhones(String phone1, String phone2) {
        // Handle null values
        if (String.isBlank(phone1) || String.isBlank(phone2)) {
            return 0;
        }
        
        // Apply phone number normalization
        String normalizedPhone1 = normalizePhone(phone1);
        String normalizedPhone2 = normalizePhone(phone2);
        
        // If normalized versions match exactly, it's a perfect match
        if (normalizedPhone1 == normalizedPhone2) {
            return 100;
        }
        
        // If we have very short normalized numbers (less than 5 digits), be cautious
        if (normalizedPhone1.length() < 5 || normalizedPhone2.length() < 5) {
            return 0; // Too short to reliably match
        }
        
        // Handle common variations
        if (isLastNDigitsMatch(normalizedPhone1, normalizedPhone2, 10)) {
            return 100; // Match on 10 digits (typical format without country code)
        }
        
        if (isLastNDigitsMatch(normalizedPhone1, normalizedPhone2, 7)) {
            return 90; // Match on last 7 digits (area code might differ)
        }
        
        // Check for partial matches with different country/area codes
        if (isLastNDigitsMatch(normalizedPhone1, normalizedPhone2, 4)) {
            return 75; // Match on last 4 digits (could be coincidence but worth flagging)
        }
        
        return 0; // No match
    }
    
    /**
     * Normalizes an email address for consistent comparison
     * 
     * @param email Email to normalize
     * @return Normalized email
     */
    private static String normalizeEmail(String email) {
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
     * Normalizes a phone number by removing non-numeric characters
     * and handling international prefixes
     * 
     * @param phone Phone number to normalize
     * @return Normalized phone number (digits only)
     */
    private static String normalizePhone(String phone) {
        if (String.isBlank(phone)) {
            return '';
        }
        
        // Remove all non-numeric characters
        String digitsOnly = phone.replaceAll('[^0-9]', '');
        
        // Handle common international prefixes
        if (digitsOnly.startsWith('00')) {
            // Convert international prefix 00 to +
            digitsOnly = digitsOnly.substring(2);
        }
        
        if (digitsOnly.startsWith('011')) {
            // Convert US international prefix 011 to +
            digitsOnly = digitsOnly.substring(3);
        }
        
        // Handle US numbers with leading 1
        if (digitsOnly.length() == 11 && digitsOnly.startsWith('1')) {
            digitsOnly = digitsOnly.substring(1);
        }
        
        return digitsOnly;
    }
    
    /**
     * Checks if two local parts are common variations of each other
     * 
     * @param local1 First local part
     * @param local2 Second local part
     * @return True if they are common variations
     */
    private static Boolean isCommonVariation(String local1, String local2) {
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
    private static Boolean isSubstringOrCommonPrefix(String local1, String local2) {
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
    
    /**
     * Checks if the last N digits of two phone numbers match
     * 
     * @param phone1 First normalized phone number
     * @param phone2 Second normalized phone number
     * @param digits Number of digits to compare
     * @return True if the last N digits match
     */
    private static Boolean isLastNDigitsMatch(String phone1, String phone2, Integer digits) {
        if (phone1.length() < digits || phone2.length() < digits) {
            return false;
        }
        
        String lastDigits1 = phone1.substring(phone1.length() - digits);
        String lastDigits2 = phone2.substring(phone2.length() - digits);
        
        return lastDigits1 == lastDigits2;
    }
}