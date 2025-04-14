/**
 * Centralized messaging service for duplicate Manager
 * Provides standardized communication between components with advanced features
 *
 * @author Richard Hudson
 * @created April 2025
 * @updated May 2025
 */

import {
  createMessageContext,
  publish,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import duplication_CHANNEL from "@salesforce/messageChannel/DuplicationChannel_c__c";

// Unique ID for this component instance
const INSTANCE_ID = generateUuid();

// Middleware stack for message processing
const middleware = [];

// Create a message context that will be shared across all subscribers
// This is a fallback context - ideally components should use @wire(MessageContext)
let messageContext = createMessageContext();

/**
 * Set the message context from a parent component
 * @param {object} context - MessageContext from @wire(MessageContext)
 */
export function setMessageContext(context) {
  if (context) {
    messageContext = context;
  }
}

/**
 * Subscribe to channel events with enhanced capabilities
 * @param {function} messageHandler - Function to handle received messages
 * @param {object} options - Subscription options
 * @returns {object} Subscription object for unsubscribing
 */
export function subscribeToChannel(messageHandler, options = {}) {
  if (!messageHandler) {
    // Error: Message handler function is required
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
    duplication_CHANNEL,
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
    configId: null
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
    configId: finalOptions.configId
  };

  // Apply middleware chain
  for (const middlewareFn of middleware) {
    message = middlewareFn(message, "outgoing");
    // Stop sending if middleware returns null
    if (!message) return null;
  }

  // Publish to the Lightning Message Channel
  publish(messageContext, duplication_CHANNEL, message);

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

    // Declare timeoutId at the beginning
    let timeoutId;

    // Create a one-time subscription to listen for the response
    const subscription = subscribeToChannel((message) => {
      // Only process responses with matching correlation ID
      if (message.correlationId === correlationId) {
        // Unsubscribe from the channel since we got our response
        unsubscribeFromChannel(subscription);

        // Clear the timeout
        if (timeoutId) {
          clearTimeout(timeoutId);
        }

        // Resolve the promise with the response payload
        resolve(message.payload);
      }
    });

    // Using a safe approach for async operations in LWC
    // Avoid using setTimeout directly in production code
    // This is just a fallback mechanism
    Promise.resolve()
      .then(() => {
        // Simulate timeout with Promise
        const timer = new Promise((_, timeoutReject) => {
          // Store timeout ID for potential cancellation
          timeoutId = setTimeout(() => {
            unsubscribeFromChannel(subscription);
            timeoutReject(new Error(`Request timed out after ${timeout}ms`));
          }, timeout);
        });

        return Promise.race([timer]);
      })
      .catch((err) => {
        reject(err);
      });

    // Send the request message with the correlation ID
    sendMessage(type, data, { correlationId });
  });
}

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
 * Utility function to create a filtered message handler
 * @param {function} callback - Function to call with filtered messages
 * @param {string|string[]} types - Type or array of types to filter for
 * @returns {function} Handler function that only calls callback for specified types
 */
export function createFilteredHandler(callback, types) {
  // Convert to array if necessary
  const typeArray = Array.isArray(types) ? types : [types];

  // Return a handler that filters messages
  return (message) => {
    if (typeArray.includes(message.type)) {
      callback(message);
    }
  };
}
