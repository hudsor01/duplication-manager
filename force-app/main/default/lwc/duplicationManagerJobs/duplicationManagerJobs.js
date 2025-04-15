import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import deleteScheduledJob from "@salesforce/apex/DuplicateRecordJobController.deleteScheduledJob";
import getDuplicateRunResults from "@salesforce/apex/DuplicateRecordController.getDuplicateRunResults";
import getScheduledJobs from "@salesforce/apex/DuplicateRecordJobController.getScheduledJobs";
import mergeDuplicateRecords from "@salesforce/apex/DuplicateRecordController.mergeDuplicateRecords";
import store from "c/duplicationStore";
import { duplicationStore } from "c/duplicationStore";

/**
 * Component for displaying and managing scheduled duplicate finder jobs
 * @component
 */
export default class DuplicationManagerJobs extends LightningElement {
  // Event handling methods for quick action buttons
  handleFindDuplicatesClick() {
    // Create event to show batch job form
    const event = new CustomEvent("showbatchform", {
      detail: {
        source: "emptyState"
      }
    });
    this.dispatchEvent(event);
  }

  handleScheduleJobClick() {
    // Create event to show schedule job form
    const event = new CustomEvent("showscheduleform", {
      detail: {
        source: "emptyState"
      }
    });
    this.dispatchEvent(event);
  }
  @api
  get jobs() {
    return this._jobsValue || [];
  }
  set jobs(value) {
    this._jobsValue = value;
  }

  // Tracked properties for reactivity
  @track paginationInfo = {
    pageSize: 10,
    currentPage: 1,
    totalRecords: 0,
    totalPages: 1
  };

  @track deleteInProgress = false;
  @track selectedJobId = null;
  @track error = null;

  // Dry run results state
  @track isDryRunResultsModalOpen = false;
  @track isLoadingDryRunResults = false;
  @track dryRunStats = {
    duplicatesFound: 0,
    totalRecords: 0,
    objectApiName: "",
    configName: ""
  };
  @track dryRunDuplicateGroups = [];
  @track selectedJobForResults = null;

  isLoading = false;

  /**
   * Lifecycle hook - Called when component is inserted into the DOM
   */
  connectedCallback() {
    // Component initialized

    // Initialize pagination from store
    const state = store.getState();
    this.paginationInfo = { ...state.pagination };

    // Load scheduled jobs if not provided
    if (!this.jobs || this.jobs.length === 0) {
      this.loadScheduledJobs();
    }
  }

  /**
   * Lifecycle hook - Called when component is removed from the DOM
   */
  disconnectedCallback() {
    // Component cleanup
  }

  /**
   * Load scheduled jobs from server
   */
  loadScheduledJobs() {
    this.isLoading = true;

    getScheduledJobs()
      .then((result) => {
        // Set backing property instead of the API property directly
        this._jobsValue = result;

        // Update store
        store.dispatch(duplicationStore.actions.UPDATE_SCHEDULED_JOBS, result);

        // Update pagination
        this.updatePagination(result.length);
      })
      .catch((error) => {
        this.handleError("Error loading scheduled jobs", error);
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  /**
   * Deletes a scheduled job
   * @param {String} jobId - The ID of the job to delete
   */
  @api
  deleteJob(jobId) {
    if (!jobId) return;

    // Store the job ID and show confirmation dialog via event
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
      this.dispatchEvent(new CustomEvent("deletecancel"));
      this.jobIdToDelete = null;
      return;
    }

    const jobId = this.jobIdToDelete;
    this.jobIdToDelete = null;

    this.isLoading = true;
    this.deleteInProgress = true;
    this.selectedJobId = jobId;

    try {
      deleteScheduledJob({ jobId: jobId })
        .then(() => {
          // Notify parent of successful deletion
          this.dispatchEvent(
            new CustomEvent("delete", {
              detail: { jobId: jobId }
            })
          );

          // Update store by removing the job
          this.removeJobFromStore(jobId);

          // Show success message
          this.showToast("Success", "Job deleted successfully", "success");
        })
        .catch((error) => {
          this.handleError("Error deleting job", error);
        })
        .finally(() => {
          this.isLoading = false;
          this.deleteInProgress = false;
          this.selectedJobId = null;
        });
    } catch (error) {
      this.handleError("Error in delete execution", error);
      this.isLoading = false;
      this.deleteInProgress = false;
      this.selectedJobId = null;
    }
  }

  /**
   * Remove a job from the store after deletion
   * @param {String} jobId - The ID of the job to remove
   */
  removeJobFromStore(jobId) {
    const state = store.getState();
    const jobs = [...state.scheduledJobs];

    // Find and remove the job
    const updatedJobs = jobs.filter((job) => job.Id !== jobId);

    // Update store
    store.dispatch(duplicationStore.actions.UPDATE_SCHEDULED_JOBS, updatedJobs);

    // Update pagination
    this.updatePagination(updatedJobs.length);

    // Update local jobs backing property
    this._jobsValue = updatedJobs;
  }

  /**
   * Update pagination information
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

    // Update local pagination
    this.paginationInfo = {
      pageSize,
      totalRecords,
      totalPages,
      currentPage
    };

    // Update store pagination
    store.dispatch(
      duplicationStore.actions.UPDATE_PAGINATION,
      this.paginationInfo
    );
  }

  /**
   * Handles the delete button click
   * @param {Event} event - The button click event
   */
  handleDeleteClick(event) {
    const jobId = event.target.dataset.id;
    this.deleteJob(jobId);
  }

  /**
   * Handle job completion notification
   * @param {Event} event - The completion event
   */
  handleJobCompletion(event) {
    const jobId = event.target.dataset.id;
    const jobStatus = event.target.dataset.status;
    const jobRecords = event.target.dataset.records || 0;
    const jobObject = event.target.dataset.object || "Unknown";

    // Create job result object
    const jobResult = {
      id: jobId,
      status: jobStatus,
      recordsProcessed: parseInt(jobRecords, 10) || 0,
      objectApiName: jobObject,
      timestamp: new Date().toISOString()
    };

    // Store selected job for results modal
    this.selectedJobForResults = jobId;

    // Open results modal with loading state
    this.isDryRunResultsModalOpen = true;
    this.isLoadingDryRunResults = true;

    // Load dry run results
    this.loadDryRunResults(jobId);

    // Dispatch event to parent
    this.dispatchEvent(
      new CustomEvent("jobcomplete", {
        detail: jobResult
      })
    );
  }

  /**
   * Handle pagination previous button click
   */
  handlePrevious() {
    if (this.paginationInfo.currentPage > 1) {
      this.handlePageChange({
        detail: { page: this.paginationInfo.currentPage - 1 }
      });
    }
  }

  /**
   * Handle pagination next button click
   */
  handleNext() {
    if (this.paginationInfo.currentPage < this.paginationInfo.totalPages) {
      this.handlePageChange({
        detail: { page: this.paginationInfo.currentPage + 1 }
      });
    }
  }

  /**
   * Handle pagination change
   * @param {Event} event - The pagination event
   */
  handlePageChange(event) {
    const page = event.detail.page;

    if (page && page !== this.paginationInfo.currentPage) {
      // Update local pagination
      this.paginationInfo = {
        ...this.paginationInfo,
        currentPage: page
      };

      // Update store pagination
      store.dispatch(duplicationStore.actions.UPDATE_PAGINATION, {
        currentPage: page
      });

      // Notify parent
      this.dispatchEvent(
        new CustomEvent("pagechange", {
          detail: { page: page }
        })
      );
    }
  }

  /**
   * Shows a toast notification
   * @param {String} title - Toast title
   * @param {String} message - Toast message
   * @param {String} variant - Toast variant (success, error, warning, info)
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
   * Handles errors and displays error messages
   * @param {String} baseMessage - The base error message
   * @param {Object} error - The error object
   */
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

    // Error handled

    // Update local error state
    this.error = {
      message: baseMessage,
      details: errorDetails,
      timestamp: new Date().toISOString()
    };

    // Add to store errors
    store.dispatch(duplicationStore.actions.ADD_ERROR, {
      message: errorMessage,
      type: "job",
      timestamp: new Date().toISOString()
    });

    this.showToast("Error", errorMessage, "error");
  }

  // Computed properties
  /**
   * Checks if there are any scheduled jobs
   * @returns {Boolean} True if there are jobs, false otherwise
   */
  get hasJobs() {
    return this.jobs && this.jobs.length > 0;
  }

  /**
   * Get the jobs for the current page with added properties
   * @returns {Array} Jobs for the current page with added properties
   */
  get paginatedJobs() {
    if (!this.jobs || !this.jobs.length) {
      return [];
    }

    const { pageSize, currentPage } = this.paginationInfo;
    const startIndex = (currentPage - 1) * pageSize;
    const endIndex = Math.min(startIndex + pageSize, this.jobs.length);

    // Add isBeingDeleted property to each job
    return this.jobs.slice(startIndex, endIndex).map((job) => ({
      ...job,
      isBeingDeleted: this.deleteInProgress && this.selectedJobId === job.Id
    }));
  }

  /**
   * Check if pagination is needed
   * @returns {Boolean} True if pagination is needed
   */
  get showPagination() {
    return this.paginationInfo.totalPages > 1;
  }

  /**
   * Check if previous button should be disabled
   * @returns {Boolean} True if previous button should be disabled
   */
  get disablePrevious() {
    return this.paginationInfo.currentPage <= 1;
  }

  /**
   * Check if next button should be disabled
   * @returns {Boolean} True if next button should be disabled
   */
  get disableNext() {
    return this.paginationInfo.currentPage >= this.paginationInfo.totalPages;
  }

  /**
   * Get job statistics summary
   * @returns {String} Summary of job statistics
   */
  get jobsStatsMessage() {
    const total = this.jobs.length;
    const completed = this.jobs.filter(
      (job) => job.Status === "Completed"
    ).length;
    const running = this.jobs.filter((job) => job.Status === "Running").length;

    return `${total} jobs total • ${completed} completed • ${running} running`;
  }

  /**
   * Check if there's an error
   * @returns {Boolean} True if there's an error
   */
  get hasError() {
    return this.error !== null;
  }

  /**
   * Load dry run results for a specific job
   * @param {String} jobId - The ID of the job to load results for
   */
  loadDryRunResults(jobId) {
    this.isLoadingDryRunResults = true;

    // Get the job details from the current jobs list
    const job = this.jobs.find((j) => j.Id === jobId);
    if (!job) {
      this.handleError("Job not found", {
        message: "Could not find job details"
      });
      this.isLoadingDryRunResults = false;
      return;
    }

    // Use getDuplicateRunResults to get actual results
    getDuplicateRunResults({
      batchJobId: jobId,
      pageSize: 10,
      pageNumber: 1
    })
      .then((result) => {
        // Process summary data
        if (result && result.summary) {
          const summary = result.summary;
          this.dryRunStats = {
            duplicatesFound: summary.duplicatesFound || 0,
            totalRecords: summary.recordsProcessed || 0,
            objectApiName: summary.objectApiName || "",
            configName: summary.configName || ""
          };
        }

        // Process duplicate groups
        if (result && result.groups) {
          this.dryRunDuplicateGroups = result.groups.map((group) => {
            return {
              id: group.id,
              groupKey: group.groupKey,
              recordCount: group.recordCount,
              fieldValues: group.fieldValues,
              matchScore: group.matchScore / 100, // Convert to decimal format for the UI
              objectName: group.objectName,
              duplicateRecordIds: group.duplicateRecordIds,
              masterRecordId: group.masterRecordId
            };
          });
        } else {
          this.dryRunDuplicateGroups = [];
        }
      })
      .catch((error) => {
        this.handleError("Error loading dry run results", error);
      })
      .finally(() => {
        this.isLoadingDryRunResults = false;
      });
  }

  /**
   * Close the dry run results modal
   */
  closeDryRunResultsModal() {
    this.isDryRunResultsModalOpen = false;
    this.selectedJobForResults = null;
  }

  /**
   * Handle merge selected button click - shows confirmation dialog
   */
  handleMergeSelectedButton() {
    // Store merge information for confirmation
    this.pendingMergeGroups = this.dryRunDuplicateGroups;

    // Fire event to show confirmation dialog instead of using confirm()
    const confirmEvent = new CustomEvent("confirmmerge", {
      detail: {
        title: "Confirm Merge Operation",
        message:
          "WARNING: This will merge the selected duplicate records. This action cannot be undone. Continue?",
        callback: this.processMergeAfterConfirmation.bind(this)
      }
    });
    this.dispatchEvent(confirmEvent);
  }

  /**
   * Process merge after confirmation
   * @param {Boolean} confirmed - Whether user confirmed the merge
   */
  processMergeAfterConfirmation(confirmed) {
    if (!confirmed || !this.pendingMergeGroups) {
      this.pendingMergeGroups = null;
      return;
    }

    const groupsToMerge = this.pendingMergeGroups;
    this.pendingMergeGroups = null;

    this.isLoadingDryRunResults = true;

    // Process each group sequentially
    this.processMergeGroups(groupsToMerge, 0)
      .then(() => {
        this.showToast(
          "Success",
          "Merge operation completed successfully",
          "success"
        );
        this.closeDryRunResultsModal();

        // Notify parent to refresh jobs
        this.dispatchEvent(
          new CustomEvent("mergecomplete", {
            detail: {
              jobId: this.selectedJobForResults,
              groupsProcessed: groupsToMerge.length
            }
          })
        );
      })
      .catch((error) => {
        this.handleError("Error during merge operation", error);
      })
      .finally(() => {
        this.isLoadingDryRunResults = false;
      });
  }

  /**
   * Process merge groups sequentially
   * @param {Array} groups - Groups to merge
   * @param {Number} index - Current index
   * @returns {Promise} Promise resolved when all groups are processed
   */
  processMergeGroups(groups, index) {
    if (index >= groups.length) {
      return Promise.resolve(); // All groups processed
    }

    const group = groups[index];
    const masterRecordId = group.masterRecordId || group.duplicateRecordIds[0];
    const duplicateIds = group.duplicateRecordIds.filter(
      (id) => id !== masterRecordId
    );

    // Skip groups with no duplicates
    if (!duplicateIds.length) {
      return this.processMergeGroups(groups, index + 1);
    }

    // Merge the current group
    return mergeDuplicateRecords({
      masterRecordId: masterRecordId,
      duplicateRecordIds: duplicateIds,
      objectApiName: group.objectName
    })
      .then(() => {
        // Process next group
        return this.processMergeGroups(groups, index + 1);
      })
      .catch(() => {
        // Error occurred while merging group, continue to next
        // Continue with next group despite error
        return this.processMergeGroups(groups, index + 1);
      });
  }

  /**
   * Check if we have detailed dry run information
   * @returns {Boolean} True if detailed information is available
   */
  get hasDryRunDetails() {
    return this.dryRunDuplicateGroups && this.dryRunDuplicateGroups.length > 0;
  }

  /**
   * Get columns for duplicate groups datatable
   * @returns {Array} Column configuration
   */
  get duplicateGroupColumns() {
    return [
      {
        label: "Object",
        fieldName: "objectName",
        type: "text",
        hideDefaultActions: true
      },
      {
        label: "Record Count",
        fieldName: "recordCount",
        type: "number",
        hideDefaultActions: true,
        cellAttributes: {
          alignment: "right"
        }
      },
      {
        label: "Field Values",
        fieldName: "fieldValues",
        type: "text",
        hideDefaultActions: true,
        wrapText: true
      },
      {
        label: "Match Score",
        fieldName: "matchScore",
        type: "percent",
        hideDefaultActions: true,
        cellAttributes: {
          alignment: "right"
        },
        typeAttributes: {
          minimumFractionDigits: 0,
          maximumFractionDigits: 0
        }
      }
    ];
  }
}
