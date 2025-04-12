/**
 * Batch Apex to archive old log records
 * @description Batch job to archive old log records by moving them to an archive object and deleting the originals
 * @author Richard Hudson
 * @since April 2025
 */
public class ArchiveOldLogsBatch implements Database.Batchable<SObject> {
    private Integer daysToRetain;
    private Datetime startTime;

    // Define a constant for the configuration name
    private static final String CONFIGURATION_NAME = 'Archive Old Logs';

    /**
     * Constructor for the batch class
     * @description Initializes the batch job with the number of days to retain logs
     * @param daysToRetain Number of days to retain logs before archiving
     */
    public ArchiveOldLogsBatch(Integer daysToRetain) {
        this.daysToRetain = daysToRetain;
    }

    /**
     * Start method for batch job
     * @description Query for old log records that need to be archived
     * @param bc Batch context
     * @return Database.QueryLocator Query locator for old logs
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // The original design referred to Log__c, but this object does not exist in the org.
        // DuplicateMergeLog__c is used instead as it contains the relevant log data for archiving.
        startTime = Datetime.now();
        return Database.getQueryLocator([
            SELECT Id, Name, CreatedDate, UserId__c, ObjectApiName__c, JobId__c,
                   MergeTime__c, MergedIds__c, MasterId__c, FieldMergeDetails__c
            FROM DuplicateMergeLog__c
            WHERE CreatedDate < :DateTime.now().addDays(-daysToRetain)
        ]);
    }

    /**
     * Execute method for batch job that archives old log records and deletes the originals
     * @description This method processes each batch of records by:
     *              1. Converting original logs to archive records
     *              2. Inserting the archive records
     *              3. Deleting successfully archived original records
     * @param bc Batch context
     * @param scope Records to process
     */
    public void execute(Database.BatchableContext bc, List<DuplicateMergeLog__c> scope) {
        // Create archive records from original logs
        List<DuplicateMergeLogArchive__c> archiveRecords = createArchiveRecords(scope);

        // Insert archive records and get successfully archived IDs
        List<String> errors = new List<String>();
        Set<Id> successfullyArchivedIds = insertArchiveRecords(scope, archiveRecords, errors);

        // Delete original records that were successfully archived
        if (!successfullyArchivedIds.isEmpty()) {
            deleteOriginalRecords(scope, successfullyArchivedIds);
        }

        // Log summary of errors if any occurred
        if (!errors.isEmpty()) {
            // Log error summary but avoid debug statements in production
            logErrorSummary(String.join(errors, '\n'));
        }
    }

    /**
     * Creates archive records from original log records
     * @description Converts log records to archive records with appropriate field mappings
     * @param originalRecords The original log records to archive
     * @return List of archive records ready to be inserted
     */
    private List<DuplicateMergeLogArchive__c> createArchiveRecords(List<DuplicateMergeLog__c> originalRecords) {
        List<DuplicateMergeLogArchive__c> archiveRecords = new List<DuplicateMergeLogArchive__c>();
        for (DuplicateMergeLog__c origRecord : originalRecords) {
            // Create archive record with data from original log
            DuplicateMergeLogArchive__c archiveRec = new DuplicateMergeLogArchive__c();
            archiveRec.OriginalLogId__c = origRecord.Id;
            // Name field is auto-populated as it's an auto-number field

            // Map standard fields between the objects
            mapStandardFields(origRecord, archiveRec);

            archiveRecords.add(archiveRec);
        }

        return archiveRecords;
    }

    /**
     * Maps standard fields from original record to archive record
     * @description Copies field values from source to destination object
     * @param origRecord Original log record
     * @param archiveRec Archive record to populate
     */
    private void mapStandardFields(DuplicateMergeLog__c origRecord, DuplicateMergeLogArchive__c archiveRec) {
        // Check if origRecord has ErrorMessages__c field before trying to access it
        if (origRecord.get('ErrorMessages__c') != null) {
            archiveRec.ErrorMessages__c = (String)origRecord.get('ErrorMessages__c');
        }
        archiveRec.UserId__c = origRecord.UserId__c;
        archiveRec.ObjectApiName__c = origRecord.ObjectApiName__c;
        archiveRec.JobId__c = origRecord.JobId__c;
        archiveRec.MergeTime__c = origRecord.MergeTime__c;
        archiveRec.MergedIds__c = origRecord.MergedIds__c;
        archiveRec.MasterId__c = origRecord.MasterId__c;
        archiveRec.FieldMergeDetails__c = origRecord.FieldMergeDetails__c;

        // Store the original created date as a string if the field exists
        if (Schema.SObjectType.DuplicateMergeLogArchive__c.fields.getMap().containsKey('OriginalCreatedDateText__c')) {
            archiveRec.put('OriginalCreatedDateText__c', String.valueOf(origRecord.CreatedDate));
        }
    }

    /**
     * Inserts archive records and processes results
     * @description Inserts archive records and tracks which ones were successful
     * @param originalRecords Original log records being processed
     * @param archiveRecords Archive records to insert
     * @param errors List to collect error messages
     * @return Set of IDs of successfully archived records
     */
    private Set<Id> insertArchiveRecords(
        List<DuplicateMergeLog__c> originalRecords,
        List<DuplicateMergeLogArchive__c> archiveRecords,
        List<String> errors
    ) {
        // Insert archive records with partial success allowed
        Database.SaveResult[] saveResults = Database.insert(archiveRecords, false);
        Set<Id> successfullyArchivedIds = new Set<Id>();

        // Process results and collect IDs of successfully archived records
        for (Integer i = 0; i < saveResults.size(); i++) {
            if (saveResults[i].isSuccess()) {
                successfullyArchivedIds.add(originalRecords[i].Id);
            } else {
                String errorMsg = buildErrorMessage('Failed to archive record ' + originalRecords[i].Id + ': ',
                                                    saveResults[i].getErrors());
                errors.add(errorMsg);
            }
        }

        return successfullyArchivedIds;
    }

    /**
     * Deletes original records that were successfully archived
     * @description Removes original log records that have been successfully archived
     * @param originalRecords All original records in the current batch
     * @param successfullyArchivedIds IDs of records that were successfully archived
     */
    private void deleteOriginalRecords(List<DuplicateMergeLog__c> originalRecords, Set<Id> successfullyArchivedIds) {
        List<DuplicateMergeLog__c> recordsToDelete = new List<DuplicateMergeLog__c>();

        for (DuplicateMergeLog__c record : originalRecords) {
            if (successfullyArchivedIds.contains(record.Id)) {
                recordsToDelete.add(record);
            }
        }

        if (!recordsToDelete.isEmpty()) {
            Database.DeleteResult[] deleteResults = Database.delete(recordsToDelete, false);

            // Log any delete errors
            for (Integer i = 0; i < deleteResults.size(); i++) {
                if (!deleteResults[i].isSuccess()) {
                    String errorMsg = buildErrorMessage('Failed to delete record ' + recordsToDelete[i].Id + ': ',
                                                        deleteResults[i].getErrors());
                    logErrorMessage(errorMsg);
                }
            }
        }
    }

    /**
     * Builds an error message from Database.Error objects
     * @description Creates a formatted error message from Database.Error objects
     * @param prefix Prefix for the error message
     * @param errors List of Database.Error objects
     * @return Formatted error message
     */
    private String buildErrorMessage(String prefix, List<Database.Error> errors) {
        String errorMsg = prefix;
        for (Database.Error err : errors) {
            errorMsg += err.getStatusCode() + ' - ' + err.getMessage() + '; ';
        }
        return errorMsg;
    }

    /**
     * Logs an error message in a production-safe way
     * @description Logs error messages using appropriate mechanism
     * @param message The error message to log
     */
    private void logErrorMessage(String message) {
        // In production, use a custom logging mechanism or platform events
        // Log to custom object instead of using System.debug
        insertErrorLog(message);
    }

    /**
     * Logs a summary of errors in a production-safe way
     * @description Logs error summary using appropriate mechanism
     * @param summary The error summary to log
     */
    private void logErrorSummary(String summary) {
        // In production, use a custom logging mechanism or platform events
        // Log to custom object instead of using System.debug
        insertErrorLog('Archive errors summary: ' + summary);
    }

    /**
     * Inserts an error log record
     * @description Creates a log entry in the error log custom object
     * @param message The error message to log
     */
    private void insertErrorLog(String message) {
        try {
            DuplicateRunResult__c errorLog = new DuplicateRunResult__c(
                ConfigurationName__c = CONFIGURATION_NAME,
                Status__c = 'Error',
                ErrorMessage__c = message.left(32000)
            );
            insert errorLog;
        } catch (Exception e) {
            System.debug('Failed to insert error log: ' + e.getMessage());
        }
    }

    /**
     * Finish method for batch job
     * @description Executes after all batches are processed
     * @param bc Batch context
     */
    public void finish(Database.BatchableContext bc) {
        // Get job info for logging purposes
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems
            FROM AsyncApexJob
            WHERE Id = :bc.getJobId()
        ];

        // Create log entry for the archive operation
        DuplicateJobStatistic__c stat = new DuplicateJobStatistic__c();
        stat.ConfigurationName__c = CONFIGURATION_NAME;
        stat.ProcessingTimeMs__c = Datetime.now().getTime() - startTime.getTime();
        stat.DuplicatesFound__c = 0;
        stat.Status__c = 'Completed';

        // Log job metrics like number of processed records and errors
        String jobSummary = 'Job completed with ' + job.NumberOfErrors + ' errors. ' +
                            'Processed ' + job.JobItemsProcessed + ' out of ' + job.TotalJobItems + ' items.';
        stat.ErrorMessages__c = jobSummary;

        try {
            insert stat;
        } catch (Exception e) {
            insertErrorLog('Error inserting DuplicateJobStatistic__c record: ' + e.getMessage());
        }
    }
}
