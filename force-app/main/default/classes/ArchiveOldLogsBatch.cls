/**
 * Batch class for archiving old duplicate merge logs
 *
 * @author Richard Hudson
 * @date April 2025
 */
global class ArchiveOldLogsBatch extends DuplicateBaseBatch {
    private Integer daysToRetain;
    private static final String CONFIGURATION_NAME = 'Archive Old Logs';

    /**
     * Constructor with days to retain parameter
     *
     * @param daysToRetain Number of days to keep logs before archiving
     */
    global ArchiveOldLogsBatch(Integer daysToRetain) {
        super('DuplicateMergeLog__c', false, 200, CONFIGURATION_NAME);
        this.daysToRetain = daysToRetain > 0 ? daysToRetain : 90; // Default to 90 days
    }

    /**
     * Build query locator for logs to archive
     */
    global override Database.QueryLocator buildQueryLocator() {
        // Calculate cutoff date
        Datetime cutoffDate = System.now().addDays(-daysToRetain);

        // Query logs older than the cutoff date
        return Database.getQueryLocator([
            SELECT Id, Name, CreatedDate, UserId__c, ObjectApiName__c, JobId__c,
                   MergeTime__c, MergedIds__c, MasterId__c, FieldMergeDetails__c,
                   ErrorMessage__c
            FROM DuplicateMergeLog__c
            WHERE CreatedDate < :cutoffDate
        ]);
    }

    /**
     * Find duplicates - not applicable for archiving
     * We'll return a map with a single key containing all records to process
     */
    global override Map<String, List<SObject>> findDuplicates(List<SObject> scope) {
        Map<String, List<SObject>> result = new Map<String, List<SObject>>();
        result.put('all_records', scope);
        return result;
    }

    /**
     * Process the records - archive logs
     */
    global override void processDuplicates(Map<String, List<SObject>> records) {
        List<SObject> scope = records.get('all_records');
        if (scope == null || scope.isEmpty()) {
            return;
        }

        try {
            // Create archive records
            List<DuplicateMergeLogArchive__c> archiveRecords = createArchiveRecords(scope);

            // Insert archive records
            Set<Id> successfullyArchivedIds = insertArchiveRecords(archiveRecords);

            // Delete original records that were successfully archived
            if (!successfullyArchivedIds.isEmpty()) {
                deleteOriginalRecords(successfullyArchivedIds);
            }

            // Update processing counts
            recordsProcessed += scope.size();

        } catch (Exception e) {
            logError('Error archiving logs', e);
        }
    }

    /**
     * Create archive records from original logs
     */
    private List<DuplicateMergeLogArchive__c> createArchiveRecords(List<SObject> scope) {
        List<DuplicateMergeLogArchive__c> archiveRecords = new List<DuplicateMergeLogArchive__c>();

        for (SObject rec : scope) {
            DuplicateMergeLog__c log = (DuplicateMergeLog__c)rec;

            // Create archive record
            DuplicateMergeLogArchive__c archive = new DuplicateMergeLogArchive__c(
                OriginalLogId__c = log.Id,
                LogName__c = log.Name,
                JobId__c = log.JobId__c,
                UserId__c = log.UserId__c,
                ObjectApiName__c = log.ObjectApiName__c,
                MergeTime__c = log.MergeTime__c,
                MergedIds__c = log.MergedIds__c,
                MasterId__c = log.MasterId__c,
                FieldMergeDetails__c = log.FieldMergeDetails__c,
                ErrorMessage__c = log.ErrorMessage__c,
                OriginalCreatedDate__c = log.CreatedDate,
                ArchiveDate__c = System.now()
            );

            archiveRecords.add(archive);
        }

        return archiveRecords;
    }

    /**
     * Insert archive records and return successfully archived IDs
     */
    private Set<Id> insertArchiveRecords(List<DuplicateMergeLogArchive__c> archiveRecords) {
        Set<Id> successIds = new Set<Id>();

        if (archiveRecords.isEmpty()) {
            return successIds;
        }

        // Insert with partial success allowed
        Database.SaveResult[] results = Database.insert(archiveRecords, false);

        // Process results
        for (Integer i = 0; i < results.size(); i++) {
            Database.SaveResult sr = results[i];
            DuplicateMergeLogArchive__c archive = archiveRecords[i];

            if (sr.isSuccess()) {
                successIds.add(archive.OriginalLogId__c);
            } else {
                for (Database.Error err : sr.getErrors()) {
                    logError('Error archiving log ' + archive.OriginalLogId__c,
                             new duplicateException(err.getMessage()));
                }
            }
        }

        return successIds;
    }

    /**
     * Delete original records that were successfully archived
     */
    private void deleteOriginalRecords(Set<Id> recordIdsToDelete) {
        if (recordIdsToDelete.isEmpty()) {
            return;
        }

        try {
            // Query to get actual records
            List<DuplicateMergeLog__c> recordsToDelete = [
                SELECT Id FROM DuplicateMergeLog__c
                WHERE Id IN :recordIdsToDelete
            ];

            // Delete with partial success allowed
            Database.DeleteResult[] results = Database.delete(recordsToDelete, false);

            // Process results
            for (Integer i = 0; i < results.size(); i++) {
                Database.DeleteResult dr = results[i];

                if (!dr.isSuccess()) {
                    for (Database.Error err : dr.getErrors()) {
                        logError('Error deleting log ' + recordsToDelete[i].Id,
                                 new duplicateException(err.getMessage()));
                    }
                }
            }

        } catch (Exception e) {
            logError('Error deleting original logs', e);
        }
    }
}
