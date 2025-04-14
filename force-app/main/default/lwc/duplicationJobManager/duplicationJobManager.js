import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { MessageContext } from "lightning/messageService";
import getScheduledJobs from "@salesforce/apex/DuplicateRecordJobController.getScheduledJobs";
import deleteScheduledJob from "@salesforce/apex/DuplicateRecordJobController.deleteScheduledJob";
import { refreshApex } from "@salesforce/apex";
import store from "c/duplicationStore";
import { duplicationStore } from "c/duplicationStore";
import {
  subscribeToChannel,
  unsubscribeFromChannel
} from "c/duplicationMessageService";
import { MESSAGE_TYPES } from "c/duplicationConstants";

/**
 * Component for managing duplicate job scheduling and monitoring
 * @component
 */
export default class DuplicationJobManager extends LightningElement {
  isLoading = true;
  error = null;
  autoRefreshEnabled = true;
  autoRefreshInterval = 30000; // 30 seconds
  selectedJobId = null;
  selectedJob = null;
  isJobDetailModalOpen = false;
  wiredJobsResult; // Store the wired result for refreshApex

  // Get message context for LMS
  @wire(MessageContext)
  messageContext;

  /**
   * Lifecycle hook - Called when component is inserted into the DOM
   */
  connectedCallback() {
    try {
      // Subscribe to store changes
      this.subscription = subscribeToChannel((message) => {
        if (message.type === MESSAGE_TYPES.STORE_UPDATED) {
          this.handleStoreChange(message.payload);
        }
      });

      // Start auto-refresh timer if enabled
      if (this.autoRefreshEnabled) {
        this.startAutoRefresh();
      }
    } catch (error) {
      this.handleError("Error initializing component", error);
    }
  }

  /**
   * Lifecycle hook - Called when component is removed from the DOM
   */
  disconnectedCallback() {
    try {
      // Unsubscribe from channel
      if (this.subscription) {
        unsubscribeFromChannel(this.subscription);
      }

      // Clear auto-refresh timer
      this.stopAutoRefresh();
    } catch (error) {
      console.error("Error cleaning up component:", error);
    }
  }

  /**
   * Handle store state changes
   */
  handleStoreChange() {
    // handle store changes if needed
    // No need to update local state since we're using the store getter
  }

  /**
   * Wire method to get scheduled jobs
   */
  @wire(getScheduledJobs)
  wiredJobs(result) {
    this.wiredJobsResult = result;
    const { error, data } = result;
    this.isLoading = false;

    if (data) {
      try {
        // Update store with scheduled jobs
        store.dispatch(duplicationStore.actions.UPDATE_SCHEDULED_JOBS, data);

        // If a job was selected and still exists, update it
        if (this.selectedJobId) {
          const updatedJob = data.find((job) => job.Id === this.selectedJobId);
          if (updatedJob) {
            this.selectedJob = updatedJob;
          }
        }
      } catch (e) {
        this.handleError("Error processing jobs data", e);
      }
    } else if (error) {
      this.handleError("Error loading scheduled jobs", error);
    }
  }

  /**
   * Start auto-refresh timer using setTimeout
   */
  startAutoRefresh() {
    if (this.autoRefreshEnabled && !this._isPolling) {
      // Starting auto-refresh
      this._isPolling = true;
      this._stopPolling = false;
      this._pollForUpdates();
    }
  }

  /**
   * Promise-based polling function using setTimeout
   */
  _pollForUpdates() {
    // If polling is stopped or component is being destroyed, don't continue
    if (this._stopPolling || !this.autoRefreshEnabled) {
      this._isPolling = false;
      return;
    }

    // Use refreshApex to refresh the wired data
    if (this.wiredJobsResult) {
      refreshApex(this.wiredJobsResult)
        .catch((error) => {
          // Silently handle refresh errors to prevent freezing
          console.error("Error refreshing jobs:", error);
        })
        .finally(() => {
          // Schedule next poll using a real delay (30 seconds)
          setTimeout(() => {
            // Check again if we should continue polling
            if (!this._stopPolling) {
              this._pollForUpdates();
            } else {
              this._isPolling = false;
            }
          }, this.autoRefreshInterval);
        });
    } else {
      // If no wired result yet, try again after delay
      setTimeout(() => {
        if (!this._stopPolling) {
          this._pollForUpdates();
        } else {
          this._isPolling = false;
        }
      }, this.autoRefreshInterval);
    }
  }

  /**
   * Stop auto-refresh polling
   */
  stopAutoRefresh() {
    if (this._isPolling) {
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
    // Use refreshApex to refresh wired data
    this.isLoading = true;
    if (this.wiredJobsResult) {
      return refreshApex(this.wiredJobsResult)
        .catch((error) => {
          this.handleError("Error refreshing jobs", error);
        })
        .finally(() => {
          this.isLoading = false;
        });
    } 
      // If no wired result yet
      this.isLoading = false;
      return Promise.resolve();
    
  }

  /**
   * Get formatted properties for the selected job
   */
  get jobTypeLabel() {
    if (!this.selectedJob) return "";
    return this.getJobTypeLabel(this.selectedJob);
  }

  /**
   * Get the created by name for the selected job
   */
  get selectedJobCreatedBy() {
    if (!this.selectedJob || !this.selectedJob.CreatedBy) return "System";
    return this.selectedJob.CreatedBy.Name || "Unknown";
  }

  /**
   * Show confirmation modal before deleting job
   * @param {Event} event - Event containing job ID
   */
  handleDeleteJob(event) {
    const jobId = event.detail.value || event.currentTarget.dataset.id;

    if (!jobId) {
      // Cannot delete job without ID
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
        callback: this.deleteJobAfterConfirmation.bind(this)
      }
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

    // Deleting job
    this.isLoading = true;

    deleteScheduledJob({ jobId: jobId })
      .then(() => {
        // Job deleted successfully
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
        // Error deleting job
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
      // Cannot view details without job ID
      return;
    }

    // Viewing job details

    // Find the job in the current list
    const state = store.getState();
    const job = state.scheduledJobs.find((j) => j.Id === jobId);

    if (job) {
      this.selectedJobId = jobId;
      this.selectedJob = job;
      this.isJobDetailModalOpen = true;
    } else {
      // Job not found in current list
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
        variant: variant
      })
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

    // Error handled
    this.error = { message: errorMessage };

    // Add to store errors
    store.dispatch(duplicationStore.actions.ADD_ERROR, {
      message: errorMessage,
      timestamp: new Date().toISOString()
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
        minute: "2-digit"
      }).format(date);
    } catch (error) {
      // Error formatting date
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
