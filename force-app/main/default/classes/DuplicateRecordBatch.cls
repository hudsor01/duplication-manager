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
    // Get fields to query
    Set<String> fieldsToQuery = new Set<String>{
      'Id',
      'CreatedDate',
      'LastModifiedDate'
    };

    // Add match fields
    List<Object> matchFields = (List<Object>) configSettings.get('matchFields');
    for (Object fieldObj : matchFields) {
      Map<String, Object> fieldConfig = (Map<String, Object>) fieldObj;
      fieldsToQuery.add((String) fieldConfig.get('field'));
    }

    // Start building the query
    this.queryString =
      'SELECT ' +
      String.join(new List<String>(fieldsToQuery), ', ') +
      ' FROM ' +
      objectApiName;

    // Add WHERE clause if specific records are provided
    if (specificRecordIds != null && !specificRecordIds.isEmpty()) {
      this.queryString += ' WHERE Id IN :specificRecordIds';
    }

    // Add ORDER BY for consistent batching
    this.queryString += ' ORDER BY Id';
  }

  /**
   * Build query locator for batch
   */
  global override Database.QueryLocator buildQueryLocator() {
    return Database.getQueryLocator(queryString);
  }

  /**
   * Find duplicates in the current batch scope
   */
  global override Map<String, List<SObject>> findDuplicates(
    List<SObject> scope
  ) {
    // Group records by match key
    Map<String, List<SObject>> duplicateGroups = new Map<String, List<SObject>>();

    for (SObject record : scope) {
      String matchKey = buildMatchKey(record);

      if (!duplicateGroups.containsKey(matchKey)) {
        duplicateGroups.put(matchKey, new List<SObject>());
      }

      duplicateGroups.get(matchKey).add(record);
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
    } catch (Exception e) {
      logError('Error merging duplicates', e);
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
