/**
 * Queueable implementation for processing duplicate records
 *
 * @author Richard Hudson
 * @since April 2025
 */
public class DuplicateQueueableProcessor implements Queueable {
  /**
   * Custom exception class for duplicate errors
   */
  public class CustomException extends Exception {
  }

  // Processing parameters
  private String configId;
  private String objectApiName;
  private Boolean isDryRun;
  private Integer batchSize;
  private String lastProcessedId;
  private Map<String, Object> configSettings;
  private Map<String, Object> context;

  // Constants for chain operations
  private static final String CHAIN_NAME = 'DuplicateProcessor';
  private static final String CONFIG_KEY = 'configId';
  private static final String DRY_RUN_KEY = 'isDryRun';
  private static final String OBJECT_KEY = 'objectApiName';
  private static final String LAST_ID_KEY = 'lastProcessedId';
  private static final String METRICS_KEY = 'metrics';
  private static final String BATCH_SIZE_KEY = 'batchSize';
  private static final String JOB_ID_KEY = 'jobId';

  /**
   * Constructor for initial execution
   * @param configId Configuration ID to use
   * @param isDryRun Whether to perform a dry run (no merge)
   */
  public DuplicateQueueableProcessor(String configId, Boolean isDryRun) {
    this.configId = configId;
    this.isDryRun = isDryRun;
    this.batchSize = 200; // Default batch size
    this.context = new Map<String, Object>();
  }

  /**
   * Default constructor for deserialization
   */
  public DuplicateQueueableProcessor() {
    // Default constructor
    this.context = new Map<String, Object>();
  }

  /**
   * Start duplicate processing with queueable
   * @param configId Configuration ID to use
   * @param isDryRun Whether to perform a dry run
   * @return Job ID
   */
  public static Id startProcessing(String configId, Boolean isDryRun) {
    DuplicateQueueableProcessor processor = new DuplicateQueueableProcessor(
      configId,
      isDryRun
    );
    return System.enqueueJob(processor);
  }

  /**
   * Execute method from Queueable interface
   * @param context The queueable context
   */
  public void execute(System.QueueableContext context) {
    // Log execution start with proper logging
    DuplicateLogger.info('DuplicateQueueableProcessor', 'Starting processor execution');

    try {
      // Load configuration - this method would be implemented to read settings
      loadConfiguration();

      // Log the object being processed
      DuplicateLogger.info('DuplicateQueueableProcessor', 
                        'Processing duplicates for object: ' + this.objectApiName);

      // Call the process method to do the actual work
      process();
    } catch (Exception e) {
      // Log errors with proper logger
      DuplicateLogger.error('DuplicateQueueableProcessor', 
                         'Error processing duplicates', e);
      
      // Create error record for monitoring
      createErrorRecord(e);
    }
  }

  /**
   * Main processing method
   */
  private void process() {
    try {
      // Log status
      DuplicateLogger.info('DuplicateQueueableProcessor', 'Processing duplicates for ' + this.objectApiName);

      // Check if we have enough governor limits to continue using our improved limits utility
      if (!DuplicateLimitUtil.isSafeToProcess()) {
        // Log current limit status
        DuplicateLogger.info('DuplicateQueueableProcessor',
                          'Approaching governor limits, chaining to next job. Limits: ' + 
                          DuplicateLimitUtil.getLimitUsageSummary());
                          
        // Chain to next job to continue processing
        DuplicateQueueableProcessor nextProcessor = new DuplicateQueueableProcessor();
        nextProcessor.configId = this.configId;
        nextProcessor.isDryRun = this.isDryRun;
        nextProcessor.objectApiName = this.objectApiName;
        nextProcessor.batchSize = this.batchSize;
        nextProcessor.lastProcessedId = getUniqueId(); // Track where we left off
        
        // Store context information for the next job
        if (this.context != null && !this.context.isEmpty()) {
            nextProcessor.context = this.context.clone();
        }
        
        // Enqueue the next processor
        System.enqueueJob(nextProcessor);
        return;
      }

      // In a real implementation, this would have actual duplicate finding logic
      // Code for processing duplicates would go here...
      
      // Periodically check limits during processing
      if (!DuplicateLimitUtil.isSafeToProcess()) {
        DuplicateLogger.warn('DuplicateQueueableProcessor', 
                          'Approaching limits during processing. Stopping early.');
        return;
      }
      
    } catch (Exception e) {
      DuplicateLogger.error('DuplicateQueueableProcessor', 
                         'Error during duplicate processing', e);
    }
  }

  /**
   * Load configuration settings from metadata
   */
  private void loadConfiguration() {
    try {
      // Query configuration with security enforced for better security
      List<DuplicateFinderSetting__mdt> settings = [
        SELECT
          DeveloperName,
          SObject_API_Name__c,
          BatchSize__c,
          MatchFields__c,
          MasterRecordStrategy__c
        FROM DuplicateFinderSetting__mdt
        WHERE DeveloperName = :configId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];

      if (!settings.isEmpty()) {
        DuplicateFinderSetting__mdt setting = settings[0];
        this.objectApiName = setting.SObject_API_Name__c;
        
        // Use the batch size from configuration or fallback to constant
        this.batchSize = setting.BatchSize__c != null ? 
                         (Integer) setting.BatchSize__c : 
                         DuplicateConstants.DEFAULT_BATCH_SIZE;

        // Create default config settings with proper null handling
        String matchFieldsStr = setting.MatchFields__c;
        List<String> matchFields = String.isNotBlank(matchFieldsStr) ? 
                                   matchFieldsStr.split(',') : 
                                   new List<String>{ 'Name' };
                                   
        this.configSettings = new Map<String, Object>{
          'matchFields' => matchFields,
          'masterRecordStrategy' => String.isNotBlank(setting.MasterRecordStrategy__c) ? 
                                    setting.MasterRecordStrategy__c : 
                                    'MostRecent'
        };
        
        DuplicateLogger.info('DuplicateQueueableProcessor', 
                          'Loaded configuration for: ' + this.objectApiName + 
                          ' with batch size: ' + this.batchSize);
      } else {
        // Default values with constants
        this.objectApiName = 'Account';
        this.batchSize = DuplicateConstants.DEFAULT_BATCH_SIZE;
        this.configSettings = new Map<String, Object>{
          'matchFields' => new List<String>{ 'Name' },
          'masterRecordStrategy' => 'MostRecent'
        };
        
        DuplicateLogger.warn('DuplicateQueueableProcessor', 
                          'Configuration not found for ID: ' + configId + 
                          '. Using defaults.');
      }
    } catch (Exception e) {
      DuplicateLogger.error('DuplicateQueueableProcessor', 
                         'Error loading configuration', e);
      throw new CustomException('Error loading configuration: ' + e.getMessage());
    }
  }

  /**
   * Check if governor limits are approaching
   * @return True if safe to continue, false if limits are close
   * @deprecated Use DuplicateLimitUtil.isSafeToProcess() instead
   */
  private Boolean checkLimits() {
    // Delegate to our centralized limit checking utility
    return DuplicateLimitUtil.isSafeToProcess();
  }
  
  /**
   * Create an error record for monitoring and reporting
   * @param e The exception that occurred
   */
  private void createErrorRecord(Exception e) {
    try {
      // Create a DeduplicationFailure__c record or similar error tracking object
      // This is just an example - adjust to match your actual schema
      if (Schema.SObjectType.DeduplicationLog__c.isCreateable()) {
        DeduplicationLog__c errorLog = new DeduplicationLog__c(
          ObjectApiName__c = this.objectApiName != null ? this.objectApiName : 'Unknown',
          ExecutionTime__c = System.now(),
          ConfigurationName__c = this.configId != null ? this.configId : 'Unknown',
          InitiatedBy__c = UserInfo.getUserId(),
          RecordIdsJSON__c = 'Error: ' + e.getMessage() + '\n' + e.getStackTraceString()
        );
        
        insert errorLog;
      }
    } catch (Exception ex) {
      // Just log but don't throw - we don't want errors in error handling
      DuplicateLogger.error('DuplicateQueueableProcessor', 
                         'Error creating error record', ex);
    }
  }

  /**
   * Generate a unique ID for tracking jobs
   * @return Unique ID string
   */
  private String getUniqueId() {
    return String.valueOf(Datetime.now().getTime()) +
      '-' +
      String.valueOf(Math.round(Math.random() * 1000000));
  }
}
