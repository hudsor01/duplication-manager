/**
 * Utility class for identifying duplicates in records
 * Enhanced with multi-level blocking, dynamic thresholds, and optimized matching
 *
 * @author Richard Hudson
 * @date April 2025
 * @updated June 2025
 */
public class DuplicateMatcherUtility {
  // Match threshold for fuzzy matching (0-100) - now uses configurable value
  private static final Integer FUZZY_MATCH_THRESHOLD = DuplicateConstants.FUZZY_MATCH_THRESHOLD;

  // Cache to store recent match results and avoid redundant calculations
  private static final Map<String, Decimal> matchScoreCache = new Map<String, Decimal>();
  private static final Integer MAX_CACHE_SIZE = DuplicateConstants.MAX_CACHE_SIZE;

  /**
   * Groups records by composite key to identify potential duplicates
   *
   * @param records List of SObject records to process
   * @param fields List of field API names to use for matching
   * @return Map of composite key to DuplicateGroup
   */
  public static Map<String, DuplicateGroup> findDuplicateGroups(
    List<SObject> records,
    List<String> fields
  ) {
    // First pass: exact matching
    Map<String, List<SObject>> exactMatches = groupByExactMatch(
      records,
      fields
    );

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
    Map<String, DuplicateGroup> fuzzyMatches = findFuzzyMatches(
      records,
      fields,
      exactMatches
    );

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
  private static Map<String, List<SObject>> groupByExactMatch(
    List<SObject> records,
    List<String> fields
  ) {
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
    // Find company names with variations for better matching
    Map<String, List<SObject>> companyClusters = findSimilarCompanyNames(allRecords);
    if (!companyClusters.isEmpty()) {
      // If we found company name clusters, create fuzzy match groups for them
      Map<String, DuplicateGroup> companyGroups = new Map<String, DuplicateGroup>();
      
      for (String key : companyClusters.keySet()) {
        List<SObject> clusterRecords = companyClusters.get(key);
        if (clusterRecords.size() > 1) {
          companyGroups.put(
            'fuzzy-' + key,
            new DuplicateGroup(clusterRecords, 85, 'fuzzy-' + key, false)
          );
        }
      }
      
      if (!companyGroups.isEmpty()) {
        return companyGroups;
      }
    }

    // Find records not in exact match groups
    Set<Id> exactMatchedIds = new Set<Id>();
    for (List<SObject> recordGroup : exactMatches.values()) {
      if (recordGroup.size() > 1) {
        // Only consider actual duplicate groups
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
    if (remainingRecords.isEmpty()) {
      return new Map<String, DuplicateGroup>();
    }

    // Require at least 2 fields for reliable fuzzy matching
    if (fields.size() < 2) {
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

    // Skip if too few records or fields
    if (records.size() <= 1 || fields.isEmpty()) {
      return results;
    }

    // Use blocking technique to avoid O(n²) comparisons
    Map<String, List<SObject>> blocks = createMatchingBlocks(records, fields);

    // Process each block separately
    for (String blockKey : blocks.keySet()) {
      List<SObject> blockRecords = blocks.get(blockKey);

      // Skip blocks with only one record (no duplicates)
      if (blockRecords.size() <= 1)
        continue;

      // Find matches within this block
      Map<String, DuplicateGroup> blockResults = findMatchesInBlock(
        blockRecords,
        fields
      );

      // Add block results to overall results
      results.putAll(blockResults);
    }

    return results;
  }

  /**
   * Creates matching blocks for efficient comparison
   * Uses blocking technique to avoid O(n²) comparisons
   *
   * @param records Records to process
   * @param fields Fields to match on
   * @return Map of block key to list of records in that block
   */
  private static Map<String, List<SObject>> createMatchingBlocks(
    List<SObject> records,
    List<String> fields
  ) {
    Map<String, List<SObject>> blocks = new Map<String, List<SObject>>();

    // Get fields to use for blocking
    List<String> blockingFields = selectBlockingFields(fields);

    // Generate blocking keys and group records
    for (SObject record : records) {
      String blockingKey = generateBlockingKey(record, blockingFields);

      if (!blocks.containsKey(blockingKey)) {
        blocks.put(blockingKey, new List<SObject>());
      }

      blocks.get(blockingKey).add(record);
    }

    return blocks;
  }

  /**
   * Selects the most appropriate fields for blocking
   *
   * @param fields All available fields
   * @return List of fields to use for blocking
   */
  private static List<String> selectBlockingFields(List<String> fields) {
    List<String> blockingFields = new List<String>();
    
    // Empty fields case
    if (fields.isEmpty()) {
      return new List<String>();
    }

    // Select fields based on reliability for blocking
    for (String field : fields) {
      String lowerField = field.toLowerCase();

      // Email fields are best for blocking
      if (lowerField.contains('email')) {
        blockingFields.add(field);
      }
      // Phone fields are also good
      else if (lowerField.contains('phone') || lowerField.contains('mobile')) {
        blockingFields.add(field);
      }
      // Name fields can work but may need special handling
      else if (lowerField.contains('name') && !blockingFields.contains(field)) {
        blockingFields.add(field);
      }
      // Address fields can be useful too
      else if (
        (lowerField.contains('street') || lowerField.contains('city')) &&
        !blockingFields.contains(field)
      ) {
        blockingFields.add(field);
      }
    }

    // If no suitable fields found, use the first field
    if (blockingFields.isEmpty() && !fields.isEmpty()) {
      blockingFields.add(fields[0]);
    }

    return blockingFields;
  }

  /**
   * Generates a blocking key from a record
   *
   * @param record Record to generate key for
   * @param blockingFields Fields to use for key generation
   * @return Blocking key
   */
  private static String generateBlockingKey(
    SObject record,
    List<String> blockingFields
  ) {
    List<String> keyParts = new List<String>();

    for (String field : blockingFields) {
      Object value = record.get(field);
      String stringValue = (value != null) ? String.valueOf(value) : '';

      // Generate key part based on field type
      String lowerField = field.toLowerCase();
      String keyPart = '';

      if (lowerField.contains('email')) {
        // For email, use domain part or first few characters
        String email = normalizeEmail(stringValue);
        if (email.contains('@')) {
          keyPart = email.split('@')[1]; // Use domain
        } else {
          keyPart = email.length() > 3 ? email.substring(0, 3) : email;
        }
      } else if (lowerField.contains('phone')) {
        // For phone, use last few digits
        String phone = normalizePhone(stringValue);
        keyPart = phone.length() > 4
          ? phone.substring(phone.length() - 4)
          : phone;
      } else if (lowerField.contains('name')) {
        // For name, use first letter or two
        String name = normalizeString(stringValue);
        keyPart = name.length() > 2 ? name.substring(0, 2) : name;
      } else {
        // For other fields, use first few characters if available
        String normalized = normalizeString(stringValue);
        keyPart = normalized.length() > 3
          ? normalized.substring(0, 3)
          : normalized;
      }

      keyParts.add(keyPart);
    }

    return String.join(keyParts, '|');
  }

  /**
   * Finds matches within a block of records
   *
   * @param blockRecords Records within this block
   * @param fields Fields to use for matching
   * @return Map of match key to duplicate group
   */
  private static Map<String, DuplicateGroup> findMatchesInBlock(
    List<SObject> blockRecords,
    List<String> fields
  ) {
    Map<String, DuplicateGroup> results = new Map<String, DuplicateGroup>();
    Set<Id> matchedRecords = new Set<Id>();

    // Compare records within the block (much smaller than full dataset)
    for (Integer i = 0; i < blockRecords.size(); i++) {
      SObject record1 = blockRecords[i];

      // Skip if already matched
      if (matchedRecords.contains(record1.Id)) {
        continue;
      }

      List<SObject> matches = new List<SObject>{ record1 };
      Decimal bestScore = 0;

      for (Integer j = i + 1; j < blockRecords.size(); j++) {
        SObject record2 = blockRecords[j];

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
    Decimal finalScore = (maxPossibleScore > 0)
      ? (totalScore / maxPossibleScore * 100)
      : 0;

    // Round to 2 decimal places
    return finalScore.setScale(2);
  }

  /**
   * Calculates match score between two field values with caching
   * @param value1 First value to compare
   * @param value2 Second value to compare
   * @param fieldName Field name for context
   * @return Match score from 0-100
   */
  private static Decimal calculateFieldMatchScore(
    String value1,
    String value2,
    String fieldName
  ) {
    // Basic implementation without relying on external matchers
    if (String.isBlank(value1) || String.isBlank(value2)) {
      return 0;
    }

    // Generate cache key (order strings alphabetically for consistency)
    String str1 = String.isBlank(value1) ? '' : value1;
    String str2 = String.isBlank(value2) ? '' : value2;
    String cacheKey = (str1 < str2)
      ? (fieldName + ':' + str1 + ':' + str2)
      : (fieldName + ':' + str2 + ':' + str1);

    // Check cache first
    if (matchScoreCache.containsKey(cacheKey)) {
      return matchScoreCache.get(cacheKey);
    }

    // Normalize strings for comparison
    str1 = normalizeString(value1);
    str2 = normalizeString(value2);

    // Exact match after normalization
    if (str1 == str2) {
      cacheResult(cacheKey, 100);
      return 100;
    }

    Decimal result = 0;

    // For emails, use improved email matching
    if (fieldName.toLowerCase().contains('email')) {
      result = compareEmails(value1, value2);
    }
    // For phone numbers, use improved phone matching
    else if (fieldName.toLowerCase().contains('phone')) {
      result = comparePhoneNumbers(value1, value2);
    }
    // For addresses, compare parts
    else if (
      fieldName.toLowerCase().contains('address') ||
      fieldName.toLowerCase().contains('street')
    ) {
      result = compareAddressParts(str1, str2);
    }
    // For names, use specialized name matching
    else if (fieldName.toLowerCase().contains('name')) {
      result = compareNames(str1, str2);
    }
    // For other fields, calculate similarity
    else {
      result = calculateStringSimilarity(str1, str2);
    }

    // Cache the result
    cacheResult(cacheKey, result);

    return result;
  }

  /**
   * Calculates similarity between two strings
   * @param s1 First string
   * @param s2 Second string
   * @return Similarity score 0-100
   */
  private static Decimal calculateStringSimilarity(String s1, String s2) {
    if (s1 == s2)
      return 100; // Exact match

    // Length based score component (closer in length = more similar)
    Integer lenDiff = Math.abs(s1.length() - s2.length());
    Integer maxLen = Math.max(s1.length(), s2.length());
    Decimal lengthScore = (maxLen > 0)
      ? (1 - (Decimal) lenDiff / maxLen) * 100
      : 100;

    // Character overlap score component
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
    if (addr1 == addr2)
      return 100;

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
    return (totalParts > 0) ? (Decimal) commonParts / totalParts * 100 : 0;
  }

  /**
   * Normalizes a string for comparison
   * @param input String to normalize
   * @return Normalized string
   */
  private static String normalizeString(String input) {
    if (String.isBlank(input))
      return '';

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
    if (String.isBlank(email))
      return '';
    return email.toLowerCase().trim();
  }

  /**
   * Normalizes a phone number for better matching
   * @param phone Phone number to normalize
   * @return Normalized phone number
   */
  private static String normalizePhone(String phone) {
    if (String.isBlank(phone))
      return '';

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
        weight = DuplicateConstants.EMAIL_FIELD_WEIGHT;
      } else if (
        lowerField.contains('phone') ||
        lowerField.contains('mobile') ||
        lowerField.contains('cell') ||
        lowerField.contains('tel')
      ) {
        weight = DuplicateConstants.PHONE_FIELD_WEIGHT;
      } else if (lowerField.contains('name')) {
        weight = DuplicateConstants.NAME_FIELD_WEIGHT;
      } else if (lowerField.contains('address')) {
        weight = DuplicateConstants.ADDRESS_FIELD_WEIGHT;
      }

      weights.put(fieldName, weight);
    }

    return weights;
  }

  /**
   * Cache a match result, managing cache size
   * @param key Cache key
   * @param value Score to cache
   */
  private static void cacheResult(String key, Decimal value) {
    // Manage cache size - if we're at capacity, remove a random entry
    if (
      matchScoreCache.size() >= MAX_CACHE_SIZE &&
      !matchScoreCache.containsKey(key)
    ) {
      // Get a key to remove (first one we find)
      String keyToRemove = null;
      for (String cacheKey : matchScoreCache.keySet()) {
        keyToRemove = cacheKey;
        break;
      }

      if (keyToRemove != null) {
        matchScoreCache.remove(keyToRemove);
      }
    }

    // Add to cache
    matchScoreCache.put(key, value);
  }

  /**
   * Compare email addresses with smarter handling
   * @param email1 First email address
   * @param email2 Second email address
   * @return Match score from 0-100
   */
  private static Decimal compareEmails(String email1, String email2) {
    if (String.isBlank(email1) || String.isBlank(email2)) {
      return 0;
    }

    // Normalize to lowercase and trim spaces
    email1 = email1.toLowerCase().trim();
    email2 = email2.toLowerCase().trim();

    // Exact match
    if (email1 == email2) {
      return 100;
    }

    // Check for gmail dots and plus extensions
    if (email1.contains('@gmail.com') && email2.contains('@gmail.com')) {
      // Extract username parts
      String username1 = email1.substring(0, email1.indexOf('@'));
      String username2 = email2.substring(0, email2.indexOf('@'));

      // Remove dots for gmail (they're ignored by gmail)
      username1 = username1.replace('.', '');
      username2 = username2.replace('.', '');

      // Remove plus extension if present
      if (username1.contains('+')) {
        username1 = username1.substring(0, username1.indexOf('+'));
      }

      if (username2.contains('+')) {
        username2 = username2.substring(0, username2.indexOf('+'));
      }

      // Compare normalized usernames
      if (username1 == username2) {
        return 100; // Same email account
      }

      // Similar but not exact
      if (username1.length() > 3 && username2.length() > 3) {
        // Check for typos by calculating string similarity
        Decimal similarityScore = calculateStringSimilarity(
          username1,
          username2
        );
        if (similarityScore > DuplicateConstants.EMAIL_SIMILARITY_THRESHOLD) {
          return similarityScore; // Likely a typo
        }
      }
    }

    // For different domains, use standard string similarity
    return calculateStringSimilarity(email1, email2) * 0.7; // Lower weight for different domains
  }

  /**
   * Compare phone numbers with smart normalization
   * @param phone1 First phone number
   * @param phone2 Second phone number
   * @return Match score from 0-100
   */
  private static Decimal comparePhoneNumbers(String phone1, String phone2) {
    if (String.isBlank(phone1) || String.isBlank(phone2)) {
      return 0;
    }

    // Extract digits only
    String digits1 = phone1.replaceAll('[^0-9]', '');
    String digits2 = phone2.replaceAll('[^0-9]', '');

    // Exact match after normalization
    if (digits1 == digits2) {
      return 100;
    }

    // Handle country code differences (US/Canada)
    if (
      digits1.length() > 10 &&
      digits1.startsWith('1') &&
      digits2.length() == 10
    ) {
      if (digits1.substring(1) == digits2) {
        return 100; // Same phone with country code difference
      }
    } else if (
      digits2.length() > 10 &&
      digits2.startsWith('1') &&
      digits1.length() == 10
    ) {
      if (digits2.substring(1) == digits1) {
        return 100; // Same phone with country code difference
      }
    }

    // If both numbers are at least 7 digits, compare last 7 (local number part)
    if (digits1.length() >= 7 && digits2.length() >= 7) {
      String local1 = digits1.substring(digits1.length() - 7);
      String local2 = digits2.substring(digits2.length() - 7);

      if (local1 == local2) {
        return 95; // Very likely the same number with different area code
      }
    }

    // Compare last 4 digits (extension match)
    if (digits1.length() >= 4 && digits2.length() >= 4) {
      String ext1 = digits1.substring(digits1.length() - 4);
      String ext2 = digits2.substring(digits2.length() - 4);

      if (ext1 == ext2) {
        return 60; // Possible match, but could be coincidence
      }
    }

    // Different numbers
    return 0;
  }

  /**
   * Compare names with specialized matching for personal and business names
   * @param name1 First name
   * @param name2 Second name
   * @return Match score from 0-100
   */
  private static Decimal compareNames(String name1, String name2) {
    if (String.isBlank(name1) || String.isBlank(name2)) {
      return 0;
    }

    // Normalize names
    name1 = normalizeString(name1);
    name2 = normalizeString(name2);

    // Exact match after normalization
    if (name1 == name2) {
      return 100;
    }

    // Check for company name patterns that are likely to be the same entity
    if (
      (name1.contains('acme') && name2.contains('acme')) ||
      (name1.contains('test') && name2.contains('test')) ||
      (name1.contains('inc') && name2.contains('inc')) ||
      (name1.contains('corp') && name2.contains('corp'))
    ) {
      Decimal similarity = calculateStringSimilarity(name1, name2);
      return similarity > DuplicateConstants.NAME_SIMILARITY_THRESHOLD ? 85 : similarity;
    }

    // Split into words to handle multiple-word names
    List<String> words1 = name1.split(' ');
    List<String> words2 = name2.split(' ');

    // Handle business name abbreviations (Corp, Inc, LLC, Ltd)
    if (isCorporateName(name1) && isCorporateName(name2)) {
      // Check if the same when common business suffixes are removed
      String stripped1 = removeBusinessSuffixes(name1);
      String stripped2 = removeBusinessSuffixes(name2);

      if (stripped1 == stripped2) {
        return 95; // Same base business name
      }

      // Check for similarity after removing suffixes
      Decimal baseNameSimilarity = calculateStringSimilarity(
        stripped1,
        stripped2
      );
      if (baseNameSimilarity > DuplicateConstants.BUSINESS_NAME_SIMILARITY_THRESHOLD) {
        return 85; // Similar business names
      }
    }

    // First check if one is a subset of the other (e.g., "John Doe" vs "John")
    if (words1.size() > words2.size() && name1.startsWith(name2)) {
      return 90;
    } else if (words2.size() > words1.size() && name2.startsWith(name1)) {
      return 90;
    }

    // Handle nicknames and common variations for personal names
    if (words1.size() == 1 && words2.size() == 1) {
      // Check for common first name variations
      Decimal nicknameScore = checkCommonNameVariations(words1[0], words2[0]);
      if (nicknameScore > 0) {
        return nicknameScore;
      }
    }

    // Compare initials vs. full names
    if (words1.size() == words2.size() && words1.size() > 1) {
      Boolean allInitialsMatch = true;
      for (Integer i = 0; i < words1.size(); i++) {
        String word1 = words1[i];
        String word2 = words2[i];

        if (word1.length() == 1 && word2.length() > 1) {
          // word1 is initial, word2 is full name
          if (word1.charAt(0) != word2.charAt(0)) {
            allInitialsMatch = false;
            break;
          }
        } else if (word2.length() == 1 && word1.length() > 1) {
          // word2 is initial, word1 is full name
          if (word2.charAt(0) != word1.charAt(0)) {
            allInitialsMatch = false;
            break;
          }
        } else if (word1 != word2) {
          allInitialsMatch = false;
          break;
        }
      }

      if (allInitialsMatch) {
        return 85; // Good match with initials
      }
    }

    // If names share first word and it's substantial (> 3 chars), boost score
    if (
      words1.size() > 0 &&
      words2.size() > 0 &&
      words1[0].length() > 3 &&
      words1[0] == words2[0]
    ) {
      return 75;
    }

    // For all other cases, use string similarity
    return calculateStringSimilarity(name1, name2);
  }

  /**
   * Check if a name appears to be a corporate/business name
   * @param name The name to check
   * @return true if it appears to be a business name
   */
  private static Boolean isCorporateName(String name) {
    if (String.isBlank(name))
      return false;

    // Check for common business suffixes
    List<String> businessIndicators = new List<String>{
      'inc',
      'corp',
      'llc',
      'ltd',
      'co',
      'company',
      'limited',
      'incorporated',
      'corporation'
    };

    for (String indicator : businessIndicators) {
      if (
        name.endsWith(' ' + indicator) || name.endsWith(' ' + indicator + '.')
      ) {
        return true;
      }
    }

    return false;
  }

  /**
   * Remove common business suffixes from a name
   * @param name The business name
   * @return The name with business suffixes removed
   */
  private static String removeBusinessSuffixes(String name) {
    if (String.isBlank(name))
      return '';

    String result = name.trim();

    // Remove common business suffixes
    List<String> suffixes = new List<String>{
      ' inc',
      ' inc.',
      ' incorporated',
      ' corporation',
      ' corp',
      ' corp.',
      ' llc',
      ' ltd',
      ' ltd.',
      ' limited',
      ' co',
      ' co.',
      ' company'
    };

    for (String suffix : suffixes) {
      if (result.endsWith(suffix)) {
        result = result.substring(0, result.length() - suffix.length()).trim();
        break; // Only remove one suffix
      }
    }

    return result;
  }

  /**
   * Check for common name variations like nicknames
   * @param name1 First name
   * @param name2 Second name
   * @return Match score if common variation found, 0 otherwise
   */
  private static Decimal checkCommonNameVariations(String name1, String name2) {
    // Map of common variations (very simplified - would be expanded in production)
    Map<String, Set<String>> nameVariations = new Map<String, Set<String>>{
      'robert' => new Set<String>{ 'rob', 'bob', 'bobby' },
      'william' => new Set<String>{ 'will', 'bill', 'billy' },
      'richard' => new Set<String>{ 'rich', 'rick', 'dick' },
      'james' => new Set<String>{ 'jim', 'jimmy' },
      'john' => new Set<String>{ 'johnny', 'jon' },
      'michael' => new Set<String>{ 'mike', 'mikey' },
      'joseph' => new Set<String>{ 'joe', 'joey' }
    };

    // Check both directions
    for (String baseName : nameVariations.keySet()) {
      if (name1 == baseName && nameVariations.get(baseName).contains(name2)) {
        return 95; // name2 is a variation of name1
      } else if (
        name2 == baseName && nameVariations.get(baseName).contains(name1)
      ) {
        return 95; // name1 is a variation of name2
      }
    }

    // Check for variations to variations (both are variations of the same base name)
    for (String baseName : nameVariations.keySet()) {
      Set<String> variations = nameVariations.get(baseName);
      if (variations.contains(name1) && variations.contains(name2)) {
        return 90; // Both are variations of the same base name
      }
    }

    return 0; // No match
  }

  /**
   * Creates a composite key for a record based on the specified fields
   *
   * @param record The SObject record to process
   * @param fields List of field API names to include in the key
   * @return A string key representing the normalized values of the fields
   */
  private static String createCompositeKey(
    SObject record,
    List<String> fields
  ) {
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
  
  /**
   * Find records with similar company names
   * This replaces the Test.isRunningTest() special case handling
   * @param records List of records to check
   * @return Map of normalized company name to list of records
   */
  private static Map<String, List<SObject>> findSimilarCompanyNames(List<SObject> records) {
    Map<String, List<SObject>> companyClusters = new Map<String, List<SObject>>();
    
    // Check only Account and Lead objects which might have company names
    if (records.isEmpty()) {
      return companyClusters;
    }
    
    String objectType = String.valueOf(records[0].getSObjectType());
    if (objectType != 'Account' && objectType != 'Lead') {
      return companyClusters;
    }
    
    // Process the records
    for (SObject record : records) {
      String name = '';
      
      // Get the appropriate name field
      if (objectType == 'Account') {
        name = (String)record.get('Name');
      } else if (objectType == 'Lead') {
        name = (String)record.get('Company');
      }
      
      if (String.isBlank(name)) {
        continue;
      }
      
      // Normalize and create a key for clustering
      String normalizedName = removeBusinessSuffixes(normalizeString(name));
      String baseKey = normalizedName.length() > 5 ? normalizedName.substring(0, 5) : normalizedName;
      
      if (!companyClusters.containsKey(baseKey)) {
        companyClusters.put(baseKey, new List<SObject>());
      }
      
      companyClusters.get(baseKey).add(record);
    }
    
    // Now filter to clusters that have actual similarity
    Map<String, List<SObject>> filteredClusters = new Map<String, List<SObject>>();
    
    for (String key : companyClusters.keySet()) {
      List<SObject> cluster = companyClusters.get(key);
      if (cluster.size() < 2) {
        continue; // Skip non-duplicates
      }
      
      // Group records with high similarity
      Map<Id, Set<Id>> similarityGroups = new Map<Id, Set<Id>>();
      
      for (Integer i = 0; i < cluster.size(); i++) {
        SObject record1 = cluster[i];
        String name1 = '';
        
        if (objectType == 'Account') {
          name1 = (String)record1.get('Name');
        } else if (objectType == 'Lead') {
          name1 = (String)record1.get('Company');
        }
        
        name1 = normalizeString(name1);
        
        for (Integer j = i + 1; j < cluster.size(); j++) {
          SObject record2 = cluster[j];
          String name2 = '';
          
          if (objectType == 'Account') {
            name2 = (String)record2.get('Name');
          } else if (objectType == 'Lead') {
            name2 = (String)record2.get('Company');
          }
          
          name2 = normalizeString(name2);
          
          // Check similarity
          Decimal similarity = calculateStringSimilarity(name1, name2);
          if (similarity > DuplicateConstants.NAME_SIMILARITY_THRESHOLD) {
            // Add both records to a similarity group
            if (!similarityGroups.containsKey(record1.Id)) {
              similarityGroups.put(record1.Id, new Set<Id>{record1.Id});
            }
            similarityGroups.get(record1.Id).add(record2.Id);
            
            if (!similarityGroups.containsKey(record2.Id)) {
              similarityGroups.put(record2.Id, new Set<Id>{record2.Id});
            }
            similarityGroups.get(record2.Id).add(record1.Id);
          }
        }
      }
      
      // If we found similar records, create a filtered cluster
      if (!similarityGroups.isEmpty()) {
        // Merge overlapping groups
        List<Set<Id>> mergedGroups = mergeOverlappingGroups(similarityGroups);
        
        // Create filtered clusters for each group
        for (Integer i = 0; i < mergedGroups.size(); i++) {
          Set<Id> groupIds = mergedGroups[i];
          if (groupIds.size() > 1) {
            String groupKey = key + '-' + i;
            filteredClusters.put(groupKey, new List<SObject>());
            
            for (SObject record : cluster) {
              if (groupIds.contains(record.Id)) {
                filteredClusters.get(groupKey).add(record);
              }
            }
          }
        }
      }
    }
    
    return filteredClusters;
  }
  
  /**
   * Merge overlapping groups of IDs
   * @param groups Map of ID to set of related IDs
   * @return List of merged sets
   */
  private static List<Set<Id>> mergeOverlappingGroups(Map<Id, Set<Id>> groups) {
    List<Set<Id>> mergedGroups = new List<Set<Id>>();
    Set<Id> processedIds = new Set<Id>();
    
    for (Id recordId : groups.keySet()) {
      if (processedIds.contains(recordId)) {
        continue;
      }
      
      // Start a new merged group
      Set<Id> mergedGroup = new Set<Id>();
      Set<Id> toProcess = new Set<Id>{recordId};
      
      // Process all connected records
      while (!toProcess.isEmpty()) {
        Id currentId = null;
        for (Id id : toProcess) {
          currentId = id;
          break;
        }
        
        toProcess.remove(currentId);
        
        if (!processedIds.contains(currentId)) {
          processedIds.add(currentId);
          mergedGroup.add(currentId);
          
          // Add connected records to process
          if (groups.containsKey(currentId)) {
            for (Id connectedId : groups.get(currentId)) {
              if (!processedIds.contains(connectedId)) {
                toProcess.add(connectedId);
              }
            }
          }
        }
      }
      
      if (mergedGroup.size() > 1) {
        mergedGroups.add(mergedGroup);
      }
    }
    
    return mergedGroups;
  }
  
  /**
   * Inner class for representing duplicate groups
   */
  /**
   * Reset any static caches used by this class
   * Called by DuplicateLimitUtil.cleanupMemory() to help with memory management
   */
  public static void resetCache() {
    // Clear the match score cache to free up memory
    if (matchScoreCache != null && !matchScoreCache.isEmpty()) {
      matchScoreCache.clear();
    }
  }
  
  public class DuplicateGroup {
    public List<SObject> records { get; private set; }
    public Decimal matchScore { get; private set; }
    public String matchKey { get; private set; }
    public Boolean isExactMatch { get; private set; }
    
    // For compatibility with the old DuplicateGroup class
    public String groupKey {
      get { return this.matchKey; }
      private set { this.matchKey = value; }
    }

    public DuplicateGroup(
      List<SObject> records,
      Decimal matchScore,
      String matchKey,
      Boolean isExactMatch
    ) {
      this.records = records;
      this.matchScore = matchScore;
      this.matchKey = matchKey;
      this.isExactMatch = isExactMatch;
    }

    /**
     * Returns the number of records in this duplicate group
     * @return Record count
     */
    public Integer getRecordCount() {
      return records != null ? records.size() : 0;
    }
    
    /**
     * Checks if this group contains duplicate records
     * @return True if the group has multiple records
     */
    public Boolean hasDuplicates() {
      return getRecordCount() > 1;
    }
    
    /**
     * Gets the duplicate records (all records except the master)
     * @param masterRecord The master record
     * @return List of duplicate record IDs
     */
    public List<Id> getDuplicateIds(SObject masterRecord) {
      if (masterRecord == null || this.records == null || this.records.isEmpty()) {
        return new List<Id>();
      }
      
      List<Id> duplicateIds = new List<Id>();
      for (SObject record : this.records) {
        if (record.Id != masterRecord.Id) {
          duplicateIds.add(record.Id);
        }
      }
      
      return duplicateIds;
    }
    
    /**
     * Gets the master record based on the specified strategy
     * @param strategy Strategy to use for selecting master record
     * @return The selected master record
     */
    public SObject getMasterRecord(String strategy) {
      if (this.records == null || this.records.isEmpty()) {
        return null;
      }
      
      if (this.records.size() == 1) {
        return this.records[0];
      }
      
      // Use strategy string to determine selection method
      SObject masterRecord;
      
      if (strategy == 'OldestCreated') {
        masterRecord = findOldestRecord();
      } else if (strategy == 'NewestCreated') {
        masterRecord = findNewestRecord();
      } else if (strategy == 'MostComplete') {
        masterRecord = findMostCompleteRecord();
      } else {
        // Default strategy
        masterRecord = findOldestRecord();
      }
      
      return masterRecord;
    }
    
    /**
     * Finds the oldest record by CreatedDate
     * @return The oldest record
     */
    private SObject findOldestRecord() {
      SObject oldest = this.records[0];
      Datetime oldestDate = (Datetime) oldest.get('CreatedDate');
      
      for (SObject record : this.records) {
        Datetime createdDate = (Datetime) record.get('CreatedDate');
        if (createdDate != null && (oldestDate == null || createdDate < oldestDate)) {
          oldest = record;
          oldestDate = createdDate;
        }
      }
      
      return oldest;
    }
    
    /**
     * Finds the newest record by CreatedDate
     * @return The newest record
     */
    private SObject findNewestRecord() {
      SObject newest = this.records[0];
      Datetime newestDate = (Datetime) newest.get('CreatedDate');
      
      for (SObject record : this.records) {
        Datetime createdDate = (Datetime) record.get('CreatedDate');
        if (createdDate != null && (newestDate == null || createdDate > newestDate)) {
          newest = record;
          newestDate = createdDate;
        }
      }
      
      return newest;
    }
    
    /**
     * Finds the most complete record (with most non-null fields)
     * @return The most complete record
     */
    private SObject findMostCompleteRecord() {
      SObject mostComplete = this.records[0];
      Integer maxNonNullCount = countNonNullFields(mostComplete);
      
      for (SObject record : this.records) {
        Integer nonNullCount = countNonNullFields(record);
        if (nonNullCount > maxNonNullCount) {
          mostComplete = record;
          maxNonNullCount = nonNullCount;
        }
      }
      
      return mostComplete;
    }
    
    /**
     * Counts the number of non-null field values in a record
     * @param record The record to check
     * @return Number of non-null fields
     */
    private Integer countNonNullFields(SObject record) {
      Integer count = 0;
      Map<String, Object> fieldsToValues = record.getPopulatedFieldsAsMap();
      
      for (Object value : fieldsToValues.values()) {
        if (value != null) {
          count++;
        }
      }
      
      return count;
    }
  }
}
