/**
 * Centralized error handling service for duplicate Manager
 * Provides standardized error handling methods for all components
 */
import { sendMessage } from "c/duplicationMessageService";
import { MESSAGE_TYPES } from "c/duplicationConstants";

// Error severity levels
export const ERROR_LEVELS = {
  INFO: "info",
  WARNING: "warning",
  ERROR: "error",
  CRITICAL: "critical"
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
  UNKNOWN: "unknown"
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
    broadcast: true,
    context: {},
    recoveryAction: null,
    ...options
  };

  // Format the error with context
  const formattedError = formatError(source, operation, error, config);

  // Log the error for debugging
  logError(formattedError);

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
    type: errorType
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
 * Broadcast error to other components via LMS
 * @private
 */
function broadcastError(error) {
  sendMessage(MESSAGE_TYPES.ERROR_OCCURRED, error);
}

/**
 * Generate a unique ID for the error
 * @private
 */
function generateErrorId() {
  return "err_" + Date.now() + "_" + Math.random().toString(36).substr(2, 9);
}

/**
 * Sanitize error messages to prevent leaking sensitive information
 * @param {String} message - Error message to sanitize
 * @returns {String} Sanitized message
 */
export function sanitizeErrorMessage(message) {
  if (!message) return "";

  // Convert to string if not already
  const strMessage = String(message);

  // Remove any potential tokens, session IDs, or sensitive data patterns
  return strMessage
    .replace(
      /Bearer [a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]+/g,
      "Bearer [REDACTED]"
    )
    .replace(/[a-zA-Z0-9]{20,}/g, "[REDACTED_ID]")
    .replace(/password(=|:).+?($|&|"|')/gi, "password=[REDACTED]$1")
    .replace(/token(=|:).+?($|&|"|')/gi, "token=[REDACTED]$1")
    .replace(/key(=|:).+?($|&|"|')/gi, "key=[REDACTED]$1")
    .substring(0, 150); // Limit length
}

/**
 * Standard recovery actions for common error scenarios
 */
export const RECOVERY_ACTIONS = {
  /**
   * Retry a failed operation
   * @param {function} operation - Function to retry
   * @param {number} maxAttempts - Maximum retry attempts
   */
  retry(operation, maxAttempts = 3) {
    let attempts = 0;

    return () => {
      attempts++;

      if (attempts > maxAttempts) {
        return Promise.reject(
          new Error(`Maximum retry attempts (${maxAttempts}) exceeded`)
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
  }
};
