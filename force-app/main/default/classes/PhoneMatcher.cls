/**
 * Specialized matcher for phone number fields
 * Provides enhanced phone matching with international number support
 *
 * @author Richard Hudson
 * @date April 2025
 */
public class PhoneMatcher implements FieldMatcherInterface {
    /**
     * Determines if this matcher can handle the specified field
     * 
     * @param fieldName API name of the field
     * @return True if this is a phone field
     */
    public Boolean canHandleField(String fieldName) {
        if (String.isBlank(fieldName)) {
            return false;
        }
        
        String normalizedFieldName = fieldName.toLowerCase();
        return normalizedFieldName.contains('phone') || 
               normalizedFieldName.endsWith('phone') ||
               normalizedFieldName.contains('mobile') || 
               normalizedFieldName.contains('cell') ||
               normalizedFieldName.contains('tel') ||
               normalizedFieldName.contains('fax');
    }
    
    /**
     * Calculates match score between two phone numbers
     * 
     * @param phone1 First phone number
     * @param phone2 Second phone number
     * @return Match score (0-100)
     */
    public Decimal calculateMatchScore(String phone1, String phone2) {
        // Handle null values
        if (String.isBlank(phone1) || String.isBlank(phone2)) {
            return 0;
        }
        
        // Apply phone number normalization
        String normalizedPhone1 = normalizePhoneNumber(phone1);
        String normalizedPhone2 = normalizePhoneNumber(phone2);
        
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
     * Normalizes a phone number by removing all non-numeric characters
     * 
     * @param phoneNumber Phone number to normalize
     * @return Normalized phone number (digits only)
     */
    private String normalizePhoneNumber(String phoneNumber) {
        if (String.isBlank(phoneNumber)) {
            return '';
        }
        
        // Remove all non-numeric characters
        String digitsOnly = phoneNumber.replaceAll('[^0-9]', '');
        
        // Handle common leading characters for international numbers
        if (digitsOnly.startsWith('00')) {
            // Convert international prefix 00 to +
            digitsOnly = digitsOnly.substring(2);
        }
        
        if (digitsOnly.startsWith('011')) {
            // Convert US international prefix 011 to +
            digitsOnly = digitsOnly.substring(3);
        }
        
        // Handle country code 1 for US/Canada
        if (digitsOnly.length() == 11 && digitsOnly.startsWith('1')) {
            digitsOnly = digitsOnly.substring(1);
        }
        
        return digitsOnly;
    }
    
    /**
     * Checks if the last N digits of two phone numbers match
     * 
     * @param phone1 First normalized phone number
     * @param phone2 Second normalized phone number
     * @param digits Number of digits to compare
     * @return True if the last N digits match
     */
    private Boolean isLastNDigitsMatch(String phone1, String phone2, Integer digits) {
        if (phone1.length() < digits || phone2.length() < digits) {
            return false;
        }
        
        String lastDigits1 = phone1.substring(phone1.length() - digits);
        String lastDigits2 = phone2.substring(phone2.length() - digits);
        
        return lastDigits1 == lastDigits2;
    }
}