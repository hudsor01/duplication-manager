/**
 * Component for displaying summary statistics about duplicate records
 *
 * @author Richard Hudson
 * @since April 2025
 */
import { LightningElement, api, track } from "lwc";
import getDuplicateStatistics from "@salesforce/apex/DRSCStats.getDuplicateStatistics";
import store from "c/duplicationStore";
import { duplicationStore } from "c/duplicationStore";

export default class DuplicationStatsSummary extends LightningElement {
  /**
   * @api
   * @description Object API name to filter statistics by (optional)
   * @type {String}
   */
  @api objectApiName;

  /**
   * @api
   * @description Time range to filter statistics by
   * @type {String}
   */
  @api timeRange = "ALL_TIME"; // ALL_TIME, THIS_MONTH, THIS_WEEK, TODAY

  // Tracked properties for component state
  @track totalDuplicates = 0;
  @track recordsProcessed = 0;
  @track recordsMerged = 0;
  @track isLoading = true;
  @track error;

  // Store subscription unsubscribe function
  unsubscribe = null;

  /**
   * Lifecycle hook - Component connected to DOM
   */
  connectedCallback() {
    // Subscribe to store changes
    this.unsubscribe = store.subscribe(this.handleStoreChange.bind(this));

    // Load initial statistics
    this.loadStatistics();
  }

  /**
   * Lifecycle hook - Component disconnected from DOM
   */
  disconnectedCallback() {
    // Unsubscribe from store
    if (this.unsubscribe) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
  }

  /**
   * @api
   * @description Refreshes statistics data
   */
  @api
  refresh() {
    this.loadStatistics();
  }

  /**
   * Handle store state changes
   * @param {Object} state - Current store state
   */
  handleStoreChange(state) {
    this.syncFromStore(state);
  }

  /**
   * Synchronize component state from store
   * @param {Object} state - Store state
   */
  syncFromStore(state) {
    // If no state is provided, get it from store
    const storeState = state || store.getState();

    // Only update if we have statistics and we're not loading from API
    if (!this.isLoading && storeState.statistics) {
      // Filter statistics by object if specified
      if (
        this.objectApiName &&
        storeState.statistics.byObject &&
        storeState.statistics.byObject[this.objectApiName]
      ) {
        const objStats = storeState.statistics.byObject[this.objectApiName];
        this.totalDuplicates = objStats.totalDuplicates || 0;
        this.recordsMerged = objStats.totalMerged || 0;
      } else {
        // Use global statistics
        this.totalDuplicates = storeState.statistics.totalDuplicates || 0;
        this.recordsMerged = storeState.statistics.totalMerged || 0;
      }

      // Set processed records
      if (storeState.statistics.totalJobs) {
        this.recordsProcessed = storeState.statistics.totalJobs;
      }
    }
  }

  /**
   * Load statistics from the server
   */
  loadStatistics() {
    // Set loading state
    this.isLoading = true;
    store.dispatch(duplicationStore.actions.SET_LOADING, true);

    // Call Apex controller method
    getDuplicateStatistics()
      .then((result) => {
        // Update store with statistics
        store.dispatch(duplicationStore.actions.UPDATE_STATISTICS, result);

        // Update local component state
        this.processStatisticsResult(result);

        // Clear error state
        this.error = undefined;

        // Dispatch refreshed event
        this.dispatchRefreshedEvent(result);
      })
      .catch((error) => {
        this.handleError("Error loading duplicate statistics", error);
      })
      .finally(() => {
        this.isLoading = false;
        store.dispatch(duplicationStore.actions.SET_LOADING, false);
      });
  }

  /**
   * Process statistics result from API
   * @param {Object} result - Statistics result from API
   */
  processStatisticsResult(result) {
    // Set default values for safety
    this.totalDuplicates = 0;
    this.recordsProcessed = 0;
    this.recordsMerged = 0;

    if (!result) {
      return;
    }

    // Process statistics based on objectApiName filter
    if (
      this.objectApiName &&
      result.byObject &&
      result.byObject[this.objectApiName]
    ) {
      const objStats = result.byObject[this.objectApiName];
      this.totalDuplicates = objStats.totalDuplicates || 0;
      this.recordsMerged = objStats.totalMerged || 0;
    } else {
      // Use global statistics
      this.totalDuplicates = result.totalDuplicates || 0;
      this.recordsMerged = result.totalMerged || 0;
    }

    // Set processed records
    if (result.totalJobs) {
      this.recordsProcessed = result.totalJobs;
    }
  }

  /**
   * Dispatch refreshed event to notify parent components
   * @param {Object} result - The statistics result
   */
  dispatchRefreshedEvent(result) {
    // Create custom event
    const refreshedEvent = new CustomEvent("refreshed", {
      detail: {
        objectApiName: this.objectApiName,
        timeRange: this.timeRange,
        statistics: result,
        timestamp: new Date().toISOString()
      },
      bubbles: false,
      composed: false
    });

    // Dispatch the event
    this.dispatchEvent(refreshedEvent);
  }

  /**
   * Handle error from API call
   * @param {String} baseMessage - Base error message
   * @param {Object} error - Error object
   */
  handleError(baseMessage, error) {
    let errorMessage = baseMessage;
    let errorDetails = "";

    // Extract error details
    if (error) {
      if (error.body && error.body.message) {
        errorDetails = error.body.message;
      } else if (error.message) {
        errorDetails = error.message;
      } else {
        errorDetails = JSON.stringify(error);
      }

      errorMessage += ": " + errorDetails;
    }

    console.error(errorMessage);

    // Create structured error object
    const errorObj = {
      message: baseMessage,
      details: errorDetails,
      timestamp: new Date().toISOString(),
      type: "statistics",
      id: `err-${Date.now()}-${Math.floor(Math.random() * 1000)}`
    };

    // Set local error state
    this.error = errorObj;

    // Add to store
    store.dispatch(duplicationStore.actions.ADD_ERROR, errorObj);
  }

  /**
   * Check if component has an error
   * @returns {Boolean} True if there is an error
   */
  get hasError() {
    return !!this.error;
  }

  /**
   * Get formatted error message
   * @returns {String} Formatted error message
   */
  get errorMessage() {
    return this.error ? `${this.error.message}: ${this.error.details}` : "";
  }
}
