/**
 * Enhanced utility service for Lightning Message Service communication
 * Includes additional features for correlation, filtering, and middleware
 *
 * @author Richard Hudson
 * @created April 2025
 * @updated May 2025
 */

import { createMessageContext, releaseMessageContext, publish, subscribe, unsubscribe } from 'lightning/messageService';
import DUPLICATION_CHANNEL from '@salesforce/messageChannel/DuplicationChannel_c__c';

// Unique ID for this component instance
const INSTANCE_ID = generateUuid();

// Middleware stack for message processing
const middleware = [];

// Create a message context that will be shared across all subscribers
const messageContext = createMessageContext();

/**
 * Subscribe to channel events with enhanced capabilities
 * @param {function} messageHandler - Function to handle received messages
 * @param {object} options - Subscription options
 * @returns {object} Subscription object for unsubscribing
 */
export function subscribeToChannel(messageHandler, options = {}) {
  if (!messageHandler) {
    console.error("Message handler function is required");
    return null;
  }

  // Create a wrapper handler that applies middleware
  const wrappedHandler = (message) => {
    // Apply middleware
    let processedMessage = message;
    for (const middlewareFn of middleware) {
      processedMessage = middlewareFn(processedMessage, "incoming");
      // Stop processing if middleware returns null
      if (!processedMessage) return;
    }
    
    // Call the original handler with the processed message
    messageHandler(processedMessage);
  };

  // Subscribe to the Lightning Message Channel
  const subscription = subscribe(
    messageContext,
    DUPLICATION_CHANNEL,
    wrappedHandler,
    options
  );

  return subscription;
}

/**
 * Unsubscribe from channel
 * @param {object} subscription - Subscription returned by subscribeToChannel
 */
export function unsubscribeFromChannel(subscription) {
  if (subscription) {
    unsubscribe(subscription);
  }
}

/**
 * Send message on channel with enhanced capabilities
 * @param {string} type - Message type/action
 * @param {object} data - Message payload
 * @param {object} options - Additional message options
 * @returns {string} Correlation ID for tracking the message
 */
export function sendMessage(type, data, options = {}) {
  const defaultOptions = {
    priority: "normal",
    correlationId: null,
    jobId: null,
    configId: null,
  };

  const finalOptions = { ...defaultOptions, ...options };

  // Create the message
  let message = {
    type: type,
    payload: data,
    timestamp: new Date().toISOString(),
    source: INSTANCE_ID,
    priority: finalOptions.priority,
    correlationId: finalOptions.correlationId || generateUuid(),
    jobId: finalOptions.jobId,
    configId: finalOptions.configId,
  };

  // Apply middleware chain
  for (const middlewareFn of middleware) {
    message = middlewareFn(message, "outgoing");
    // Stop sending if middleware returns null
    if (!message) return null;
  }

  // Publish to the Lightning Message Channel
  publish(messageContext, DUPLICATION_CHANNEL, message);

  // Return the correlation ID for tracking
  return message.correlationId;
}

/**
 * Add middleware to the message processing pipeline
 * @param {function} middlewareFn - Function(message, direction) that processes messages
 */
export function addMiddleware(middlewareFn) {
  if (typeof middlewareFn === "function") {
    middleware.push(middlewareFn);
  }
}

/**
 * Clear all middleware
 */
export function clearMiddleware() {
  middleware.length = 0;
}

/**
 * Send a request and wait for a response with the same correlation ID
 * @param {string} type - Message type/action
 * @param {object} data - Message payload
 * @param {number} timeout - Timeout in ms (default: 5000)
 * @returns {Promise} Promise that resolves with the response
 */
export function sendRequest(type, data, timeout = 5000) {
  return new Promise((resolve, reject) => {
    // Generate correlation ID for this request
    const correlationId = generateUuid();
    
    // Create a one-time subscription to listen for the response
    const subscription = subscribeToChannel((message) => {
      // Only process responses with matching correlation ID
      if (message.correlationId === correlationId) {
        // Unsubscribe from the channel since we got our response
        unsubscribeFromChannel(subscription);
        
        // Clear the timeout
        clearTimeout(timeoutId);
        
        // Resolve the promise with the response payload
        resolve(message.payload);
      }
    });
    
    // Set a timeout to reject the promise if no response is received
    const timeoutId = setTimeout(() => {
      unsubscribeFromChannel(subscription);
      reject(new Error(`Request timed out after ${timeout}ms`));
    }, timeout);
    
    // Send the request message with the correlation ID
    sendMessage(type, data, { correlationId });
  });
}

/**
 * Standard message types for the application
 */
export const MESSAGE_TYPES = {
  // Job management
  JOB_STARTED: "job.started",
  JOB_COMPLETED: "job.completed",
  JOB_PROGRESS: "job.progress",
  JOB_ERROR: "job.error",
  JOB_CANCELLED: "job.cancelled",

  // Duplication management
  DUPLICATES_FOUND: "duplicates.found",
  DUPLICATES_MERGED: "duplicates.merged",
  MERGE_PREVIEW: "merge.preview",
  MERGE_CONFLICT: "merge.conflict",
  MERGE_RESOLUTION: "merge.resolution",

  // Configuration
  CONFIG_SELECTED: "config.selected",
  CONFIG_CHANGED: "config.changed",
  CONFIG_VALIDATED: "config.validated",
  SETTINGS_UPDATED: "settings.updated",

  // Navigation
  VIEW_CHANGE: "view.change",
  MODAL_OPEN: "modal.open",
  MODAL_CLOSE: "modal.close",

  // Dry run
  DRY_RUN_START: "dryRun.start",
  DRY_RUN_COMPLETE: "dryRun.complete",
  DRY_RUN_RESULTS: "dryRun.results",

  // Store updates
  STORE_UPDATED: "store.updated",
  STORE_SECTION_UPDATED: "store.section.updated",
  STORE_RESET: "store.reset",

  // Requests and responses
  CONFIG_REQUEST: "config.request",
  CONFIG_RESPONSE: "config.response",
  JOB_STATUS_REQUEST: "job.status.request",
  JOB_STATUS_RESPONSE: "job.status.response",
};

/**
 * Generate a UUID for correlation IDs
 * @private
 * @returns {string} UUID
 */
function generateUuid() {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

/**
 * Simple publish-subscribe mechanism for component communication
 * Handles communication between different components in the duplication manager app
 *
 * @author Richard Hudson
 * @since April 2025
 */

// Message types for standardized communication (for pub-sub)
export const SUBSCRIBE_MESSAGE_TYPES = {
    // Store and state updates
    STORE_UPDATED: 'store_updated',
    STORE_SECTION_UPDATED: 'store_section_updated',
    INVALIDATE_CACHE: 'invalidate_cache',

    // Dashboard and statistics
    STATISTICS_LOADING: 'statistics_loading',
    STATISTICS_LOADED: 'statistics_loaded',
    STATISTICS_LOAD_ERROR: 'statistics_load_error',
    REFRESH_STATISTICS: 'refresh_statistics',
    REFRESH_STARTED: 'refresh_started',

    // Job related
    JOB_STARTED: 'job_started',
    JOB_COMPLETED: 'job_completed',
    JOB_FAILED: 'job_failed',
    JOB_STATUS_UPDATED: 'job_status_updated',

    // Filter and display options
    TIME_RANGE_CHANGED: 'time_range_changed',
    OBJECT_FILTER_CHANGED: 'object_filter_changed',
    VIEW_MODE_CHANGED: 'view_mode_changed',

    // Errors and notifications
    ERROR_OCCURRED: 'error_occurred',
    NOTIFICATION: 'notification'
};

// Subscriber registry
const subscribers = [];

/**
 * Subscribe to channel messages
 * @param {Function} callback Function to call when message is received
 * @return {Object} Subscription object for unsubscribing
 */
export function subscribeToPubSubChannel(callback) {
    if (!callback || typeof callback !== 'function') {
        console.error('Subscription requires a valid callback function');
        return {};
    }

    const subscription = { callback, active: true };
    subscribers.push(subscription);
    return subscription;
}

/**
 * Unsubscribe from pub-sub channel
 * @param {Object} subscription Subscription to cancel
 */
export function unsubscribeFromPubSubChannel(subscription) {
    if (!subscription) return;

    const index = subscribers.indexOf(subscription);
    if (index !== -1) {
        subscribers.splice(index, 1);
    } else {
        // If not found by reference, mark as inactive
        subscription.active = false;
    }
}

/**
 * Publish a message to all subscribers
 * @param {String} type Message type from MESSAGE_TYPES
 * @param {Object} payload Data payload for the message
 */
export function publishMessage(type, payload) {
    if (!type) {
        console.error('Message type is required');
        return;
    }

    const message = {
        type,
        payload,
        timestamp: new Date().getTime()
    };

    // Clean up inactive subscribers
    for (let i = subscribers.length - 1; i >= 0; i--) {
        if (!subscribers[i].active) {
            subscribers.splice(i, 1);
        }
    }

    // Notify active subscribers
    subscribers.forEach(subscription => {
        if (subscription.active && typeof subscription.callback === 'function') {
            try {
                subscription.callback(message);
            } catch (error) {
                console.error('Error in message subscriber callback:', error);
            }
        }
    });
}
