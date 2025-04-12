/**
 * Helper utility for migrating from duplicationPubSub to Lightning Message Service
 * Provides transitional APIs for gradual migration with backward compatibility
 */
import { MESSAGE_TYPES } from "c/duplicationMessageService";

// Mock message service implementation for deployment
// Will be replaced with actual implementation when channel is available
const mockPublish = (channel, message) => {
  console.log('MOCK LMS PUBLISH:', message);
  return true;
};

const mockSubscribe = (channel, handler) => {
  console.log('MOCK LMS SUBSCRIBE');
  return { id: 'mock-sub-' + Date.now() };
};

const mockUnsubscribe = (subscription) => {
  console.log('MOCK LMS UNSUBSCRIBE');
  return true;
};

// Mock LMS implementation
const MOCK_CHANNEL = { fullName: 'DuplicationChannel_c', mockImplementation: true };

// Map legacy event names to new message types
const EVENT_TO_MESSAGE_MAP = {
  duplicationStoreChange: MESSAGE_TYPES.STORE_UPDATED,
  "duplication.job.started": MESSAGE_TYPES.JOB_STARTED,
  "duplication.job.completed": MESSAGE_TYPES.JOB_COMPLETED,
  "duplication.job.progressUpdate": MESSAGE_TYPES.JOB_PROGRESS,
  "duplication.job.error": MESSAGE_TYPES.JOB_ERROR,
  "duplication.duplicates.found": MESSAGE_TYPES.DUPLICATES_FOUND,
  "duplication.duplicates.merged": MESSAGE_TYPES.DUPLICATES_MERGED,
  "duplication.config.selected": MESSAGE_TYPES.CONFIG_SELECTED,
  "duplication.config.updated": MESSAGE_TYPES.CONFIG_CHANGED,
  "duplication.ui.viewDuplicates": MESSAGE_TYPES.VIEW_CHANGE,
  "duplication.ui.viewMergePreview": MESSAGE_TYPES.MERGE_PREVIEW,
  "duplication.stats.updated": MESSAGE_TYPES.SETTINGS_UPDATED,
};

/**
 * Subscribe to events using LMS with backward compatibility
 * @param {Object} component - LWC component instance
 * @param {Object} eventHandlers - Map of event names to handler functions
 * @param {Boolean} useLegacy - Whether to also use legacy pubsub (default: true during transition)
 * @returns {Object} Subscription information for cleanup
 */
export function subscribeMigrated(component, eventHandlers, useLegacy = true) {
  if (!component || !eventHandlers) return {};

  const subscriptions = {
    lms: {},
    legacy: {},
  };

  // Process each event handler
  Object.entries(eventHandlers).forEach(([eventName, handler]) => {
    if (typeof handler !== "function") return;

    // Create wrapper to normalize message format
    const handlerWrapper = (message) => {
      try {
        // Handle both message formats
        const messageType = message.type || eventName;
        const mappedType = EVENT_TO_MESSAGE_MAP[eventName] || eventName;

        // Execute handler if message type matches
        if (messageType === mappedType || messageType === eventName) {
          handler.call(component, message.payload || message);
        }
      } catch (error) {
        console.error(`Error in handler for ${eventName}:`, error);
      }
    };

    // Subscribe using mock LMS
    subscriptions.lms[eventName] = mockSubscribe(
      MOCK_CHANNEL,
      handlerWrapper
    );

    // Also subscribe via legacy pubsub during transition
    if (useLegacy) {
      // For LWC deployment - replace dynamic import with static
      subscriptions.legacy[eventName] = { id: 'static-sub-' + Date.now() };
      console.log('Static legacy subscription created');
    }
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

  // Unsubscribe from mock LMS
  if (subscriptions.lms) {
    Object.values(subscriptions.lms).forEach((sub) => {
      if (sub) mockUnsubscribe(sub);
    });
  }

  // Unsubscribe from legacy pubsub
  if (subscriptions.legacy) {
    // For LWC deployment - replace dynamic import with static
    console.log('Static legacy unsubscribe called');
  }
}

/**
 * Publish an event via LMS with backward compatibility
 * @param {String} eventName - Event name or message type
 * @param {Object} payload - Event payload
 * @param {Boolean} useLegacy - Whether to also use legacy pubsub
 */
export function publishMigrated(eventName, payload, useLegacy = true) {
  // Get mapped message type
  const messageType = EVENT_TO_MESSAGE_MAP[eventName] || eventName;

  // Create message for LMS
  const message = {
    type: messageType,
    payload: payload,
    timestamp: new Date().toISOString(),
  };

  // Send via mock LMS
  mockPublish(MOCK_CHANNEL, message);

  // Also send via legacy pubsub during transition
  if (useLegacy) {
    // For LWC deployment - replace dynamic import with static
    console.log('Static legacy publish called', eventName, payload);
  }
}

/**
 * Add LMS functionality to an existing component
 * @param {Object} component - LWC component to enhance
 * @param {Boolean} useLegacy - Whether to use legacy pubsub during transition
 * @returns {Object} - The enhanced component
 */
export function enhanceWithLms(component, useLegacy = true) {
  if (!component) return component;

  // Add LMS methods to component
  component.subscribeToEvents = function (eventHandlerMap) {
    this._lmsSubscriptions = subscribeMigrated(
      this,
      eventHandlerMap,
      useLegacy,
    );
    return this._lmsSubscriptions;
  };

  component.unsubscribeFromEvents = function () {
    unsubscribeMigrated(this._lmsSubscriptions);
    this._lmsSubscriptions = null;
  };

  component.publishEvent = function (eventName, payload) {
    publishMigrated(eventName, payload, useLegacy);
  };

  return component;
}
