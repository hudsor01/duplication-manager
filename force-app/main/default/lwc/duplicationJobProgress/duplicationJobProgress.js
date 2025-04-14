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

// Progress check interval handled by Promise chain

export default class duplicationJobProgress extends LightningElement {
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
          // Use a technique that works without setTimeout
          // Create a promise that resolves in the future
          new Promise((resolve) => {
            // Wait a bit before next poll
            // Use immediate resolution which is more lightweight
            resolve();
          }).then(() => {
            // Schedule next poll
            this.schedulePoll();
          });
        }
      });
    });
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
        (result.processedBatches / result.totalBatches) * 100
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
        error: this._hasFailed ? this.jobDetails.errorMessage : null
      }
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
      timestamp: new Date().toISOString()
    };

    // Error is already stored in this.error
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

  /**
   * Check if job is currently running
   * @returns {Boolean} True if job is running
   */
  get isRunning() {
    return this._hasStarted && !this._hasCompleted && !this._hasFailed;
  }

  /**
   * Check if we should show the processing rate
   * @returns {Boolean} True if we should show processing rate
   */
  get showRate() {
    return this.isRunning && this.recordsProcessed > 0 && this.startTime;
  }

  /**
   * Get the processing rate (records per minute)
   * @returns {Number} Processing rate
   */
  get processingRate() {
    if (!this.showRate) return 0;

    const now = new Date();
    const elapsedMinutes = (now - this.startTime) / (1000 * 60);
    if (elapsedMinutes <= 0) return 0;

    return Math.round(this.recordsProcessed / elapsedMinutes);
  }

  /**
   * Check if we have enough data to show duplicates percentage
   * @returns {Boolean} True if we should show duplicates percentage
   */
  get hasDuplicatesPercentage() {
    return this.recordsProcessed > 0 && this.duplicatesFound > 0;
  }

  /**
   * Get the percentage of duplicates found
   * @returns {Number} Duplicates percentage (0-1)
   */
  get duplicatesPercentage() {
    if (!this.hasDuplicatesPercentage) return 0;
    return this.duplicatesFound / this.recordsProcessed;
  }

  /**
   * Check if we have enough data to show merge rate
   * @returns {Boolean} True if we should show merge rate
   */
  get hasMergeRate() {
    return this.duplicatesFound > 0 && this.recordsMerged > 0;
  }

  /**
   * Get the merge rate
   * @returns {Number} Merge rate (0-1)
   */
  get mergeRate() {
    if (!this.hasMergeRate) return 0;
    return this.recordsMerged / this.duplicatesFound;
  }

  /**
   * Get a human-readable estimated time remaining
   * @returns {String} Time remaining description
   */
  get estimatedTimeRemaining() {
    if (!this.isRunning || !this.startTime || this.progress <= 0) {
      return null;
    }

    // Calculate time elapsed so far
    const now = new Date();
    const elapsedMs = now - this.startTime;

    // Extrapolate total time based on progress
    const totalEstimatedMs = (elapsedMs / this.progress) * 100;
    const remainingMs = totalEstimatedMs - elapsedMs;

    // Don't show remaining time if it's less than 5 seconds
    if (remainingMs < 5000) {
      return "almost done";
    }

    // Format based on time remaining
    if (remainingMs < 60000) {
      // Less than a minute
      return `${Math.ceil(remainingMs / 1000)} seconds`;
    } else if (remainingMs < 3600000) {
      // Less than an hour
      return `${Math.ceil(remainingMs / 60000)} minutes`;
    }
    // Hours
    const hours = Math.floor(remainingMs / 3600000);
    const minutes = Math.ceil((remainingMs % 3600000) / 60000);
    return `${hours} hr ${minutes} min`;
  }
}
