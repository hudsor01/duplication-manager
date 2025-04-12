/**
 * @description Class for retrieving statistics for duplicates found and merged
 * @author Richard Hudson
 * @date 2025-04-11
 */
public with sharing class DRSCStats {
    /**
     * @description Static method for retrieving statistics for duplicates found and merged during a specific time period
     * 
     * @param timeRange String identifying the time range (TODAY, YESTERDAY, etc.)
     * @return Map<String, Object> Statistics for the specified time range
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getDuplicateStatistics(String timeRange) {
        Map<String, Object> stats = new Map<String, Object>();

        try {
            // Default time range if not provided
            if (String.isBlank(timeRange)) {
                timeRange = 'LAST_30_DAYS';
            }

            // Get date range
            Date startDate = DRSCDate.getStartDateForRange(timeRange);
            Date endDate = Date.today();

            // Records found stats - from DuplicateJobStatistic__c
            Integer duplicatesFound = 0;
            Double duplicatesTrend = 0;

            // Verify object and field-level security
            if (!Schema.sObjectType.DuplicateJobStatistic__c.isAccessible() ||
                !Schema.sObjectType.DuplicateJobStatistic__c.fields.DuplicatesFound__c.isAccessible() ||
                !Schema.sObjectType.DuplicateJobStatistic__c.fields.JobCompletionTime__c.isAccessible()) {
                throw new AuraHandledException('Insufficient access to DuplicateJobStatistic__c object or fields');
            }
            
            // Calculate duplicates found using bind variables for security
            String foundQuery = 'SELECT SUM(DuplicatesFound__c) foundCount FROM DuplicateJobStatistic__c';
            if (startDate != null) {
                foundQuery += ' WHERE JobCompletionTime__c >= :startDate AND JobCompletionTime__c <= :endDate';
            }

            // Using bind variables (startDate and endDate) prevents SOQL injection
            AggregateResult[] foundResults = Database.query(foundQuery);
            if (foundResults != null && !foundResults.isEmpty() && foundResults[0].get('foundCount') != null) {
                duplicatesFound = Integer.valueOf(foundResults[0].get('foundCount'));
            }

            // Records merged stats - from DuplicateMergeLog__c
            Integer recordsMerged = 0;
            Double mergesTrend = 0;

            // Verify object and field-level security for DuplicateMergeLog__c
            if (!Schema.sObjectType.DuplicateMergeLog__c.isAccessible() ||
                !Schema.sObjectType.DuplicateMergeLog__c.fields.MergeTime__c.isAccessible()) {
                throw new AuraHandledException('Insufficient access to DuplicateMergeLog__c object or fields');
            }
            
            // Calculate records merged using bind variables for security
            String mergedQuery = 'SELECT COUNT() FROM DuplicateMergeLog__c';
            if (startDate != null) {
                mergedQuery += ' WHERE MergeTime__c >= :startDate AND MergeTime__c <= :endDate';
            }

            // Database.countQuery with bind variables prevents SOQL injection
            recordsMerged = Database.countQuery(mergedQuery);

            // Calculate trends - compare to previous period
            if (startDate != null) {
                Date previousStartDate = startDate.addDays(-1 * (endDate.daysBetween(startDate)));
                Date previousEndDate = startDate.addDays(-1);

                // Previous duplicates found - using bind variables for security
                // Object security was already validated above
                String prevFoundQuery = 'SELECT SUM(DuplicatesFound__c) foundCount FROM DuplicateJobStatistic__c ' +
                                       'WHERE JobCompletionTime__c >= :previousStartDate AND JobCompletionTime__c <= :previousEndDate';

                // Using bind variables (previousStartDate and previousEndDate) prevents SOQL injection
                AggregateResult[] prevFoundResults = Database.query(prevFoundQuery);
                Integer prevDuplicatesFound = 0;

                if (prevFoundResults != null && !prevFoundResults.isEmpty() && prevFoundResults[0].get('foundCount') != null) {
                    prevDuplicatesFound = Integer.valueOf(prevFoundResults[0].get('foundCount'));
                }

                // Previous records merged - using bind variables for security
                // Object security was already validated above
                String prevMergedQuery = 'SELECT COUNT() FROM DuplicateMergeLog__c ' +
                                        'WHERE MergeTime__c >= :previousStartDate AND MergeTime__c <= :previousEndDate';

                // Database.countQuery with bind variables prevents SOQL injection
                Integer prevRecordsMerged = Database.countQuery(prevMergedQuery);

                // Calculate percentage change
                if (prevDuplicatesFound > 0) {
                    duplicatesTrend = ((duplicatesFound - prevDuplicatesFound) / (Double)prevDuplicatesFound) * 100;
                }

                if (prevRecordsMerged > 0) {
                    mergesTrend = ((recordsMerged - prevRecordsMerged) / (Double)prevRecordsMerged) * 100;
                }
            }

            // Set results
            stats.put('duplicatesFound', duplicatesFound);
            stats.put('recordsMerged', recordsMerged);
            stats.put('duplicatesTrend', duplicatesTrend);
            stats.put('mergesTrend', mergesTrend);
            stats.put('timeRange', timeRange);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting duplicate statistics: ' + e.getMessage());
            throw new AuraHandledException('Error getting duplicate statistics: ' + e.getMessage());
        }

        return stats;
    }
}