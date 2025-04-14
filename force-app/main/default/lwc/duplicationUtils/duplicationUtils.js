/**
 * Utility functions for the duplicate Manager application
 * Centralizes common operations used across components
 *
 * @author Richard Hudson
 * @since April 2025
 */

/**
 * Format an error into a standardized structure
 * @param {String} baseMessage - Base error message
 * @param {Object} error - Error object from API call or exception
 * @returns {Object} Standardized error object
 */
export const formatError = (baseMessage, error) => {
  let errorDetails = "";

  // Extract error details
  if (error) {
    if (error.body && error.body.message) {
      errorDetails = error.body.message;
    } else if (error.message) {
      errorDetails = error.message;
    } else {
      errorDetails = JSON.stringify(error);
    }
  }

  // Create structured error object
  return {
    message: baseMessage,
    details: errorDetails,
    timestamp: new Date().toISOString(),
    type: error && error.type ? error.type : "general",
    id: `err-${Date.now()}-${Math.floor(Math.random() * 1000)}`
  };
};

/**
 * Check if localStorage is available and working
 * @returns {Boolean} True if localStorage is available
 */
export const isLocalStorageAvailable = () => {
  try {
    const test = "test";
    localStorage.setItem(test, test);
    localStorage.removeItem(test);
    return true;
  } catch (e) {
    return false;
  }
};

/**
 * Format a date for display
 * @param {String|Date} date - Date to format
 * @param {Boolean} includeTime - Whether to include time in the format
 * @returns {String} Formatted date string
 */
export const formatDate = (date, includeTime = false) => {
  if (!date) {
    return "";
  }

  const dateObj = date instanceof Date ? date : new Date(date);

  if (isNaN(dateObj.getTime())) {
    return "";
  }

  const options = {
    year: "numeric",
    month: "short",
    day: "numeric"
  };

  if (includeTime) {
    options.hour = "2-digit";
    options.minute = "2-digit";
  }

  return dateObj.toLocaleString(undefined, options);
};

/**
 * Format a number with commas
 * @param {Number} number - Number to format
 * @returns {String} Formatted number string
 */
export const formatNumber = (number) => {
  if (number === null || number === undefined) {
    return "0";
  }

  return number.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
};

/**
 * Calculate percentage from two numbers
 * @param {Number} part - The numerator
 * @param {Number} total - The denominator
 * @param {Number} decimals - Number of decimal places to include
 * @returns {Number} Calculated percentage
 */
export const calculatePercentage = (part, total, decimals = 1) => {
  if (!total || total === 0) {
    return 0;
  }

  const percentage = (part / total) * 100;
  return Number(percentage.toFixed(decimals));
};

/**
 * Truncate a string to a maximum length with ellipsis
 * @param {String} str - String to truncate
 * @param {Number} maxLength - Maximum length before truncation
 * @returns {String} Truncated string
 */
export const truncateString = (str, maxLength = 100) => {
  if (!str || str.length <= maxLength) {
    return str;
  }

  return str.substring(0, maxLength) + "...";
};

/**
 * Deep clone an object
 * @param {Object} obj - Object to clone
 * @returns {Object} Cloned object
 */
export const deepClone = (obj) => {
  return JSON.parse(JSON.stringify(obj));
};

/**
 * Get relative time description (e.g., "2 hours ago")
 * @param {String|Date} timestamp - Timestamp to format
 * @returns {String} Relative time description
 */
export const getRelativeTimeDescription = (timestamp) => {
  if (!timestamp) {
    return "";
  }

  const now = new Date();
  const date = timestamp instanceof Date ? timestamp : new Date(timestamp);

  if (isNaN(date.getTime())) {
    return "";
  }

  const diffMs = now - date;
  const diffSec = Math.floor(diffMs / 1000);
  const diffMin = Math.floor(diffSec / 60);
  const diffHr = Math.floor(diffMin / 60);
  const diffDays = Math.floor(diffHr / 24);

  if (diffSec < 60) {
    return "just now";
  } else if (diffMin < 60) {
    return `${diffMin} minute${diffMin !== 1 ? "s" : ""} ago`;
  } else if (diffHr < 24) {
    return `${diffHr} hour${diffHr !== 1 ? "s" : ""} ago`;
  } else if (diffDays < 7) {
    return `${diffDays} day${diffDays !== 1 ? "s" : ""} ago`;
  }
  return formatDate(date);
};

/**
 * Parse JSON safely
 * @param {String} jsonString - JSON string to parse
 * @param {*} defaultValue - Default value if parsing fails
 * @returns {*} Parsed object or default value
 */
export const parseJSON = (jsonString, defaultValue = {}) => {
  try {
    return JSON.parse(jsonString);
  } catch (e) {
    console.error("Error parsing JSON:", e);
    return defaultValue;
  }
};

/**
 * Generate a unique ID
 * @returns {String} Unique ID
 */
export const generateUniqueId = () => {
  return `id-${Date.now()}-${Math.floor(Math.random() * 10000)}`;
};

/**
 * Debounce a function to prevent rapid successive calls
 * Note: This implementation uses Promise-based delays instead of setTimeout to comply with LWC restrictions
 * @param {Function} func - Function to debounce
 * @param {Number} wait - Wait time in milliseconds
 * @returns {Function} Debounced function
 */
export const debounce = (func, wait = 300) => {
  let pending = false;
  let pendingArgs = null;

  const executeWithDelay = (args) => {
    // Mark as pending
    pending = true;
    pendingArgs = args;

    // Create a Promise to handle the delay
    return new Promise((resolve) => {
      // Use Promise chain to simulate delay
      let startTime = Date.now();

      // Function to check if enough time has passed
      const checkTime = () => {
        const elapsed = Date.now() - startTime;
        if (elapsed >= wait) {
          // Time has passed, execute function
          try {
            func(...pendingArgs);
          } finally {
            pending = false;
            pendingArgs = null;
          }
          resolve();
        } else {
          // Not enough time has passed, check again in the next microtask
          Promise.resolve().then(checkTime);
        }
      };

      // Start checking
      Promise.resolve().then(checkTime);
    });
  };

  return function executedFunction(...args) {
    // If there's a pending execution, update the arguments
    if (pending) {
      pendingArgs = args;
      return;
    }

    // Start a new delayed execution
    executeWithDelay(args);
  };
};

/**
 * Check if an object is empty
 * @param {Object} obj - Object to check
 * @returns {Boolean} True if object is empty
 */
export const isEmptyObject = (obj) => {
  return (
    obj !== null && typeof obj === "object" && Object.keys(obj).length === 0
  );
};

/**
 * Convert a field API name to a label
 * @param {String} fieldName - Field API name
 * @returns {String} Human-readable field label
 */
export const fieldNameToLabel = (fieldName) => {
  if (!fieldName) {
    return "";
  }

  // Remove __c suffix if present
  let label = fieldName.replace(/__c$/i, "");

  // Replace underscores with spaces
  label = label.replace(/_/g, " ");

  // Split camelCase into separate words
  label = label.replace(/([a-z])([A-Z])/g, "$1 $2");

  // Capitalize first letter of each word
  label = label.replace(/\b\w/g, (c) => c.toUpperCase());

  return label;
};

/**
 * Get time range filter options for statistics
 * @returns {Array} Array of time range options
 */
export const getTimeRangeOptions = () => {
  return [
    { label: "All Time", value: "ALL_TIME" },
    { label: "This Month", value: "THIS_MONTH" },
    { label: "This Week", value: "THIS_WEEK" },
    { label: "Today", value: "TODAY" }
  ];
};

/**
 * Convert a time range value to a readable label
 * @param {String} timeRange - Time range value
 * @returns {String} Human-readable time range label
 */
export const timeRangeToLabel = (timeRange) => {
  const options = getTimeRangeOptions();
  const option = options.find((opt) => opt.value === timeRange);
  return option ? option.label : "";
};

/**
 * Get object data for a given object API name
 * This could be expanded to include more metadata about the object
 * @param {String} objectApiName - API name of the object
 * @returns {Object} Object metadata
 */
export const getObjectData = (objectApiName) => {
  // Common objects mapping
  const objectData = {
    Account: {
      label: "Account",
      icon: "standard:account",
      color: "#7F8DE1"
    },
    Contact: {
      label: "Contact",
      icon: "standard:contact",
      color: "#A094ED"
    },
    Lead: {
      label: "Lead",
      icon: "standard:lead",
      color: "#F88962"
    },
    Opportunity: {
      label: "Opportunity",
      icon: "standard:opportunity",
      color: "#FCB95B"
    },
    Case: {
      label: "Case",
      icon: "standard:case",
      color: "#F2CF5B"
    }
  };

  // Return data for the requested object or a generic fallback
  return (
    objectData[objectApiName] || {
      label: fieldNameToLabel(objectApiName),
      icon: "standard:custom_object",
      color: "#8199AF"
    }
  );
};
