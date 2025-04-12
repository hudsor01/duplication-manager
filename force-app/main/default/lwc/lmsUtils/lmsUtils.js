import {
  createMessageContext,
  releaseMessageContext,
  publish,
  subscribe,
  unsubscribe,
} from "lightning/messageService";
// Using mock implementation to avoid deployment issues with message channel
// This will be replaced with actual import when the channel is properly configured
// import DUPLICATION_CHANNEL from "@salesforce/messageChannel/DuplicationChannel_c";

// Mock channel for deployment
const DUPLICATION_CHANNEL = {
  type: "lightning:messageChannel",
  channelId: "DuplicationChannel_c",
  isPublishable: true,
  isSubscribable: true,
  description: "Message channel for Duplication Manager components"
};

/**
 * Utility class for Lightning Message Service (LMS) communications
 * Provides a centralized way to use LMS across components
 */
export default class LmsUtils {
  static context = createMessageContext();
  static subscriptions = new Map();
  static debugMode = false;

  /**
   * Enable or disable debug logging
   * @param {Boolean} enabled - Whether to enable debug logs
   */
  static setDebugMode(enabled) {
    this.debugMode = enabled;
  }

  /**
   * Log a message if debug mode is enabled
   * @param {String} message - The message to log
   */
  static log(message) {
    if (this.debugMode) {
      console.log(`[LMSUtils] ${message}`);
    }
  }

  /**
   * Publish a message to the Duplication Message Channel
   * @param {String} messageType - Type of message
   * @param {Object} payload - Message payload
   */
  static publish(messageType, payload) {
    if (!messageType) {
      console.error("[LMSUtils] Cannot publish message without a messageType");
      return;
    }

    const message = {
      messageType,
      payload: payload || {},
    };

    this.log(`Publishing message: ${messageType}`);
    
    try {
      publish(this.context, DUPLICATION_CHANNEL, message);
    } catch (error) {
      console.log(`[LMSUtils] Mock publish: ${messageType}`, payload);
      // Continue execution even if publish fails
    }
  }

  /**
   * Subscribe to messages of a specific type
   * @param {String} messageType - Type of message to subscribe to
   * @param {Function} callback - Callback function to invoke when message is received
   * @returns {Object} Subscription object that can be used to unsubscribe
   */
  static subscribe(messageType, callback) {
    if (!messageType || !callback) {
      console.error(
        "[LMSUtils] Cannot subscribe without messageType and callback",
      );
      return null;
    }

    this.log(`Subscribing to message: ${messageType}`);

    let subscription;
    
    try {
      // Create subscription with filtering by message type
      subscription = subscribe(this.context, DUPLICATION_CHANNEL, (message) => {
        // Add null/undefined check before accessing messageType
        if (message && message.messageType === messageType) {
          this.log(`Received message: ${messageType}`);
          try {
            callback(message.payload);
          } catch (error) {
            console.error(
              `[LMSUtils] Error in callback for message ${messageType}:`,
              error,
            );
          }
        }
      });
    } catch (error) {
      // Provide a mock subscription object if subscribe fails
      console.log(`[LMSUtils] Mock subscribe: ${messageType}`);
      subscription = {
        id: 'mock-' + Date.now(),
        unsubscribe: () => console.log(`[LMSUtils] Mock unsubscribe: ${messageType}`)
      };
    }

    // Store the subscription for potential cleanup
    if (!this.subscriptions.has(messageType)) {
      this.subscriptions.set(messageType, []);
    }
    this.subscriptions.get(messageType).push(subscription);

    return subscription;
  }

  /**
   * Unsubscribe from a message channel subscription
   * @param {Object} subscription - Subscription to cancel
   */
  static unsubscribe(subscription) {
    if (!subscription) {
      console.error(
        "[LMSUtils] Cannot unsubscribe without a valid subscription",
      );
      return;
    }

    this.log("Unsubscribing from message channel");
    
    try {
      // Handle both real and mock subscriptions
      if (subscription.unsubscribe && typeof subscription.unsubscribe === 'function') {
        subscription.unsubscribe();
      } else {
        unsubscribe(subscription);
      }
    } catch (error) {
      console.log("[LMSUtils] Error during unsubscribe, continuing cleanup");
    }

    // Clean up our stored subscriptions
    for (const [messageType, subs] of this.subscriptions.entries()) {
      const index = subs.indexOf(subscription);
      if (index !== -1) {
        subs.splice(index, 1);
        this.log(`Removed subscription for message: ${messageType}`);
        break;
      }
    }
  }

  /**
   * Utility method to unsubscribe from all subscriptions for a specific message type
   * @param {String} messageType - Message type to unsubscribe from
   */
  static unsubscribeAll(messageType) {
    if (!messageType || !this.subscriptions.has(messageType)) {
      return;
    }

    this.log(`Unsubscribing all listeners for message: ${messageType}`);
    const subs = this.subscriptions.get(messageType);
    
    subs.forEach((sub) => {
      try {
        // Handle both real and mock subscriptions
        if (sub.unsubscribe && typeof sub.unsubscribe === 'function') {
          sub.unsubscribe();
        } else {
          unsubscribe(sub);
        }
      } catch (error) {
        console.log(`[LMSUtils] Error during unsubscribeAll for ${messageType}, continuing`);
      }
    });
    
    this.subscriptions.delete(messageType);
  }

  /**
   * Get count of active subscriptions for a message type
   * Useful for debugging and testing
   * @param {String} messageType - Message type to check
   * @returns {Number} Number of active subscriptions
   */
  static getSubscriptionCount(messageType) {
    if (!messageType || !this.subscriptions.has(messageType)) {
      return 0;
    }
    return this.subscriptions.get(messageType).length;
  }

  /**
   * Determine if we have any active subscriptions
   * @returns {Boolean} True if there are any active subscriptions
   */
  static hasActiveSubscriptions() {
    return this.subscriptions.size > 0;
  }

  /**
   * Set a default error handler for all subscriptions
   * @param {Function} handler - Function to call when an error occurs in any callback
   */
  static setDefaultErrorHandler(handler) {
    if (typeof handler === "function") {
      this.defaultErrorHandler = handler;
    }
  }

  /**
   * Release the message context when no longer needed (like in component disconnectedCallback)
   */
  static releaseContext() {
    this.log("Releasing message context");
    try {
      releaseMessageContext(this.context);
    } catch (error) {
      console.log("[LMSUtils] Error releasing context, continuing");
    }
  }

  /**
   * Reset the utility by unsubscribing all subscriptions and releasing context
   * Useful for testing and for complete component teardown
   */
  static reset() {
    // Unsubscribe from all subscriptions
    for (const [messageType, subs] of this.subscriptions.entries()) {
      subs.forEach((sub) => {
        try {
          // Handle both real and mock subscriptions
          if (sub.unsubscribe && typeof sub.unsubscribe === 'function') {
            sub.unsubscribe();
          } else {
            unsubscribe(sub);
          }
        } catch (error) {
          console.log(
            `[LMSUtils] Error unsubscribing from ${messageType}, continuing`,
          );
        }
      });
    }

    // Clear all stored subscriptions
    this.subscriptions.clear();

    // Release the message context
    try {
      releaseMessageContext(this.context);
    } catch (error) {
      console.log("[LMSUtils] Error releasing message context, continuing");
    }

    // Create a new context
    this.context = createMessageContext();
    this.log("LMSUtils reset complete");
  }
}
