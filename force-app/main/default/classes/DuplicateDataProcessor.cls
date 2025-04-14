/**
 * Data processor implementation for duplicate management
 * @description Handles data processing in queueable context
 *
 * @author Richard Hudson
 * @date April 2025
 */
public class DuplicateDataProcessor {
    // Simple context map to store values
    private Map<String, Object> context;
    private String objectName;
    private Set<Id> recordIds;
    
    /**
     * @description Default constructor
     */
    public DuplicateDataProcessor() {
        this.context = new Map<String, Object>();
    }
    
    /**
     * @description Constructor with context
     * @param contextMap The context map for this processor
     */
    public DuplicateDataProcessor(Map<String, Object> contextMap) {
        this.context = contextMap != null ? contextMap : new Map<String, Object>();
    }
    
    /**
     * @description Constructor with object name and record IDs
     * @param objectName The API name of the object to process
     * @param recordIds Set of record IDs to process
     */
    public DuplicateDataProcessor(String objectName, Set<Id> recordIds) {
        this.context = new Map<String, Object>();
        this.objectName = objectName;
        this.recordIds = recordIds;
    }
    
    /**
     * @description Set context value
     * @param key Context key
     * @param value Value to store
     */
    public void setContextValue(String key, Object value) {
        if (context == null) {
            context = new Map<String, Object>();
        }
        context.put(key, value);
    }
    
    /**
     * @description Get context value
     * @param key Context key
     * @return The stored value
     */
    public Object getContextValue(String key) {
        return context != null ? context.get(key) : null;
    }
    
    /**
     * @description Start data processing based on object and record IDs
     */
    public void process() {
        // Set completion status in context
        setContextValue('processingComplete', true);
        
        // If we have record IDs, set the count in context
        if (recordIds != null) {
            setContextValue('recordsProcessed', recordIds.size());
        } else {
            setContextValue('recordsProcessed', 0);
        }
        
        // Process records based on volume
        if (recordIds != null && recordIds.size() > 0) {
            if (recordIds.size() > 200) {
                // For large volumes, consider using batch processing
                // Start a batch job to handle the processing
                processBatchRecords(objectName, recordIds);
            } else {
                // For smaller volumes, process directly
                processRecordsDirectly(objectName, recordIds);
            }
        }
    }
    
    /**
     * Execute method to be compatible with queueable processing
     * @param externalContext The external context map
     */
    public void execute(Map<String, Object> externalContext) {
        // Merge external context with our context
        if (externalContext != null) {
            if (context == null) {
                context = new Map<String, Object>();
            }
            context.putAll(externalContext);
        }
        
        // Process the data
        process();
    }
    
    /**
     * Simplified execute method with no parameters
     */
    public void execute() {
        process();
    }
    
    /**
     * Process a larger volume of records via batch
     * @param objectName The API name of the object to process
     * @param recordIds Set of record IDs to process
     */
    private void processBatchRecords(String objectName, Set<Id> recordIds) {
        try {
            // Create a batch instance for processing
            DuplicateRecordBatch batchJob = new DuplicateRecordBatch();
            batchJob.setRecordIds(new List<Id>(recordIds));
            
            // Start the batch job
            Database.executeBatch(batchJob, 200);
            
            // Update context with processing info
            setContextValue('batchJobStarted', true);
            setContextValue('recordIdsSubmitted', recordIds.size());
        } catch(Exception e) {
            setContextValue('error', e.getMessage());
            setContextValue('processingComplete', false);
            setContextValue('processingSuccess', false);
        }
    }
    
    /**
     * Process a small volume of records directly
     * @param objectName The API name of the object to process
     * @param recordIds Set of record IDs to process
     */
    private void processRecordsDirectly(String objectName, Set<Id> recordIds) {
        try {
            // Process records in current transaction
            // Simple query to get records
            String query = 'SELECT Id FROM ' + objectName + ' WHERE Id IN :recordIds';
            List<SObject> records = Database.query(query);
            
            // Process each record
            for (SObject record : records) {
                // Apply processing logic
                // This would be replaced with actual processing
                // such as detecting duplicates, scoring, etc.
            }
            
            // Update context with success
            setContextValue('processingSuccess', true);
            setContextValue('recordsProcessedDirectly', records.size());
        } catch(Exception e) {
            setContextValue('error', e.getMessage());
            setContextValue('processingComplete', false);
            setContextValue('processingSuccess', false);
        }
    }
}
