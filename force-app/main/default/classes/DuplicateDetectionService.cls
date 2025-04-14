/**
 * DuplicateDetectionService
 * @description Service class for handling duplicate detection operations
 */
public with sharing class DuplicateDetectionService {
  /**
   * Performs a direct duplicate check on a single record
   *
   * @param objectApiName API name of the object to check
   * @param recordId ID of the record to check
   * @param matchFields List of fields to use for matching
   * @return Map containing duplicate information
   */
  public Map<String, Object> checkForDuplicates(
    String objectApiName,
    Id recordId,
    List<String> matchFields
  ) {
    // Validate inputs
    validateInputs(objectApiName, recordId, matchFields);

    // Get the source record with match fields
    SObject record = getSourceRecord(objectApiName, recordId, matchFields);

    // Find potential duplicate records
    List<SObject> potentialDupes = findPotentialDuplicates(
      objectApiName,
      recordId,
      matchFields,
      record
    );

    // Score and filter duplicates
    List<Map<String, Object>> duplicates = scoreAndFilterDuplicates(
      potentialDupes,
      record,
      matchFields
    );

    // Build result
    Map<String, Object> result = new Map<String, Object>();
    result.put('duplicatesFound', duplicates.size());
    result.put('duplicates', duplicates);

    return result;
  }

  /**
   * Gets statistics about duplicates for a record using Name field
   *
   * @param recordId ID of the record to check for duplicates
   * @return Map containing duplicate statistics
   */
  public Map<String, Object> getDuplicateStatistics(String recordId) {
    if (String.isBlank(recordId)) {
      throw new duplicateException('Record Id is required');
    }

    Id recId = Id.valueOf(recordId);
    String objectName = recId.getSobjectType().getDescribe().getName();

    // Query the record and get name
    SObject record = queryRecordName(recordId, objectName);
    String name = (String) record.get('Name');

    // Count duplicates based on Name field
    Integer dupCount = countDuplicatesByName(objectName, recordId, name);

    // Build result
    Map<String, Object> stats = new Map<String, Object>();
    stats.put('duplicateCount', dupCount);
    stats.put('matchField', 'Name');
    stats.put('originalName', name);
    stats.put(
      'warning',
      dupCount > 0 ? 'Duplicates found' : 'No duplicates found'
    );
    return stats;
  }

  /**
   * Gets duplicate records for a specific record using Name field
   *
   * @param recordId ID of the record to get duplicates for
   * @return List of duplicate records
   */
  public List<SObject> getDuplicateRecords(String recordId) {
    if (String.isBlank(recordId)) {
      throw new duplicateException('Record Id is required');
    }

    Id recId = Id.valueOf(recordId);
    String objectName = recId.getSobjectType().getDescribe().getName();

    // Query the record and get name
    SObject record = queryRecordName(recordId, objectName);
    String name = (String) record.get('Name');

    // Query duplicate records
    String dupQuery = buildNameDuplicateQuery(objectName, recordId, name);
    return Database.query(dupQuery + ' WITH SECURITY_ENFORCED');
  }

  // Private helper methods

  /**
   * Validates check for duplicates inputs
   */
  private void validateInputs(
    String objectApiName,
    Id recordId,
    List<String> matchFields
  ) {
    if (
      String.isBlank(objectApiName) ||
      recordId == null ||
      matchFields == null ||
      matchFields.isEmpty()
    ) {
      throw new duplicateException('Missing required parameters');
    }
  }

  /**
   * Gets the source record with all match fields
   */
  private SObject getSourceRecord(
    String objectApiName,
    Id recordId,
    List<String> matchFields
  ) {
    // Build query to get record with match fields
    String recordQuery = buildSourceRecordQuery(
      objectApiName,
      recordId,
      matchFields
    );

    // Get the record
    List<SObject> records = Database.query(recordQuery);
    if (records.isEmpty()) {
      throw new duplicateException('Record not found');
    }

    return records[0];
  }

  /**
   * Builds query to get source record with match fields
   */
  private String buildSourceRecordQuery(
    String objectApiName,
    Id recordId,
    List<String> matchFields
  ) {
    String recordQuery = 'SELECT Id';
    for (String field : matchFields) {
      recordQuery += ', ' + field.trim();
    }
    recordQuery += ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1';

    return recordQuery;
  }

  /**
   * Finds potential duplicates based on match fields
   */
  private List<SObject> findPotentialDuplicates(
    String objectApiName,
    Id recordId,
    List<String> matchFields,
    SObject record
  ) {
    // Build query with conditions based on field values
    String potentialDupesQuery = buildPotentialDupesQuery(
      objectApiName,
      recordId,
      matchFields,
      record
    );
    System.debug(
      LoggingLevel.FINE,
      'Duplicate search query: ' + potentialDupesQuery
    );

    // Execute query with security enforced
    return Database.query(potentialDupesQuery + ' WITH SECURITY_ENFORCED');
  }

  /**
   * Builds query for potential duplicates
   */
  private String buildPotentialDupesQuery(
    String objectApiName,
    Id recordId,
    List<String> matchFields,
    SObject record
  ) {
    String query = 'SELECT Id';

    // Add fields
    for (String field : matchFields) {
      query += ', ' + field.trim();
    }
    query += ' FROM ' + objectApiName + ' WHERE Id != :recordId';

    // Add field conditions
    List<String> fieldConditions = buildFieldConditions(matchFields, record);

    if (!fieldConditions.isEmpty()) {
      query += ' AND (' + String.join(fieldConditions, ' OR ') + ')';
    }

    return query;
  }

  /**
   * Builds field conditions for potential duplicates query
   */
  private List<String> buildFieldConditions(
    List<String> matchFields,
    SObject record
  ) {
    List<String> fieldConditions = new List<String>();

    for (String field : matchFields) {
      String fieldName = field.trim();
      Object fieldValue = record.get(fieldName);

      if (fieldValue != null) {
        if (fieldValue instanceof String) {
          // For strings, use LIKE for partial matching
          String strValue = (String) fieldValue;
          if (String.isNotBlank(strValue)) {
            fieldConditions.add(
              fieldName +
                ' LIKE \'%' +
                String.escapeSingleQuotes(strValue) +
                '%\''
            );
          }
        } else {
          // For other types, use exact matching
          fieldConditions.add(fieldName + ' = \'' + fieldValue + '\'');
        }
      }
    }

    return fieldConditions;
  }

  /**
   * Scores and filters potential duplicates
   */
  private List<Map<String, Object>> scoreAndFilterDuplicates(
    List<SObject> potentialDupes,
    SObject record,
    List<String> matchFields
  ) {
    List<Map<String, Object>> duplicates = new List<Map<String, Object>>();

    for (SObject potentialDupe : potentialDupes) {
      Map<String, Object> scoreResult = calculateMatchScore(
        potentialDupe,
        record,
        matchFields
      );
      Decimal matchScore = (Decimal) scoreResult.get('score');

      if (matchScore > 50) {
        Map<String, Object> dupInfo = new Map<String, Object>();
        dupInfo.put('id', potentialDupe.Id);
        dupInfo.put('matchScore', matchScore);
        dupInfo.put('isExactMatch', scoreResult.get('isExactMatch'));
        duplicates.add(dupInfo);
      }
    }

    return duplicates;
  }

  /**
   * Calculates match score between two records with weighted fields and advanced string matching
   *
   * @param dupeRecord The potential duplicate record
   * @param sourceRecord The source record to compare against
   * @param matchFields List of fields to use for matching
   * @return Map containing match score and match details
   */
  private Map<String, Object> calculateMatchScore(
    SObject dupeRecord,
    SObject sourceRecord,
    List<String> matchFields
  ) {
    // Get field weights from configuration or use defaults
    Map<String, Double> fieldWeights = getFieldWeights(matchFields);

    Decimal matchScore = 0;
    Decimal totalWeight = 0;
    Integer matchCount = 0;

    // Fields that matched and their scores
    Map<String, Decimal> fieldScores = new Map<String, Decimal>();

    for (String field : matchFields) {
      // Get the weight for this field (default to 1.0 if not specified)
      Double fieldWeight = fieldWeights.containsKey(field)
        ? fieldWeights.get(field)
        : 1.0;
      totalWeight += fieldWeight;

      Object origValue = sourceRecord.get(field);
      Object dupeValue = dupeRecord.get(field);

      // Skip if either value is null
      if (origValue == null || dupeValue == null) {
        fieldScores.put(field, 0);
        continue;
      }

      // Calculate score based on field type
      Decimal fieldScore = 0;

      if (origValue instanceof String && dupeValue instanceof String) {
        // String comparison with normalization
        String origStr = ((String) origValue).toLowerCase().trim();
        String dupeStr = ((String) dupeValue).toLowerCase().trim();

        if (origStr.equals(dupeStr)) {
          // Exact match after normalization
          fieldScore = 1.0;
          matchCount++;
        } else {
          // Calculate string similarity
          fieldScore = calculateStringSimilarity(origStr, dupeStr);

          // Only count as a match if similarity is high enough
          if (fieldScore > 0.8) {
            matchCount++;
          }
        }
      } else if (origValue == dupeValue) {
        // Exact match for non-string types
        fieldScore = 1.0;
        matchCount++;
      }

      // Add to total score with weighting
      matchScore += fieldScore * fieldWeight;
      fieldScores.put(field, fieldScore);
    }

    // Normalize score based on total weight
    Decimal normalizedScore = (totalWeight > 0)
      ? (matchScore / totalWeight) * 100
      : 0;

    // Build result map
    Map<String, Object> result = new Map<String, Object>();
    result.put('score', normalizedScore);
    result.put('isExactMatch', (matchCount == matchFields.size()));
    result.put('fieldScores', fieldScores);
    result.put('matchCount', matchCount);

    return result;
  }

  /**
   * Calculates similarity between two strings
   * Uses a combination of containment and Levenshtein distance
   *
   * @param str1 First string to compare
   * @param str2 Second string to compare
   * @return Similarity score between 0 and 1
   */
  private Decimal calculateStringSimilarity(String str1, String str2) {
    // If either string is empty, no match
    if (String.isBlank(str1) || String.isBlank(str2)) {
      return 0;
    }

    // Perfect match
    if (str1 == str2) {
      return 1.0;
    }

    // Check if either string contains the other
    if (str1.contains(str2)) {
      return 0.9;
    } else if (str2.contains(str1)) {
      return 0.9;
    }

    // For shorter strings, use StringNormalizer if available
    try {
      if (str1.length() <= 100 && str2.length() <= 100) {
        // Normalize strings to remove special characters and standardize
        String normalized1 = StringNormalizer.normalize(str1);
        String normalized2 = StringNormalizer.normalize(str2);

        // If normalized strings match, high similarity
        if (normalized1 == normalized2) {
          return 0.95;
        }

        // For shorter strings, calculate Levenshtein distance
        if (normalized1.length() <= 50 && normalized2.length() <= 50) {
          Integer distance = LevenshteinCalculator.calculateDistance(
            normalized1,
            normalized2
          );
          Integer maxLength = Math.max(
            normalized1.length(),
            normalized2.length()
          );

          if (maxLength > 0) {
            // Convert distance to similarity (1 - distance/maxLength)
            Decimal similarity =
              1 - (Decimal.valueOf(distance) / Decimal.valueOf(maxLength));
            return similarity;
          }
        }
      }
    } catch (Exception e) {
      // Fall back to simpler matching if any errors occur
      System.debug(
        LoggingLevel.ERROR,
        'Error calculating string similarity: ' + e.getMessage()
      );
    }

    // Fallback to basic partial matching
    Set<String> words1 = new Set<String>(str1.split('\\s+'));
    Set<String> words2 = new Set<String>(str2.split('\\s+'));

    // Count common words
    Integer commonWords = 0;
    for (String word : words1) {
      if (words2.contains(word)) {
        commonWords++;
      }
    }

    // Calculate Jaccard similarity (intersection / union)
    Set<String> union = new Set<String>(words1);
    union.addAll(words2);

    if (union.size() > 0) {
      return Decimal.valueOf(commonWords) / Decimal.valueOf(union.size());
    }

    return 0;
  }

  /**
   * Gets field weights from configuration
   * This could be enhanced to read from custom metadata settings
   *
   * @param matchFields List of fields to get weights for
   * @return Map of field names to weights
   */
  private Map<String, Double> getFieldWeights(List<String> matchFields) {
    Map<String, Double> weights = new Map<String, Double>();

    // Define default weights based on field importance
    // Email and Phone are highly reliable for matching
    weights.put('Email', 0.8);
    weights.put('Email__c', 0.8);
    weights.put('PersonEmail', 0.8);

    weights.put('Phone', 0.7);
    weights.put('Phone__c', 0.7);
    weights.put('PersonMobilePhone', 0.7);
    weights.put('MobilePhone', 0.7);

    // Name fields are important but can have variations
    weights.put('Name', 0.6);
    weights.put('FirstName', 0.5);
    weights.put('LastName', 0.6);
    weights.put('Company', 0.6);

    // Address fields are moderately reliable
    weights.put('BillingStreet', 0.5);
    weights.put('BillingCity', 0.4);
    weights.put('BillingState', 0.3);
    weights.put('BillingPostalCode', 0.5);
    weights.put('BillingCountry', 0.3);

    weights.put('ShippingStreet', 0.5);
    weights.put('ShippingCity', 0.4);
    weights.put('ShippingState', 0.3);
    weights.put('ShippingPostalCode', 0.5);
    weights.put('ShippingCountry', 0.3);

    weights.put('MailingStreet', 0.5);
    weights.put('MailingCity', 0.4);
    weights.put('MailingState', 0.3);
    weights.put('MailingPostalCode', 0.5);
    weights.put('MailingCountry', 0.3);

    // Website is moderately reliable
    weights.put('Website', 0.5);

    // Other fields get default weight
    for (String field : matchFields) {
      if (!weights.containsKey(field)) {
        weights.put(field, 0.5); // Default weight
      }
    }

    return weights;
  }

  /**
   * Queries a record to get its Name field
   */
  private SObject queryRecordName(String recordId, String objectName) {
    try {
      SObject record = Database.query(
        'SELECT Name FROM ' +
          String.escapeSingleQuotes(objectName) +
          ' WHERE Id = :recordId LIMIT 1 WITH SECURITY_ENFORCED'
      );

      if (record == null) {
        throw new duplicateException('Record not found for Id: ' + recordId);
      }

      return record;
    } catch (Exception e) {
      throw new duplicateException('Record query failed: ' + e.getMessage());
    }
  }

  /**
   * Counts duplicate records based on Name field
   */
  private Integer countDuplicatesByName(
    String objectName,
    String recordId,
    String name
  ) {
    String countQuery =
      'SELECT COUNT() FROM ' +
      String.escapeSingleQuotes(objectName) +
      ' WHERE Name = :name AND Id != :recordId WITH SECURITY_ENFORCED';

    return Database.countQuery(countQuery);
  }

  /**
   * Builds query to find duplicates by Name field
   */
  private String buildNameDuplicateQuery(
    String objectName,
    String recordId,
    String name
  ) {
    return 'SELECT Id, Name FROM ' +
      String.escapeSingleQuotes(objectName) +
      ' WHERE Name = :name AND Id != :recordId';
    // NOTE: WITH SECURITY_ENFORCED is added when this query is executed
  }
}
