/**
 * Utility for monitoring and managing Salesforce governor limits
 * Used to prevent limit exceptions in batch and queueable processing
 *
 * @author Richard Hudson
 * @date April 2025
 */
public without sharing class DuplicateLimitUtil {
    
    /**
     * Check if any limits are approaching thresholds
     * @return True if safe to continue, false if approaching limits
     */
    public static Boolean isSafeToProcess() {
        // Check all critical limits
        return isCpuLimitSafe() && 
               isHeapLimitSafe() && 
               isQueryLimitSafe() && 
               isDmlLimitSafe();
    }
    
    /**
     * Check if CPU time limit is safe
     * @return True if safe, false if approaching limit
     */
    public static Boolean isCpuLimitSafe() {
        Long cpuTime = Limits.getCpuTime();
        Long cpuLimit = Limits.getLimitCpuTime();
        
        // Log usage if approaching limit
        if ((Decimal)cpuTime / cpuLimit > 0.5) {
            DuplicateLogger.info('DuplicateLimitUtil', 'CPU time usage: ' + cpuTime + ' of ' + cpuLimit);
        }
        
        return cpuTime < cpuLimit * DuplicateConstants.CPU_USAGE_THRESHOLD;
    }
    
    /**
     * Check if heap size limit is safe
     * @return True if safe, false if approaching limit
     */
    public static Boolean isHeapLimitSafe() {
        Long heapSize = Limits.getHeapSize();
        Long heapLimit = Limits.getLimitHeapSize();
        
        // Log usage if approaching limit
        if ((Decimal)heapSize / heapLimit > 0.5) {
            DuplicateLogger.info('DuplicateLimitUtil', 'Heap usage: ' + heapSize + ' of ' + heapLimit);
        }
        
        return heapSize < heapLimit * DuplicateConstants.HEAP_USAGE_THRESHOLD;
    }
    
    /**
     * Check if SOQL query limit is safe
     * @return True if safe, false if approaching limit
     */
    public static Boolean isQueryLimitSafe() {
        Integer queries = Limits.getQueries();
        Integer queryLimit = Limits.getLimitQueries();
        
        return queries < queryLimit * DuplicateConstants.QUERY_USAGE_THRESHOLD;
    }
    
    /**
     * Check if DML limit is safe
     * @return True if safe, false if approaching limit
     */
    public static Boolean isDmlLimitSafe() {
        Integer dmlRows = Limits.getDmlRows();
        Integer dmlRowLimit = Limits.getLimitDmlRows();
        
        Integer dmlStmts = Limits.getDmlStatements();
        Integer dmlStmtLimit = Limits.getLimitDmlStatements();
        
        return dmlRows < dmlRowLimit * DuplicateConstants.DML_USAGE_THRESHOLD
            && dmlStmts < dmlStmtLimit * DuplicateConstants.DML_USAGE_THRESHOLD;
    }
    
    /**
     * Get a summary of current limit usage
     * @return String containing limit usage information
     */
    public static String getLimitUsageSummary() {
        return 'CPU: ' + Limits.getCpuTime() + '/' + Limits.getLimitCpuTime() 
             + ', Heap: ' + Limits.getHeapSize() + '/' + Limits.getLimitHeapSize()
             + ', SOQL: ' + Limits.getQueries() + '/' + Limits.getLimitQueries()
             + ', DML: ' + Limits.getDmlStatements() + '/' + Limits.getLimitDmlStatements()
             + ', DML Rows: ' + Limits.getDmlRows() + '/' + Limits.getLimitDmlRows();
    }
    
    /**
     * Cleanup memory where possible
     * Better approach than the naive implementation in DuplicateRecordBatch
     */
    public static void cleanupMemory() {
        // While we can't force garbage collection, we can help it along
        // by nulling out static variables where possible
        
        // Log memory usage before cleanup attempt
        Long beforeHeap = Limits.getHeapSize();
        DuplicateLogger.debug('DuplicateLimitUtil', 'Heap before cleanup: ' + beforeHeap);
        
        // Run garbage collection strategy
        // Note: This doesn't guarantee GC, but can help
        DuplicateMatcherUtility.resetCache();
        
        // Log after attempted cleanup
        Long afterHeap = Limits.getHeapSize();
        DuplicateLogger.debug('DuplicateLimitUtil', 
                           'Heap after cleanup: ' + afterHeap + 
                           ' (Change: ' + (beforeHeap - afterHeap) + ')');
    }
}