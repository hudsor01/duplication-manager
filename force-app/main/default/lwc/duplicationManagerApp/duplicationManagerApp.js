/**
 * Main component for managing duplicate records
 * Migrated to use Lightning Message Service
 */
import { LightningElement, wire, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { MessageContext } from "lightning/messageService";
import { sendMessage, setMessageContext } from "c/duplicationMessageService";
import { MESSAGE_TYPES } from "c/duplicationConstants";
import { subscribeMigrated, unsubscribeMigrated } from "c/duplicationLmsHelper";
import getActiveSettings from "@salesforce/apex/DuplicateRecordController.getActiveSettings";
import getScheduledJobs from "@salesforce/apex/DuplicateRecordJobController.getScheduledJobs";
import runDuplicateFinder from "@salesforce/apex/DuplicateRecordJobController.runDuplicateFinderBatch";
import store, { duplicationStore } from "c/duplicationStore";

/**
 * Main component for managing duplicate records
 * @component
 */
export default class DuplicationManagerApp extends LightningElement {
  // Use @track for complex objects that need reactivity
  @track settings = [];
  @track selectedSetting = null;
  @track scheduledJobs = [];
  @track error = null;
  @track healthCheckResults = null;
  @track healthCheckHasIssues = false;
  @track healthCheckHasErrors = false;
  @track paginationInfo = {
    pageSize: 10,
    currentPage: 1,
    totalRecords: 0,
    totalPages: 1
  };

  // Use regular properties for primitives or simple values
  selectedSettingId = "";
  isLoading = true;
  isScheduleModalOpen = false;
  isConfirmationModalOpen = false;
  confirmationMessage = "";
  refreshInProgress = false;
  lastRefreshTime = null;
  draftJob = null;

  // Additional error tracking for specific operations
  refreshError = null;
  jobOperationError = null;

  @track activeTabName = "config";
  @track showScheduleModal = false;
  @track showRunJobModal = false;

  /**
   * Wire the MessageContext for LMS
   */
  @wire(MessageContext)
  messageContext;

  /**
   * Lifecycle hook - Called when component is inserted into the DOM
   */
  connectedCallback() {
    // Component connected to DOM
    this.error = null;

    // Subscribe to store changes using LMS helper
    this._subscriptions = subscribeMigrated(this, {
      duplicationStoreChange: this.handleStoreChange
    });

    // Set the message context for the messaging service
    setMessageContext(this.messageContext);

    // Initialize store with MessageContext
    store.initialize(this.messageContext);

    // Initialize from store
    this.syncFromStore();

    // Load any existing draft job
    store.dispatch(duplicationStore.actions.LOAD_DRAFT_JOB);
  }

  /**
   * Lifecycle hook - Called when component is removed from the DOM
   */
  disconnectedCallback() {
    // Component removed from DOM

    // Unsubscribe using LMS helper
    unsubscribeMigrated(this._subscriptions);
  }

  /**
   * Lifecycle hook - Called after component renders or re-renders
   */
  renderedCallback() {
    // Ensure message context is set after rendering
    if (this.messageContext) {
      setMessageContext(this.messageContext);
    }
  }

  /**
   * Lifecycle hook - Handles errors that occur in child components
   * @param {Error} error - The error object
   */
  errorCallback(error) {
    // Error in component or child component
    this.error = error;
    this.showToast("Error", `Component error: ${error.message}`, "error");
  }

  /**
   * Handle store state changes
   */
  handleStoreChange = () => {
    this.syncFromStore();
  };

  /**
   * Handle messages from LMS channel
   * @param {Object} message - Message from LMS channel
   */
  handleChannelMessage = (message) => {
    switch (message.type) {
      case MESSAGE_TYPES.JOB_COMPLETED:
        if (message.payload) {
          this.handleJobCompleted({ detail: message.payload });
        }
        break;
      case MESSAGE_TYPES.JOB_ERROR:
        this.handleError("Job error", message.payload);
        break;
      case MESSAGE_TYPES.CONFIG_SELECTED:
        if (message.payload && message.payload.configId) {
          this.handleSettingChange({
            detail: { value: message.payload.configId }
          });
        }
        break;
      default:
        // Handle other messages as needed
        break;
    }
  };

  /**
   * Synchronize component state from store
   */
  syncFromStore() {
    const state = store.getState();
    this.isLoading = state.isLoading;

    // Use spread operator to trigger reactivity
    this.settings = [...state.configurations];
    this.selectedSetting = state.selectedConfiguration;
    this.selectedSettingId = this.selectedSetting
      ? this.selectedSetting.DeveloperName
      : "";
    this.scheduledJobs = [...state.scheduledJobs];
    this.paginationInfo = { ...state.pagination };
    this.draftJob = state.draftJob;

    // Update error state
    if (state.errors && state.errors.length > 0) {
      this.error = state.errors[state.errors.length - 1]; // Latest error
    } else {
      this.error = null;
    }
  }

  // Wire methods to get data from server
  @wire(getActiveSettings)
  wiredSettings({ error, data }) {
    // Set loading state in store
    store.dispatch(duplicationStore.actions.SET_LOADING, true);

    if (data) {
      try {
        // Only fetch data if not in cache
        if (!store.isCacheValid("configurations")) {
          const configurations = Array.isArray(data) ? data : [];
          store.dispatch(
            duplicationStore.actions.SET_CONFIGURATIONS,
            configurations
          );

          if (configurations.length === 0) {
            this.handleError("No active settings found", {
              message:
                "Please verify duplicate Settings are active in your org",
              type: "configuration"
            });
          }
        }
      } catch (e) {
        this.handleError("Error processing settings data", e);
        store.dispatch(duplicationStore.actions.SET_LOADING, false);
      }
    } else if (error) {
      this.handleError("Error loading settings", error);
      store.dispatch(duplicationStore.actions.SET_LOADING, false);
    }
  }

  @wire(getScheduledJobs)
  wiredJobs({ error, data }) {
    // Set loading state in store
    store.dispatch(duplicationStore.actions.SET_LOADING, true);

    // Mark cache as pending
    store.dispatch(duplicationStore.actions.SET_CACHE_PENDING, {
      section: "jobs",
      status: true
    });

    if (data) {
      // Update store with jobs data
      store.dispatch(duplicationStore.actions.UPDATE_SCHEDULED_JOBS, data);
      this.updatePagination(data.length);
    } else if (error) {
      this.handleError("Error loading scheduled jobs", error);
    }
    store.dispatch(duplicationStore.actions.SET_LOADING, false);
  }

  // Event handlers
  handleSettingChange(event) {
    try {
      const settingName = event.detail.value || event.target.value;

      if (settingName) {
        // Find setting in store
        const state = store.getState();
        const selectedSetting = state.configurations.find(
          (setting) => setting.DeveloperName === settingName
        );

        // Update store with selected setting
        if (selectedSetting) {
          store.dispatch(
            duplicationStore.actions.SELECT_CONFIGURATION,
            selectedSetting
          );
        } else {
          this.showToast(
            "Warning",
            "Selected setting could not be found",
            "warning"
          );
        }
      } else {
        store.dispatch(duplicationStore.actions.SELECT_CONFIGURATION, null);
      }
    } catch (error) {
      this.handleError("Error changing setting", error);
    }
  }

  handleDryRun() {
    if (!this.selectedSetting) {
      this.showToast("Warning", "Please select a configuration", "warning");
      return;
    }

    // Check for health check errors
    if (this.healthCheckHasErrors) {
      this.showToast(
        "Error",
        "Cannot proceed due to critical health check issues. Please address the issues first.",
        "error"
      );
      return;
    }

    // Set loading state in store
    store.dispatch(duplicationStore.actions.SET_LOADING, true);

    try {
      runDuplicateFinder({
        configId: this.selectedSetting.DeveloperName,
        isDryRun: true,
        batchSize: 200
      })
        .then((result) => {
          // Success handling
          this.showToast(
            "Success",
            "Dry run started successfully (Job ID: " + result + ")",
            "success"
          );

          // Save job information for results display
          const jobInfo = {
            id: result,
            objectApiName: this.selectedSetting.ObjectApiName,
            configName: this.selectedSetting.MasterLabel,
            isDryRun: true,
            timestamp: new Date().toISOString()
          };

          // Store in session storage for results display
          try {
            sessionStorage.setItem("lastDryRunJob", JSON.stringify(jobInfo));
          } catch (e) {
            // Error storing job info in session storage
          }

          // Invalidate jobs cache to trigger refresh
          store.dispatch(duplicationStore.actions.INVALIDATE_CACHE, "jobs");

          // Update statistics if necessary
          this.updateStatisticsAfterJobStart();

          // Send message via LMS
          sendMessage(MESSAGE_TYPES.DRY_RUN_COMPLETE, {
            jobId: result,
            configId: this.selectedSetting.DeveloperName
          });
        })
        .catch((error) => {
          this.handleError("Error starting dry run", error);
        })
        .finally(() => {
          store.dispatch(duplicationStore.actions.SET_LOADING, false);
        });
    } catch (error) {
      this.handleError("Error in dry run execution", error);
      store.dispatch(duplicationStore.actions.SET_LOADING, false);
    }
  }

  /**
   * Handle health check complete event
   * @param {Event} event - Health check event
   */
  handleHealthCheckComplete(event) {
    const healthCheckResults = event.detail;
    this.healthCheckResults = healthCheckResults;
    this.healthCheckHasIssues =
      healthCheckResults && healthCheckResults.hasIssues;
    this.healthCheckHasErrors =
      healthCheckResults &&
      healthCheckResults.issues &&
      healthCheckResults.issues.some((issue) => issue.severity === "error");

    // If there are critical errors, prevent the user from running the job
    if (this.healthCheckHasErrors) {
      this.showToast(
        "Warning",
        "Critical health check issues found. Please review and address the issues before proceeding.",
        "warning"
      );
    }
  }

  handleRunMerge() {
    if (!this.selectedSetting) {
      this.showToast("Warning", "Please select a configuration", "warning");
      return;
    }

    // Show the confirmation modal instead of using confirm()
    this.confirmationMessage =
      "WARNING: This will merge duplicate records. This action cannot be undone. Continue?";
    this.isConfirmationModalOpen = true;
  }

  handleConfirmMerge() {
    // Close the confirmation modal
    this.isConfirmationModalOpen = false;

    // Check for health check errors
    if (this.healthCheckHasErrors) {
      this.showToast(
        "Error",
        "Cannot proceed due to critical health check issues. Please address the issues first.",
        "error"
      );
      return;
    }

    // Set loading state in store
    store.dispatch(duplicationStore.actions.SET_LOADING, true);

    try {
      runDuplicateFinder({
        configId: this.selectedSetting.DeveloperName,
        isDryRun: false,
        batchSize: 200
      })
        .then((result) => {
          // Success handling with clearer feedback
          this.showToast(
            "Success",
            "Merge operation started successfully (Job ID: " + result + ")",
            "success"
          );

          // Additional information toast
          this.showToast(
            "Information",
            "Refresh the jobs list to check status. Records will be merged when the job completes.",
            "info"
          );

          // Invalidate jobs cache to trigger refresh
          store.dispatch(duplicationStore.actions.INVALIDATE_CACHE, "jobs");

          // Track merge job start in statistics
          this.updateStatisticsAfterJobStart();

          // Clear draft job after successful merge
          if (
            this.draftJob &&
            this.draftJob.configId === this.selectedSetting.DeveloperName
          ) {
            store.dispatch(duplicationStore.actions.CLEAR_DRAFT_JOB);
          }

          // Publish job started event via LMS
          sendMessage(MESSAGE_TYPES.JOB_STARTED, {
            jobId: result,
            configId: this.selectedSetting.DeveloperName,
            isDryRun: false
          });
        })
        .catch((error) => {
          this.handleError("Error starting merge", error);
        })
        .finally(() => {
          store.dispatch(duplicationStore.actions.SET_LOADING, false);
        });
    } catch (error) {
      this.handleError("Error in merge execution", error);
      store.dispatch(duplicationStore.actions.SET_LOADING, false);
    }
  }

  handleCancelMerge() {
    // Save current configuration as draft job before closing
    if (this.selectedSetting) {
      this.saveDraftJob();
    }

    // Close the confirmation modal
    this.isConfirmationModalOpen = false;
  }

  handleDeleteJob(event) {
    const jobId = event.detail.jobId || event.target.dataset.id;
    // Set loading state in store
    store.dispatch(duplicationStore.actions.SET_LOADING, true);
    // Child component will handle the deletion and fire event
    this.template.querySelector("c-duplication-manager-jobs").deleteJob(jobId);
  }

  handleJobDeleted() {
    this.showToast("Success", "Job deleted successfully", "success");
    this.refreshJobs();
  }

  handleJobCompleted(event) {
    // Extract job result information
    const jobResult = event.detail;
    if (jobResult) {
      // Check if job was a dry run
      const isDryRun = this.checkIfDryRunJob(jobResult.id);

      // Check if job completed with zero records
      if (jobResult.recordsProcessed === 0) {
        this.showToast(
          "Information",
          "Job completed with zero duplicate records found",
          "info"
        );
      } else {
        // Normal success message
        const actionText = isDryRun ? "found" : "merged";
        this.showToast(
          "Success",
          `Job completed successfully. ${actionText} ${jobResult.recordsProcessed} records.`,
          "success"
        );

        // Update statistics with job result
        store.dispatch(duplicationStore.actions.ADD_MERGE_RESULT, {
          id: jobResult.id,
          objectApiName: jobResult.objectApiName,
          count: jobResult.recordsProcessed,
          isDryRun: isDryRun
        });

        // Publish job completed event via LMS
        sendMessage(MESSAGE_TYPES.JOB_COMPLETED, jobResult);
      }

      // Refresh jobs list
      this.refreshJobs();
    }
  }

  /**
   * Handle merge request from dry run results
   * @param {Event} event - Event containing merge request details
   */
  handleMergeRequest(event) {
    const mergeDetails = event.detail;
    if (mergeDetails && mergeDetails.jobId) {
      // Set loading state
      store.dispatch(duplicationStore.actions.SET_LOADING, true);

      // Call the real Apex method to merge the records
      runDuplicateFinder({
        configId: this.selectedSetting?.DeveloperName,
        isDryRun: false,
        batchSize: 200
      })
        .then((result) => {
          this.showToast(
            "Success",
            "Merge operation started successfully (Job ID: " + result + ")",
            "success"
          );
          store.dispatch(duplicationStore.actions.SET_LOADING, false);
          this.refreshJobs();
        })
        .catch((error) => {
          this.handleError("Error starting merge", error);
          store.dispatch(duplicationStore.actions.SET_LOADING, false);
        });
    }
  }

  refreshJobs() {
    // Set loading and error states
    this.refreshInProgress = true;
    this.refreshError = null;
    store.dispatch(duplicationStore.actions.SET_LOADING, true);

    // Invalidate cache
    store.dispatch(duplicationStore.actions.INVALIDATE_CACHE, "jobs");

    return getScheduledJobs()
      .then((result) => {
        // Process result
        store.dispatch(duplicationStore.actions.UPDATE_SCHEDULED_JOBS, result);
        this.updatePagination(result.length);
        this.lastRefreshTime = new Date().toLocaleTimeString();
      })
      .catch((error) => {
        // Detailed error handling for refresh operation

        const errorMessage = "Error refreshing jobs";
        let errorDetails = "";

        if (error) {
          if (error.body && error.body.message) {
            errorDetails = error.body.message;
          } else if (error.message) {
            errorDetails = error.message;
          } else {
            errorDetails = JSON.stringify(error);
          }
        }

        // Store specific refresh error
        this.refreshError = {
          message: errorMessage,
          details: errorDetails,
          timestamp: new Date().toISOString()
        };

        // Add to global error store
        store.dispatch(duplicationStore.actions.ADD_ERROR, {
          message: `${errorMessage}: ${errorDetails}`,
          type: "refresh",
          timestamp: new Date().toISOString()
        });

        // Show toast with retry option
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Error refreshing jobs",
            message: errorDetails,
            variant: "error",
            mode: "sticky"
          })
        );
      })
      .finally(() => {
        // Reset loading states
        this.refreshInProgress = false;
        store.dispatch(duplicationStore.actions.SET_LOADING, false);
      });
  }

  /**
   * Update pagination information based on total records
   * @param {Number} totalRecords - Total number of records
   */
  updatePagination(totalRecords) {
    const pageSize = this.paginationInfo.pageSize;
    const totalPages = Math.ceil(totalRecords / pageSize) || 1;

    // Ensure current page is valid
    let currentPage = this.paginationInfo.currentPage;
    if (currentPage > totalPages) {
      currentPage = totalPages;
    }

    // Update pagination in store
    store.dispatch(duplicationStore.actions.UPDATE_PAGINATION, {
      pageSize,
      totalRecords,
      totalPages,
      currentPage
    });
  }

  /**
   * Handle pagination changes
   * @param {Event} event - Pagination event
   */
  handlePageChange(event) {
    const pageNumber = event.detail.page;

    if (pageNumber && pageNumber !== this.paginationInfo.currentPage) {
      // Update pagination in store
      store.dispatch(duplicationStore.actions.UPDATE_PAGINATION, {
        currentPage: pageNumber
      });
    }
  }

  /**
   * Update statistics after a job starts
   */
  updateStatisticsAfterJobStart() {
    if (this.selectedSetting) {
      // Create a pending job entry for statistics
      const jobInfo = {
        objectApiName: this.selectedSetting.ObjectApiName,
        configName: this.selectedSetting.MasterLabel,
        status: "Running",
        timestamp: new Date().toISOString()
      };

      // Notify statistics
      store.dispatch(duplicationStore.actions.ADD_MERGE_RESULT, jobInfo);
    }
  }

  /**
   * Check if a job is a dry run based on stored information or naming convention
   * @param {String} jobId - ID of the job to check
   * @returns {Boolean} True if job is a dry run
   */
  checkIfDryRunJob(jobId) {
    // First check session storage
    try {
      const lastJobInfo = sessionStorage.getItem("lastDryRunJob");
      if (lastJobInfo) {
        const jobInfo = JSON.parse(lastJobInfo);
        if (jobInfo.id === jobId) {
          return jobInfo.isDryRun === true;
        }
      }
    } catch (e) {
      // Error retrieving job info from session storage
    }

    // Check job name in scheduled jobs
    const job = this.scheduledJobs.find((j) => j.Id === jobId);
    if (job && job.CronJobDetail && job.CronJobDetail.Name) {
      return (
        job.CronJobDetail.Name.toLowerCase().includes("dry run") ||
        job.CronJobDetail.Name.toLowerCase().includes("find only")
      );
    }

    // Default to false
    return false;
  }

  /**
   * Get the configuration ID for a job
   * @param {String} jobId - ID of the job
   * @returns {String} Configuration ID associated with the job
   */
  getConfigIdForJob(jobId) {
    // First check session storage
    try {
      const lastJobInfo = sessionStorage.getItem("lastDryRunJob");
      if (lastJobInfo) {
        const jobInfo = JSON.parse(lastJobInfo);
        if (jobInfo.id === jobId && jobInfo.configId) {
          return jobInfo.configId;
        }
      }
    } catch (e) {
      // Error retrieving job info from session storage
    }

    // Check job in scheduled jobs
    const job = this.scheduledJobs.find((j) => j.Id === jobId);
    if (job && job.Setting) {
      return job.Setting;
    }

    return null;
  }

  handleScheduleJob() {
    // The child scheduler component will handle the actual scheduling
    this.showToast("Success", "Job scheduled successfully", "success");
    this.closeScheduleModal();
    this.refreshJobs();
  }

  // Helper methods
  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: title,
        message: message,
        variant: variant
      })
    );
  }

  handleError(baseMessage, error) {
    let errorMessage = baseMessage;
    let errorDetails = "";

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

    // Log error message

    // Create structured error object
    const errorObj = {
      message: baseMessage,
      details: errorDetails,
      timestamp: new Date().toISOString(),
      type: error && error.type ? error.type : "general"
    };

    // Add to store
    store.dispatch(duplicationStore.actions.ADD_ERROR, errorObj);

    // Show toast for user
    this.showToast("Error", errorMessage, "error");
  }

  // Computed properties
  get isButtonDisabled() {
    return !this.selectedSetting || this.healthCheckHasErrors;
  }

  get hasError() {
    return this.error !== null;
  }

  get hasRefreshError() {
    return this.refreshError !== null;
  }

  get showJobList() {
    return this.scheduledJobs && this.scheduledJobs.length > 0;
  }

  get confirmationModalClass() {
    return this.isConfirmationModalOpen
      ? "slds-modal slds-fade-in-open"
      : "slds-modal";
  }

  get confirmationBackdropClass() {
    return this.isConfirmationModalOpen
      ? "slds-backdrop slds-backdrop_open"
      : "slds-backdrop";
  }

  get noJobsMessage() {
    return this.isLoading
      ? "Loading jobs..."
      : "No scheduled jobs found. Use the buttons above to start a job or schedule one for later.";
  }

  get lastRefreshTimeFormatted() {
    return this.lastRefreshTime
      ? `Last refreshed at ${this.lastRefreshTime}`
      : "";
  }

  get hasDraftJob() {
    return !!this.draftJob;
  }

  get draftJobLabel() {
    if (!this.draftJob) {
      return "";
    }

    return (
      this.draftJob.configName ||
      this.draftJob.objectApiName ||
      "Unknown Configuration"
    );
  }

  /**
   * Gets setting options for combobox
   * @returns {Array} Array of options with label and value
   */
  get settingOptions() {
    if (
      !this.settings ||
      !Array.isArray(this.settings) ||
      this.settings.length === 0
    ) {
      return [];
    }

    try {
      const options = this.settings
        .map((setting) => {
          if (!setting.DeveloperName || !setting.MasterLabel) {
            return null;
          }
          return {
            label: `${setting.MasterLabel || "Unknown"} (${setting.ObjectApiName || "Unknown"})`,
            value: setting.DeveloperName
          };
        })
        .filter((option) => option !== null);

      return options;
    } catch (error) {
      return [];
    }
  }

  /**
   * Saves the current configuration as a draft job
   */
  saveDraftJob() {
    if (!this.selectedSetting) {
      return;
    }

    // Create draft job object
    const draftJob = {
      configId: this.selectedSetting.DeveloperName,
      objectApiName: this.selectedSetting.ObjectApiName,
      configName: this.selectedSetting.MasterLabel,
      batchSize: this.selectedSetting.BatchSize,
      matchFields: this.selectedSetting.MatchFields,
      lastModified: new Date().toISOString()
    };

    // Save to store
    store.dispatch(duplicationStore.actions.SAVE_DRAFT_JOB, draftJob);
    this.showToast(
      "Information",
      "Your configuration has been saved as a draft",
      "info"
    );
  }

  /**
   * Loads the draft job from the store
   */
  loadDraftJob() {
    if (!this.draftJob) {
      return;
    }

    // Find the configuration in the settings
    const configToLoad = this.settings.find(
      (setting) => setting.DeveloperName === this.draftJob.configId
    );

    if (configToLoad) {
      // Select the configuration
      store.dispatch(
        duplicationStore.actions.SELECT_CONFIGURATION,
        configToLoad
      );
      this.showToast("Success", "Draft job loaded successfully", "success");
    } else {
      this.showToast(
        "Warning",
        "Could not find the configuration for this draft job",
        "warning"
      );
    }
  }

  /**
   * Clears the current draft job
   */
  clearDraftJob() {
    store.dispatch(duplicationStore.actions.CLEAR_DRAFT_JOB);
    this.showToast("Success", "Draft job cleared", "success");
  }

  // Tab switching
  handleTabChange(event) {
    this.activeTabName = event.target.value;
  }

  // Configuration selection
  handleConfigSelected(event) {
    const config = event.detail;
    this.selectedConfiguration = config;
  }

  // Schedule modal methods
  openScheduleModal() {
    if (!this.selectedSetting) {
      this.showToast("Warning", "Please select a configuration", "warning");
      return;
    }
    this.isScheduleModalOpen = true;
  }

  closeScheduleModal() {
    this.isScheduleModalOpen = false;
  }

  // Open run job modal
  openRunJobModal() {
    if (!this.selectedConfiguration) {
      this.showToast("Error", "Please select a configuration first", "error");
      return;
    }
    this.showRunJobModal = true;
  }

  // Close run job modal
  closeRunJobModal() {
    this.showRunJobModal = false;
  }

  // Handle job scheduled event
  handleJobScheduled(event) {
    const details = event.detail;
    this.showScheduleModal = false;
    this.showToast(
      "Success",
      `Job "${details.jobName}" scheduled successfully`,
      "success"
    );
  }

  // Handle job run event
  handleJobRun(event) {
    const details = event.detail;
    this.showRunJobModal = false;
    this.showToast(
      "Success",
      `Job started with ID: ${details.jobId}`,
      "success"
    );

    // Switch to logs tab
    this.activeTabName = "logs";
  }
}
