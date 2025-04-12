/**
 * Class for running duplicate finder batch jobs
 * @author Richard Hudson
 * @date 2025-04-11
 */
public class DRCBatch {
    /**
     * Static method for running a duplicate finder batch job with the specified configuration
     * 
     * @param settingDeveloperName Developer name of the configuration setting to use
     * @param isDryRun Whether to run in dry run mode (find but don't merge)
     * @param batchSize Number of records per batch (default 200)
     * @return Id The batch job ID
     */
    @AuraEnabled
    public static Id runDuplicateFinderBatch(String settingDeveloperName, Boolean isDryRun, Integer batchSize) {
        if (String.isBlank(settingDeveloperName)) {
            throw new AuraHandledException('Setting Developer Name is required');
        }
        
        // Default batch size if not provided
        if (batchSize == null || batchSize <= 0) {
            batchSize = 200;
        }
        
        try {
            // Start the batch job with the provided parameters
            // Create a DuplicateRecordBatch instance and execute it
            DuplicateRecordBatch batchJob = new DuplicateRecordBatch(settingDeveloperName, isDryRun);
            
            // Execute the batch job
            Id batchJobId = Database.executeBatch(batchJob, batchSize);
            
            return batchJobId;
        } catch (Exception e) {
            throw new AuraHandledException('Error starting batch job: ' + e.getMessage());
        }
    }
}