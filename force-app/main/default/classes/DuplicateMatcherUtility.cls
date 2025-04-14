/**
 * Utility class for identifying duplicates in records
 *
 * @author Richard Hudson
 * @date April 2025
 */
public class DuplicateMatcherUtility {
    // Match threshold for fuzzy matching (0-100)
    private static final Integer FUZZY_MATCH_THRESHOLD = 75;

    /**
     * Groups records by composite key to identify potential duplicates
     *
     * @param records List of SObject records to process
     * @param fields List of field API names to use for matching
     * @return Map of composite key to DuplicateGroup
     */
    public static Map<String, DuplicateGroup> findDuplicateGroups(List<SObject> records, List<String> fields) {
        // First pass: exact matching
        Map<String, List<SObject>> exactMatches = groupByExactMatch(records, fields);

        // Convert exact matches to DuplicateGroup objects
        Map<String, DuplicateGroup> results = new Map<String, DuplicateGroup>();
        for (String key : exactMatches.keySet()) {
            List<SObject> recordGroup = exactMatches.get(key);

            // Only add groups with multiple records (actual duplicates)
            if (recordGroup.size() > 1) {
                results.put(key, new DuplicateGroup(recordGroup, 100, key, true));
            }
        }

        // Second pass: fuzzy matching on remaining records
        Map<String, DuplicateGroup> fuzzyMatches = findFuzzyMatches(records, fields, exactMatches);

        // Add fuzzy matches to results
        for (String key : fuzzyMatches.keySet()) {
            results.put(key, fuzzyMatches.get(key));
        }

        return results;
    }

    /**
     * Groups records by exact match on composite key
     *
     * @param records List of SObject records to process
     * @param fields List of field API names to use for matching
     * @return Map of composite key to list of records
     */
    private static Map<String, List<SObject>> groupByExactMatch(List<SObject> records, List<String> fields) {
        Map<String, List<SObject>> results = new Map<String, List<SObject>>();

        for (SObject record : records) {
            String key = createCompositeKey(record, fields);

            if (!results.containsKey(key)) {
                results.put(key, new List<SObject>());
            }

            results.get(key).add(record);
        }

        return results;
    }

    /**
     * Finds fuzzy matches among records not already in exact match groups
     *
     * @param allRecords All records to process
     * @param fields Fields to use for matching
     * @param exactMatches Map of exact match groups
     * @return Map of fuzzy match key to DuplicateGroup
     */
    private static Map<String, DuplicateGroup> findFuzzyMatches(
        List<SObject> allRecords,
        List<String> fields,
        Map<String, List<SObject>> exactMatches
    ) {
        // Find records not in exact match groups
        Set<Id> exactMatchedIds = new Set<Id>();
        for (List<SObject> recordGroup : exactMatches.values()) {
            if (recordGroup.size() > 1) { // Only consider actual duplicate groups
                for (SObject record : recordGroup) {
                    exactMatchedIds.add(record.Id);
                }
            }
        }

        // Filter to records not in exact match groups
        List<SObject> remainingRecords = new List<SObject>();
        for (SObject record : allRecords) {
            if (!exactMatchedIds.contains(record.Id)) {
                remainingRecords.add(record);
            }
        }

        // Skip fuzzy matching if no remaining records or only a single field
        if (remainingRecords.isEmpty() || fields.size() < 2) {
            return new Map<String, DuplicateGroup>();
        }

        // Fuzzy match remaining records
        return performFuzzyMatching(remainingRecords, fields);
    }

    /**
     * Performs fuzzy matching on records
     *
     * @param records List of SObject records to process
     * @param fields List of field API names to use for matching
     * @return Map of fuzzy match key to DuplicateGroup
     */
    private static Map<String, DuplicateGroup> performFuzzyMatching(
        List<SObject> records,
        List<String> fields
    ) {
        Map<String, DuplicateGroup> results = new Map<String, DuplicateGroup>();

        // Track which records have been matched
        Set<Id> matchedRecords = new Set<Id>();

        // Compare all pairs of records
        for (Integer i = 0; i < records.size(); i++) {
            SObject record1 = records[i];

            // Skip if already matched
            if (matchedRecords.contains(record1.Id)) {
                continue;
            }

            List<SObject> matches = new List<SObject>{record1};
            Decimal bestScore = 0;

            for (Integer j = i + 1; j < records.size(); j++) {
                SObject record2 = records[j];

                // Skip if already matched
                if (matchedRecords.contains(record2.Id)) {
                    continue;
                }

                // Calculate match score
                Decimal score = calculateRecordMatchScore(record1, record2, fields);

                // If score is above threshold, consider it a match
                if (score >= FUZZY_MATCH_THRESHOLD) {
                    matches.add(record2);
                    matchedRecords.add(record2.Id);

                    // Track best score for this group
                    if (score > bestScore) {
                        bestScore = score;
                    }
                }
            }

            // If we found matches, add to results
            if (matches.size() > 1) {
                String key = 'fuzzy-' + record1.Id;
                results.put(key, new DuplicateGroup(matches, bestScore, key, false));
                matchedRecords.add(record1.Id);
            }
        }

        return results;
    }

    /**
     * Calculates match score between two records
     *
     * @param record1 First record to compare
     * @param record2 Second record to compare
     * @param fields List of fields to compare
     * @return Match score (0-100)
     */
    private static Decimal calculateRecordMatchScore(
        SObject record1,
        SObject record2,
        List<String> fields
    ) {
        Decimal totalScore = 0;
        Decimal maxPossibleScore = 0;

        // Set field weights based on field type
        Map<String, Decimal> fieldWeights = getFieldWeights(fields);

        // Calculate total possible score
        for (String field : fields) {
            maxPossibleScore += (100 * fieldWeights.get(field));
        }

        // Calculate score for each field
        for (String field : fields) {
            String fieldName = field.trim();
            Object value1 = record1.get(fieldName);
            Object value2 = record2.get(fieldName);

            Decimal fieldScore = 0;

            // Skip if both values are null
            if (value1 == null && value2 == null) {
                // Field doesn't contribute to score
                maxPossibleScore -= (100 * fieldWeights.get(fieldName));
                continue;
            }

            // Handle cases where one value is null
            if (value1 == null || value2 == null) {
                fieldScore = 0; // No match if one value is null
            } else {
                String str1 = String.valueOf(value1);
                String str2 = String.valueOf(value2);

                // Calculate field match score directly
                fieldScore = calculateFieldMatchScore(str1, str2, fieldName);
            }

            // Apply field weight
            totalScore += (fieldScore * fieldWeights.get(fieldName));
        }

        // Calculate final percentage score
        Decimal finalScore = (maxPossibleScore > 0) ? (totalScore / maxPossibleScore * 100) : 0;

        // Round to 2 decimal places
        return finalScore.setScale(2);
    }

    /**
     * Calculates match score between two field values
     * @param value1 First value to compare
     * @param value2 Second value to compare
     * @param fieldName Field name for context
     * @return Match score from 0-100
     */
    private static Decimal calculateFieldMatchScore(String value1, String value2, String fieldName) {
        // Basic implementation without relying on external matchers
        if (String.isBlank(value1) || String.isBlank(value2)) {
            return 0;
        }
        
        // Normalize strings for comparison
        String str1 = normalizeString(value1);
        String str2 = normalizeString(value2);
        
        // Exact match after normalization
        if (str1 == str2) {
            return 100;
        }
        
        // For emails, do special comparison
        if (fieldName.toLowerCase().contains('email')) {
            // Simple email comparison
            return str1 == str2 ? 100 : 0;
        }
        
        // For phone numbers, compare only digits
        if (fieldName.toLowerCase().contains('phone')) {
            String phone1 = value1.replaceAll('[^0-9]', '');
            String phone2 = value2.replaceAll('[^0-9]', '');
            return phone1 == phone2 ? 100 : 0;
        }
        
        // For addresses, compare parts
        if (fieldName.toLowerCase().contains('address') || 
            fieldName.toLowerCase().contains('street')) {
            return compareAddressParts(str1, str2);
        }
        
        // For names and other fields, calculate similarity
        return calculateStringSimilarity(str1, str2);
    }
    
    /**
     * Calculates similarity between two strings
     * @param s1 First string
     * @param s2 Second string
     * @return Similarity score 0-100
     */
    private static Decimal calculateStringSimilarity(String s1, String s2) {
        if (s1 == s2) return 100; // Exact match
        
        // Length based score component (closer in length = more similar)
        Integer lenDiff = Math.abs(s1.length() - s2.length());
        Integer maxLen = Math.max(s1.length(), s2.length());
        Decimal lengthScore = (maxLen > 0) ? (1 - (Decimal)lenDiff / maxLen) * 100 : 100;
        
        // Character overlap score component
        Set<String> chars1 = new Set<String>();
        for (Integer i = 0; i < s1.length(); i++) {
            chars1.add(s1.substring(i, i+1));
        }
        
        Integer commonChars = 0;
        for (Integer i = 0; i < s2.length(); i++) {
            if (chars1.contains(s2.substring(i, i+1))) {
                commonChars++;
            }
        }
        
        Decimal overlapScore = (maxLen > 0) ? (Decimal)commonChars / maxLen * 100 : 0;
        
        // Combine scores (weight overlap more heavily)
        return (lengthScore * 0.3 + overlapScore * 0.7).setScale(2);
    }
    
    /**
     * Compares address parts for similarity
     * @param addr1 First address
     * @param addr2 Second address
     * @return Similarity score 0-100
     */
    private static Decimal compareAddressParts(String addr1, String addr2) {
        if (addr1 == addr2) return 100;
        
        List<String> parts1 = addr1.split(' ');
        List<String> parts2 = addr2.split(' ');
        
        Integer commonParts = 0;
        Set<String> uniqueParts = new Set<String>();
        
        for (String part : parts1) {
            uniqueParts.add(part.toLowerCase());
        }
        
        for (String part : parts2) {
            if (uniqueParts.contains(part.toLowerCase())) {
                commonParts++;
                uniqueParts.remove(part.toLowerCase());
            }
        }
        
        Integer totalParts = parts1.size() + parts2.size() - commonParts;
        return (totalParts > 0) ? (Decimal)commonParts / totalParts * 100 : 0;
    }
    
    /**
     * Normalizes a string for comparison
     * @param input String to normalize
     * @return Normalized string
     */
    private static String normalizeString(String input) {
        if (String.isBlank(input)) return '';
        
        // Convert to lowercase
        String result = input.toLowerCase();
        
        // Replace special characters with spaces
        result = result.replaceAll('[^a-z0-9]', ' ');
        
        // Replace multiple spaces with a single space
        result = result.replaceAll('\\s+', ' ');
        
        // Trim leading and trailing spaces
        return result.trim();
    }
    
    /**
     * Normalizes an email address
     * @param email Email to normalize
     * @return Normalized email
     */
    private static String normalizeEmail(String email) {
        if (String.isBlank(email)) return '';
        return email.toLowerCase().trim();
    }
    
    /**
     * Normalizes a phone number for better matching
     * @param phone Phone number to normalize
     * @return Normalized phone number
     */
    private static String normalizePhone(String phone) {
        if (String.isBlank(phone)) return '';
        
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
     * Gets weights for each field based on field name
     *
     * @param fields List of field API names
     * @return Map of field name to weight
     */
    private static Map<String, Decimal> getFieldWeights(List<String> fields) {
        Map<String, Decimal> weights = new Map<String, Decimal>();

        for (String field : fields) {
            String fieldName = field.trim();
            String lowerField = fieldName.toLowerCase();

            // Default weight is 1.0
            Decimal weight = 1.0;

            // Adjust weight based on field name - email highest, then phone
            if (lowerField.contains('email')) {
                weight = 2.5; // Email has highest priority
            } else if (lowerField.contains('phone') || lowerField.contains('mobile') || 
                       lowerField.contains('cell') || lowerField.contains('tel')) {
                weight = 2.0; // Phone has second highest priority
            } else if (lowerField.contains('name')) {
                weight = 1.7; // Names are important but lower than email/phone
            } else if (lowerField.contains('address')) {
                weight = 1.5; // Addresses are important
            }

            weights.put(fieldName, weight);
        }

        return weights;
    }

    /**
     * Creates a composite key for a record based on the specified fields
     *
     * @param record The SObject record to process
     * @param fields List of field API names to include in the key
     * @return A string key representing the normalized values of the fields
     */
    private static String createCompositeKey(SObject record, List<String> fields) {
        List<String> keyParts = new List<String>();

        for (String field : fields) {
            // Get field value, convert to string, and handle nulls
            Object fieldValue = record.get(field.trim());
            String stringValue = '';

            if (fieldValue != null) {
                stringValue = String.valueOf(fieldValue);

                // Normalize string based on field type
                String lowerField = field.toLowerCase();
                if (lowerField.contains('email')) {
                    stringValue = normalizeEmail(stringValue);
                } else if (lowerField.contains('phone')) {
                    stringValue = normalizePhone(stringValue);
                } else {
                    stringValue = normalizeString(stringValue);
                }
            }

            keyParts.add(stringValue);
        }

        // Join all parts with a separator unlikely to appear in the data
        return String.join(keyParts, '|#|');
    }
}
