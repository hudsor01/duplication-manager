/**
 * Service class for duplicate Manager statistics
 * Provides centralized methods for statistics generation
 *
 * @author Richard Hudson
 * @date April 2025
 */
public with sharing class DuplicateStatisticsService {

    /**
     * Get detailed statistics for the dashboard
     * @param timeRange Time range to include
     * @return Map of statistics data
     */
    public static Map<String, Object> getDetailedStatistics(String timeRange) {
        Map<String, Object> result = new Map<String, Object>();

        try {
            // Get date range
            Datetime startDate = getStartDateForRange(timeRange);

            // Overall stats
            Integer totalDuplicatesFound = 0;
            Integer totalRecordsMerged = 0;

            // Stats by object
            Map<String, Map<String, Object>> statsByObject = new Map<String, Map<String, Object>>();

            // Query job statistics
            List<duplicateJobStatistic__c> stats = [
                SELECT Id, ObjectApiName__c, DuplicatesFound__c, RecordsMerged__c, RecordsProcessed__c,
                       JobStartTime__c, JobCompletionTime__c, Status__c, IsDryRun__c, ProcessingTimeMs__c
                FROM duplicateJobStatistic__c
                WHERE JobStartTime__c >= :startDate
                AND Status__c = 'Completed'
                ORDER BY JobStartTime__c DESC
            ];

            // Process job statistics
            for (duplicateJobStatistic__c stat : stats) {
                String objectName = stat.ObjectApiName__c;

                // Add to overall stats
                totalDuplicatesFound += Integer.valueOf(stat.DuplicatesFound__c);

                if (!stat.IsDryRun__c) {
                    totalRecordsMerged += Integer.valueOf(stat.RecordsMerged__c);
                }

                // Add to object stats
                if (!statsByObject.containsKey(objectName)) {
                    statsByObject.put(objectName, new Map<String, Object>{
                        'totalDuplicates' => 0,
                        'totalMerged' => 0,
                        'totalProcessed' => 0,
                        'jobCount' => 0,
                        'averageProcessingTime' => 0
                    });
                }

                Map<String, Object> objStats = statsByObject.get(objectName);

                // Update object stats
                objStats.put('totalDuplicates',
                    Integer.valueOf(objStats.get('totalDuplicates')) + Integer.valueOf(stat.DuplicatesFound__c));

                if (!stat.IsDryRun__c) {
                    objStats.put('totalMerged',
                        Integer.valueOf(objStats.get('totalMerged')) + Integer.valueOf(stat.RecordsMerged__c));
                }

                objStats.put('totalProcessed',
                    Integer.valueOf(objStats.get('totalProcessed')) + Integer.valueOf(stat.RecordsProcessed__c));

                objStats.put('jobCount', Integer.valueOf(objStats.get('jobCount')) + 1);

                // Update average processing time
                if (stat.ProcessingTimeMs__c != null) {
                    Integer jobCount = Integer.valueOf(objStats.get('jobCount'));
                    Decimal currentAvg = Decimal.valueOf(String.valueOf(objStats.get('averageProcessingTime')));
                    Decimal newAvg = ((currentAvg * (jobCount - 1)) + stat.ProcessingTimeMs__c) / jobCount;
                    objStats.put('averageProcessingTime', newAvg);
                }
            }

            // Get recent merges
            List<DuplicateMergeLog__c> recentMerges = [
                SELECT Id, MasterId__c, MergedIds__c, ObjectApiName__c, MergeTime__c,
                       FieldMergeDetails__c, UserId__c, MatchScore__c
                FROM DuplicateMergeLog__c
                WHERE MergeTime__c >= :startDate
                ORDER BY MergeTime__c DESC
                LIMIT 10
            ];

            // Build result map
            result.put('totalDuplicates', totalDuplicatesFound);
            result.put('totalMerged', totalRecordsMerged);
            result.put('byObject', statsByObject);
            result.put('recentMerges', recentMerges);

            // Add time range info
            result.put('timeRange', timeRange);
            result.put('startDate', startDate);
            result.put('endDate', Datetime.now());

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting statistics: ' + e.getMessage());
            throw e;
        }

        return result;
    }

    /**
     * Get start date for a time range
     * @param timeRange Time range string
     * @return Start date
     */
    private static Datetime getStartDateForRange(String timeRange) {
        Datetime now = Datetime.now();

        if (timeRange == 'LAST_7_DAYS') {
            return now.addDays(-7);
        } else if (timeRange == 'LAST_30_DAYS') {
            return now.addDays(-30);
        } else if (timeRange == 'LAST_90_DAYS') {
            return now.addDays(-90);
        } else if (timeRange == 'THIS_YEAR') {
            return Datetime.newInstance(now.year(), 1, 1, 0, 0, 0);
        } else if (timeRange == 'ALL') {
            return Datetime.newInstance(1900, 1, 1, 0, 0, 0);
        } else {
            // Default to last 30 days
            return now.addDays(-30);
        }
    }
}
