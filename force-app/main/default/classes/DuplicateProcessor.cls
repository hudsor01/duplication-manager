/**
 * Main processor class for duplicate detection and merging
 * Enhanced to provide detailed results for reporting and review
 *
 * @author Richard Hudson
 * @date April 2025
 */
public class DuplicateProcessor {
  // Default batch size
  private static final Integer DEFAULT_BATCH_SIZE = 200;

  /**
   * Finds duplicate records based on the specified configuration
   * @param records List of records to process
   * @param matchFields List of fields to use for matching
   * @return Map of duplicate groups
   */
  public static Map<String, DuplicateGroup> findDuplicates(
    List<SObject> records,
    List<String> matchFields
  ) {
    // Validate input
    if (records == null || records.isEmpty()) {
      return new Map<String, DuplicateGroup>();
    }

    if (matchFields == null || matchFields.isEmpty()) {
      throw new DuplicateProcessorException('Match fields must be specified');
    }

    // Find duplicates
    return DuplicateMatcherUtility.findDuplicateGroups(records, matchFields);
  }

  /**
   * Merges duplicate records based on the specified configuration
   *
   * @param duplicateGroups Map of duplicate groups
   * @param masterRecordStrategy Strategy for selecting master record
   * @return Map of merge results by group key
   */
  public static Map<String, DuplicateMergeUtility.MergeResult> mergeDuplicates(
    Map<String, DuplicateGroup> duplicateGroups,
    String masterRecordStrategy
  ) {
    // Validate input
    if (duplicateGroups == null || duplicateGroups.isEmpty()) {
      return new Map<String, DuplicateMergeUtility.MergeResult>();
    }

    // Merge each group
    Map<String, DuplicateMergeUtility.MergeResult> results = new Map<String, DuplicateMergeUtility.MergeResult>();

    for (String key : duplicateGroups.keySet()) {
      DuplicateGroup dupGroup = duplicateGroups.get(key);

      // Skip groups without duplicates
      if (!dupGroup.hasDuplicates()) {
        continue;
      }

      // Merge group
      DuplicateMergeUtility.MergeResult result = DuplicateMergeUtility.mergeGroup(
        dupGroup,
        masterRecordStrategy
      );
      results.put(key, result);
    }

    return results;
  }

  /**
   * Processes records for duplicates in batch mode
   *
   * @param records List of records to process
   * @param matchFields List of fields to use for matching
   * @param masterRecordStrategy Strategy for selecting master record
   * @param dryRun If true, will not perform merges
   * @return Processing result
   */
  public static ProcessingResult processBatch(
    List<SObject> records,
    List<String> matchFields,
    String masterRecordStrategy,
    Boolean dryRun
  ) {
    Long startTime = System.currentTimeMillis();

    // Find duplicates
    Map<String, DuplicateGroup> duplicateGroups = findDuplicates(
      records,
      matchFields
    );

    // Initialize result
    ProcessingResult result = new ProcessingResult();
    result.totalRecordsProcessed = records.size();
    result.duplicateGroupsFound = duplicateGroups.size();
    result.duplicateGroups = duplicateGroups;

    // Calculate average match score
    if (!duplicateGroups.isEmpty()) {
      Decimal totalScore = 0;
      for (DuplicateGroup dupGroup : duplicateGroups.values()) {
        totalScore += dupGroup.matchScore;
      }
      result.averageMatchScore = (totalScore / duplicateGroups.size())
        .setScale(2);
    }

    // If not a dry run, perform merges
    if (!dryRun && !duplicateGroups.isEmpty()) {
      Map<String, DuplicateMergeUtility.MergeResult> mergeResults = mergeDuplicates(
        duplicateGroups,
        masterRecordStrategy
      );

      // Count merged records
      for (
        DuplicateMergeUtility.MergeResult mergeResult : mergeResults.values()
      ) {
        result.recordsMerged += mergeResult.recordsMerged;

        // Collect errors
        if (mergeResult.hasErrors()) {
          result.errors.addAll(mergeResult.errors);
        }
      }
    }

    // Calculate processing time
    result.processingTimeMs = System.currentTimeMillis() - startTime;

    return result;
  }

  /**
   * Loads configuration from custom metadata
   *
   * @param settingDeveloperName Developer name of the metadata setting
   * @return Configuration object
   */
  public static DuplicateConfiguration loadConfiguration(
    String settingDeveloperName
  ) {
    // Query configuration from custom metadata
    String query =
      'SELECT MasterLabel, DeveloperName, ObjectApiName__c, ' +
      'MatchFields__c, MasterRecordStrategy__c, BatchSize__c ' +
      'FROM DuplicateFinderSetting__mdt ' +
      'WHERE DeveloperName = :settingDeveloperName ' +
      'AND IsActive__c = true LIMIT 1';

    List<SObject> settings = Database.query(query);

    // Check if setting exists
    if (settings.isEmpty()) {
      throw new DuplicateProcessorException(
        'Configuration "' + settingDeveloperName + '" not found or not active'
      );
    }

    SObject setting = settings[0];

    // Create configuration
    DuplicateConfiguration config = new DuplicateConfiguration();
    config.name = (String) setting.get('MasterLabel');
    config.developerName = (String) setting.get('DeveloperName');
    config.objectApiName = (String) setting.get('ObjectApiName__c');

    // Parse match fields
    String matchFieldsStr = (String) setting.get('MatchFields__c');
    if (String.isNotBlank(matchFieldsStr)) {
      config.matchFields = new List<String>();
      for (String field : matchFieldsStr.split(',')) {
        config.matchFields.add(field.trim());
      }
    }

    // Set master record strategy
    config.masterRecordStrategy = (String) setting.get(
      'MasterRecordStrategy__c'
    );

    // Set batch size
    Object batchSizeObj = setting.get('BatchSize__c');
    config.batchSize = (batchSizeObj != null)
      ? Integer.valueOf(batchSizeObj)
      : DEFAULT_BATCH_SIZE;

    return config;
  }

  /**
   * Class to encapsulate processing results
   */
  public class ProcessingResult {
    public Integer totalRecordsProcessed { get; set; }
    public Integer duplicateGroupsFound { get; set; }
    public Integer recordsMerged { get; set; }
    public Long processingTimeMs { get; set; }
    public Decimal averageMatchScore { get; set; }
    public List<String> errors { get; set; }
    public Map<String, DuplicateGroup> duplicateGroups { get; set; }

    /**
     * Constructor
     */
    public ProcessingResult() {
      this.totalRecordsProcessed = 0;
      this.duplicateGroupsFound = 0;
      this.recordsMerged = 0;
      this.processingTimeMs = 0;
      this.averageMatchScore = 0;
      this.errors = new List<String>();
      this.duplicateGroups = new Map<String, DuplicateGroup>();
    }

    /**
     * Check if there were any errors
     *
     * @return True if there were errors
     */
    public Boolean hasErrors() {
      return !this.errors.isEmpty();
    }

    /**
     * Get error count
     *
     * @return Number of errors
     */
    public Integer getErrorCount() {
      return this.errors.size();
    }

    /**
     * Get processing time in seconds
     *
     * @return Processing time in seconds
     */
    public Decimal getProcessingTimeInSeconds() {
      return this.processingTimeMs / 1000.0;
    }
  }

  /**
   * Class to encapsulate duplicate finder configuration
   */
  public class DuplicateConfiguration {
    public String name { get; set; }
    public String developerName { get; set; }
    public String objectApiName { get; set; }
    public List<String> matchFields { get; set; }
    public String masterRecordStrategy { get; set; }
    public Integer batchSize { get; set; }

    /**
     * Constructor
     */
    public DuplicateConfiguration() {
      this.matchFields = new List<String>();
      this.batchSize = DEFAULT_BATCH_SIZE;
    }
  }

  /**
   * Custom exception class for duplicate processor errors
   */
  public class DuplicateProcessorException extends Exception {
  }
}
