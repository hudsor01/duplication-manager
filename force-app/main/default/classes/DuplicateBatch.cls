/**
 * Main batch implementation for duplicate detection and merging
 * Extends duplicateBaseBatch with specific implementation
 *
 * @author Richard Hudson
 * @date April 2025
 */
global class DuplicateBatch extends DuplicateBaseBatch {

    // Configuration
    private String duplicateRuleId;
    private List<String> additionalFields;

    /**
     * Constructor for batch job
     * @param objectName API name of object to deduplicate
     * @param duplicateRuleId ID of duplicate rule to use
     * @param additionalFields Additional fields to preserve
     * @param isDryRun Whether to perform a dry run
     */
    global DuplicateBatch(
        String objectName,
        String duplicateRuleId,
        List<String> additionalFields,
        Boolean isDryRun
    ) {
        // Call parent constructor
        super(objectName, isDryRun, null);

        this.duplicateRuleId = duplicateRuleId;
        this.additionalFields = additionalFields;
    }

    /**
     * Build the query locator for this batch
     * @return Query locator for batch processing
     */
    global override Database.QueryLocator buildQueryLocator() {
        // Build fields to query
        Set<String> fieldsToQuery = new Set<String>{'Id', 'Name', 'CreatedDate', 'LastModifiedDate'};

        // Add additional fields for data preservation
        if (additionalFields != null) {
            fieldsToQuery.addAll(additionalFields);
        }

        // Build the query
        String query = 'SELECT ' + String.join(new List<String>(fieldsToQuery), ', ') +
                       ' FROM ' + objectApiName;

        return Database.getQueryLocator(query);
    }

    /**
     * Find duplicates in a batch of records
     * @param scope Records to check for duplicates
     * @return Map of duplicate groups
     */
    global override Map<String, List<SObject>> findDuplicates(List<SObject> scope) {
        Map<String, List<SObject>> duplicateGroups = new Map<String, List<SObject>>();

        try {
            // Get record IDs
            Set<Id> recordIds = new Set<Id>();
            for (SObject record : scope) {
                recordIds.add(record.Id);
            }

            // Create map for easier access
            Map<Id, SObject> recordsById = new Map<Id, SObject>();
            for (SObject record : scope) {
                recordsById.put(record.Id, record);
            }

            // Find duplicates using DuplicateRecordSet objects
            findDuplicatesUsingDuplicateSets(recordIds, recordsById, duplicateGroups);
            
        } catch (Exception e) {
            logError('Error finding duplicates', e);
        }

        return duplicateGroups;
    }

    /**
     * Process duplicate groups found in batch
     * @param duplicates Map of duplicate groups
     */
    global override void processDuplicates(Map<String, List<SObject>> duplicates) {
        try {
            // Process each duplicate group
            for (String key : duplicates.keySet()) {
                List<SObject> dupGroup = duplicates.get(key);

                // Only process if we have duplicates
                if (dupGroup.size() > 1) {
                    duplicatesFound += (dupGroup.size() - 1);

                    // Skip actual merging if dry run
                    if (!isDryRun) {
                        processDuplicateGroup(dupGroup);
                    }
                }
            }
        } catch (Exception e) {
            logError('Error processing duplicates', e);
        }
    }

    /**
     * Find duplicates using DuplicateRecordSet objects
     * @param recordIds IDs of records to check
     * @param recordsById Map of records by ID
     * @param duplicateGroups Map to store duplicate groups
     */
    private void findDuplicatesUsingDuplicateSets(
        Set<Id> recordIds,
        Map<Id, SObject> recordsById,
        Map<String, List<SObject>> duplicateGroups
    ) {
        // Track duplicates for statistics
        Integer dupesFound = 0;
        
        // Query for duplicate record sets
        List<DuplicateRecordSet> duplicateSets = [
            SELECT Id, DuplicateRuleId,
                (SELECT Id, RecordId FROM DuplicateRecordItems)
            FROM DuplicateRecordSet
            WHERE DuplicateRuleId = :duplicateRuleId
            AND Id IN (
                SELECT DuplicateRecordSetId
                FROM DuplicateRecordItem
                WHERE RecordId IN :recordIds
            )
        ];

        // Process each duplicate set
        for (DuplicateRecordSet drs : duplicateSets) {
            // Get duplicate record IDs
            Set<Id> dupeRecordIds = new Set<Id>();
            for (DuplicateRecordItem dri : drs.DuplicateRecordItems) {
                dupeRecordIds.add(dri.RecordId);
            }

            // Filter to records in our batch
            Set<Id> batchDupeIds = new Set<Id>();
            for (Id dupeId : dupeRecordIds) {
                if (recordIds.contains(dupeId)) {
                    batchDupeIds.add(dupeId);
                }
            }

            // Process if we have at least 2 duplicates in our batch
            if (batchDupeIds.size() > 1) {
                // Increment duplicate count
                dupesFound++;
                
                // Create duplicate group
                List<SObject> dupeGroup = new List<SObject>();
                for (Id dupeId : batchDupeIds) {
                    dupeGroup.add(recordsById.get(dupeId));
                }

                // Find master ID
                SObject master = selectMasterRecord(dupeGroup, 'mostRecent');

                // Add to duplicate groups
                duplicateGroups.put(master.Id, dupeGroup);
            }
        }
        
        // Update batch metrics
        if (dupesFound > 0) {
            duplicatesFound += dupesFound;
        }
    }

    // Method findDuplicatesUsingAPI has been removed to eliminate Datacloud API dependency

    /**
     * Process a group of duplicate records
     * @param recordGroup Duplicate records
     */
    private void processDuplicateGroup(List<SObject> recordGroup) {
        try {
            // Select master record
            SObject master = selectMasterRecord(recordGroup, 'mostRecent');

            // Get duplicates (excluding master)
            List<SObject> duplicates = new List<SObject>();
            for (SObject rec : recordGroup) {
                if (rec.Id != master.Id) {
                    duplicates.add(rec);
                }
            }

            // Skip if no duplicates
            if (duplicates.isEmpty()) return;

            // Process in chunks (Salesforce limit of 2 records per merge)
            List<List<SObject>> chunks = DuplicateServicesUtil.chunkRecords(duplicates, 2);

            for (List<SObject> chunk : chunks) {
                if (performMerge(master, chunk)) {
                    recordsMerged += chunk.size();

                    // Log merge
                    logMerge(master, chunk);
                }
            }
        } catch (Exception e) {
            logError('Error processing duplicate group', e);
        }
    }

    /**
     * Perform merge operation
     * @param master Master record
     * @param duplicates Duplicate records (max 2)
     * @return Whether merge was successful
     */
    private Boolean performMerge(SObject master, List<SObject> duplicates) {
        try {
            // Preserve data in notes before merging
            createDataPreservationNotes(master, duplicates);

            // Get duplicate IDs
            List<Id> dupIds = DuplicateServicesUtil.getRecordIds(duplicates);

            // Perform merge based on number of records
            if (dupIds.size() == 1) {
                Database.merge(master, dupIds[0]);
            } else if (dupIds.size() == 2) {
                Database.merge(master, dupIds);
            }

            return true;
        } catch (Exception e) {
            logError('Error merging records', e);
            return false;
        }
    }

    /**
     * Create notes to preserve data before merging
     * @param master Master record
     * @param duplicates Duplicate records
     */
    private void createDataPreservationNotes(SObject master, List<SObject> duplicates) {
        // Get map of master field values
        Map<String, Object> masterFields = master.getPopulatedFieldsAsMap();
        List<Note> notesToInsert = new List<Note>();

        // Process each duplicate
        for (SObject duplicate : duplicates) {
            // Track conflicts
            Map<String, Object> conflicts = new Map<String, Object>();
            Map<String, Object> dupFields = duplicate.getPopulatedFieldsAsMap();

            // Check additional fields for conflicts
            if (additionalFields != null) {
                for (String field : additionalFields) {
                    // Skip system fields
                    if (isSystemField(field)) continue;

                    // Get values
                    Object dupValue = dupFields.get(field);
                    Object masterValue = masterFields.containsKey(field) ? masterFields.get(field) : null;

                    // Record conflict if values differ and duplicate has non-null value
                    if (dupValue != null && !areEqual(dupValue, masterValue)) {
                        conflicts.put(field, dupValue);
                    }
                }
            }

            // Create note if conflicts exist
            if (!conflicts.isEmpty()) {
                notesToInsert.add(createNoteForConflicts(master.Id, duplicate.Id, conflicts));
            }
        }

        // With ContentNote, linking to records is handled automatically via the parent object's FeedItem record
        // So we simply insert the notes, and the system will take care of sharing
        if (!notesToInsert.isEmpty()) {
            insert notesToInsert;
        }
    }

    /**
     * Create a note for field conflicts
     * @param masterId Master record ID
     * @param duplicateId Duplicate record ID
     * @param conflicts Map of field conflicts
     * @return Note to insert
     */
    private Note createNoteForConflicts(Id masterId, Id duplicateId, Map<String, Object> conflicts) {
        // Build note content
        String title = 'Merge Conflict - Record ' + duplicateId;

        String body = 'The following fields had conflicts when merging record ' +
                     duplicateId + ' into ' + masterId + ':\n\n';

        // Add conflicts
        for (String field : conflicts.keySet()) {
            Object value = conflicts.get(field);
            body += field + ': ' + (value != null ? String.valueOf(value) : 'null') + '\n';
        }

        // Create note
        Note note = new Note();
        note.Title = title;
        note.Body = body;
        note.ParentId = masterId;
        
        return note;
    }

    /**
     * Log merge operation
     * @param master Master record
     * @param duplicates Merged duplicate records
     */
    private void logMerge(SObject master, List<SObject> duplicates) {
        try {
            // Create merge log
            DuplicateServicesUtil.createMergeLog(
                master.Id,
                DuplicateServicesUtil.getRecordIds(duplicates),
                objectApiName,
                batchJobId,
                null,
                null
            );
        } catch (Exception e) {
            logError('Error logging merge', e);
        }
    }

    /**
     * Check if two objects are equal
     * @param a First object
     * @param b Second object
     * @return Whether they're equal
     */
    private Boolean areEqual(Object a, Object b) {
        if (a == null && b == null) return true;
        if (a == null || b == null) return false;
        return String.valueOf(a).equals(String.valueOf(b));
    }

    /**
     * Check if field is a system field
     * @param fieldName Field name
     * @return Whether it's a system field
     */
    private Boolean isSystemField(String fieldName) {
        return (fieldName == 'Id' || fieldName == 'IsDeleted' ||
               fieldName == 'CreatedDate' || fieldName == 'CreatedById' ||
               fieldName == 'LastModifiedDate' || fieldName == 'LastModifiedById' ||
               fieldName == 'SystemModstamp');
    }
}
