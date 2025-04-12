import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getScheduledJobs from "@salesforce/apex/DuplicateRecordController.getScheduledJobs";
import deleteScheduledJob from "@salesforce/apex/DuplicateRecordJobController.deleteScheduledJob";
import store from "c/duplicationStore";
import { DuplicationStore } from "c/duplicationStore";
import { register as registerListener, unregister as unregisterListener } from "c/duplicationPubSub";

/**
 * Component for managing duplication job scheduling and monitoring
 * @component
 */
export default class DuplicationJobManager extends LightningElement {
  isLoading = true;
  error = null;
  refreshTimerId = null;
  autoRefreshEnabled = true;
  autoRefreshInterval = 30000; // 30 seconds
  selectedJobId = null;
  selectedJob = null;
  isJobDetailModalOpen = false;

  /**
   * Lifecycle hook - Called when component is inserted into the DOM
   */
  connectedCallback() {
    console.log("duplicationJobManager component connected to DOM");

    // Subscribe to store changes
    registerListener(
      "duplicationStoreChange",
      this.handleStoreChange.bind(this),
    );

    // Start auto-refresh timer
    this.startAutoRefresh();
  }

  /**
   * Lifecycle hook - Called when component is removed from the DOM
   */
  disconnectedCallback() {
    console.log("duplicationJobManager component removed from DOM");
    unregisterListener("duplicationStoreChange", this.handleStoreChange);

    // Clear auto-refresh timer
    this.stopAutoRefresh();
  }

  /**
   * Handle store state changes
   */
  handleStoreChange() {
    // handle store changes if needed
  }

  /**
   * Wire method to get scheduled jobs
   */
  @wire(getScheduledJobs)
  wiredJobs({ error, data }) {
    this.isLoading = false;

    if (data) {
      try {
        console.log("Jobs loaded:", data.length);

        // Update store with scheduled jobs
        store.dispatch(DuplicationStore.actions.UPDATE_SCHEDULED_JOBS, data);

        // If a job was selected and still exists, update it
        if (this.selectedJobId) {
          const updatedJob = data.find((job) => job.Id === this.selectedJobId);
          if (updatedJob) {
            this.selectedJob = updatedJob;
          }
        }
      } catch (e) {
        console.error("Error processing jobs data:", e);
        this.handleError("Error processing jobs data", e);
      }
    } else if (error) {
      console.error("Error in wiredJobs:", error);
      this.handleError("Error loading scheduled jobs", error);
    }
  }

  /**
   * Start auto-refresh timer using Promise-based polling
   */
  startAutoRefresh() {
    if (this.autoRefreshEnabled && !this._isPolling) {
      console.log(
        `Starting auto-refresh (interval: ${this.autoRefreshInterval}ms)`,
      );
      this._isPolling = true;
      this._stopPolling = false;
      this._pollForUpdates();
    }
  }

  /**
   * Promise-based polling function that replaces setInterval
   */
  _pollForUpdates() {
    // If polling is stopped or component is being destroyed, don't continue
    if (this._stopPolling || !this.autoRefreshEnabled) {
      this._isPolling = false;
      return;
    }

    // Execute refresh jobs
    this.refreshJobs().finally(() => {
      // Schedule next poll using Promise chain
      this._simulateDelay(this.autoRefreshInterval).then(() => {
        // Check again if we should continue polling
        if (!this._stopPolling) {
          this._pollForUpdates();
        } else {
          this._isPolling = false;
        }
      });
    });
  }

  /**
   * Promise-based delay function
   * @param {Number} ms - Delay in milliseconds
   * @returns {Promise} Promise that resolves after the delay
   */
  _simulateDelay(ms) {
    const startTime = Date.now();

    return new Promise((resolve) => {
      // Function to check if enough time has passed
      const checkTime = () => {
        const elapsed = Date.now() - startTime;
        if (elapsed >= ms) {
          resolve();
        } else {
          // Check again in the next microtask
          Promise.resolve().then(checkTime);
        }
      };

      // Start checking
      Promise.resolve().then(checkTime);
    });
  }

  /**
   * Stop auto-refresh polling
   */
  stopAutoRefresh() {
    if (this._isPolling) {
      console.log("Stopping auto-refresh");
      this._stopPolling = true;
    }
  }

  /**
   * Toggle auto-refresh setting
   */
  handleAutoRefreshToggle() {
    this.autoRefreshEnabled = !this.autoRefreshEnabled;

    if (this.autoRefreshEnabled) {
      this.startAutoRefresh();
      this.showToast("Auto-Refresh", "Auto-refresh enabled", "success");
    } else {
      this.stopAutoRefresh();
      this.showToast("Auto-Refresh", "Auto-refresh disabled", "info");
    }
  }

  /**
   * Manually refresh jobs
   */
  refreshJobs() {
    console.log("Manually refreshing jobs");

    this.isLoading = true;
    return getScheduledJobs()
      .then((result) => {
        console.log("Jobs refreshed:", result.length);
        store.dispatch(DuplicationStore.actions.UPDATE_SCHEDULED_JOBS, result);
      })
      .catch((error) => {
        console.error("Error refreshing jobs:", error);
        this.handleError("Error refreshing jobs", error);
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  /**
   * Show confirmation modal before deleting job
   * @param {Event} event - Event containing job ID
   */
  handleDeleteJob(event) {
    const jobId = event.detail.value || event.currentTarget.dataset.id;

    if (!jobId) {
      console.error("No job ID provided for deletion");
      return;
    }

    // Store the job ID for deletion
    this.jobIdToDelete = jobId;

    // Fire event to show confirmation dialog instead of using confirm()
    const confirmEvent = new CustomEvent("confirmdelete", {
      detail: {
        jobId: jobId,
        title: "Confirm Deletion",
        message: "Are you sure you want to delete this scheduled job?",
        callback: this.deleteJobAfterConfirmation.bind(this),
      },
    });
    this.dispatchEvent(confirmEvent);
  }

  /**
   * Delete job after confirmation
   * @param {Boolean} confirmed - Whether user confirmed the deletion
   */
  deleteJobAfterConfirmation(confirmed) {
    if (!confirmed || !this.jobIdToDelete) {
      // User canceled the deletion
      this.jobIdToDelete = null;
      return;
    }

    const jobId = this.jobIdToDelete;
    this.jobIdToDelete = null;

    console.log("Deleting job:", jobId);
    this.isLoading = true;

    deleteScheduledJob({ jobId: jobId })
      .then(() => {
        console.log("Job deleted successfully");
        this.showToast("Success", "Job deleted successfully", "success");

        // If we deleted the selected job, clear the selection
        if (this.selectedJobId === jobId) {
          this.selectedJobId = null;
          this.selectedJob = null;
          this.isJobDetailModalOpen = false;
        }

        // Refresh the jobs list
        return this.refreshJobs();
      })
      .catch((error) => {
        console.error("Error deleting job:", error);
        this.handleError("Error deleting job", error);
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  /**
   * Handle job selection for details view
   * @param {Event} event - Event containing job ID
   */
  handleViewJobDetails(event) {
    const jobId = event.detail.value || event.currentTarget.dataset.id;

    if (!jobId) {
      console.error("No job ID provided for detail view");
      return;
    }

    console.log("Viewing job details:", jobId);

    // Find the job in the current list
    const state = store.getState();
    const job = state.scheduledJobs.find((j) => j.Id === jobId);

    if (job) {
      this.selectedJobId = jobId;
      this.selectedJob = job;
      this.isJobDetailModalOpen = true;
    } else {
      console.error("Job not found in current list:", jobId);
      this.showToast("Error", "Job details not found", "error");
    }
  }

  /**
   * Close job detail modal
   */
  handleCloseJobDetail() {
    this.isJobDetailModalOpen = false;
  }

  /**
   * Show toast notification
   * @param {String} title - Toast title
   * @param {String} message - Toast message
   * @param {String} variant - Toast variant (info, success, warning, error)
   */
  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: title,
        message: message,
        variant: variant,
      }),
    );
  }

  /**
   * Handle errors with proper messaging
   * @param {String} baseMessage - Base error message
   * @param {Error} error - Error object
   */
  handleError(baseMessage, error) {
    let errorMessage = baseMessage;

    if (error) {
      if (error.body && error.body.message) {
        errorMessage += ": " + error.body.message;
      } else if (error.message) {
        errorMessage += ": " + error.message;
      } else {
        errorMessage += ": " + JSON.stringify(error);
      }
    }

    console.error(errorMessage);
    this.error = { message: errorMessage };

    // Add to store errors
    store.dispatch(DuplicationStore.actions.ADD_ERROR, {
      message: errorMessage,
      timestamp: new Date().toISOString(),
    });

    this.showToast("Error", errorMessage, "error");
  }

  /**
   * Get scheduled jobs from store
   * @returns {Array} Array of scheduled jobs
   */
  get scheduledJobs() {
    const state = store.getState();
    return state.scheduledJobs || [];
  }

  /**
   * Check if there are scheduled jobs
   * @returns {Boolean} True if there are scheduled jobs
   */
  get hasScheduledJobs() {
    return this.scheduledJobs.length > 0;
  }

  /**
   * Check if auto-refresh is active
   * @returns {Boolean} True if auto-refresh is active
   */
  get isAutoRefreshActive() {
    return this.autoRefreshEnabled;
  }

  /**
   * Get button icon name based on auto-refresh state
   * @returns {String} Icon name
   */
  get autoRefreshIconName() {
    return this.isAutoRefreshActive ? "utility:pause" : "utility:play";
  }

  /**
   * Get alternative text for auto-refresh button
   * @returns {String} Alternative text
   */
  get autoRefreshAltText() {
    return this.isAutoRefreshActive
      ? "Disable Auto-Refresh"
      : "Enable Auto-Refresh";
  }

  /**
   * Get title for auto-refresh button
   * @returns {String} Button title
   */
  get autoRefreshTitle() {
    return this.isAutoRefreshActive
      ? "Disable Auto-Refresh"
      : "Enable Auto-Refresh";
  }

  /**
   * Display error state
   * @returns {Boolean} True if there's an error
   */
  get hasError() {
    return this.error !== null;
  }

  /**
   * Format timestamp for display
   * @param {String} timestamp - ISO timestamp
   * @returns {String} Formatted date/time
   */
  formatDateTime(timestamp) {
    if (!timestamp) return "";

    try {
      const date = new Date(timestamp);
      return new Intl.DateTimeFormat("en-US", {
        year: "numeric",
        month: "short",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      }).format(date);
    } catch (error) {
      console.error("Error formatting date:", error);
      return timestamp;
    }
  }

  /**
   * Format job type for display
   * @param {Object} job - Job object
   * @returns {String} Formatted job type
   */
  getJobTypeLabel(job) {
    if (!job) return "";

    if (job.isDryRun) {
      return "Dry Run (Find Only)";
    }
    return "Merge Operation";
  }
}
