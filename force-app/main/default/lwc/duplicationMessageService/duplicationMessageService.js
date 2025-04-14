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

// Middleware stack for message processing - limit to prevent performance issues
const middleware = [];
const MAX_MIDDLEWARE = 5;

// Create a message context that will be shared across all subscribers
// This is a fallback context - ideally components should use @wire(MessageContext)
let messageContext = createMessageContext();

// Track all active subscriptions for proper cleanup - use WeakSet to prevent memory leaks
const activeSubscriptions = new WeakSet();

// Track pending requests to avoid memory leaks
const pendingRequests = new Map();

// Flag to prevent multiple rapid message sending that can cause browser freezing
let isProcessingMessage = false;
const MESSAGE_THROTTLE_MS = 50; // Increased from 10ms to 50ms to prevent Safari freezing

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
    return null;
  }

  // Create a wrapper handler that applies middleware and adds error handling
  const wrappedHandler = (message) => {
    try {
      if (!message) return;
      
      // Optimize middleware processing - only apply if there are any
      if (middleware.length === 0) {
        messageHandler(message);
        return;
      }
      
      // Apply middleware with short-circuit for better performance
      let processedMessage = message;
      for (let i = 0; i < middleware.length && processedMessage; i++) {
        processedMessage = middleware[i](processedMessage, "incoming");
      }

      // Call the original handler with the processed message if still valid
      if (processedMessage) {
        messageHandler(processedMessage);
      }
    } catch (error) {
      // Silent error handling
    }
  };

  // Subscribe to the Lightning Message Channel
  const subscription = subscribe(
    messageContext,
    duplication_CHANNEL,
    wrappedHandler,
    options
  );
  
  // Track subscription for global cleanup if needed
  if (subscription) {
    activeSubscriptions.add(subscription);
  }

  return subscription;
}

/**
 * Unsubscribe from channel
 * @param {object} subscription - Subscription returned by subscribeToChannel
 */
export function unsubscribeFromChannel(subscription) {
  if (!subscription) return;
  
  try {
    unsubscribe(subscription);
    
    // Remove from active subscriptions tracking - WeakSet will handle cleanup automatically
  } catch (error) {
    // Silent error handling
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
  if (!type) return null;
  
  // Handle high priority messages immediately, otherwise throttle to prevent browser freezing
  if (options.priority !== "high" && isProcessingMessage) {
    // Return a correlation ID but queue the message for later processing
    const correlationId = options.correlationId || generateUuid();
    
    // Use requestAnimationFrame for better performance than setTimeout
    window.requestAnimationFrame(() => {
      sendMessage(type, data, {...options, correlationId});
    });
    
    return correlationId;
  }
  
  try {
    isProcessingMessage = true;
    
    const defaultOptions = {
      priority: "normal",
      correlationId: null,
      jobId: null,
      configId: null
    };

    const finalOptions = { ...defaultOptions, ...options };

    // Create the message - use simpler timestamp for better performance
    let message = {
      type: type,
      payload: data,
      timestamp: Date.now(),
      source: INSTANCE_ID,
      priority: finalOptions.priority,
      correlationId: finalOptions.correlationId || generateUuid(),
      jobId: finalOptions.jobId,
      configId: finalOptions.configId
    };

    // Apply middleware if any exist
    if (middleware.length > 0) {
      // Apply middleware chain with short-circuit optimization
      for (let i = 0; i < middleware.length && message; i++) {
        message = middleware[i](message, "outgoing");
      }
      
      // Stop sending if middleware nullified the message
      if (!message) {
        isProcessingMessage = false;
        return null;
      }
    }

    // Publish to the Lightning Message Channel
    publish(messageContext, duplication_CHANNEL, message);

    // Use requestAnimationFrame to reset flag for better browser repaint cycles
    window.requestAnimationFrame(() => {
      isProcessingMessage = false;
    });
    
    // Return the correlation ID for tracking
    return message.correlationId;
  } catch (error) {
    // Silent error handling
    isProcessingMessage = false;
    return null;
  }
}

/**
 * Add middleware to the message processing pipeline
 * @param {function} middlewareFn - Function(message, direction) that processes messages
 * @returns {boolean} True if middleware was added successfully
 */
export function addMiddleware(middlewareFn) {
  if (typeof middlewareFn === "function" && middleware.length < MAX_MIDDLEWARE) {
    middleware.push(middlewareFn);
    return true;
  }
  return false;
}

/**
 * Clear all middleware
 */
export function clearMiddleware() {
  middleware.length = 0;
}

/**
 * Clean up all active subscriptions
 * Use this on app unload or manual cleanup if needed
 */
export function cleanupAllSubscriptions() {
  try {
    // Clean up any pending requests
    pendingRequests.forEach((request, id) => {
      if (request.timeoutId) {
        clearTimeout(request.timeoutId);
      }
      if (request.subscription) {
        unsubscribeFromChannel(request.subscription);
      }
    });
    
    pendingRequests.clear();
  } catch (error) {
    // Silent error handling
  }
}

/**
 * Send a request and wait for a response with the same correlation ID
 * @param {string} type - Message type/action
 * @param {object} data - Message payload
 * @param {number} timeout - Optional timeout in ms (defaults to 10000)
 * @returns {Promise} Promise that resolves with the response
 */
export function sendRequest(type, data, timeout = 10000) {
  return new Promise((resolve, reject) => {
    try {
      // Generate correlation ID for this request
      const correlationId = generateUuid();

      // Track our subscription for cleanup
      let subscriptionRef;
      let timeoutId;

      // Create a one-time subscription to listen for the response
      const subscription = subscribeToChannel((message) => {
        if (!message || !message.correlationId || message.correlationId !== correlationId) return;
        
        // Clear timeout to prevent memory leaks
        if (timeoutId) {
          clearTimeout(timeoutId);
          timeoutId = null;
        }

        // Unsubscribe from the channel since we got our response
        if (subscriptionRef) {
          unsubscribeFromChannel(subscriptionRef);
          subscriptionRef = null;
        }
        
        // Remove from pending requests
        pendingRequests.delete(correlationId);

        // Resolve the promise with the response payload
        resolve(message.payload);
      });

      // Store reference to subscription
      subscriptionRef = subscription;

      // Track this pending request for potential cleanup
      pendingRequests.set(correlationId, {
        subscription: subscriptionRef,
        timeoutId: null,
        startTime: Date.now()
      });
      
      // Set timeout to prevent lingering subscriptions - reduced from default 30s to 10s
      timeoutId = setTimeout(() => {
        // Unsubscribe from the channel on timeout
        if (subscriptionRef) {
          unsubscribeFromChannel(subscriptionRef);
          subscriptionRef = null;
        }
        
        // Remove from pending requests
        pendingRequests.delete(correlationId);
        
        reject(new Error(`Request timed out after ${timeout}ms`));
      }, timeout);
      
      // Update the timeoutId in the pending requests map
      if (pendingRequests.has(correlationId)) {
        pendingRequests.get(correlationId).timeoutId = timeoutId;
      }

      // Send the request message with the correlation ID
      sendMessage(type, data, { correlationId, priority: "high" });
    } catch (error) {
      // Reject with error
      reject(error);
    }
  });
}

/**
 * Generate a UUID for correlation IDs
 * @private
 * @returns {string} UUID
 */
function generateUuid() {
  try {
    // Simplified UUID generation for better performance
    return Date.now().toString(36) + Math.random().toString(36).substring(2, 9);
  } catch (error) {
    // Fallback UUID in case of error
    return `fallback-${Date.now()}`;
  }
}

/**
 * Utility function to create a filtered message handler
 * @param {function} callback - Function to call with filtered messages
 * @param {string|string[]} types - Type or array of types to filter for
 * @returns {function} Handler function that only calls callback for specified types
 */
export function createFilteredHandler(callback, types) {
  if (!callback || !types) return (message) => {};
  
  // Convert to array if necessary
  const typeArray = Array.isArray(types) ? types : [types];
  
  // Create a Set for faster lookups
  const typeSet = new Set(typeArray);

  // Return an optimized handler that filters messages
  return (message) => {
    try {
      if (!message || !message.type) return;
      
      if (typeSet.has(message.type)) {
        callback(message);
      }
    } catch (error) {
      // Silent error handling
    }
  };
}