/**
 * Enhanced centralized store for duplication manager application state
 * Uses Lightning Message Service exclusively for communication
 *
 * @author Original Author
 * @updated Richard Hudson - May 2025
 */
// import { MessageContext } from 'lightning/messageService';
import {
  sendMessage,
  subscribeToChannel,
  unsubscribeFromChannel,
  MESSAGE_TYPES,
} from "c/duplicationMessageService";

/**
 * Utility to check if we're in a browser environment with localStorage
 * @returns {Boolean} True if localStorage is available
 */
const isLocalStorageAvailable = () => {
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
 * Load initial draft job from localStorage if available
 * @returns {Object|null} Draft job or null if not found
 */
const loadInitialDraftJob = () => {
  if (!isLocalStorageAvailable()) {
    return null;
  }

  try {
    const savedDraft = localStorage.getItem("duplicationDraftJob");

    // Parse draft job data
    const draft = savedDraft ? JSON.parse(savedDraft) : null;

    // Add timestamp if not present
    if (draft && !draft.timestamp) {
      draft.timestamp = new Date().toISOString();
    }

    // Add status if not present
    if (draft && !draft.status) {
      draft.status = "draft";
    }

    return draft;
  } catch (e) {
    console.error("Error loading initial draft job:", e);
    return null;
  }
};

// Cache timeout in milliseconds (5 minutes)
const CACHE_TIMEOUT = 5 * 60 * 1000;

// Initial state
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
    configurations: {
      timestamp: null,
      isPending: false,
    },
    jobs: {
      timestamp: null,
      isPending: false,
    },
    statistics: {
      timestamp: null,
      isPending: false,
    },
  },
  // Statistics
  statistics: {
    totalDuplicates: 0,
    byObject: {},
    recentMerges: [],
  },
  // Pagination state
  pagination: {
    pageSize: 10,
    currentPage: 1,
    totalRecords: 0,
    totalPages: 1,
  },
};

// Store implementation
class DuplicationStore {
  _state = { ...initialState };
  _listeners = [];
  _messageContext = null;
  _subscription = null;
  _instanceId = "store-" + Date.now() + "-" + Math.floor(Math.random() * 10000);

  /**
   * Initialize the store with a message context
   * @param {MessageContext} messageContext - LWC message context
   */
  initialize(messageContext) {
    this._messageContext = messageContext;

    // Subscribe to store-related messages
    this._subscription = subscribeToChannel(
      (message) => {
        // Only process store update messages
        if (message.type === MESSAGE_TYPES.STORE_UPDATED) {
          // Update internal state from message
          const storeUpdate = message.payload;

          // Skip if message came from this instance
          if (message.source === this._instanceId) {
            return;
          }

          // Apply the update to our state
          this._applyExternalUpdate(storeUpdate);
        } else if (message.type === MESSAGE_TYPES.STORE_SECTION_UPDATED) {
          // Handle sectional updates
          const sectionUpdate = message.payload;

          // Skip if message came from this instance
          if (message.source === this._instanceId) {
            return;
          }

          // Apply the section update to our state
          if (sectionUpdate && sectionUpdate.section && sectionUpdate.state) {
            this._applyExternalSectionUpdate(
              sectionUpdate.section,
              sectionUpdate.state,
            );
          }
        }
      },
      { filter: (msg) => msg.type.startsWith("store.") },
    );

    console.log("Store initialized with instance ID:", this._instanceId);
  }

  /**
   * Clean up subscriptions when store is no longer needed
   */
  dispose() {
    if (this._subscription) {
      unsubscribeFromChannel(this._subscription);
      this._subscription = null;
    }
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
    const currentState = this.getState();

    // Notify direct subscribers
    this._listeners.forEach((listener) => {
      try {
        listener(currentState, prevState);
      } catch (error) {
        console.error("Error in store listener:", error);
      }
    });
  }

  /**
   * Get current state
   * @returns {Object} Current application state
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
    if (this._state[section] !== undefined) {
      return Array.isArray(this._state[section])
        ? [...this._state[section]]
        : { ...this._state[section] };
    }
    return undefined;
  }

  /**
   * Check if a cached section is still valid
   * @param {String} section - Cache section to check
   * @returns {Boolean} True if cache is valid
   */
  isCacheValid(section) {
    if (!this._state.cache[section] || !this._state.cache[section].timestamp) {
      return false;
    }

    const now = new Date().getTime();
    const timestamp = this._state.cache[section].timestamp;
    return now - timestamp < CACHE_TIMEOUT;
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
   * Get message timestamp
   * @returns {String} ISO timestamp
   * @private
   */
  _getTimestamp() {
    return new Date().toISOString();
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
    INVALIDATE_CACHE: "INVALIDATE_CACHE",
  };

  /**
   * Dispatch an action to update state
   * @param {string} actionType - Type of action to dispatch
   * @param {*} payload - Action payload
   */
  dispatch(actionType, payload) {
    console.log(`Dispatching action: ${actionType}`, payload);

    const prevState = { ...this._state };
    let stateChanged = false;

    switch (actionType) {
      case DuplicationStore.actions.SET_CONFIGURATIONS:
        this._state.configurations = Array.isArray(payload) ? payload : [];
        // Update cache timestamp
        this._state.cache.configurations = {
          timestamp: new Date().getTime(),
          isPending: false,
        };
        stateChanged = true;
        break;

      case DuplicationStore.actions.SELECT_CONFIGURATION:
        this._state.selectedConfiguration = payload;
        // Add to recent configurations if not already present
        if (
          payload &&
          !this._state.recentConfigurations.some(
            (c) => c.DeveloperName === payload.DeveloperName,
          )
        ) {
          this._state.recentConfigurations = [
            payload,
            ...this._state.recentConfigurations.slice(0, 4), // Keep last 5 including current
          ];
        }
        stateChanged = true;
        break;

      case DuplicationStore.actions.UPDATE_SCHEDULED_JOBS:
        this._state.scheduledJobs = Array.isArray(payload) ? payload : [];
        // Update cache timestamp
        this._state.cache.jobs = {
          timestamp: new Date().getTime(),
          isPending: false,
        };
        stateChanged = true;
        break;

      case DuplicationStore.actions.UPDATE_ACTIVE_JOBS:
        this._state.activeJobs = Array.isArray(payload) ? payload : [];
        stateChanged = true;
        break;

      case DuplicationStore.actions.SET_LOADING:
        this._state.isLoading = Boolean(payload);
        stateChanged = true;
        break;

      case DuplicationStore.actions.SET_CACHE_PENDING:
        if (payload && payload.section && this._state.cache[payload.section]) {
          this._state.cache[payload.section].isPending = Boolean(
            payload.status,
          );
          stateChanged = true;
        }
        break;

      case DuplicationStore.actions.ADD_ERROR: {
        // Add timestamp if not already present
        const errorObj = { ...payload };
        if (!errorObj.timestamp) {
          errorObj.timestamp = new Date().toISOString();
        }
        // Add unique id for error reference
        if (!errorObj.id) {
          errorObj.id = `err-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
        }
        this._state.errors = [...this._state.errors, errorObj];
        stateChanged = true;
        break;
      }

      case DuplicationStore.actions.CLEAR_ERRORS:
        this._state.errors = [];
        stateChanged = true;
        break;

      case DuplicationStore.actions.ADD_RECENT_CONFIGURATION:
        if (
          payload &&
          !this._state.recentConfigurations.some(
            (c) => c.DeveloperName === payload.DeveloperName,
          )
        ) {
          this._state.recentConfigurations = [
            payload,
            ...this._state.recentConfigurations.slice(0, 4), // Keep last 5 including current
          ];
          stateChanged = true;
        }
        break;

      case DuplicationStore.actions.CLEAR_RECENT_CONFIGURATIONS:
        this._state.recentConfigurations = [];
        stateChanged = true;
        break;

      case DuplicationStore.actions.SET_MERGE_RULES:
        this._state.mergeRules = Array.isArray(payload) ? payload : [];
        stateChanged = true;
        break;

      case DuplicationStore.actions.UPDATE_STATISTICS:
        this._state.statistics = { ...this._state.statistics, ...payload };
        // Update cache timestamp
        this._state.cache.statistics = {
          timestamp: new Date().getTime(),
          isPending: false,
        };
        stateChanged = true;
        break;

      case DuplicationStore.actions.ADD_MERGE_RESULT:
        if (payload) {
          // Add to recent merges with timestamp
          const mergeResult = {
            ...payload,
            timestamp: payload.timestamp || new Date().toISOString(),
          };
          this._state.statistics.recentMerges = [
            mergeResult,
            ...this._state.statistics.recentMerges.slice(0, 9), // Keep last 10
          ];

          // Update object statistics if applicable
          if (payload.objectApiName && payload.count) {
            const objStats = this._state.statistics.byObject[
              payload.objectApiName
            ] || {
              totalDuplicates: 0,
              totalMerged: 0,
            };

            objStats.totalMerged += payload.count;
            this._state.statistics.byObject[payload.objectApiName] = objStats;

            // Update total count
            this._state.statistics.totalDuplicates += payload.count;
          }

          stateChanged = true;
        }
        break;

      case DuplicationStore.actions.UPDATE_PAGINATION:
        this._state.pagination = { ...this._state.pagination, ...payload };
        stateChanged = true;
        break;

      case DuplicationStore.actions.INVALIDATE_CACHE:
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

      case DuplicationStore.actions.SAVE_DRAFT_JOB:
        if (payload) {
          // Preserve any existing draft data if merging with partial updates
          const existingDraft = this._state.draftJob || {};

          this._state.draftJob = {
            ...existingDraft,
            ...payload,
            timestamp: new Date().toISOString(),
            status: payload.status || existingDraft.status || "draft",
            lastModified: new Date().toISOString(),
            savedBy: payload.savedBy || existingDraft.savedBy,
          };

          // Save to localStorage for persistence
          try {
            localStorage.setItem(
              "duplicationDraftJob",
              JSON.stringify(this._state.draftJob),
            );
          } catch (storageError) {
            console.error(
              "Error saving draft job to localStorage:",
              storageError,
            );
          }

          stateChanged = true;
        }
        break;

      case DuplicationStore.actions.LOAD_DRAFT_JOB:
        try {
          // Try to load from localStorage first
          const savedDraft = localStorage.getItem("duplicationDraftJob");
          if (savedDraft) {
            this._state.draftJob = JSON.parse(savedDraft);
            stateChanged = true;
          } else if (payload) {
            // If we have a payload, use that instead
            this._state.draftJob = payload;
            stateChanged = true;
          }
        } catch (loadError) {
          console.error(
            "Error loading draft job from localStorage:",
            loadError,
          );
        }
        break;

      case DuplicationStore.actions.CLEAR_DRAFT_JOB:
        if (this._state.draftJob) {
          this._state.draftJob = null;

          // Remove from localStorage
          try {
            localStorage.removeItem("duplicationDraftJob");
          } catch (removeError) {
            console.error(
              "Error removing draft job from localStorage:",
              removeError,
            );
          }

          stateChanged = true;
        }
        break;

      case DuplicationStore.actions.RESET_STATE:
        this._state = { ...initialState };

        // Clear localStorage
        try {
          localStorage.removeItem("duplicationDraftJob");
        } catch (resetError) {
          console.error(
            "Error removing draft job from localStorage:",
            resetError,
          );
        }

        stateChanged = true;
        break;

      default:
        console.warn(`Unknown action type: ${actionType}`);
    }

    if (stateChanged) {
      // Determine which section was updated for more granular updates
      let updatedSection = null;

      // Map action types to state sections
      switch (actionType) {
        case DuplicationStore.actions.SET_CONFIGURATIONS:
        case DuplicationStore.actions.SELECT_CONFIGURATION:
          updatedSection = "configurations";
          break;
        case DuplicationStore.actions.UPDATE_SCHEDULED_JOBS:
        case DuplicationStore.actions.UPDATE_ACTIVE_JOBS:
          updatedSection = "jobs";
          break;
        case DuplicationStore.actions.SAVE_DRAFT_JOB:
        case DuplicationStore.actions.LOAD_DRAFT_JOB:
        case DuplicationStore.actions.CLEAR_DRAFT_JOB:
          updatedSection = "draftJob";
          break;
        case DuplicationStore.actions.UPDATE_STATISTICS:
        case DuplicationStore.actions.ADD_MERGE_RESULT:
          updatedSection = "statistics";
          break;
        case DuplicationStore.actions.UPDATE_PAGINATION:
          updatedSection = "pagination";
          break;
        case DuplicationStore.actions.ADD_ERROR:
        case DuplicationStore.actions.CLEAR_ERRORS:
          updatedSection = "errors";
          break;
        // Global state updates don't have a specific section
        default:
          updatedSection = null;
      }

      this._notifyListeners(prevState, updatedSection);
    }
  }

  /**
   * Subscribe to state changes
   * @param {function} listener - Function to call on state change
   * @returns {function} Unsubscribe function
   */
  subscribe(listener) {
    this._listeners.push(listener);
    return () => {
      this._listeners = this._listeners.filter((l) => l !== listener);
    };
  }

  /**
   * Notify all subscribed listeners about state change
   * @param {Object} prevState - Previous state for comparison
   * @param {String} updatedSection - Section of state that was updated
   * @private
   */
  _notifyListeners(prevState, updatedSection) {
    const currentState = this.getState();

    // Use Lightning Message Service with enhanced capabilities
    if (updatedSection) {
      // If a specific section was updated, publish just that section
      sendMessage(
        MESSAGE_TYPES.STORE_SECTION_UPDATED,
        { section: updatedSection, state: currentState[updatedSection] },
        {
          priority: "normal",
          source: this._instanceId,
        },
      );
    } else {
      // Otherwise publish the full state update
      sendMessage(MESSAGE_TYPES.STORE_UPDATED, currentState, {
        priority: "normal",
        source: this._instanceId,
      });
    }

    // Also notify local listeners
    this._notifyLocalListeners(prevState);
  }
}

// Create and export singleton instance
const store = new DuplicationStore();
export { legacyStore };
export { DuplicationStore };

/**
 * Simple store implementation for state management across components
 * Implements a Redux-like pattern with actions and reducers
 *
 * @author Richard Hudson
 * @since April 2025
 */

// Store state
let state = {
    isLoading: false,
    statistics: null,
    selectedTimeRange: 'LAST_30_DAYS',
    errors: [],
    jobs: {
        recent: [],
        scheduled: [],
        current: null
    },
    ui: {
        viewMode: 'card'
    },
    cache: {}
};

// Action types
const ACTION_TYPES = {
    SET_LOADING: 'SET_LOADING',
    UPDATE_STATISTICS: 'UPDATE_STATISTICS',
    SET_TIME_RANGE: 'SET_TIME_RANGE',
    ADD_ERROR: 'ADD_ERROR',
    CLEAR_ERRORS: 'CLEAR_ERROR',
    UPDATE_JOBS: 'UPDATE_JOBS',
    SET_CURRENT_JOB: 'SET_CURRENT_JOB',
    SET_VIEW_MODE: 'SET_VIEW_MODE',
    INVALIDATE_CACHE: 'INVALIDATE_CACHE',
    SET_CACHE_ITEM: 'SET_CACHE_ITEM'
};

// Actions
export const actions = {
    SET_LOADING: 'SET_LOADING',
    UPDATE_STATISTICS: 'UPDATE_STATISTICS',
    SET_TIME_RANGE: 'SET_TIME_RANGE',
    ADD_ERROR: 'ADD_ERROR',
    CLEAR_ERRORS: 'CLEAR_ERROR',
    UPDATE_JOBS: 'UPDATE_JOBS',
    SET_CURRENT_JOB: 'SET_CURRENT_JOB',
    SET_VIEW_MODE: 'SET_VIEW_MODE',
    INVALIDATE_CACHE: 'INVALIDATE_CACHE',
    SET_CACHE_ITEM: 'SET_CACHE_ITEM'
};

/**
 * Reducer function to handle state updates
 * @param {Object} currentState Current state
 * @param {String} actionType Type of action
 * @param {Object} payload Action payload data
 * @return {Object} New state
 */
function reducer(currentState, actionType, payload) {
    // Return a new state object (immutability)
    let newState = JSON.parse(JSON.stringify(currentState));

    switch(actionType) {
        case ACTION_TYPES.SET_LOADING:
            newState.isLoading = payload;
            break;

        case ACTION_TYPES.UPDATE_STATISTICS:
            newState.statistics = payload;
            break;

        case ACTION_TYPES.SET_TIME_RANGE:
            newState.selectedTimeRange = payload;
            break;

        case ACTION_TYPES.ADD_ERROR:
            newState.errors.push({
                ...payload,
                id: generateId(),
                timestamp: payload.timestamp || new Date().toISOString()
            });
            // Keep only the most recent 10 errors
            if (newState.errors.length > 10) {
                newState.errors = newState.errors.slice(newState.errors.length - 10);
            }
            break;

        case ACTION_TYPES.CLEAR_ERRORS:
            newState.errors = [];
            break;

        case ACTION_TYPES.UPDATE_JOBS:
            if (payload.recent) {
                newState.jobs.recent = payload.recent;
            }
            if (payload.scheduled) {
                newState.jobs.scheduled = payload.scheduled;
            }
            break;

        case ACTION_TYPES.SET_CURRENT_JOB:
            newState.jobs.current = payload;
            break;

        case ACTION_TYPES.SET_VIEW_MODE:
            newState.ui.viewMode = payload;
            break;

        case ACTION_TYPES.INVALIDATE_CACHE:
            if (typeof payload === 'string') {
                // Invalidate specific cache item
                delete newState.cache[payload];
            } else {
                // Invalidate all cache
                newState.cache = {};
            }
            break;

        case ACTION_TYPES.SET_CACHE_ITEM:
            if (payload && payload.key) {
                newState.cache[payload.key] = {
                    data: payload.data,
                    timestamp: new Date().toISOString()
                };
            }
            break;
    }

    return newState;
}

/**
 * Simple store implementation
 */
const legacyStore = {
    /**
     * Dispatch an action to update state
     * @param {String} actionType Type of action
     * @param {Object} payload Action payload data
     */
    dispatch(actionType, payload) {
        const oldState = state;
        state = reducer(state, actionType, payload);

        // Send message to notify subscribers
        sendMessage('store_updated', {
            section: getSectionFromAction(actionType),
            actionType,
            previousState: oldState,
            currentState: state
        });
    },

    /**
     * Get current state (returns a copy to prevent direct mutation)
     * @returns {Object} Current state
     */
    getState() {
        return JSON.parse(JSON.stringify(state));
    },

    /**
     * Check if a cache item exists and is valid
     * @param {String} key Cache item key
     * @param {Number} maxAgeMs Maximum age in milliseconds
     * @returns {Boolean} True if cache item is valid
     */
    isCacheValid(key, maxAgeMs = 300000) {
        if (!state.cache[key] || !state.cache[key].timestamp) {
            return false;
        }

        const timestamp = new Date(state.cache[key].timestamp).getTime();
        const now = new Date().getTime();

        return (now - timestamp) < maxAgeMs;
    },

    /**
     * Get a cached item
     * @param {String} key Cache item key
     * @returns {Object} Cached data or null
     */
    getCacheItem(key) {
        return state.cache[key] ? state.cache[key].data : null;
    },

    /**
     * Initial state to reset to
     */
    initialState: { ...state }
};

/**
 * Helper to determine which section of state was affected by an action
 * @param {String} actionType Action type
 * @returns {String} State section name
 */
function getSectionFromAction(actionType) {
    if (actionType.includes('STATISTICS')) {
        return 'statistics';
    } else if (actionType.includes('JOB')) {
        return 'jobs';
    } else if (actionType.includes('ERROR')) {
        return 'errors';
    } else if (actionType.includes('CACHE')) {
        return 'cache';
    } else if (actionType.includes('VIEW_MODE')) {
        return 'ui';
    } else if (actionType.includes('TIME_RANGE')) {
        return 'timeRange';
    }

    return 'general';
}

/**
 * Generate a random ID
 * @returns {String} Random ID
 */
function generateId() {
    return Math.random().toString(36).substring(2, 15) +
        Math.random().toString(36).substring(2, 15);
}

export default store;
