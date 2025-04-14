/**
 * Enhanced centralized store for duplicate manager application state
 * Uses Lightning Message Service exclusively for communication
 * Performance optimized to prevent freezing in Safari and other browsers
 *
 * @author Richard Hudson
 * @updated Richard Hudson - May 2025
 */
import {
  sendMessage,
  subscribeToChannel,
  unsubscribeFromChannel
} from "c/duplicationMessageService";
import { MESSAGE_TYPES } from "c/duplicationConstants";

// Throttle time for state updates to prevent freezing (ms)
const UPDATE_THROTTLE_MS = 200; // Increased from 50ms to 200ms to prevent Safari freezing

// Flag to track if updates are being throttled
let isThrottlingUpdates = false;
let pendingUpdate = null;

/**
 * Utility to safely check if we're in a browser environment with localStorage
 * @returns {Boolean} True if localStorage is available
 */
const isLocalStorageAvailable = (() => {
  let result = null;
  return () => {
    if (result !== null) return result;
    
    try {
      const test = "test";
      localStorage.setItem(test, test);
      localStorage.removeItem(test);
      result = true;
    } catch (e) {
      result = false;
    }
    return result;
  };
})();

/**
 * Safe localStorage wrapper with fallback
 */
const safeStorage = {
  getItem(key) {
    if (!isLocalStorageAvailable()) return null;
    try {
      return localStorage.getItem(key);
    } catch (e) {
      return null;
    }
  },
  setItem(key, value) {
    if (!isLocalStorageAvailable()) return;
    try {
      localStorage.setItem(key, value);
      return true;
    } catch (e) {
      return false;
    }
  },
  removeItem(key) {
    if (!isLocalStorageAvailable()) return;
    try {
      localStorage.removeItem(key);
      return true;
    } catch (e) {
      return false;
    }
  }
};

/**
 * Load initial draft job from localStorage if available
 * @returns {Object|null} Draft job or null if not found
 */
const loadInitialDraftJob = () => {
  const savedDraft = safeStorage.getItem("duplicateDraftJob");

  try {
    // Parse draft job data
    const draft = savedDraft ? JSON.parse(savedDraft) : null;
    if (!draft) return null;

    // Add missing fields
    if (!draft.timestamp) {
      draft.timestamp = Date.now();
    }
    if (!draft.status) {
      draft.status = "draft";
    }

    return draft;
  } catch (e) {
    return null;
  }
};

// Cache timeout in milliseconds (5 minutes)
const CACHE_TIMEOUT = 5 * 60 * 1000;

// Initial state - minimal version to reduce memory usage
const initialState = {
  configurations: [],
  selectedConfiguration: null,
  scheduledJobs: [],
  activeJobs: [],
  mergeRules: [],
  recentConfigurations: [],
  isLoading: false,
  errors: [],
  // Draft job state
  draftJob: loadInitialDraftJob(),
  // Cache metadata
  cache: {
    configurations: { timestamp: null, isPending: false },
    jobs: { timestamp: null, isPending: false },
    statistics: { timestamp: null, isPending: false }
  },
  // Statistics
  statistics: {
    totalDuplicates: 0,
    byObject: {},
    recentMerges: []
  },
  // Pagination state
  pagination: {
    pageSize: 10,
    currentPage: 1,
    totalRecords: 0,
    totalPages: 1
  }
};

// Store implementation
class duplicationStore {
  _state = { ...initialState };
  _listeners = [];
  _messageContext = null;
  _subscription = null;
  _instanceId = `store-${Date.now()}-${Math.floor(Math.random() * 10000)}`;
  _updateTimerId = null;
  _isInitialized = false;

  /**
   * Initialize the store with a message context
   * @param {MessageContext} messageContext - LWC message context
   */
  initialize(messageContext) {
    // Prevent double initialization which causes memory leaks
    if (this._isInitialized) return;
    
    try {
      this._messageContext = messageContext;
      this._isInitialized = true;

      // Make sure store has the initial state
      if (!this._state) {
        this._state = { ...initialState };
      }

      // Ensure loading state is initially false to prevent hangs
      this._state.isLoading = false;

      // Subscribe to store-related messages using optimized service
      this._subscription = subscribeToChannel(
        (message) => {
          try {
            // Only process our store messages
            if (!message || !message.type) return;
            
            // Skip our own messages
            if (message.source === this._instanceId) {
              return;
            }
            
            if (message.type === MESSAGE_TYPES.STORE_UPDATED) {
              // Update internal state from message
              this._applyExternalUpdate(message.payload);
            } else if (message.type === MESSAGE_TYPES.STORE_SECTION_UPDATED && message.payload) {
              // Apply sectional update if properly formed
              const { section, state } = message.payload;
              if (section && state) {
                this._applyExternalSectionUpdate(section, state);
              }
            }
          } catch (error) {
            // Silent error handling
          }
        },
        { filter: (msg) => msg && msg.type && msg.type.startsWith("store.") }
      );

      // Broadcast initial state to ensure all components sync
      // Use setTimeout to avoid Safari rendering issues
      setTimeout(() => {
        // Only send minimal state information to avoid large messages
        const minimalState = {
          isLoading: this._state.isLoading,
          hasConfiguration: !!this._state.selectedConfiguration,
          initialized: true
        };
        
        sendMessage(MESSAGE_TYPES.STORE_UPDATED, minimalState, {
          priority: "high",
          source: this._instanceId
        });
      }, 100); // Slight delay to ensure DOM is ready
    } catch (error) {
      // Reset to safe state on error
      this._state = { ...initialState, isLoading: false };
    }
  }

  /**
   * Clean up subscriptions when store is no longer needed
   */
  dispose() {
    this._isInitialized = false;
    
    // Cancel any pending updates
    if (this._updateTimerId) {
      clearTimeout(this._updateTimerId);
      this._updateTimerId = null;
    }
    
    // Clear pending update
    pendingUpdate = null;
    
    // Unsubscribe from messages
    if (this._subscription) {
      unsubscribeFromChannel(this._subscription);
      this._subscription = null;
    }
    
    // Clear listeners to prevent memory leaks
    this._listeners = [];
  }

  /**
   * Apply an external state update from another store instance
   * @param {Object} update - The state update to apply
   * @private
   */
  _applyExternalUpdate(update) {
    if (!update) return;

    const prevState = { ...this._state };

    // Apply the update (shallow copy at top level)
    this._state = { ...this._state, ...update };

    // Notify local listeners only (don't republish)
    this._notifyLocalListeners(prevState);
  }

  /**
   * Apply an external section update from another store instance
   * @param {String} section - The section to update
   * @param {Object} sectionState - The new section state
   * @private
   */
  _applyExternalSectionUpdate(section, sectionState) {
    if (!section || !sectionState) return;

    const prevState = { ...this._state };

    // Update just the specified section
    this._state[section] = Array.isArray(sectionState)
      ? [...sectionState]
      : { ...sectionState };

    // Notify local listeners only (don't republish)
    this._notifyLocalListeners(prevState);
  }

  /**
   * Notify just the local listeners (without broadcasting)
   * @param {Object} prevState - Previous state for comparison
   * @private
   */
  _notifyLocalListeners(prevState) {
    if (this._listeners.length === 0) return;
    
    const currentState = this.getState();

    // Use setTimeout instead of requestAnimationFrame to avoid Safari issues
    setTimeout(() => {
      // Notify direct subscribers - protect against errors in listeners
      this._listeners.forEach((listener) => {
        try {
          listener(currentState, prevState);
        } catch (error) {
          // Silent error handling
        }
      });
    }, 0);
  }

  /**
   * Get current state
   * @returns {Object} Shallow copy of current application state
   */
  getState() {
    return { ...this._state };
  }

  /**
   * Get a specific section of state
   * @param {String} section - The state section to retrieve
   * @returns {Object} The requested state section
   */
  getStateSection(section) {
    if (!section || this._state[section] === undefined) {
      return undefined;
    }
    
    return Array.isArray(this._state[section])
      ? [...this._state[section]]
      : { ...this._state[section] };
  }

  /**
   * Check if a cached section is still valid
   * @param {String} section - Cache section to check
   * @returns {Boolean} True if cache is valid
   */
  isCacheValid(section) {
    if (!section || !this._state.cache[section] || !this._state.cache[section].timestamp) {
      return false;
    }

    return Date.now() - this._state.cache[section].timestamp < CACHE_TIMEOUT;
  }

  /**
   * Check if there is an active draft job
   * @returns {Boolean} True if there is an active draft job
   */
  hasDraftJob() {
    return !!this._state.draftJob;
  }

  /**
   * Check if the draft job is for the specified configuration
   * @param {String} configId - Configuration ID to check
   * @returns {Boolean} True if draft is for the specified configuration
   */
  isDraftForConfig(configId) {
    return this._state.draftJob && this._state.draftJob.configId === configId;
  }

  /**
   * Action types for state mutations
   */
  static actions = {
    // Data actions
    SET_CONFIGURATIONS: "SET_CONFIGURATIONS",
    SELECT_CONFIGURATION: "SELECT_CONFIGURATION",
    UPDATE_SCHEDULED_JOBS: "UPDATE_SCHEDULED_JOBS",
    UPDATE_ACTIVE_JOBS: "UPDATE_ACTIVE_JOBS",
    SET_MERGE_RULES: "SET_MERGE_RULES",

    // Draft job actions
    SAVE_DRAFT_JOB: "SAVE_DRAFT_JOB",
    LOAD_DRAFT_JOB: "LOAD_DRAFT_JOB",
    CLEAR_DRAFT_JOB: "CLEAR_DRAFT_JOB",

    // UI state actions
    SET_LOADING: "SET_LOADING",
    SET_CACHE_PENDING: "SET_CACHE_PENDING",
    UPDATE_PAGINATION: "UPDATE_PAGINATION",

    // Recent items actions
    ADD_RECENT_CONFIGURATION: "ADD_RECENT_CONFIGURATION",
    CLEAR_RECENT_CONFIGURATIONS: "CLEAR_RECENT_CONFIGURATIONS",

    // Error handling
    ADD_ERROR: "ADD_ERROR",
    CLEAR_ERRORS: "CLEAR_ERRORS",

    // Statistics
    UPDATE_STATISTICS: "UPDATE_STATISTICS",
    ADD_MERGE_RESULT: "ADD_MERGE_RESULT",

    // Global actions
    RESET_STATE: "RESET_STATE",
    INVALIDATE_CACHE: "INVALIDATE_CACHE"
  };

  /**
   * Dispatch an action to update state
   * @param {string} actionType - Type of action to dispatch
   * @param {*} payload - Action payload
   */
  dispatch(actionType, payload) {
    // Check if action type is valid
    if (!actionType || !duplicationStore.actions) {
      return;
    }

    // Process action
    try {
      const prevState = { ...this._state };
      let stateChanged = false;
      let updatedSection = null;

      switch (actionType) {
        case duplicationStore.actions.SET_CONFIGURATIONS:
          this._state.configurations = Array.isArray(payload) ? payload : [];
          // Update cache timestamp
          this._state.cache.configurations = {
            timestamp: Date.now(),
            isPending: false
          };
          updatedSection = "configurations";
          stateChanged = true;
          break;

        case duplicationStore.actions.SELECT_CONFIGURATION:
          this._state.selectedConfiguration = payload;
          // Add to recent configurations if not already present
          if (
            payload &&
            !this._state.recentConfigurations.some(
              (c) => c.DeveloperName === payload.DeveloperName
            )
          ) {
            this._state.recentConfigurations = [
              payload,
              ...this._state.recentConfigurations.slice(0, 4) // Keep last 5 including current
            ];
          }
          updatedSection = "configurations";
          stateChanged = true;
          break;

        case duplicationStore.actions.UPDATE_SCHEDULED_JOBS:
          this._state.scheduledJobs = Array.isArray(payload) ? payload : [];
          // Update cache timestamp
          this._state.cache.jobs = {
            timestamp: Date.now(),
            isPending: false
          };
          updatedSection = "jobs";
          stateChanged = true;
          break;

        case duplicationStore.actions.UPDATE_ACTIVE_JOBS:
          this._state.activeJobs = Array.isArray(payload) ? payload : [];
          updatedSection = "jobs";
          stateChanged = true;
          break;

        case duplicationStore.actions.SET_LOADING:
          this._state.isLoading = Boolean(payload);
          stateChanged = true;
          break;

        case duplicationStore.actions.SET_CACHE_PENDING:
          if (
            payload &&
            payload.section &&
            this._state.cache[payload.section]
          ) {
            this._state.cache[payload.section].isPending = Boolean(payload.status);
            stateChanged = true;
          }
          break;

        case duplicationStore.actions.ADD_ERROR: {
          if (!payload) break;
          // Add timestamp and ID for error reference
          const errorObj = { 
            ...payload,
            timestamp: payload.timestamp || Date.now(),
            id: payload.id || `err-${Date.now()}-${Math.floor(Math.random() * 1000)}`
          };
          this._state.errors = [...this._state.errors, errorObj];
          updatedSection = "errors";
          stateChanged = true;
          break;
        }

        case duplicationStore.actions.CLEAR_ERRORS:
          this._state.errors = [];
          updatedSection = "errors";
          stateChanged = true;
          break;

        case duplicationStore.actions.ADD_RECENT_CONFIGURATION:
          if (
            payload &&
            !this._state.recentConfigurations.some(
              (c) => c.DeveloperName === payload.DeveloperName
            )
          ) {
            this._state.recentConfigurations = [
              payload,
              ...this._state.recentConfigurations.slice(0, 4) // Keep last 5 including current
            ];
            stateChanged = true;
          }
          break;

        case duplicationStore.actions.CLEAR_RECENT_CONFIGURATIONS:
          this._state.recentConfigurations = [];
          stateChanged = true;
          break;

        case duplicationStore.actions.SET_MERGE_RULES:
          this._state.mergeRules = Array.isArray(payload) ? payload : [];
          stateChanged = true;
          break;

        case duplicationStore.actions.UPDATE_STATISTICS:
          this._state.statistics = { ...this._state.statistics, ...payload };
          // Update cache timestamp
          this._state.cache.statistics = {
            timestamp: Date.now(),
            isPending: false
          };
          updatedSection = "statistics";
          stateChanged = true;
          break;

        case duplicationStore.actions.ADD_MERGE_RESULT:
          if (payload) {
            // Add to recent merges with timestamp
            const mergeResult = {
              ...payload,
              timestamp: payload.timestamp || Date.now()
            };
            this._state.statistics.recentMerges = [
              mergeResult,
              ...this._state.statistics.recentMerges.slice(0, 9) // Keep last 10
            ];

            // Update object statistics if applicable
            if (payload.objectApiName && payload.count) {
              const objStats = this._state.statistics.byObject[payload.objectApiName] || {
                totalDuplicates: 0,
                totalMerged: 0
              };

              objStats.totalMerged += payload.count;
              this._state.statistics.byObject[payload.objectApiName] = objStats;

              // Update total count
              this._state.statistics.totalDuplicates += payload.count;
            }
            
            updatedSection = "statistics";
            stateChanged = true;
          }
          break;

        case duplicationStore.actions.UPDATE_PAGINATION:
          this._state.pagination = { ...this._state.pagination, ...payload };
          updatedSection = "pagination";
          stateChanged = true;
          break;

        case duplicationStore.actions.INVALIDATE_CACHE:
          if (payload && this._state.cache[payload]) {
            // Invalidate specific cache
            this._state.cache[payload].timestamp = null;
          } else {
            // Invalidate all caches
            Object.keys(this._state.cache).forEach((key) => {
              this._state.cache[key].timestamp = null;
            });
          }
          stateChanged = true;
          break;

        case duplicationStore.actions.SAVE_DRAFT_JOB:
          if (payload) {
            // Preserve any existing draft data if merging with partial updates
            const existingDraft = this._state.draftJob || {};

            this._state.draftJob = {
              ...existingDraft,
              ...payload,
              timestamp: Date.now(),
              status: payload.status || existingDraft.status || "draft",
              lastModified: Date.now(),
              savedBy: payload.savedBy || existingDraft.savedBy
            };

            // Save to localStorage for persistence - use safeStorage wrapper
            safeStorage.setItem(
              "duplicateDraftJob",
              JSON.stringify(this._state.draftJob)
            );

            updatedSection = "draftJob";
            stateChanged = true;
          }
          break;

        case duplicationStore.actions.LOAD_DRAFT_JOB:
          try {
            // Try to load from localStorage first
            const savedDraft = safeStorage.getItem("duplicateDraftJob");
            if (savedDraft) {
              this._state.draftJob = JSON.parse(savedDraft);
              stateChanged = true;
            } else if (payload) {
              // If we have a payload, use that instead
              this._state.draftJob = payload;
              stateChanged = true;
            }
            updatedSection = "draftJob";
          } catch (loadError) {
            // Silent error handling for localStorage
          }
          break;

        case duplicationStore.actions.CLEAR_DRAFT_JOB:
          if (this._state.draftJob) {
            this._state.draftJob = null;
            // Remove from localStorage
            safeStorage.removeItem("duplicateDraftJob");
            updatedSection = "draftJob";
            stateChanged = true;
          }
          break;

        case duplicationStore.actions.RESET_STATE:
          this._state = { ...initialState };
          // Clear localStorage
          safeStorage.removeItem("duplicateDraftJob");
          stateChanged = true;
          break;

        default:
          // No action matched
          break;
      }

      if (stateChanged) {
        // Use the throttling mechanism to prevent excessive updates
        this._scheduleUpdate(prevState, updatedSection);
      }
    } catch (error) {
      // Silent error handling
    }
  }

  /**
   * Schedule an update with throttling to prevent freezing
   * @param {Object} prevState - Previous state for comparison
   * @param {String} updatedSection - Section of state that was updated
   * @private
   */
  _scheduleUpdate(prevState, updatedSection) {
    // If we're already throttling updates, just update the pending update data
    if (isThrottlingUpdates) {
      pendingUpdate = { prevState, updatedSection };
      return;
    }
    
    // Set throttling flag
    isThrottlingUpdates = true;
    
    // Schedule this update immediately
    this._processPendingUpdate(prevState, updatedSection);
    
    // Schedule processing for future updates
    this._updateTimerId = setTimeout(() => {
      isThrottlingUpdates = false;
      this._updateTimerId = null;
      
      // If there's a pending update, process it
      if (pendingUpdate) {
        const { prevState, updatedSection } = pendingUpdate;
        pendingUpdate = null;
        this._scheduleUpdate(prevState, updatedSection);
      }
    }, UPDATE_THROTTLE_MS);
  }
  
  /**
   * Process a pending update by notifying listeners
   * @param {Object} prevState - Previous state for comparison
   * @param {String} updatedSection - Section of state that was updated
   * @private
   */
  _processPendingUpdate(prevState, updatedSection) {
    const currentState = this.getState();
    
    // Use setTimeout instead of requestAnimationFrame to avoid Safari issues
    setTimeout(() => {
      // Use Lightning Message Service with optimized messaging
      if (updatedSection) {
        // If a specific section was updated, publish just that section
        sendMessage(
          MESSAGE_TYPES.STORE_SECTION_UPDATED,
          { section: updatedSection, state: currentState[updatedSection] },
          {
            priority: "normal",
            source: this._instanceId
          }
        );
      } else {
        // For full state updates, send only key information instead of the entire state
        // This reduces the message size and prevents unnecessary re-renders
        const minimalState = {
          isLoading: currentState.isLoading,
          hasError: currentState.errors && currentState.errors.length > 0,
          lastUpdated: new Date().toISOString()
        };
        
        sendMessage(MESSAGE_TYPES.STORE_UPDATED, minimalState, {
          priority: "normal",
          source: this._instanceId
        });
      }

      // Also notify local listeners
      this._notifyLocalListeners(prevState);
    }, 0);
  }

  /**
   * Subscribe to state changes
   * @param {function} listener - Function to call on state change
   * @returns {function} Unsubscribe function
   */
  subscribe(listener) {
    if (typeof listener !== 'function') return () => {};
    
    this._listeners.push(listener);
    
    // Return unsubscribe function
    return () => {
      this._listeners = this._listeners.filter((l) => l !== listener);
    };
  }
}

/**
 * Create and export singleton instance
 */
const store = new duplicationStore();

export { duplicationStore };
export default store;
