/**
 * Batch class for finding duplicates using Salesforce standard duplicate rules
 * 
 * @author Richard Hudson
 * @date April 2025
 */
public class DuplicateRuleFinderBatch extends DuplicateBaseBatch {
    
    private String duplicateRuleId;
    private List<String> additionalFields;
    
    /**
     * Constructor with all parameters
     * 
     * @param objectName API name of the object to process
     * @param duplicateRuleId ID of the duplicate rule to use
     * @param additionalFields Additional fields to query beyond the minimum required
     * @param isDryRun Whether to perform a dry run (find only, no merge)
     */
    public DuplicateRuleFinderBatch(
        String objectName,
        String duplicateRuleId,
        List<String> additionalFields,
        Boolean isDryRun
    ) {
        super(objectName, isDryRun, 200, 'Standard Duplicate Rule');
        this.duplicateRuleId = duplicateRuleId;
        this.additionalFields = additionalFields;
    }
    
    /**
     * Build query locator for the batch
     */
    public override Database.QueryLocator buildQueryLocator() {
        // Build fields to query
        Set<String> fieldsToQuery = new Set<String>{'Id', 'Name', 'CreatedDate', 'LastModifiedDate'};
        
        // Add additional fields for preservation
        if (additionalFields != null) {
            fieldsToQuery.addAll(additionalFields);
        }
        
        // Build query
        String query = 'SELECT ' + String.join(new List<String>(fieldsToQuery), ', ') + 
                      ' FROM ' + objectApiName;
        
        return Database.getQueryLocator(query);
    }
    
    /**
     * Find duplicates using Salesforce duplicate rules
     */
    public override Map<String, List<SObject>> findDuplicates(List<SObject> scope) {
        Map<String, List<SObject>> duplicateGroups = new Map<String, List<SObject>>();
        
        try {
            // Use Salesforce's duplicate rule detection
            List<Datacloud.FindDuplicatesResult> results = Datacloud.FindDuplicates.findDuplicates(scope);
            
            // Process duplicate results
            for (Integer i = 0; i < results.size(); i++) {
                Datacloud.FindDuplicatesResult findDupeResult = results[i];
                SObject record = scope[i];
                
                for (Datacloud.DuplicateResult dupeResult : findDupeResult.getDuplicateResults()) {
                    // Skip if wrong duplicate rule
                    if (duplicateRuleId != null && dupeResult.getDuplicateRule() != duplicateRuleId) {
                        continue;
                    }
                    
                    // Process each duplicate group
                    for (Datacloud.MatchResult matchResult : dupeResult.getMatchResults()) {
                        String groupKey = 'Group_' + dupeResult.getDuplicateRule() + '_' + matchResult.getRule() + '_' + i;
                        
                        if (!duplicateGroups.containsKey(groupKey)) {
                            duplicateGroups.put(groupKey, new List<SObject>());
                            // Add the original record to the group
                            duplicateGroups.get(groupKey).add(record);
                        }
                        
                        // Add matched records to the group
                        for (Datacloud.MatchRecord matchRecord : matchResult.getMatchRecords()) {
                            SObject matchedRecord = matchRecord.getRecord();
                            duplicateGroups.get(groupKey).add(matchedRecord);
                        }
                    }
                }
            }
            
            // Filter out groups with only one record
            for (String key : duplicateGroups.keySet().clone()) {
                if (duplicateGroups.get(key).size() <= 1) {
                    duplicateGroups.remove(key);
                }
            }
        } catch (Exception e) {
            logError('Error finding duplicates', e);
        }
        
        return duplicateGroups;
    }
    
    /**
     * Process duplicate groups
     */
    public override void processDuplicates(Map<String, List<SObject>> duplicateGroups) {
        // Process each duplicate group
        for (String groupKey : duplicateGroups.keySet()) {
            List<SObject> dupeGroup = duplicateGroups.get(groupKey);
            
            if (dupeGroup.size() <= 1) {
                continue;
            }
            
            // Count duplicates found
            duplicatesFound += (dupeGroup.size() - 1);
            
            // Create a duplicate group record for reporting
            SObject masterRecord = selectMasterRecord(dupeGroup, 'OldestCreated');
            Decimal matchScore = 100; // Standard duplicate rule matches are high confidence
            Id groupId = createDuplicateGroup(dupeGroup, masterRecord, matchScore);
            
            // If not a dry run, process the duplicates by merging or logging
            if (!isDryRun && masterRecord != null) {
                try {
                    // Merge the duplicates
                    mergeDuplicates(masterRecord, dupeGroup, groupId);
                } catch (Exception e) {
                    logError('Error processing duplicate group', e);
                }
            }
        }
    }
    
    /**
     * Merge duplicate records
     */
    private void mergeDuplicates(SObject masterRecord, List<SObject> duplicates, Id groupId) {
        try {
            // Get master record ID
            Id masterId = (Id)masterRecord.get('Id');
            
            // Get records to merge
            List<Id> recordsToMerge = new List<Id>();
            for (SObject rec : duplicates) {
                Id recId = (Id)rec.get('Id');
                if (recId != masterId) {
                    recordsToMerge.add(recId);
                }
            }
            
            // Skip if nothing to merge
            if (recordsToMerge.isEmpty()) {
                return;
            }
            
            // Use merge service to merge records
            DuplicateRecordUtility.mergeRecords(objectApiName, masterId, recordsToMerge);
            
            // Update counts
            recordsMerged += recordsToMerge.size();
            
            // Log merge activity
            logMergeActivity(masterId, recordsToMerge, groupId);
            
        } catch (Exception e) {
            logError('Error merging duplicates', e);
        }
    }
    
    /**
     * Log merge activity
     */
    private void logMergeActivity(Id masterId, List<Id> mergedIds, Id groupId) {
        try {
            DuplicateMergeLog__c log = new DuplicateMergeLog__c(
                JobId__c = batchJobId,
                MasterId__c = masterId,
                MergedIds__c = String.join(mergedIds, ','),
                ObjectApiName__c = objectApiName,
                MergeTime__c = System.now(),
                UserId__c = UserInfo.getUserId()
            );
            
            insert log;
            
        } catch (Exception e) {
            logError('Error logging merge activity', e);
        }
    }
}