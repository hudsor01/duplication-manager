/**
 * DuplicateConfig
 * Configuration class for the duplicate finder framework
 * @author Richard Hudson
 * @updated Richard Hudson - April 2025
 */
public class DuplicateConfig {
  // Properties to hold configuration settings
  public String objectApiName { get; set; }
  public List<String> matchFields { get; set; }
  public Integer batchSize { get; set; }
  public String masterRecordStrategy { get; set; }
  public Boolean isActive { get; set; }

  // Enhanced properties
  public Integer matchThreshold { get; set; }
  public Map<String, Decimal> fieldWeights { get; set; }
  public String preMergeHandler { get; set; }
  public String postMergeHandler { get; set; }
  public String description { get; set; }
  public Integer version { get; set; }

  // Constructor
  public DuplicateConfig() {
    this.matchFields = new List<String>();
    this.batchSize = 200;
    this.masterRecordStrategy = 'MostRecent';
    this.isActive = true;
    this.matchThreshold = 75;
    this.fieldWeights = new Map<String, Decimal>();
    this.version = 1;
  }

  // Constructor with object name
  public DuplicateConfig(String objectApiName) {
    this();
    this.objectApiName = objectApiName;
  }

  // Constructor with all parameters
  public DuplicateConfig(
    String objectApiName,
    List<String> matchFields,
    Integer batchSize,
    String masterRecordStrategy,
    Boolean isActive
  ) {
    this();
    this.objectApiName = objectApiName;
    this.matchFields = matchFields;
    this.batchSize = batchSize;
    this.masterRecordStrategy = masterRecordStrategy;
    this.isActive = isActive;
  }

  // Full constructor with all enhanced parameters
  public DuplicateConfig(
    String objectApiName,
    List<String> matchFields,
    Integer batchSize,
    String masterRecordStrategy,
    Boolean isActive,
    Integer matchThreshold,
    Map<String, Decimal> fieldWeights,
    String preMergeHandler,
    String postMergeHandler
  ) {
    this.objectApiName = objectApiName;
    this.matchFields = matchFields;
    this.batchSize = batchSize;
    this.masterRecordStrategy = masterRecordStrategy;
    this.isActive = isActive;
    this.matchThreshold = matchThreshold;
    this.fieldWeights = fieldWeights;
    this.preMergeHandler = preMergeHandler;
    this.postMergeHandler = postMergeHandler;
    this.version = 1;
  }

  // Methods to validate configuration
  public Boolean isValid() {
    return String.isNotBlank(objectApiName) &&
      matchFields != null &&
      !matchFields.isEmpty() &&
      batchSize > 0 &&
      isActive == true;
  }

  /**
   * Get field match weight
   * @param fieldName API name of the field
   * @return Decimal Weight for the field (1.0 by default)
   */
  public Decimal getFieldWeight(String fieldName) {
    if (fieldWeights != null && fieldWeights.containsKey(fieldName)) {
      return fieldWeights.get(fieldName);
    }
    return 1.0; // Default weight
  }

  /**
   * Set field weight
   * @param fieldName API name of the field
   * @param weight Weight to assign to the field
   */
  public void setFieldWeight(String fieldName, Decimal weight) {
    if (fieldWeights == null) {
      fieldWeights = new Map<String, Decimal>();
    }
    fieldWeights.put(fieldName, weight);
  }

  /**
   * @deprecated Use fromConfiguration method instead
   */
  public static DuplicateConfig fromCustomMetadata(String settingName) {
    System.debug(
      LoggingLevel.WARN,
      'DuplicateConfig.fromCustomMetadata is deprecated. Use DuplicateConfig.fromConfiguration instead.'
    );
    return fromConfiguration(settingName);
  }

  /**
   * Factory method to create from DuplicationConfiguration__mdt
   * @param configName DeveloperName of the configuration record
   * @return DuplicateConfig populated with values from custom metadata
   */
  public static DuplicateConfig fromConfiguration(String configName) {
    // Create empty config
    DuplicateConfig config = new DuplicateConfig();

    try {
      // First try to get from DuplicationConfiguration__mdt
      List<DuplicationConfiguration__mdt> configs = [
        SELECT
          Id,
          DeveloperName,
          ObjectApiName__c,
          MatchFields__c,
          BatchSize__c,
          MasterRecordStrategy__c,
          IsActive__c,
          MatchThreshold__c,
          MatchFieldWeights__c,
          PreMergeApexHandler__c,
          PostMergeApexHandler__c,
          Description__c,
          Version__c
        FROM DuplicationConfiguration__mdt
        WHERE DeveloperName = :configName
        LIMIT 1
      ];

      if (!configs.isEmpty()) {
        DuplicationConfiguration__mdt setting = configs[0];

        // Populate config from setting
        config.objectApiName = setting.ObjectApiName__c;
        config.matchFields = setting.MatchFields__c != null
          ? setting.MatchFields__c.split(',')
          : new List<String>();
        config.batchSize = setting.BatchSize__c != null
          ? Integer.valueOf(setting.BatchSize__c)
          : 200;
        config.masterRecordStrategy = setting.MasterRecordStrategy__c;
        config.isActive = setting.IsActive__c;
        config.matchThreshold = setting.MatchThreshold__c != null
          ? Integer.valueOf(setting.MatchThreshold__c)
          : 75;
        config.preMergeHandler = setting.PreMergeApexHandler__c;
        config.postMergeHandler = setting.PostMergeApexHandler__c;
        config.description = setting.Description__c;

        // Parse field weights if available
        if (String.isNotBlank(setting.MatchFieldWeights__c)) {
          try {
            config.fieldWeights = (Map<String, Decimal>) JSON.deserialize(
              setting.MatchFieldWeights__c,
              Map<String, Decimal>.class
            );
          } catch (Exception e) {
            System.debug(
              LoggingLevel.ERROR,
              'Error parsing field weights: ' + e.getMessage()
            );
            config.fieldWeights = new Map<String, Decimal>();
          }
        }

        // Parse version
        if (setting.Version__c != null) {
          try {
            Decimal versionDecimal = setting.Version__c;
            String versionStr = String.valueOf(versionDecimal);
            if (versionStr.contains('.')) {
              config.version = Integer.valueOf(
                versionStr.substring(0, versionStr.indexOf('.'))
              );
            } else {
              config.version = Integer.valueOf(versionStr);
            }
          } catch (Exception e) {
            config.version = 1;
          }
        }

        return config;
      }

      // Fall back to legacy DuplicateFinderSetting__mdt if not found
      System.debug(
        LoggingLevel.WARN,
        'Configuration not found in DuplicationConfiguration__mdt, falling back to DuplicateFinderSetting__mdt'
      );
      List<DuplicateFinderSetting__mdt> legacySettings = [
        SELECT
          SObject_API_Name__c,
          MatchFields__c,
          BatchSize__c,
          MasterRecordStrategy__c,
          IsActive__c
        FROM DuplicateFinderSetting__mdt
        WHERE DeveloperName = :configName
        LIMIT 1
      ];

      if (!legacySettings.isEmpty()) {
        DuplicateFinderSetting__mdt setting = legacySettings[0];

        // Populate config from legacy setting
        config.objectApiName = String.isNotBlank(setting.SObject_API_Name__c)
          ? setting.SObject_API_Name__c
          : 'Account';

        String fieldsList = setting.MatchFields__c;

        config.matchFields = String.isNotBlank(fieldsList)
          ? fieldsList.split(',')
          : new List<String>();
        config.batchSize = setting.BatchSize__c != null
          ? Integer.valueOf(setting.BatchSize__c)
          : 200;
        config.masterRecordStrategy = setting.MasterRecordStrategy__c;
        config.isActive = setting.IsActive__c;
      }

      return config;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error loading configuration: ' + e.getMessage()
      );
      return config;
    }
  }

  /**
   * Create a JSON representation of this config
   * @return String JSON string
   */
  public String toJson() {
    return JSON.serialize(this);
  }

  /**
   * Create a config from JSON
   * @param jsonStr JSON string representation
   * @return DuplicateConfig Configuration object
   */
  public static DuplicateConfig fromJson(String jsonStr) {
    try {
      return (DuplicateConfig) JSON.deserialize(jsonStr, DuplicateConfig.class);
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error deserializing config: ' + e.getMessage()
      );
      return new DuplicateConfig();
    }
  }

  /**
   * Create a DuplicateConfig from DuplicationConfiguration__mdt
   * This method is for enhanced metadata compatibility
   */
  public static DuplicateConfig fromEnhancedMetadata(String configName) {
    // Create empty config
    DuplicateConfig config = new DuplicateConfig();

    try {
      // Query for the configuration metadata
      List<DuplicationConfiguration__mdt> configs = [
        SELECT
          Id,
          DeveloperName,
          ObjectApiName__c,
          MatchFields__c,
          BatchSize__c,
          MasterRecordStrategy__c,
          IsActive__c,
          MatchThreshold__c,
          MatchFieldWeights__c,
          PreMergeApexHandler__c,
          PostMergeApexHandler__c,
          Description__c,
          Version__c
        FROM DuplicationConfiguration__mdt
        WHERE DeveloperName = :configName
        LIMIT 1
      ];

      if (!configs.isEmpty()) {
        DuplicationConfiguration__mdt setting = configs[0];

        // Populate config from setting
        config.objectApiName = setting.ObjectApiName__c;
        config.matchFields = setting.MatchFields__c != null
          ? setting.MatchFields__c.split(',')
          : new List<String>();
        config.batchSize = setting.BatchSize__c != null
          ? Integer.valueOf(setting.BatchSize__c)
          : 200;
        config.masterRecordStrategy = setting.MasterRecordStrategy__c;
        config.isActive = setting.IsActive__c;
        config.matchThreshold = setting.MatchThreshold__c != null
          ? Integer.valueOf(setting.MatchThreshold__c)
          : 75;
        config.preMergeHandler = setting.PreMergeApexHandler__c;
        config.postMergeHandler = setting.PostMergeApexHandler__c;
        config.description = setting.Description__c;

        // Parse field weights if available
        if (String.isNotBlank(setting.MatchFieldWeights__c)) {
          try {
            config.fieldWeights = (Map<String, Decimal>) JSON.deserialize(
              setting.MatchFieldWeights__c,
              Map<String, Decimal>.class
            );
          } catch (Exception e) {
            System.debug(
              LoggingLevel.ERROR,
              'Error parsing field weights: ' + e.getMessage()
            );
            config.fieldWeights = new Map<String, Decimal>();
          }
        }

        // Parse version
        if (setting.Version__c != null) {
          try {
            Decimal versionDecimal = setting.Version__c;
            String versionStr = String.valueOf(versionDecimal);
            if (versionStr.contains('.')) {
              config.version = Integer.valueOf(
                versionStr.substring(0, versionStr.indexOf('.'))
              );
            } else {
              config.version = Integer.valueOf(versionStr);
            }
          } catch (Exception e) {
            config.version = 1;
          }
        }
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error loading enhanced configuration: ' + e.getMessage()
      );
    }

    return config;
  }
}
