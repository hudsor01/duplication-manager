/**
 * Utility class providing shared services for duplicate functionality
 * Centralizes common functions to reduce duplicate across classes
 *
 * @author Richard Hudson
 * @date April 2025
 */
public class DuplicateServicesUtil {
  // Configuration cache
  private static Map<String, DuplicationConfiguration__mdt> configCache;

  /**
   * Get configuration for an object
   * @param objectApiName API name of the object
   * @return Configuration record
   */
  public static DuplicationConfiguration__mdt getObjectConfiguration(
    String objectApiName
  ) {
    // Initialize cache if needed
    if (configCache == null) {
      configCache = new Map<String, DuplicationConfiguration__mdt>();
    }

    // Check cache first
    if (configCache.containsKey(objectApiName)) {
      return configCache.get(objectApiName);
    }

    // Query for configuration
    List<DuplicationConfiguration__mdt> configs = [
      SELECT
        Id,
        DeveloperName,
        MasterLabel,
        BatchSize__c,
        IsActive__c,
        MasterRecordStrategy__c,
        MatchFields__c,
        MatchFieldWeights__c,
        MatchThreshold__c,
        ObjectApiName__c,
        PostMergeApexHandler__c,
        PreMergeApexHandler__c
      FROM DuplicationConfiguration__mdt
      WHERE ObjectApiName__c = :objectApiName AND IsActive__c = TRUE
      LIMIT 1
    ];

    // Return config if found
    if (!configs.isEmpty()) {
      DuplicationConfiguration__mdt config = configs[0];
      configCache.put(objectApiName, config);
      return config;
    }

    // Return null if no config found
    return null;
  }

  /**
   * Parse match fields configuration from JSON
   * @param jsonConfig JSON configuration string
   * @return Parsed match fields configuration
   */
  public static Map<String, Decimal> parseMatchFieldWeights(String jsonConfig) {
    Map<String, Decimal> fieldWeights = new Map<String, Decimal>();

    if (String.isBlank(jsonConfig)) {
      return fieldWeights;
    }

    try {
      // Parse JSON configuration
      Map<String, Object> parsedConfig = (Map<String, Object>) JSON.deserializeUntyped(
        jsonConfig
      );

      // Convert to field weights map
      for (String fieldName : parsedConfig.keySet()) {
        Object weightObj = parsedConfig.get(fieldName);

        // Handle different types of weight values
        if (weightObj instanceof Decimal) {
          fieldWeights.put(fieldName, (Decimal) weightObj);
        } else if (weightObj instanceof Integer) {
          Integer intValue = (Integer) weightObj;
          fieldWeights.put(fieldName, Decimal.valueOf(intValue));
        } else if (weightObj instanceof String) {
          fieldWeights.put(fieldName, Decimal.valueOf((String) weightObj));
        }
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error parsing match field weights: ' + e.getMessage()
      );
    }

    return fieldWeights;
  }

  /**
   * Calculate match score between two records
   * @param record1 First record
   * @param record2 Second record
   * @param fieldWeights Map of field weights
   * @return Match score (0-100)
   */
  public static Decimal calculateRecordMatchScore(
    SObject record1,
    SObject record2,
    Map<String, Decimal> fieldWeights
  ) {
    if (
      record1 == null ||
      record2 == null ||
      fieldWeights == null ||
      fieldWeights.isEmpty()
    ) {
      return 0;
    }

    // Get matcher registry
    DuplicateMatcherRegistry registry = DuplicateMatcherRegistry.getInstance();

    // Calculate weighted score
    Decimal totalScore = 0;
    Decimal totalWeight = 0;

    for (String fieldName : fieldWeights.keySet()) {
      Decimal weight = fieldWeights.get(fieldName);

      // Skip fields with zero weight
      if (weight <= 0) {
        continue;
      }

      // Get field values
      Object value1 = record1.get(fieldName);
      Object value2 = record2.get(fieldName);

      // Skip if both values are null
      if (value1 == null && value2 == null) {
        continue;
      }

      // Convert to strings for comparison
      String strValue1 = value1 != null ? String.valueOf(value1) : '';
      String strValue2 = value2 != null ? String.valueOf(value2) : '';

      // Calculate field match score
      Decimal fieldScore = registry.calculateMatchScore(
        strValue1,
        strValue2,
        fieldName
      );

      // Add weighted score
      totalScore += fieldScore * weight;
      totalWeight += weight;
    }

    // Return weighted average
    return totalWeight > 0 ? (totalScore / totalWeight).setScale(2) : 0;
  }

  /**
   * Create standardized merge log
   * @param masterId Master record ID
   * @param mergedIds IDs of merged records
   * @param objectName API name of the object
   * @param jobId Batch job ID
   * @param conflicts Field conflicts
   * @param errorMessage Error message if merge failed
   */
  public static void createMergeLog(
    Id masterId,
    List<Id> mergedIds,
    String objectName,
    String jobId,
    Map<String, List<Object>> conflicts,
    String errorMessage
  ) {
    try {
      // Create merge log record
      DuplicateMergeLog__c log = new DuplicateMergeLog__c(
        MasterId__c = masterId,
        MergedIds__c = String.join(mergedIds, ','),
        ObjectApiName__c = objectName,
        MergeTime__c = System.now(),
        JobId__c = jobId,
        UserId__c = UserInfo.getUserId()
      );

      // Add conflict details if any
      if (conflicts != null && !conflicts.isEmpty()) {
        log.FieldMergeDetails__c = JSON.serialize(conflicts);
      }

      // Add error message if any
      if (String.isNotBlank(errorMessage)) {
        log.ErrorMessage__c = errorMessage;
      }

      insert log;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error creating merge log: ' + e.getMessage()
      );
    }
  }

  /**
   * Chunk a list into smaller lists
   * @param records List to chunk
   * @param chunkSize Size of each chunk
   * @return List of chunks
   */
  public static List<List<SObject>> chunkRecords(
    List<SObject> records,
    Integer chunkSize
  ) {
    List<List<SObject>> result = new List<List<SObject>>();

    if (records == null || records.isEmpty()) {
      return result;
    }

    // Use default chunk size if not specified
    Integer size = (chunkSize != null && chunkSize > 0) ? chunkSize : 200;

    // Split records into chunks
    for (Integer i = 0; i < records.size(); i += size) {
      List<SObject> chunk = new List<SObject>();

      for (Integer j = i; j < i + size && j < records.size(); j++) {
        chunk.add(records[j]);
      }

      result.add(chunk);
    }

    return result;
  }

  /**
   * Get a list of record IDs from SObjects
   * @param records List of SObjects
   * @return List of record IDs
   */
  public static List<Id> getRecordIds(List<SObject> records) {
    List<Id> ids = new List<Id>();

    if (records != null) {
      for (SObject rec : records) {
        ids.add(rec.Id);
      }
    }

    return ids;
  }
}
