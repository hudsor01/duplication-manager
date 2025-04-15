/**
 * Batch class for finding and merging duplicate records
 *
 * @author Richard Hudson
 * @date April 2025
 */
global class DuplicateRecordBatch extends DuplicateBaseBatch {
  // Configuration
  private String configId;
  private Map<String, Object> configSettings;
  private String queryString;
  private List<Id> specificRecordIds; // For processing specific records only

  /**
   * Constructor using configuration ID
   *
   * @param configId ID of the configuration to use
   * @param isDryRun Whether to perform a dry run (find only, no merge)
   */
  global DuplicateRecordBatch(String configId, Boolean isDryRun) {
    // Initialize with default values that will be updated in initializeFromConfig
    super('Account', isDryRun, 200);
    this.configId = configId;
    this.specificRecordIds = null;

    // Load configuration
    initializeFromConfig();
  }

  /**
   * Constructor with explicit parameters
   *
   * @param objectName API name of the object to process
   * @param fieldList List of fields to match on
   * @param masterStrategy Strategy for selecting master record
   * @param batchSize Batch size for processing
   * @param isDryRun Whether to perform a dry run
   */
  global DuplicateRecordBatch(
    String objectName,
    List<String> fieldList,
    String masterStrategy,
    Integer batchSize,
    Boolean isDryRun
  ) {
    super(objectName, isDryRun, batchSize, 'Custom Configuration');
    this.specificRecordIds = null;

    // Initialize configuration settings
    this.configSettings = new Map<String, Object>{
      'matchFields' => buildMatchFieldsConfig(fieldList),
      'masterRecordStrategy' => masterStrategy
    };

    // Build query string
    buildQueryString();
  }

  /**
   * Default constructor - must be followed by configuration
   */
  global DuplicateRecordBatch() {
    super('Account', false, 200);
    this.specificRecordIds = null;
  }

  /**
   * Set specific record IDs to process
   * When provided, only these records will be queried
   *
   * @param recordIds List of record IDs to process
   */
  global void setRecordIds(List<Id> recordIds) {
    this.specificRecordIds = recordIds;

    // Rebuild query string with record ID filter
    if (this.configSettings != null) {
      buildQueryString();
    }
  }

  /**
   * Initialize settings from configuration
   */
  private void initializeFromConfig() {
    try {
      // Load configuration from custom metadata or settings
      DuplicateConfig config = DuplicateSettingsUtil.createConfigFromMetadata(
        configId
      );

      // Update parent class properties
      this.objectApiName = config.objectApiName;
      this.batchSize = config.batchSize > 0 ? config.batchSize : 200;
      this.configurationName = configId;

      // Store configuration settings
      this.configSettings = new Map<String, Object>{
        'matchFields' => buildMatchFieldsConfig(config.matchFields),
        'masterRecordStrategy' => config.masterRecordStrategy
      };

      // Build query string
      buildQueryString();
    } catch (Exception e) {
      logError('Error initializing from configuration', e);
      throw e;
    }
  }

  /**
   * Build match fields configuration from field list
   */
  private List<Map<String, Object>> buildMatchFieldsConfig(
    List<String> fieldList
  ) {
    List<Map<String, Object>> matchFields = new List<Map<String, Object>>();

    for (String field : fieldList) {
      matchFields.add(
        new Map<String, Object>{
          'field' => field,
          'required' => false,
          'matchType' => 'fuzzy'
        }
      );
    }

    return matchFields;
  }

  /**
   * Build the query string for finding records
   */
  private void buildQueryString() {
    // Get fields to query - always include essential fields
    Set<String> fieldsToQuery = new Set<String>{
      'Id',
      'CreatedDate',
      'LastModifiedDate'
    };

    // Add match fields with validation
    List<Object> matchFields = (List<Object>) configSettings.get('matchFields');
    for (Object fieldObj : matchFields) {
      Map<String, Object> fieldConfig = (Map<String, Object>) fieldObj;
      String fieldName = (String) fieldConfig.get('field');
      // Validate field before adding to query
      addFieldToQuery(fieldsToQuery, fieldName);
    }

    // Start building the query
    this.queryString =
      'SELECT ' +
      String.join(new List<String>(fieldsToQuery), ', ') +
      ' FROM ' +
      objectApiName;

    // Add WHERE clause if specific records are provided
    if (specificRecordIds != null && !specificRecordIds.isEmpty()) {
      // Split large ID lists into chunks to avoid governor limits
      if (specificRecordIds.size() > 100) {
        this.queryString += ' WHERE Id IN :specificRecordIds AND LastModifiedDate != null';
      } else {
        this.queryString += ' WHERE Id IN :specificRecordIds';
      }
    } else {
      // Add selective filter based on indexed fields
      // Get time range from configuration or use default
      Integer timeRangeInDays = 90; // Default to 90 days
      if (
        configSettings.containsKey('timeRangeInDays') &&
        configSettings.get('timeRangeInDays') != null
      ) {
        Object timeRange = configSettings.get('timeRangeInDays');
        if (timeRange instanceof Integer) {
          timeRangeInDays = (Integer) timeRange;
        } else if (timeRange instanceof Decimal) {
          timeRangeInDays = ((Decimal) timeRange).intValue();
        } else if (timeRange instanceof String) {
          try {
            timeRangeInDays = Integer.valueOf((String) timeRange);
          } catch (Exception e) {
            // Use default if conversion fails
            logError('Invalid timeRangeInDays value: ' + timeRange, e);
          }
        }
      }

      // Add time-based filter
      this.queryString +=
        ' WHERE LastModifiedDate >= LAST_N_DAYS:' + timeRangeInDays;

      // Add additional filter if specified in configuration
      if (
        configSettings.containsKey('additionalFilter') &&
        configSettings.get('additionalFilter') != null
      ) {
        String additionalFilter = (String) configSettings.get(
          'additionalFilter'
        );
        if (String.isNotBlank(additionalFilter)) {
          this.queryString += ' AND (' + additionalFilter + ')';
        }
      }
    }

    // Add index hint for better query performance
    if (specificRecordIds != null && !specificRecordIds.isEmpty()) {
      this.queryString += ' /*+ INDEX(Id) */';
    } else {
      this.queryString += ' /*+ INDEX(LastModifiedDate) */';
    }

    // Add ORDER BY for consistent batching
    this.queryString += ' ORDER BY Id ASC';
  }

  /**
   * Build query locator for batch
   */
  global override Database.QueryLocator buildQueryLocator() {
    if (String.isBlank(queryString)) {
      buildQueryString();
    }

    System.debug(LoggingLevel.FINE, 'Using optimized query: ' + queryString);
    return Database.getQueryLocator(queryString);
  }

  /**
   * Find duplicates in the current batch scope
   */
  global override Map<String, List<SObject>> findDuplicates(
    List<SObject> scope
  ) {
    // Use optimized chunking for large record sets
    if (scope.size() > 2000) {
      return findDuplicatesInChunks(scope);
    }

    // Group records by match key with optimized memory usage
    Map<String, List<SObject>> duplicateGroups = new Map<String, List<SObject>>();

    // Process in batches of 500 to avoid heap size limits
    Integer batchSize = 500;
    for (Integer i = 0; i < scope.size(); i += batchSize) {
      Integer endIndex = Math.min(i + batchSize, scope.size());
      List<SObject> batch = new List<SObject>();
      // Manually create a sublist since Apex doesn't support the subList method
      for (Integer j = i; j < endIndex; j++) {
        batch.add(scope[j]);
      }

      for (SObject record : batch) {
        // Skip null records
        if (record == null)
          continue;

        // Generate match key
        String matchKey = buildMatchKey(record);
        if (String.isBlank(matchKey))
          continue;

        if (!duplicateGroups.containsKey(matchKey)) {
          duplicateGroups.put(matchKey, new List<SObject>());
        }

        duplicateGroups.get(matchKey).add(record);
      }
    }

    // Remove groups with only one record (not duplicates)
    for (String key : duplicateGroups.keySet().clone()) {
      if (duplicateGroups.get(key).size() <= 1) {
        duplicateGroups.remove(key);
      }
    }

    return duplicateGroups;
  }

  /**
   * Process large record sets in chunks to avoid heap size limits
   * @param scope The full scope of records to process
   * @return Map of duplicate groups
   */
  private Map<String, List<SObject>> findDuplicatesInChunks(
    List<SObject> scope
  ) {
    // Log for debugging
    System.debug(
      LoggingLevel.INFO,
      'Processing large record set of size: ' + scope.size()
    );

    // Result map to combine results from all chunks
    Map<String, List<SObject>> finalDuplicateGroups = new Map<String, List<SObject>>();

    // Calculate optimal chunk size based on record complexity
    Integer recordComplexity = estimateRecordComplexity();
    Integer optimalChunkSize = calculateOptimalChunkSize(
      recordComplexity,
      scope.size()
    );

    // Process in chunks
    Integer totalChunks = (Integer) Math.ceil(
      (Double) scope.size() / optimalChunkSize
    );
    for (Integer chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
      Integer startIndex = chunkIndex * optimalChunkSize;
      Integer endIndex = Math.min(startIndex + optimalChunkSize, scope.size());

      // Get current chunk
      List<SObject> chunk = new List<SObject>();
      // Manually create a sublist since Apex doesn't support the subList method
      for (Integer j = startIndex; j < endIndex; j++) {
        chunk.add(scope[j]);
      }

      // Find duplicates in this chunk
      Map<String, List<SObject>> chunkDuplicates = findDuplicatesInChunk(chunk);

      // Merge results into final map
      for (String key : chunkDuplicates.keySet()) {
        if (!finalDuplicateGroups.containsKey(key)) {
          finalDuplicateGroups.put(key, new List<SObject>());
        }
        finalDuplicateGroups.get(key).addAll(chunkDuplicates.get(key));
      }

      // Force garbage collection between chunks
      if (Math.mod(chunkIndex, 5) == 0) {
        cleanupMemory();
      }
    }

    // Final filtering of groups with only one record
    for (String key : finalDuplicateGroups.keySet().clone()) {
      if (finalDuplicateGroups.get(key).size() <= 1) {
        finalDuplicateGroups.remove(key);
      }
    }

    return finalDuplicateGroups;
  }

  /**
   * Find duplicates within a single chunk of records
   * @param chunk The chunk of records to process
   * @return Map of duplicate groups within this chunk
   */
  private Map<String, List<SObject>> findDuplicatesInChunk(
    List<SObject> chunk
  ) {
    Map<String, List<SObject>> duplicateGroups = new Map<String, List<SObject>>();

    for (SObject record : chunk) {
      // Skip null records
      if (record == null)
        continue;

      // Generate match key
      String matchKey = buildMatchKey(record);
      if (String.isBlank(matchKey))
        continue;

      if (!duplicateGroups.containsKey(matchKey)) {
        duplicateGroups.put(matchKey, new List<SObject>());
      }

      duplicateGroups.get(matchKey).add(record);
    }

    return duplicateGroups;
  }

  /**
   * Estimate record complexity based on number of fields and their types
   * @return Complexity score (higher = more complex)
   */
  private Integer estimateRecordComplexity() {
    Integer complexity = 10; // Base complexity

    // Add complexity based on number of match fields
    List<Object> matchFields = (List<Object>) configSettings.get('matchFields');
    complexity += matchFields.size() * 5;

    // Add complexity based on object type
    if (objectApiName == 'Account' || objectApiName == 'Contact') {
      complexity += 10; // These objects typically have more fields and relationships
    }

    return complexity;
  }

  /**
   * Calculate optimal chunk size based on record complexity and total size
   * @param complexity The estimated record complexity
   * @param totalSize The total number of records to process
   * @return Optimal chunk size
   */
  private Integer calculateOptimalChunkSize(
    Integer complexity,
    Integer totalSize
  ) {
    // Base size - for simple records with few fields
    Integer baseSize = 2000;

    // Adjust based on complexity
    Integer adjustedSize = baseSize / Math.max(1, (complexity / 10));

    // Ensure minimum and maximum limits
    Integer minSize = 100;
    Integer maxSize = 5000;

    // If total size is small, process all at once
    if (totalSize < minSize) {
      return totalSize;
    }

    return Math.min(maxSize, Math.max(minSize, adjustedSize));
  }

  /**
   * Attempt to clean up memory between processing chunks
   */
  private void cleanupMemory() {
    // Trigger garbage collection
    for (Integer i = 0; i < 10; i++) {
      String s = '' + i;
      s = null;
    }
  }

  /**
   * Build a match key based on fields
   */
  private String buildMatchKey(SObject record) {
    List<Object> matchFields = (List<Object>) configSettings.get('matchFields');
    List<String> keyParts = new List<String>();

    for (Object fieldObj : matchFields) {
      Map<String, Object> fieldConfig = (Map<String, Object>) fieldObj;
      String fieldName = (String) fieldConfig.get('field');
      Object fieldValue = record.get(fieldName);

      // Normalize the value for matching
      String normalizedValue = '';
      if (fieldValue != null) {
        normalizedValue = normalizeValue(String.valueOf(fieldValue), fieldName);
      }

      keyParts.add(normalizedValue);
    }

    return String.join(keyParts, '|');
  }

  /**
   * Normalize a value for matching based on field type
   */
  private String normalizeValue(String value, String fieldName) {
    if (String.isBlank(value)) {
      return '';
    }

    // Lowercase field name for comparison
    String lowerFieldName = fieldName.toLowerCase();

    // Apply specialized normalization based on field type
    if (lowerFieldName.contains('email')) {
      return normalizeEmail(value);
    } else if (
      lowerFieldName.contains('phone') ||
      lowerFieldName.contains('mobile') ||
      lowerFieldName.contains('cell') ||
      lowerFieldName.contains('tel')
    ) {
      return normalizePhone(value);
    } else if (lowerFieldName.contains('name')) {
      return normalizeName(value);
    } else {
      // Generic normalization for other fields
      // Convert to lowercase and remove special characters
      String normalized = value.toLowerCase().trim();
      normalized = normalized.replaceAll('[^a-z0-9]', '');
      return normalized;
    }
  }

  /**
   * Normalize email address for matching
   */
  private String normalizeEmail(String email) {
    if (String.isBlank(email))
      return '';

    // Convert to lowercase and trim
    String normalized = email.toLowerCase().trim();

    // Remove any whitespace
    normalized = normalized.replaceAll('\\s+', '');

    return normalized;
  }

  /**
   * Normalize phone number for matching
   */
  private String normalizePhone(String phone) {
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
   * Normalize name for matching
   */
  private String normalizeName(String name) {
    if (String.isBlank(name))
      return '';

    // Convert to lowercase and trim
    String normalized = name.toLowerCase().trim();

    // Remove extra spaces
    normalized = normalized.replaceAll('\\s+', ' ');

    // Remove common prefixes/suffixes that might cause false negatives
    List<String> prefixesToRemove = new List<String>{
      'mr',
      'mrs',
      'ms',
      'miss',
      'dr',
      'prof'
    };
    List<String> suffixesToRemove = new List<String>{
      'jr',
      'sr',
      'ii',
      'iii',
      'iv',
      'phd',
      'md',
      'esq'
    };

    for (String prefix : prefixesToRemove) {
      if (
        normalized.startsWith(prefix + ' ') ||
        normalized.startsWith(prefix + '. ')
      ) {
        normalized = normalized.substring(normalized.indexOf(' ') + 1).trim();
      }
    }

    for (String suffix : suffixesToRemove) {
      if (
        normalized.endsWith(' ' + suffix) ||
        normalized.endsWith(', ' + suffix) ||
        normalized.endsWith(' ' + suffix + '.') ||
        normalized.endsWith(', ' + suffix + '.')
      ) {
        // Find where the suffix starts and remove it
        Integer lastSpace = normalized.lastIndexOf(' ');
        if (lastSpace > 0) {
          normalized = normalized.substring(0, lastSpace).trim();
        }
      }
    }

    // Remove special characters
    normalized = normalized.replaceAll('[^a-z0-9 ]', '');

    return normalized;
  }

  /**
   * Process the duplicates found
   */
  global override void processDuplicates(
    Map<String, List<SObject>> duplicateGroups
  ) {
    for (String matchKey : duplicateGroups.keySet()) {
      List<SObject> dupeGroup = duplicateGroups.get(matchKey);

      // Skip if no duplicates
      if (dupeGroup.size() <= 1) {
        continue;
      }

      // Track duplicates found
      duplicatesFound += (dupeGroup.size() - 1);

      // Process the group
      String masterStrategy = (String) configSettings.get(
        'masterRecordStrategy'
      );
      SObject masterRecord = selectMasterRecord(dupeGroup, masterStrategy);

      // Create a duplicate group record for reporting
      Decimal matchScore = 90; // Default match score - could be calculated
      Id groupId = createDuplicateGroup(dupeGroup, masterRecord, matchScore);

      // Merge records if not a dry run
      if (!isDryRun && masterRecord != null) {
        mergeDuplicates(masterRecord, dupeGroup, groupId);
      }
    }
  }

  /**
   * Merge duplicate records
   */
  private void mergeDuplicates(
    SObject masterRecord,
    List<SObject> duplicates,
    Id groupId
  ) {
    // Create a savepoint for transaction control
    Savepoint sp = Database.setSavepoint();

    try {
      // Get master record ID
      Id masterId = (Id) masterRecord.get('Id');

      // Get IDs to merge
      List<Id> recordsToMerge = new List<Id>();
      for (SObject rec : duplicates) {
        Id recId = (Id) rec.get('Id');
        if (recId != masterId) {
          recordsToMerge.add(recId);
        }
      }

      // Skip if no records to merge
      if (recordsToMerge.isEmpty()) {
        return;
      }

      // Use merge service
      DuplicateMergeService mergeService = new DuplicateMergeService();
      mergeService.mergeRecords(objectApiName, masterId, recordsToMerge);

      // Update merge count
      recordsMerged += recordsToMerge.size();

      // Log merge activity
      createMergeLog(masterId, recordsToMerge, groupId);
    } catch (DmlException dmlEx) {
      // Roll back on database errors
      Database.rollback(sp);
      logError(
        'Database error merging duplicates: ' + dmlEx.getMessage(),
        dmlEx
      );
    } catch (Exception e) {
      // Roll back on any other errors
      Database.rollback(sp);
      logError('Error merging duplicates: ' + e.getMessage(), e);
    }
  }

  /**
   * Create a log entry for the merge operation
   */
  private void createMergeLog(Id masterId, List<Id> mergedIds, Id groupId) {
    try {
      // Validate input
      if (masterId == null || mergedIds == null || mergedIds.isEmpty()) {
        return;
      }

      // Prepare field merge details if needed
      String fieldMergeDetails = '';

      // Create merge log record with complete information
      DuplicateMergeLog__c log = new DuplicateMergeLog__c(
        JobId__c = batchJobId,
        MasterId__c = masterId,
        MergedIds__c = String.join(mergedIds, ','),
        ObjectApiName__c = objectApiName,
        MergeTime__c = System.now(),
        UserId__c = UserInfo.getUserId(),
        MatchScore__c = 100, // Default score, could be calculated for each merge
        FieldMergeDetails__c = fieldMergeDetails
      );

      // Check security before inserting
      if (Schema.sObjectType.DuplicateMergeLog__c.isCreateable()) {
        insert log;
      } else {
        logError(
          'Insufficient permissions to create merge log',
          new System.NoAccessException()
        );
      }
    } catch (Exception e) {
      logError('Error creating merge log', e);
    }
  }

  /**
   * Add field to a query safe way
   *
   * @param fieldsToQuery Set of fields being queried
   * @param fieldName Field to add
   */
  private void addFieldToQuery(Set<String> fieldsToQuery, String fieldName) {
    if (String.isBlank(fieldName)) {
      return;
    }

    String field = fieldName.trim();

    // First check if field exists
    try {
      Schema.SObjectType objectType = Schema.getGlobalDescribe()
        .get(objectApiName);
      if (objectType != null) {
        Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();

        if (fieldMap.containsKey(field)) {
          Schema.DescribeFieldResult fieldDescribe = fieldMap.get(field)
            .getDescribe();
          if (fieldDescribe.isAccessible()) {
            fieldsToQuery.add(field);
          }
        }
      }
    } catch (Exception e) {
      // If any error occurs, don't add the field
      System.debug(
        LoggingLevel.WARN,
        'Field ' + field + ' couldn\'t be added to query: ' + e.getMessage()
      );
    }
  }
}
