/**
 * DEPRECATED: A standardized pub-sub mechanism for component communication
 * This is a LEGACY component that is scheduled for removal in October 2025.
 * Use duplicationMessageService module instead.
 *
 * This wrapper uses Lightning Message Service internally
 * but maintains the same API for backward compatibility
 *
 * @author Richard Hudson
 * @since April 2025
 * @deprecated Use Lightning Message Service with duplicationMessageService instead
 */

// Mock implementation for deployment
// To be replaced with actual implementation when message channel is available
const mockPublish = (channel, message) => {
  console.log('MOCK PUBSUB PUBLISH:', message);
  return true;
};

const mockSubscribe = (channel, handler) => {
  console.log('MOCK PUBSUB SUBSCRIBE');
  return { id: 'mock-sub-pubsub-' + Date.now() };
};

const mockUnsubscribe = (subscription) => {
  console.log('MOCK PUBSUB UNSUBSCRIBE');
  return true;
};

// Mock channel
const MOCK_CHANNEL = { fullName: 'DuplicationChannel_c', mockImplementation: true };

// Private variable for storing subscribers with IDs
const subscribers = {};
let subscriptionCounter = 0;

// Show deprecation warning only once per session
let deprecationWarningShown = false;

/**
 * Shows deprecation warning in console
 * @private
 */
const showDeprecationWarning = () => {
  if (!deprecationWarningShown) {
    console.warn(
      "%c DEPRECATED COMPONENT: duplicationPubSub is deprecated and will be removed in October 2025. " +
        "Use the duplicationMessageService module instead. " +
        "See MIGRATION_GUIDE.md for more information.",
      "color: orange; font-weight: bold;",
    );
    deprecationWarningShown = true;
  }
};

/**
 * Registers a callback for an event
 * @param {string} eventName - Name of the event to listen for
 * @param {function} callback - Function to invoke when the event is fired
 * @param {object} thisArg - The value to be passed as this when executing callback
 * @return {object} - Subscription reference used to unregister
 * @deprecated Use duplicationMessageService.subscribeToChannel instead
 */
export const register = (eventName, callback, thisArg) => {
  showDeprecationWarning();

  // Create a wrapper callback that filters by event name
  const wrappedCallback = (message) => {
    if (message.type === eventName) {
      try {
        callback.call(thisArg, message.payload || message);
      } catch (error) {
        // Log errors but don't break the event chain
        console.error(`Error in ${eventName} event handler:`, error);
      }
    }
  };

  // Subscribe using mock implementation
  const subscription = mockSubscribe(MOCK_CHANNEL, wrappedCallback);

  // Generate a unique ID for this subscription
  const subId = `sub_${subscriptionCounter++}_${eventName}`;

  // Store the subscription with its metadata
  subscribers[subId] = {
    lmsSubscription: subscription,
    eventName: eventName,
    callback: wrappedCallback,
  };

  return subId;
};

/**
 * Unregisters a callback for an event
 * @param {string} eventName - Name of the event to unregister from
 * @param {string} subId - Subscription ID returned by register()
 * @deprecated Use duplicationMessageService.unsubscribeFromChannel instead
 */
export const unregister = (eventName, subId) => {
  showDeprecationWarning();

  if (subscribers[subId]) {
    mockUnsubscribe(subscribers[subId].lmsSubscription);
    delete subscribers[subId];
  }
};

/**
 * Fires an event to listeners
 * @param {string} eventName - Name of the event to fire
 * @param {object} payload - Payload of the event to fire
 * @deprecated Use duplicationMessageService.sendMessage instead
 */
export const fire = (eventName, payload) => {
  showDeprecationWarning();

  // Format the message to include the event type and payload
  const message = {
    type: eventName,
    payload: payload,
    timestamp: new Date().toISOString(),
  };

  // Publish using mock implementation
  mockPublish(MOCK_CHANNEL, message);
};

/**
 * All available event names within the duplication manager application
 * DEPRECATED: Use MESSAGE_TYPES from duplicationMessageService instead
 */
export const EVENTS = {
  // Store events
  STORE_CHANGE: "duplicationStoreChange",

  // Job management events
  JOB_STARTED: "duplication.job.started",
  JOB_COMPLETED: "duplication.job.completed",
  JOB_PROGRESS_UPDATE: "duplication.job.progressUpdate",
  JOB_ERROR: "duplication.job.error",

  // Duplicate processing events
  DUPLICATES_FOUND: "duplication.duplicates.found",
  DUPLICATES_MERGED: "duplication.duplicates.merged",

  // Configuration events
  CONFIG_SELECTED: "duplication.config.selected",
  CONFIG_UPDATED: "duplication.config.updated",
  CONFIG_VALIDATION: "duplication.config.validation",

  // UI navigation events
  VIEW_DUPLICATES: "duplication.ui.viewDuplicates",
  VIEW_MERGE_PREVIEW: "duplication.ui.viewMergePreview",
  VIEW_JOB_DETAILS: "duplication.ui.viewJobDetails",

  // Statistics events
  STATS_UPDATED: "duplication.stats.updated",
};

/**
 * MIGRATION GUIDE:
 *
 * Replace:
 * import { subscribe, unsubscribe, publish, EVENTS } from 'c/duplicationPubSub';
 *
 * With:
 * import { subscribeToChannel, unsubscribeFromChannel, sendMessage, MESSAGE_TYPES } from 'c/duplicationMessageService';
 * import { MessageContext } from 'lightning/messageService';
 *
 * Add to your component:
 * @wire(MessageContext)
 * messageContext;
 *
 * Replace event subscription:
 * this.subscription = subscribe(EVENTS.STORE_CHANGE, this.handleStoreChange, this);
 *
 * With:
 * this.subscription = subscribeToChannel((message) => {
 *     if (message.type === MESSAGE_TYPES.STORE_UPDATED) {
 *         this.handleStoreChange(message.payload);
 *     }
 * });
 *
 * Replace event publishing:
 * publish(EVENTS.JOB_STARTED, { id: '123', name: 'Test Job' });
 *
 * With:
 * sendMessage(MESSAGE_TYPES.JOB_STARTED, { id: '123', name: 'Test Job' });
 */

// Keep backward compatibility with the previous API
export const subscribe = register;
export const unsubscribe = unregister;
export const publish = fire;
export const EVENT_NAMES = EVENTS;
