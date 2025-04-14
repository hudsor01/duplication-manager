/**
 * Centralized data service for Duplication Manager
 * Provides standardized data access methods for all components
 */
import { sendMessage, MESSAGE_TYPES } from "c/duplicationMessageService";
import { handleError } from "c/duplicationErrorService";

// Apex methods
import getDuplicateRules from "@salesforce/apex/DuplicateController.getDuplicateRules";
import getRecentJobs from "@salesforce/apex/DuplicateController.getRecentJobs";
import getDetailedStatistics from "@salesforce/apex/DuplicateController.getDetailedStatistics";
import runDuplicateJob from "@salesforce/apex/DuplicateController.runDuplicateJob";
import getJobStatus from "@salesforce/apex/DuplicateController.getJobStatus";
import getPreservableFields from "@salesforce/apex/DuplicateController.getPreservableFields";
import getDuplicateGroups from "@salesforce/apex/DuplicateController.getDuplicateGroups";
import getMergeConflicts from "@salesforce/apex/DuplicateController.getMergeConflicts";
import mergeDuplicates from "@salesforce/apex/DuplicateController.mergeDuplicates";

// Cache for data
const cache = {
  duplicateRules: {},
  fields: {},
  statistics: null,
  statisticsTimestamp: null,
  jobs: null,
  jobsTimestamp: null,
  duplicateGroups: {}
};

// Cache TTL in milliseconds
const CACHE_TTL = {
  RULES: 1000 * 60 * 15, // 15 minutes
  FIELDS: 1000 * 60 * 15, // 15 minutes
  STATISTICS: 1000 * 60 * 5, // 5 minutes
  JOBS: 1000 * 60 * 2, // 2 minutes
  GROUPS: 1000 * 60 * 5, // 5 minutes
};

/**
 * Clear all caches
 */
export function clearAllCaches() {
  cache.duplicateRules = {};
  cache.fields = {};
  cache.statistics = null;
  cache.statisticsTimestamp = null;
  cache.jobs = null;
  cache.jobsTimestamp = null;
  cache.duplicateGroups = {};
}

/**
 * Clear a specific cache
 * @param {string} cacheType - Type of cache to clear
 */
export function clearCache(cacheType) {
  switch (cacheType) {
    case "rules":
      cache.duplicateRules = {};
      break;
    case "fields":
      cache.fields = {};
      break;
    case "statistics":
      cache.statistics = null;
      cache.statisticsTimestamp = null;
      break;
    case "jobs":
      cache.jobs = null;
      cache.jobsTimestamp = null;
      break;
    case "groups":
      cache.duplicateGroups = {};
      break;
    default:
      // Clear all by default
      clearAllCaches();
  }
}

/**
 * Get available duplicate rules for an object
 * @param {string} objectName - API name of the object
 * @returns {Promise<Array>} - List of duplicate rules
 */
export function getAvailableDuplicateRules(objectName) {
  // Check cache first
  if (
    cache.duplicateRules[objectName] &&
    cache.duplicateRules[objectName].timestamp > Date.now() - CACHE_TTL.RULES
  ) {
    return Promise.resolve(cache.duplicateRules[objectName].data);
  }

  // Fetch from server
  return getDuplicateRules({ objectName: objectName })
    .then((result) => {
      // Update cache
      cache.duplicateRules[objectName] = {
        data: result,
        timestamp: Date.now(),
      };
      return result;
    })
    .catch((error) => {
      const formattedError = handleError(
        "duplicationDataService",
        "getAvailableDuplicationRules",
        error
      );
      return Promise.reject(formattedError);
    });
}

/**
 * Get available fields for an object
 * @param {string} objectName - API name of the object
 * @returns {Promise<Array>} - List of fields
 */
export function getAvailableFields(objectName) {
  // Check cache first
  if (
    cache.fields[objectName] &&
    cache.fields[objectName].timestamp > Date.now() - CACHE_TTL.FIELDS
  ) {
    return Promise.resolve(cache.fields[objectName].data);
  }

  // Fetch from server
  return getPreservableFields({ objectName: objectName })
    .then((result) => {
      // Update cache
      cache.fields[objectName] = {
        data: result,
        timestamp: Date.now(),
      };
      return result;
    })
    .catch((error) => {
      const formattedError = handleError(
        "duplicationDataService",
        "getAvailableFields",
        error
      );
      return Promise.reject(formattedError);
    });
}

/**
 * Get duplicate statistics
 * @param {string} timeRange - Time range for statistics
 * @returns {Promise<Object>} - Statistics data
 */
export function getStatistics(timeRange) {
  // Broadcast that statistics are loading
  sendMessage(MESSAGE_TYPES.STATISTICS_LOADING, {
    timeRange: timeRange,
  });

  // Check cache (if not forced refresh)
  if (
    cache.statistics &&
    cache.statisticsTimestamp > Date.now() - CACHE_TTL.STATISTICS &&
    cache.statistics.timeRange === timeRange
  ) {
    // Broadcast that statistics are loaded from cache
    sendMessage(MESSAGE_TYPES.STATISTICS_LOADED, {
      timeRange: timeRange,
      statistics: cache.statistics.data,
      timestamp: new Date().toISOString(),
      fromCache: true,
    });

    return Promise.resolve(cache.statistics.data);
  }

  // Fetch from server
  return getDetailedStatistics({ timeRange: timeRange })
    .then((result) => {
      // Update cache
      cache.statistics = {
        data: result,
        timeRange: timeRange,
        timestamp: Date.now(),
      };

      // Broadcast that statistics are loaded
      sendMessage(MESSAGE_TYPES.STATISTICS_LOADED, {
        timeRange: timeRange,
        statistics: result,
        timestamp: new Date().toISOString(),
      });

      return result;
    })
    .catch((error) => {
      const formattedError = handleError(
        "duplicationDataService",
        "getStatistics",
        error
      );

      // Broadcast error
      sendMessage(MESSAGE_TYPES.STATISTICS_LOAD_ERROR, {
        timeRange: timeRange,
        error: formattedError.message,
        timestamp: new Date().toISOString(),
      });

      return Promise.reject(formattedError);
    });
}

/**
 * Get recent duplicate jobs
 * @returns {Promise<Array>} - List of recent jobs
 */
export function getRecentDuplicationJobs() {
  // Check cache
  if (
    cache.jobs &&
    cache.jobsTimestamp > Date.now() - CACHE_TTL.JOBS
  ) {
    return Promise.resolve(cache.jobs.data);
  }

  // Fetch from server
  return getRecentJobs()
    .then((result) => {
      // Update cache
      cache.jobs = {
        data: result,
        timestamp: Date.now(),
      };
      return result;
    })
    .catch((error) => {
      const formattedError = handleError(
        "duplicationDataService",
        "getRecentDuplicationJobs",
        error
      );
      return Promise.reject(formattedError);
    });
}

/**
 * Run a duplicate detection job
 * @param {Object} config - Job configuration
 * @returns {Promise<string>} - Job ID
 */
export function runDuplication(config) {
  return runDuplicateJob(config)
    .then((jobId) => {
      // Clear jobs cache to ensure fresh data
      clearCache("jobs");

      // Broadcast job started message
      sendMessage(MESSAGE_TYPES.JOB_STARTED, {
        jobId: jobId,
        config: config,
        timestamp: new Date().toISOString(),
      });

      return jobId;
    })
    .catch((error) => {
      const formattedError = handleError(
        "duplicationDataService",
        "runDuplication",
        error
      );
      return Promise.reject(formattedError);
    });
}

/**
 * Check status of a duplicate job
 * @param {string} jobId - ID of the job to check
 * @returns {Promise<Object>} - Job status
 */
export function checkJobStatus(jobId) {
  return getJobStatus({ jobId: jobId })
    .then((status) => {
      // If job completed, clear jobs cache
      if (
        status.status === "Completed" ||
        status.status === "Failed" ||
        status.status === "Aborted"
      ) {
        clearCache("jobs");

        // Broadcast job completion
        sendMessage(MESSAGE_TYPES.JOB_COMPLETED, {
          jobId: jobId,
          status: status,
          timestamp: new Date().toISOString(),
        });
      }

      return status;
    })
    .catch((error) => {
      const formattedError = handleError(
        "duplicationDataService",
        "checkJobStatus",
        error
      );
      return Promise.reject(formattedError);
    });
}

/**
 * Get duplicate groups for a run result
 * @param {string} runResultId - ID of the run result
 * @returns {Promise<Array>} - List of duplicate groups
 */
export function getDuplicateGroupsForResult(runResultId) {
  // Check cache
  if (
    cache.duplicateGroups[runResultId] &&
    cache.duplicateGroups[runResultId].timestamp > Date.now() - CACHE_TTL.GROUPS
  ) {
    return Promise.resolve(cache.duplicateGroups[runResultId].data);
  }

  // Fetch from server
  return getDuplicateGroups({ runResultId: runResultId })
    .then((result) => {
      // Update cache
      cache.duplicateGroups[runResultId] = {
        data: result,
        timestamp: Date.now(),
      };
      return result;
    })
    .catch((error) => {
      const formattedError = handleError(
        "duplicationDataService",
        "getDuplicateGroupsForResult",
        error
      );
      return Promise.reject(formattedError);
    });
}

/**
 * Get merge conflicts between records
 * @param {string} masterId - ID of the master record
 * @param {Array<string>} duplicateIds - IDs of duplicate records
 * @returns {Promise<Object>} - Merge conflicts
 */
export function getMergeConflictsForRecords(masterId, duplicateIds) {
  return getMergeConflicts({
    masterId: masterId,
    duplicateIds: duplicateIds,
  })
    .then((result) => {
      return result;
    })
    .catch((error) => {
      const formattedError = handleError(
        "duplicationDataService",
        "getMergeConflictsForRecords",
        error
      );
      return Promise.reject(formattedError);
    });
}

/**
 * Merge duplicate records
 * @param {string} masterId - ID of the master record
 * @param {Array<string>} duplicateIds - IDs of duplicate records
 * @param {Object} fieldSelections - Field selections for merge conflicts
 * @returns {Promise<Object>} - Merge result
 */
export function mergeDuplicateRecords(masterId, duplicateIds, fieldSelections) {
  return mergeDuplicates({
    masterId: masterId,
    duplicateIds: duplicateIds,
    fieldSelections: fieldSelections,
  })
    .then((result) => {
      // Clear caches that might be affected
      clearCache("statistics");
      clearCache("jobs");
      clearCache("groups");

      // Broadcast merge completed
      sendMessage(MESSAGE_TYPES.MERGE_COMPLETED, {
        masterId: masterId,
        duplicateIds: duplicateIds,
        result: result,
        timestamp: new Date().toISOString(),
      });

      return result;
    })
    .catch((error) => {
      const formattedError = handleError(
        "duplicationDataService",
        "mergeDuplicateRecords",
        error
      );

      // Broadcast merge error
      sendMessage(MESSAGE_TYPES.MERGE_ERROR, {
        masterId: masterId,
        duplicateIds: duplicateIds,
        error: formattedError.message,
        timestamp: new Date().toISOString(),
      });

      return Promise.reject(formattedError);
    });
}
