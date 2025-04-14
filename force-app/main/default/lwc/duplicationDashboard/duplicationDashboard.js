import { LightningElement, track, wire } from "lwc";
import { MessageContext } from "lightning/messageService";
import {
  subscribeToChannel,
  unsubscribeFromChannel,
  sendMessage
} from "c/duplicationMessageService";
import { MESSAGE_TYPES } from "c/duplicationConstants";
import { TIME_RANGES } from "c/duplicationConstants";
import store from "c/duplicationStore";
import * as duplicationStore from "c/duplicationStore";
import getDetailedStatistics from "@salesforce/apex/DuplicateController.getDetailedStatistics";
/**
 * Enhanced dashboard component displaying duplication record statistics with modern UI
 *
 * @author Richard Hudson
 * @updated May 2025
 */
export default class DuplicationDashboard extends LightningElement {
  // Statistics data
  @track statistics = {
    totalDuplicates: 0,
    totalMerged: 0,
    byObject: {},
    recentMerges: [],
  };

  // Data and display state
  @track chartData = [];
  @track isLoading = true;
  @track error = null;
  @track lastRefresh = null;
  @track timeRange = "LAST_30_DAYS"; // Default time range
  @track lastPeriodStats = null; // For trend calculation

  // UI state
  @track debounceTimeout = null;
  @track showTableView = true; // Always show table view instead of chart

  // Store subscriptions
  subscriptions = [];

  // Get message context for LMS
  @wire(MessageContext)
  messageContext;

  /**
   * Lifecycle hook - Component connected to DOM
   */
  connectedCallback() {
    // Subscribe to messages
    this.subscribeToMessages();

    // Show loading indicator
    this.isLoading = true;
    store.dispatch(duplicationStore.actions.SET_LOADING, true);

    // Load statistics from server
    this.loadStatistics();
  }

  /**
   * Lifecycle hook - Component disconnected from DOM
   */
  disconnectedCallback() {
    // Clear any pending timeouts
    if (this.debounceTimeout) {
      window.clearTimeout(this.debounceTimeout);
      this.debounceTimeout = null;
    }

    // Unsubscribe from all messages
    this.unsubscribeFromMessages();
  }

  /**
   * Subscribe to LMS messages
   */
  subscribeToMessages() {
    // Subscribe to store changes
    const storeSubscription = subscribeToChannel((message) => {
      if (
        message.type === MESSAGE_TYPES.STORE_UPDATED ||
        message.type === MESSAGE_TYPES.STORE_SECTION_UPDATED
      ) {
        this.handleStoreChange(message.payload);
      }
    });
    this.subscriptions.push(storeSubscription);

    // Subscribe to refresh requests
    const refreshSubscription = subscribeToChannel((message) => {
      if (message.type === MESSAGE_TYPES.REFRESH_STATISTICS) {
        this.handleRefresh();
      }
    });
    this.subscriptions.push(refreshSubscription);

    // Subscribe to time range changes
    const timeRangeSubscription = subscribeToChannel((message) => {
      if (
        message.type === MESSAGE_TYPES.TIME_RANGE_CHANGED &&
        message.payload &&
        message.payload.timeRange &&
        message.payload.source !== "dashboard"
      ) {
        if (this.timeRange !== message.payload.timeRange) {
          this.timeRange = message.payload.timeRange;
          this.handleRefresh();
        }
      }
    });
    this.subscriptions.push(timeRangeSubscription);

    // Subscribe to job completion messages
    const jobCompletionSubscription = subscribeToChannel((message) => {
      if (message.type === MESSAGE_TYPES.JOB_COMPLETED) {
        // Auto refresh dashboard when jobs complete
        this.handleRefresh();
      }
    });
    this.subscriptions.push(jobCompletionSubscription);
  }

  /**
   * Unsubscribe from all messages
   */
  unsubscribeFromMessages() {
    this.subscriptions.forEach((subscription) => {
      unsubscribeFromChannel(subscription);
    });
    this.subscriptions = [];
  }

  /**
   * Handle store state changes
   */
  handleStoreChange() {
    this.syncFromStore();
  }

  /**
   * Sync component state from store
   */
  syncFromStore() {
    const state = store.getState();
    this.isLoading = state.isLoading;

    // Update statistics from store
    if (state.statistics) {
      this.statistics = { ...state.statistics };
      this.prepareChartData();
    }
  }


  /**
   * Load statistics from server
   */
  loadStatistics() {
    this.isLoading = true;

    // If we have current statistics, save them for trend calculation
    if (
      this.statistics &&
      this.statistics.totalDuplicates !== undefined &&
      this.statistics.totalMerged !== undefined
    ) {
      this.lastPeriodStats = {
        totalDuplicates: this.statistics.totalDuplicates,
        totalMerged: this.statistics.totalMerged,
        mergeRate: this.mergeRate,
      };
    }

    // Notify that statistics are loading via LMS
    sendMessage(MESSAGE_TYPES.STATISTICS_LOADING, {
      timeRange: this.timeRange,
    });

    // Use Apex method to get detailed statistics
    getDetailedStatistics({ timeRange: this.timeRange })
      .then((result) => {
        // Update store with statistics
        store.dispatch(duplicationStore.actions.UPDATE_STATISTICS, result);
        this.lastRefresh = new Date();

        // Initialize from store after updating it
        this.syncFromStore();

        // Notify that statistics are loaded via LMS
        sendMessage(MESSAGE_TYPES.STATISTICS_LOADED, {
          timeRange: this.timeRange,
          statistics: result,
          timestamp: new Date().toISOString(),
        });
      })
      .catch((error) => {
        this.handleError("Error loading statistics", error);

        // Notify about failure via LMS
        sendMessage(MESSAGE_TYPES.STATISTICS_LOAD_ERROR, {
          timeRange: this.timeRange,
          error: error.message || "Unknown error",
          timestamp: new Date().toISOString(),
        });
      })
      .finally(() => {
        // Stop loading
        this.isLoading = false;
        store.dispatch(duplicationStore.actions.SET_LOADING, false);
      });
  }

  /**
   * Prepare data for charts
   */
  prepareChartData() {
    // Prepare data for object breakdown chart
    const byObjectData = [];

    if (this.statistics.byObject) {
      Object.keys(this.statistics.byObject).forEach((objName) => {
        const objStats = this.statistics.byObject[objName];
        byObjectData.push({
          name: objName,
          value: objStats.totalDuplicates || 0,
          merged: objStats.totalMerged || 0,
          mergeRate:
            objStats.totalDuplicates > 0
              ? (objStats.totalMerged || 0) / objStats.totalDuplicates
              : 0,
        });
      });
    }

    // Sort by total duplicates
    byObjectData.sort((a, b) => b.value - a.value);

    this.chartData = byObjectData;
  }

  /**
   * Refresh statistics data - debounced to prevent multiple calls
   */
  handleRefresh() {
    // Clear any pending refresh
    if (this.debounceTimeout) {
      window.clearTimeout(this.debounceTimeout);
    }

    // Use Promise to debounce rapid clicks instead of setTimeout
    Promise.resolve().then(() => {
      // Set loading state
      this.isLoading = true;
      store.dispatch(duplicationStore.actions.SET_LOADING, true);

      // Invalidate cache
      store.dispatch(duplicationStore.actions.INVALIDATE_CACHE, "statistics");

      // Notify that refresh is happening via LMS
      sendMessage(MESSAGE_TYPES.REFRESH_STARTED, {
        component: "dashboard",
        type: "statistics",
        timestamp: new Date().toISOString(),
      });

      // Load fresh data
      this.loadStatistics();
    });
  }

  /**
   * Handle time range change
   */
  handleTimeRangeChange(event) {
    this.timeRange = event.detail.value;

    // Notify other components about the time range change via LMS
    sendMessage(MESSAGE_TYPES.TIME_RANGE_CHANGED, {
      timeRange: this.timeRange,
      source: "dashboard",
    });

    this.handleRefresh();
  }

  /**
   * Dismiss error message
   */
  dismissError() {
    this.error = null;
  }

  /**
   * Get CSS class for timeline items
   * @returns {String} CSS class string
   */
  get timelineItemClass() {
    return "timeline-item";
  }

  /**
   * Get CSS class for timeline item
   * @param {Object} merge - Merge record
   * @returns {String} CSS class
   */
  getTimelineItemClass(merge) {
    return `timeline-item ${merge.isDryRun ? "dry-run" : ""}`;
  }

  /**
   * Handle error with improved security
   * @param {String} baseMessage - Base error message
   * @param {Object} error - Error object
   */
  handleError(baseMessage, error) {
    if (!baseMessage) {
      baseMessage = "An error occurred";
    }

    // Sanitize to remove any potentially sensitive information
    let errorDetails = "";

    // Handle different error types
    if (error) {
      try {
        if (error.body && error.body.message) {
          // Apex error
          errorDetails = this.sanitizeErrorMessage(error.body.message);
        } else if (error.message) {
          // Standard JS error
          errorDetails = this.sanitizeErrorMessage(error.message);
        } else {
          // Unknown error type, convert safely
          errorDetails = this.sanitizeErrorMessage(JSON.stringify(error));
        }
      } catch (e) {
        // Error handling the error
        errorDetails = "Unable to process error details";
      }
    }

    // Add basic error info to the console (no sensitive data)
    console.error(`${baseMessage}: ${errorDetails}`);

    // Update local error state
    this.error = {
      message: baseMessage,
      details: errorDetails,
      timestamp: new Date().toISOString(),
    };

    // Add to store errors with sanitized info
    store.dispatch(duplicationStore.actions.ADD_ERROR, {
      message: baseMessage,
      details: errorDetails,
      type: "statistics",
      timestamp: new Date().toISOString(),
    });

    // Notify about error via LMS
    sendMessage(MESSAGE_TYPES.ERROR_OCCURRED, {
      message: baseMessage,
      details: errorDetails,
      type: "statistics",
      source: "dashboard",
      timestamp: new Date().toISOString(),
    });
  }

  /**
   * Sanitize error messages to prevent leaking sensitive information
   * @param {String} message - Error message to sanitize
   * @returns {String} Sanitized message
   */
  sanitizeErrorMessage(message) {
    if (!message) return "";

    // Convert to string if not already
    const strMessage = String(message);

    // Remove any potential tokens, session IDs, or sensitive data patterns
    return strMessage
      .replace(
        /Bearer [a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]+/g,
        "Bearer [REDACTED]",
      )
      .replace(/[a-zA-Z0-9]{20,}/g, "[REDACTED_ID]")
      .replace(/password(=|:).+?($|&|"|')/gi, "password=[REDACTED]$1")
      .replace(/token(=|:).+?($|&|"|')/gi, "token=[REDACTED]$1")
      .replace(/key(=|:).+?($|&|"|')/gi, "key=[REDACTED]$1")
      .substring(0, 150); // Limit length
  }

  // Computed properties

  /**
   * Get time range options
   */
  get timeRangeOptions() {
    return [
      { label: "Last 7 Days", value: TIME_RANGES.LAST_7_DAYS },
      { label: "Last 30 Days", value: TIME_RANGES.LAST_30_DAYS },
      { label: "Last 90 Days", value: TIME_RANGES.LAST_90_DAYS },
      { label: "This Year", value: TIME_RANGES.THIS_YEAR },
      { label: "All Time", value: "ALL" },
    ];
  }

  /**
   * Get human-readable time range label
   */
  get timeRangeLabel() {
    const options = this.timeRangeOptions;
    const selected = options.find((option) => option.value === this.timeRange);
    return selected ? selected.label.toLowerCase() : "all time";
  }

  /**
   * Check if statistics are empty
   * @returns {Boolean} True if statistics are empty
   */
  get hasStatistics() {
    return (
      this.statistics &&
      (this.statistics.totalDuplicates > 0 || this.statistics.totalMerged > 0) &&
      // Make sure we have real data and not just default values
      this.statistics.byObject &&
      Object.keys(this.statistics.byObject).length > 0
    );
  }

  /**
   * Check if there are recent merges
   * @returns {Boolean} True if there are recent merges
   */
  get hasRecentMerges() {
    return (
      this.statistics.recentMerges && this.statistics.recentMerges.length > 0
    );
  }

  /**
   * Check if there are stats for multiple objects
   * @returns {Boolean} True if there are stats for multiple objects
   */
  get hasMultipleObjectStats() {
    return this.objectStatsList && this.objectStatsList.length > 1;
  }

  /**
   * Get statistics by object as a list for the table view
   * @returns {Array} List of object statistics
   */
  get objectStatsList() {
    const statsList = [];

    if (this.statistics.byObject) {
      Object.keys(this.statistics.byObject).forEach((objName) => {
        const objStats = this.statistics.byObject[objName];

        // Calculate merge rate
        const totalDuplicates = objStats.totalDuplicates || 0;
        const totalMerged = objStats.totalMerged || 0;
        const mergeRate =
          totalDuplicates > 0 ? totalMerged / totalDuplicates : 0;

        statsList.push({
          name: objName,
          totalDuplicates: totalDuplicates,
          totalMerged: totalMerged,
          mergeRate: mergeRate,
        });
      });

      // Sort by total duplicates
      statsList.sort((a, b) => b.totalDuplicates - a.totalDuplicates);
    }

    return statsList;
  }

  /**
   * Get duplicates trend data
   * @returns {Boolean} True if trend data is available
   */
  get duplicatesTrend() {
    return (
      this.lastPeriodStats &&
      this.lastPeriodStats.totalDuplicates !== undefined &&
      this.statistics.totalDuplicates !== undefined
    );
  }

  /**
   * Get duplicates trend value
   * @returns {Number} Percentage change
   */
  get duplicatesTrendValue() {
    if (!this.duplicatesTrend) return 0;

    const previous = this.lastPeriodStats.totalDuplicates;
    const current = this.statistics.totalDuplicates;

    // Avoid division by zero
    if (previous === 0) return 0;

    return (current - previous) / previous;
  }

  /**
   * Check if duplicates trend is positive
   * @returns {Boolean} True if trend is positive
   */
  get isDuplicateTrendPositive() {
    return this.duplicatesTrendValue > 0;
  }

  /**
   * Get icon for duplicates trend
   * @returns {String} Icon name
   */
  get duplicatesTrendIcon() {
    return this.isDuplicateTrendPositive
      ? "utility:arrowup"
      : "utility:arrowdown";
  }

  /**
   * Get CSS class for duplicates trend
   * @returns {String} CSS class
   */
  get duplicatesTrendClass() {
    return `trend-indicator ${this.isDuplicateTrendPositive ? "trend-up" : "trend-down"}`;
  }

  /**
   * Get descriptive text for duplicates trend for screen readers
   * @returns {String} Description
   */
  get duplicatesTrendDescription() {
    const value = Math.abs(this.duplicatesTrendValue * 100).toFixed(1);
    return this.isDuplicateTrendPositive
      ? `Increased by ${value}% compared to previous period`
      : `Decreased by ${value}% compared to previous period`;
  }

  /**
   * Get merges trend data
   * @returns {Boolean} True if trend data is available
   */
  get mergesTrend() {
    return (
      this.lastPeriodStats &&
      this.lastPeriodStats.totalMerged !== undefined &&
      this.statistics.totalMerged !== undefined
    );
  }

  /**
   * Get merges trend value
   * @returns {Number} Percentage change
   */
  get mergesTrendValue() {
    if (!this.mergesTrend) return 0;

    const previous = this.lastPeriodStats.totalMerged;
    const current = this.statistics.totalMerged;

    // Avoid division by zero
    if (previous === 0) return 0;

    return (current - previous) / previous;
  }

  /**
   * Check if merges trend is positive
   * @returns {Boolean} True if trend is positive
   */
  get isMergesTrendPositive() {
    return this.mergesTrendValue > 0;
  }

  /**
   * Get icon for merges trend
   * @returns {String} Icon name
   */
  get mergesTrendIcon() {
    return this.isMergesTrendPositive ? "utility:arrowup" : "utility:arrowdown";
  }

  /**
   * Get CSS class for merges trend
   * @returns {String} CSS class
   */
  get mergesTrendClass() {
    return `trend-indicator ${this.isMergesTrendPositive ? "trend-up" : "trend-down"}`;
  }

  /**
   * Get descriptive text for merges trend for screen readers
   * @returns {String} Description
   */
  get mergesTrendDescription() {
    const value = Math.abs(this.mergesTrendValue * 100).toFixed(1);
    return this.isMergesTrendPositive
      ? `Increased by ${value}% compared to previous period`
      : `Decreased by ${value}% compared to previous period`;
  }

  /**
   * Get merge rate trend data
   * @returns {Boolean} True if trend data is available
   */
  get mergeRateTrend() {
    return (
      this.lastPeriodStats &&
      this.lastPeriodStats.mergeRate !== undefined &&
      this.mergeRate !== undefined
    );
  }

  /**
   * Get merge rate trend value
   * @returns {Number} Percentage change
   */
  get mergeRateTrendValue() {
    if (!this.mergeRateTrend) return 0;

    const previous = this.lastPeriodStats.mergeRate;
    const current = this.mergeRate;

    // Avoid division by zero
    if (previous === 0) return 0;

    return (current - previous) / previous;
  }

  /**
   * Check if merge rate trend is positive
   * @returns {Boolean} True if trend is positive
   */
  get isMergeRateTrendPositive() {
    return this.mergeRateTrendValue > 0;
  }

  /**
   * Get icon for merge rate trend
   * @returns {String} Icon name
   */
  get mergeRateTrendIcon() {
    return this.isMergeRateTrendPositive
      ? "utility:arrowup"
      : "utility:arrowdown";
  }

  /**
   * Get CSS class for merge rate trend
   * @returns {String} CSS class
   */
  get mergeRateTrendClass() {
    return `trend-indicator ${this.isMergeRateTrendPositive ? "trend-up" : "trend-down"}`;
  }

  /**
   * Get descriptive text for merge rate trend for screen readers
   * @returns {String} Description
   */
  get mergeRateTrendDescription() {
    const value = Math.abs(this.mergeRateTrendValue * 100).toFixed(1);
    return this.isMergeRateTrendPositive
      ? `Merge efficiency improved by ${value}% compared to previous period`
      : `Merge efficiency decreased by ${value}% compared to previous period`;
  }

  /**
   * Get formatted last refresh time
   * @returns {String} Formatted last refresh time
   */
  get lastRefreshFormatted() {
    if (!this.lastRefresh) return "";

    const now = new Date();
    const diff = Math.floor((now - this.lastRefresh) / 1000 / 60); // minutes

    if (diff < 1) {
      return "Last refreshed just now";
    }
    if (diff === 1) {
      return "Last refreshed 1 minute ago";
    }
    if (diff < 60) {
      return `Last refreshed ${diff} minutes ago`;
    }
    return `Last refreshed at ${this.lastRefresh.toLocaleTimeString()}`;
  }

  /**
   * Get merge rate (percentage of duplicates merged)
   * @returns {Number} Merge rate as a decimal (0.XX)
   */
  get mergeRate() {
    if (
      this.statistics &&
      this.statistics.totalDuplicates &&
      this.statistics.totalMerged
    ) {
      return this.statistics.totalMerged / this.statistics.totalDuplicates;
    }
    return 0;
  }

  /**
   * Check if there's an error
   * @returns {Boolean} True if there's an error
   */
  get hasError() {
    return this.error !== null;
  }


  /**
   * Get CSS class for dashboard container
   * @returns {String} CSS class string
   */
  get dashboardContainerClass() {
    return this.isLoading
      ? "dashboard-container loading"
      : "dashboard-container";
  }
}
