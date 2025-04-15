/**
 * Helper utility for migrating from PubSub to Lightning Message Service
 * Production implementation for Salesforce orgs with optimized performance
 */
import { createMessageContext } from "lightning/messageService";
import DUPLICATION_CHANNEL from "@salesforce/messageChannel/DuplicationChannel_c__c";
import { MESSAGE_TYPES } from "c/duplicationConstants";
import { 
  subscribeToChannel, 
  unsubscribeFromChannel, 
  sendMessage,
  createFilteredHandler
} from "c/duplicationMessageService";

// Cache message type mapping for better performance
const EVENT_TO_MESSAGE_MAP = new Map([
  ["duplicationStoreChange", MESSAGE_TYPES.STORE_UPDATED],
  ["duplicate.job.started", MESSAGE_TYPES.JOB_STARTED],
  ["duplicate.job.completed", MESSAGE_TYPES.JOB_COMPLETED],
  ["duplicate.job.progressUpdate", MESSAGE_TYPES.JOB_PROGRESS],
  ["duplicate.job.error", MESSAGE_TYPES.JOB_ERROR],
  ["duplicate.duplicates.found", MESSAGE_TYPES.DUPLICATES_FOUND],
  ["duplicate.duplicates.merged", MESSAGE_TYPES.DUPLICATES_MERGED],
  ["duplicate.config.selected", MESSAGE_TYPES.CONFIG_SELECTED],
  ["duplicate.config.updated", MESSAGE_TYPES.CONFIG_CHANGED],
  ["duplicate.ui.viewDuplicates", MESSAGE_TYPES.VIEW_CHANGE],
  ["duplicate.ui.viewMergePreview", MESSAGE_TYPES.MERGE_PREVIEW],
  ["duplicate.stats.updated", MESSAGE_TYPES.SETTINGS_UPDATED]
]);

/**
 * Subscribe to events using optimized LMS
 * @param {Object} component - LWC component instance
 * @param {Object} eventHandlers - Map of event names to handler functions
 * @returns {Object} Subscription information for cleanup
 */
export function subscribeMigrated(component, eventHandlers) {
  if (!component || !eventHandlers) return { lms: {} };

  // Get message context from component
  const messageContext = component.messageContext || createMessageContext();

  const subscriptions = {
    lms: {}
  };

  // Get all message types to listen for
  const messageTypes = Object.keys(eventHandlers).map(
    eventName => EVENT_TO_MESSAGE_MAP.get(eventName) || eventName
  );
  
  // Group event handlers by type for more efficient subscription
  const handlersByType = {};
  
  Object.entries(eventHandlers).forEach(([eventName, handler]) => {
    if (typeof handler !== "function") return;
    
    const mappedType = EVENT_TO_MESSAGE_MAP.get(eventName) || eventName;
    if (!handlersByType[mappedType]) {
      handlersByType[mappedType] = [];
    }
    
    // Store the handler with its context
    handlersByType[mappedType].push({
      originalName: eventName,
      handler: handler.bind(component)
    });
  });
  
  // Create single subscription for each unique message type
  Object.entries(handlersByType).forEach(([messageType, handlers]) => {
    // Create an optimized handler that calls all registered callbacks for this type
    const optimizedHandler = (message) => {
      if (!message || !message.type) return;
      
      try {
        const payload = message.payload || message;
        
        // Call all handlers for this message type
        handlers.forEach(handlerInfo => {
          try {
            handlerInfo.handler(payload);
          } catch (handlerError) {
            // Silent error handling
          }
        });
      } catch (error) {
        // Silent error handling
      }
    };
    
    // Subscribe using the optimized message service
    subscriptions.lms[messageType] = subscribeToChannel(
      optimizedHandler,
      { filter: msg => msg.type === messageType }
    );
  });

  // Store subscriptions on component for easier cleanup
  if (!component._lmsSubscriptions) {
    component._lmsSubscriptions = subscriptions;
  }
  
  return subscriptions;
}

/**
 * Unsubscribe from all channels
 * @param {Object} subscriptions - Subscription object from subscribeMigrated
 */
export function unsubscribeMigrated(subscriptions) {
  if (!subscriptions) return;

  try {
    // Unsubscribe from LMS using optimized service
    if (subscriptions.lms) {
      Object.values(subscriptions.lms).forEach((sub) => {
        if (sub) unsubscribeFromChannel(sub);
      });
      
      // Clear subscription references for garbage collection
      Object.keys(subscriptions.lms).forEach((key) => {
        subscriptions.lms[key] = null;
      });
    }
  } catch (error) {
    // Silent error handling for production
  }
}

/**
 * Publish an event via LMS with throttling for better performance
 * @param {String} eventName - Event name or message type
 * @param {Object} payload - Event payload
 * @param {Object} messageContext - MessageContext from the component
 * @param {String} priority - Message priority (normal, high)
 */
export function publishMigrated(eventName, payload, messageContext, priority = "normal") {
  if (!messageContext) return;

  try {
    // Get mapped message type from Map for better performance
    const messageType = EVENT_TO_MESSAGE_MAP.get(eventName) || eventName;

    // Use the optimized message service
    sendMessage(messageType, payload, { priority });
  } catch (error) {
    // Silent error handling
  }
}

/**
 * Add optimized LMS functionality to an existing component
 * @param {Object} component - LWC component to enhance
 * @returns {Object} - The enhanced component
 */
export function enhanceWithLms(component) {
  if (!component) return component;

  // Prevent duplicate enhancement
  if (component._lmsEnhanced) return component;
  component._lmsEnhanced = true;

  // Add LMS methods to component
  component.subscribeToEvents = function (eventHandlerMap) {
    // Clean up existing subscriptions if they exist
    if (this._lmsSubscriptions) {
      this.unsubscribeFromEvents();
    }
    
    this._lmsSubscriptions = subscribeMigrated(this, eventHandlerMap);
    return this._lmsSubscriptions;
  };

  component.unsubscribeFromEvents = function () {
    if (this._lmsSubscriptions) {
      unsubscribeMigrated(this._lmsSubscriptions);
      this._lmsSubscriptions = null;
    }
  };

  // Enhanced connected callback to set up context
  const originalConnectedCallback = component.connectedCallback;
  component.connectedCallback = function() {
    // Call original connectedCallback first if it exists
    if (originalConnectedCallback) {
      originalConnectedCallback.call(this);
    }
    
    // Set the flag to track rendering
    this._isConnected = true;
  };

  // Enhanced disconnect callback to ensure cleanup
  const originalDisconnectedCallback = component.disconnectedCallback;
  component.disconnectedCallback = function() {
    // Mark component as disconnected
    this._isConnected = false;
    
    // Always unsubscribe when component is disconnected
    this.unsubscribeFromEvents();
    
    // Call original disconnectedCallback if it exists
    if (originalDisconnectedCallback) {
      originalDisconnectedCallback.call(this);
    }
  };

  // Enhanced publish method with priority support
  component.publishEvent = function (eventName, payload, priority) {
    if (this._isConnected) {
      publishMigrated(eventName, payload, this.messageContext, priority);
    }
  };

  return component;
}