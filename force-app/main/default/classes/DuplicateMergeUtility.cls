/**
 * Utility class for merging duplicate records
 * 
 * @author Richard Hudson
 * @date April 2025
 */
public class DuplicateMergeUtility {
    
    /**
     * Merges a group of duplicate records
     * 
     * @param duplicateGroup The duplicate group to merge
     * @param masterRecordStrategy Strategy for selecting master record
     * @return Result containing merge statistics
     */
    public static MergeResult mergeGroup(DuplicateGroup duplicateGroup, String masterRecordStrategy) {
        // Skip if no duplicates
        if (!duplicateGroup.hasDuplicates()) {
            return new MergeResult(0, 'No duplicates to merge');
        }
        
        // Get master record
        SObject masterRecord = duplicateGroup.getMasterRecord(masterRecordStrategy);
        if (masterRecord == null) {
            return new MergeResult(0, 'Could not determine master record');
        }
        
        // Get duplicate IDs
        List<Id> duplicateIds = duplicateGroup.getDuplicateIds(masterRecord);
        if (duplicateIds.isEmpty()) {
            return new MergeResult(0, 'No duplicates to merge');
        }
        
        // Perform the merge
        return mergeRecords(masterRecord.Id, duplicateIds);
    }
    
    /**
     * Merges duplicate records into a master record
     * 
     * @param masterId ID of the master record
     * @param duplicateIds List of IDs of duplicate records to merge
     * @return Result containing merge statistics
     */
    public static MergeResult mergeRecords(Id masterId, List<Id> duplicateIds) {
        if (duplicateIds == null || duplicateIds.isEmpty()) {
            return new MergeResult(0, 'No duplicates to merge');
        }
        
        // Create documentation before merge
        try {
            createMergeDocumentationNote(masterId, duplicateIds);
        } catch (Exception e) {
            System.debug('Error creating merge documentation: ' + e.getMessage());
            // Continue with merge even if documentation fails
        }
        
        // Get the SObject type from the ID
        Schema.SObjectType sot = masterId.getSobjectType();
        
        // Keep track of successful merges
        Integer mergeCount = 0;
        List<String> errors = new List<String>();
        
        // Process duplicates in batches to avoid governor limits
        List<List<Id>> batches = batchIds(duplicateIds, 100);
        
        for (List<Id> batch : batches) {
            try {
                // Create SObject instances for the merge
                SObject masterRecord = sot.newSObject(masterId);
                
                for (Id dupeId : batch) {
                    try {
                        SObject duplicateRecord = sot.newSObject(dupeId);
                        Database.merge(masterRecord, duplicateRecord);
                        mergeCount++;
                    } catch (Exception e) {
                        String errorMsg = 'Error merging ' + dupeId + ': ' + e.getMessage();
                        errors.add(errorMsg);
                        System.debug(errorMsg);
                    }
                }
            } catch (Exception e) {
                String errorMsg = 'Error processing batch: ' + e.getMessage();
                errors.add(errorMsg);
                System.debug(errorMsg);
            }
        }
        
        // Return results
        MergeResult result = new MergeResult(mergeCount, 'Merge completed');
        result.errors.addAll(errors);
        return result;
    }
    
    /**
     * Creates a note on the master record documenting the merge
     * 
     * @param masterId ID of the master record
     * @param duplicateIds List of IDs of duplicate records being merged
     * @return The ID of the created note
     */
    private static Id createMergeDocumentationNote(Id masterId, List<Id> duplicateIds) {
        // Build note content
        String noteTitle = 'Record Merge Documentation';
        String noteBody = 'The following duplicate records were merged into this record:\n\n';
        
        for (Id dupeId : duplicateIds) {
            noteBody += '- Record ID: ' + dupeId + ' (merged on ' + 
                      Datetime.now().format('yyyy-MM-dd HH:mm:ss') + ')\n';
        }
        
        // Create a standard Note
        Note note = new Note();
        note.Title = noteTitle;
        note.Body = noteBody;
        note.ParentId = masterId;
        
        insert note;
        
        return note.Id;
    }
    
    /**
     * Splits a list of IDs into batches
     * 
     * @param ids List of IDs to batch
     * @param batchSize Size of each batch
     * @return List of ID batches
     */
    private static List<List<Id>> batchIds(List<Id> ids, Integer batchSize) {
        List<List<Id>> batches = new List<List<Id>>();
        
        Integer batchCount = (ids.size() + batchSize - 1) / batchSize;
        for (Integer i = 0; i < batchCount; i++) {
            Integer startIndex = i * batchSize;
            Integer endIndex = Math.min(startIndex + batchSize, ids.size());
            
            // Create a new batch and add the relevant IDs
            List<Id> batch = new List<Id>();
            for (Integer j = startIndex; j < endIndex; j++) {
                batch.add(ids[j]);
            }
            batches.add(batch);
        }
        
        return batches;
    }
    
    /**
     * Class to encapsulate merge operation results
     */
    public class MergeResult {
        public Integer recordsMerged { get; private set; }
        public String message { get; private set; }
        public List<String> errors { get; private set; }
        public Datetime timestamp { get; private set; }
        
        /**
         * Constructor
         * 
         * @param recordsMerged Number of records merged
         * @param message Result message
         */
        public MergeResult(Integer recordsMerged, String message) {
            this.recordsMerged = recordsMerged;
            this.message = message;
            this.errors = new List<String>();
            this.timestamp = Datetime.now();
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
    }
}