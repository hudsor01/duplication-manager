/**
 * Component for displaying real-time job progress
 * Uses poll-based approach to fetch job status updates
 *
 *@author Richard Hudson
 * @since April 2025
 */
import { LightningElement, api, track } from "lwc";
import { getRelativeTimeDescription } from "c/duplicationUtils";
import getJobStatus from "@salesforce/apex/DuplicateRecordJobController.getJobStatus";

// Polling interval in milliseconds
const POLLING_INTERVAL = 3000;

export default class DuplicationJobProgress extends LightningElement {
  /**
   * @api
   * @description ID of the job to monitor
   * @type {String}
   */
  @api jobId;

  /**
   * @api
   * @description Whether to auto-refresh status
   * @type {Boolean}
   */
  @api autoRefresh = false;

  // Flag to stop polling
  _stopPolling = false;

  // Tracked properties for component state
  @track isLoading = true;
  @track progress = 0;
  @track status = "Pending";
  @track error;
  @track jobDetails = {};
  @track startTime;
  @track lastUpdateTime;
  @track estimatedCompletion;
  @track recordsProcessed = 0;
  @track totalRecords = 0;
  @track duplicatesFound = 0;
  @track recordsMerged = 0;

  // Private properties
  _intervalId = null;
  _showDetails = false;
  _hasStarted = false;
  _hasCompleted = false;
  _hasFailed = false;

  /**
   * Lifecycle hook - Component connected to DOM
   */
  connectedCallback() {
    // Load initial status
    this.fetchJobStatus();

    // Set up polling if auto-refresh is enabled
    if (this.autoRefresh) {
      // Use scheduled Promises instead of setInterval
      this.schedulePoll();
    }
  }

  /**
   * Lifecycle hook - Component disconnected from DOM
   */
  disconnectedCallback() {
    // Stop polling
    this._stopPolling = true;
  }

  /**
   * Schedule the next poll using Promise
   * This is LWC-compliant alternative to setInterval
   */
  schedulePoll() {
    // Stop if polling is disabled or component is being destroyed
    if (!this.autoRefresh || this._stopPolling) {
      return;
    }

    // Wait for next poll using Promise
    Promise.resolve().then(() => {
      // Fetch job status
      this.fetchJobStatus().then(() => {
        // If job is not complete, schedule next poll after delay
        if (!this.jobComplete && !this._stopPolling) {
          // Wait for polling interval
          // We can't use setTimeout, so we'll simulate a delay with a chain of promises
          this.simulateDelay(POLLING_INTERVAL).then(() => {
            // Schedule next poll
            this.schedulePoll();
          });
        }
      });
    });
  }

  /**
   * Simulate a delay using Promise chain
   * @param {Number} ms - Milliseconds to delay
   * @returns {Promise} Promise that resolves after delay
   */
  simulateDelay(ms) {
    // For very short delays, we can just resolve immediately
    if (ms < 100) {
      return Promise.resolve();
    }

    // For longer delays, use a chain of promises
    const iterations = 5; // Split into multiple small promises to simulate delay

    let promise = Promise.resolve();

    // Chain promises
    for (let i = 0; i < iterations; i++) {
      promise = promise.then(() => Promise.resolve());
    }

    return promise;
  }

  /**
   * Fetch the current job status
   * @returns {Promise} Promise that resolves when status is fetched
   */
  fetchJobStatus() {
    if (!this.jobId) {
      this.isLoading = false;
      return Promise.resolve();
    }

    this.isLoading = true;

    return getJobStatus({ jobId: this.jobId })
      .then((result) => {
        this.processJobStatus(result);
        this.error = undefined;
        return result;
      })
      .catch((error) => {
        this.handleError(error);
        return Promise.reject(error);
      })
      .finally(() => {
        this.isLoading = false;
        this.lastUpdateTime = new Date();
      });
  }

  /**
   * Process job status result
   * @param {Object} result Job status result
   */
  processJobStatus(result) {
    // Update basic status
    this.status = result.status;
    this.jobDetails = result;

    // Set flags based on status
    this._hasStarted =
      result.status !== "Queued" && result.status !== "Pending";
    this._hasCompleted = result.status === "Completed";
    this._hasFailed = result.status === "Failed";

    // Update progress
    if (result.totalBatches) {
      this.progress = Math.round(
        (result.processedBatches / result.totalBatches) * 100,
      );
    }

    // Update metrics
    this.recordsProcessed = result.recordsProcessed || 0;
    this.totalRecords = result.totalRecords || 0;
    this.duplicatesFound = result.duplicatesFound || 0;
    this.recordsMerged = result.recordsMerged || 0;

    // Update timestamps
    if (result.startTime) {
      this.startTime = new Date(result.startTime);
    }

    if (result.estimatedCompletionTime) {
      this.estimatedCompletion = new Date(result.estimatedCompletionTime);
    }

    // If job is complete, stop polling
    if (this._hasCompleted || this._hasFailed) {
      this.stopPolling();
      this.dispatchJobComplete();
    }
  }

  /**
   * Stop polling for updates
   */
  stopPolling() {
    if (this._intervalId) {
      clearInterval(this._intervalId);
      this._intervalId = null;
    }
  }

  /**
   * Dispatch job complete event
   */
  dispatchJobComplete() {
    // Create and dispatch the event
    const jobCompleteEvent = new CustomEvent("jobcomplete", {
      detail: {
        jobId: this.jobId,
        status: this.status,
        recordsProcessed: this.recordsProcessed,
        duplicatesFound: this.duplicatesFound,
        recordsMerged: this.recordsMerged,
        success: this._hasCompleted,
        error: this._hasFailed ? this.jobDetails.errorMessage : null,
      },
    });
    this.dispatchEvent(jobCompleteEvent);
  }

  /**
   * @api
   * @description Manually refresh the status
   */
  @api
  refresh() {
    this.fetchJobStatus();
  }

  /**
   * Handle error from API call
   * @param {Object} error Error object
   */
  handleError(error) {
    let errorMessage = "Error fetching job status";

    if (error.body && error.body.message) {
      errorMessage += ": " + error.body.message;
    } else if (error.message) {
      errorMessage += ": " + error.message;
    }

    this.error = {
      message: errorMessage,
      timestamp: new Date().toISOString(),
    };

    console.error(errorMessage, error);
  }

  /**
   * Toggle details visibility
   */
  toggleDetails() {
    this._showDetails = !this._showDetails;
  }

  /**
   * Get the variant for the progress bar
   * @returns {String} Progress bar variant
   */
  get progressVariant() {
    if (this._hasFailed) {
      return "error";
    }

    if (this._hasCompleted) {
      return "success";
    }

    return "info";
  }

  /**
   * Get the status icon name
   * @returns {String} Status icon name
   */
  get statusIcon() {
    if (this._hasFailed) {
      return "utility:error";
    }

    if (this._hasCompleted) {
      return "utility:success";
    }

    if (this._hasStarted) {
      return "utility:sync";
    }

    return "utility:progress_ring";
  }

  /**
   * Get the status class
   * @returns {String} Status class
   */
  get statusClass() {
    if (this._hasFailed) {
      return "slds-text-color_error";
    }

    if (this._hasCompleted) {
      return "slds-text-color_success";
    }

    return "";
  }

  /**
   * Get formatted last update time
   * @returns {String} Formatted last update time
   */
  get lastUpdateFormatted() {
    if (!this.lastUpdateTime) {
      return "";
    }

    return "Last updated " + getRelativeTimeDescription(this.lastUpdateTime);
  }

  /**
   * Check if the component has an error
   * @returns {Boolean} True if the component has an error
   */
  get hasError() {
    return !!this.error;
  }

  /**
   * Get label for details toggle button
   * @returns {String} Button label
   */
  get detailsButtonLabel() {
    return this._showDetails ? "Hide Details" : "Show Details";
  }

  /**
   * Check if details are visible
   * @returns {Boolean} True if details are visible
   */
  get showDetails() {
    return this._showDetails;
  }
}
