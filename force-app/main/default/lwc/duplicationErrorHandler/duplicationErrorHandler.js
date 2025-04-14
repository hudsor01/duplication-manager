/**
 * Centralized error handling utility for the duplicate Manager application
 * Provides standardized error formatting, logging, recovery, and user notification
 */
import { sendMessage } from "c/duplicationMessageService";
import { MESSAGE_TYPES } from "c/duplicationConstants";
import store, { duplicationStore } from "c/duplicationStore";

// Error severity levels
export const ERROR_LEVELS = {
  INFO: "info",
  WARNING: "warning",
  ERROR: "error",
  CRITICAL: "critical",
};

// Error categories
export const ERROR_CATEGORIES = {
  CONFIGURATION: "configuration",
  DATA: "data",
  NETWORK: "network",
  PERMISSIONS: "permissions",
  SYSTEM: "system",
  VALIDATION: "validation",
  APEX: "apex",
  UNKNOWN: "unknown",
};

/**
 * Process and handle an error
 * @param {string} source - Component or function where error occurred
 * @param {string} operation - Operation being performed when error occurred
 * @param {Error|object|string} error - The error object or message
 * @param {object} options - Additional options for error handling
 * @returns {object} Processed error with context
 */
export function handleError(source, operation, error, options = {}) {
  // Default options
  const config = {
    level: ERROR_LEVELS.ERROR,
    category: ERROR_CATEGORIES.UNKNOWN,
    notify: true,
    store: true,
    broadcast: true,
    context: {},
    recoveryAction: null,
    ...options,
  };

  // Format the error with context
  const formattedError = formatError(source, operation, error, config);

  // Log the error for debugging
  logError(formattedError);

  // Store in global error state if configured
  if (config.store) {
    storeError(formattedError);
  }

  // Broadcast to other components if configured
  if (config.broadcast) {
    broadcastError(formattedError);
  }

  // Return the formatted error for component use
  return formattedError;
}

/**
 * Format an error with standard structure
 * @private
 */
function formatError(source, operation, error, config) {
  // Extract error message based on error type
  let errorMessage = "";
  let errorDetails = {};
  let errorType = "";

  if (typeof error === "string") {
    errorMessage = error;
  } else if (error instanceof Error) {
    errorMessage = error.message;
    errorDetails.stack = error.stack;
    errorType = error.name;
  } else if (error && error.body && error.body.message) {
    // Salesforce Apex error
    errorMessage = error.body.message;
    errorDetails.statusCode = error.statusCode;
    errorDetails.body = error.body;
    config.category = ERROR_CATEGORIES.APEX;
  } else if (error && typeof error === "object") {
    errorMessage = error.message || JSON.stringify(error);
    errorDetails = { ...error };
  } else {
    errorMessage = "Unknown error occurred";
  }

  // Format with standard structure
  return {
    id: generateErrorId(),
    source: source,
    operation: operation,
    message: errorMessage,
    details: errorDetails,
    level: config.level,
    category: config.category,
    context: config.context,
    timestamp: new Date().toISOString(),
    recoveryAction: config.recoveryAction,
    type: errorType,
  };
}

/**
 * Log error to console with formatting
 * @private
 */
function logError(error) {
  const logMsg = `[${error.level.toUpperCase()}] ${error.source} - ${error.operation}: ${error.message}`;

  switch (error.level) {
    case ERROR_LEVELS.INFO:
      console.info(logMsg, error);
      break;
    case ERROR_LEVELS.WARNING:
      console.warn(logMsg, error);
      break;
    case ERROR_LEVELS.CRITICAL:
      console.error("CRITICAL ERROR: " + logMsg, error);
      break;
    case ERROR_LEVELS.ERROR:
    default:
      console.error(logMsg, error);
  }
}

/**
 * Store error in application state
 * @private
 */
function storeError(error) {
  if (store && duplicationStore && duplicationStore.actions) {
    store.dispatch(duplicationStore.actions.ADD_ERROR, error);
  }
}

/**
 * Broadcast error to other components via LMS
 * @private
 */
function broadcastError(error) {
  sendMessage(MESSAGE_TYPES.JOB_ERROR, error);
}

/**
 * Generate a unique ID for the error
 * @private
 */
function generateErrorId() {
  return "err_" + Date.now() + "_" + Math.random().toString(36).substr(2, 9);
}

/**
 * Attempt to recover from a known error type
 * @param {object} error - Formatted error object
 * @returns {Promise} - Promise that resolves with recovery result
 */
export function attemptRecovery(error) {
  if (!error || !error.recoveryAction) {
    return Promise.reject(new Error("No recovery action defined"));
  }

  // Execute the recovery action
  return error.recoveryAction(error);
}

/**
 * Check if an error is recoverable
 * @param {object} error - Formatted error object
 * @returns {boolean} - Whether error has a recovery action
 */
export function isRecoverable(error) {
  return error && typeof error.recoveryAction === "function";
}

/**
 * Create standard recovery actions for common error scenarios
 */
export const RECOVERY_ACTIONS = {
  /**
   * Retry a failed operation
   * @param {function} operation - Function to retry
   * @param {number} maxAttempts - Maximum retry attempts
   * @param {number} delayMs - Delay between attempts in milliseconds
   */
  retry(operation, maxAttempts = 3) {
    let attempts = 0;

    return () => {
      attempts++;

      if (attempts > maxAttempts) {
        return Promise.reject(
          new Error(`Maximum retry attempts (${maxAttempts}) exceeded`),
        );
      }

      return new Promise((resolve) => {
        // Use Promise.resolve instead of setTimeout to avoid LWC restrictions
        Promise.resolve().then(() => {
          resolve(operation());
        });
      });
    };
  },

  /**
   * Fallback to a default value
   * @param {*} defaultValue - Default value to use if operation fails
   */
  fallback(defaultValue) {
    return () => Promise.resolve(defaultValue);
  },

  /**
   * Reset application state
   */
  resetState() {
    return () => {
      // Reset store state
      store.dispatch(duplicationStore.actions.RESET_STATE);
      return Promise.resolve({
        success: true,
        message: "Application state reset",
      });
    };
  },
};
