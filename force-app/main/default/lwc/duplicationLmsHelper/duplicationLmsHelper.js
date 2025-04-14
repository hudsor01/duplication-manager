/**
 * Helper utility for migrating from PubSub to Lightning Message Service
 * Production implementation for Salesforce orgs
 */
import {
  MessageContext,
  publish,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import {
  createMessageContext,
  releaseMessageContext
} from "lightning/messageService";
import DUPLICATION_CHANNEL from "@salesforce/messageChannel/DuplicationChannel_c__c";
import { MESSAGE_TYPES } from "c/duplicationConstants";

// Map legacy event names to new message types
const EVENT_TO_MESSAGE_MAP = {
  duplicationStoreChange: MESSAGE_TYPES.STORE_UPDATED,
  "duplicate.job.started": MESSAGE_TYPES.JOB_STARTED,
  "duplicate.job.completed": MESSAGE_TYPES.JOB_COMPLETED,
  "duplicate.job.progressUpdate": MESSAGE_TYPES.JOB_PROGRESS,
  "duplicate.job.error": MESSAGE_TYPES.JOB_ERROR,
  "duplicate.duplicates.found": MESSAGE_TYPES.DUPLICATES_FOUND,
  "duplicate.duplicates.merged": MESSAGE_TYPES.DUPLICATES_MERGED,
  "duplicate.config.selected": MESSAGE_TYPES.CONFIG_SELECTED,
  "duplicate.config.updated": MESSAGE_TYPES.CONFIG_CHANGED,
  "duplicate.ui.viewDuplicates": MESSAGE_TYPES.VIEW_CHANGE,
  "duplicate.ui.viewMergePreview": MESSAGE_TYPES.MERGE_PREVIEW,
  "duplicate.stats.updated": MESSAGE_TYPES.SETTINGS_UPDATED
};

/**
 * Subscribe to events using LMS
 * @param {Object} component - LWC component instance
 * @param {Object} eventHandlers - Map of event names to handler functions
 * @returns {Object} Subscription information for cleanup
 */
export function subscribeMigrated(component, eventHandlers) {
  if (!component || !eventHandlers) return {};

  // Get message context from component
  const messageContext = component.messageContext || createMessageContext();

  const subscriptions = {
    lms: {}
  };

  // Process each event handler
  Object.entries(eventHandlers).forEach(([eventName, handler]) => {
    if (typeof handler !== "function") return;

    // Create wrapper to normalize message format
    const handlerWrapper = (message) => {
      try {
        // Handle message format
        const messageType = message.type || eventName;
        const mappedType = EVENT_TO_MESSAGE_MAP[eventName] || eventName;

        // Execute handler if message type matches
        if (messageType === mappedType || messageType === eventName) {
          handler.call(component, message.payload || message);
        }
      } catch (error) {
        // Production error handling without console.log
      }
    };

    // Subscribe using LMS
    subscriptions.lms[eventName] = subscribe(
      messageContext,
      DUPLICATION_CHANNEL,
      handlerWrapper
    );
  });

  // Store subscriptions on component for easier cleanup
  component._lmsSubscriptions = subscriptions;
  return subscriptions;
}

/**
 * Unsubscribe from all channels
 * @param {Object} subscriptions - Subscription object from subscribeMigrated
 */
export function unsubscribeMigrated(subscriptions) {
  if (!subscriptions) return;

  // Unsubscribe from LMS
  if (subscriptions.lms) {
    Object.values(subscriptions.lms).forEach((sub) => {
      if (sub) unsubscribe(sub);
    });
  }
}

/**
 * Publish an event via LMS
 * @param {String} eventName - Event name or message type
 * @param {Object} payload - Event payload
 * @param {Object} messageContext - MessageContext from the component
 */
export function publishMigrated(eventName, payload, messageContext) {
  if (!messageContext) return;

  // Get mapped message type
  const messageType = EVENT_TO_MESSAGE_MAP[eventName] || eventName;

  // Create message for LMS
  const message = {
    type: messageType,
    payload: payload,
    timestamp: new Date().toISOString()
  };

  // Send via LMS
  publish(messageContext, DUPLICATION_CHANNEL, message);
}

/**
 * Add LMS functionality to an existing component
 * @param {Object} component - LWC component to enhance
 * @returns {Object} - The enhanced component
 */
export function enhanceWithLms(component) {
  if (!component) return component;

  // Add LMS methods to component
  component.subscribeToEvents = function (eventHandlerMap) {
    this._lmsSubscriptions = subscribeMigrated(this, eventHandlerMap);
    return this._lmsSubscriptions;
  };

  component.unsubscribeFromEvents = function () {
    unsubscribeMigrated(this._lmsSubscriptions);
    this._lmsSubscriptions = null;
  };

  component.publishEvent = function (eventName, payload) {
    publishMigrated(eventName, payload, this.messageContext);
  };

  return component;
}
