import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { MessageContext } from "lightning/messageService";
import runDuplicateFinderBatch from "@salesforce/apex/DuplicateRecordController.runDuplicateFinderBatch";
import store from "c/duplicationStore";
import { duplicationStore } from "c/duplicationStore";
import { subscribeToChannel, unsubscribeFromChannel } from "c/duplicationMessageService";
import { MESSAGE_TYPES } from "c/duplicationConstants";

/**
 * Component for controlling batch operations for duplicate management
 * @component
 */
export default class DuplicationBatchController extends LightningElement {
  isLoading = false;
  error = null;
  batchSize = 200; // Default batch size
  batchSizeOptions = [
    { label: "50 Records", value: 50 },
    { label: "100 Records", value: 100 },
    { label: "200 Records", value: 200 },
    { label: "500 Records", value: 500 },
    { label: "1000 Records", value: 1000 },
  ];

  // Get message context for LMS
  @wire(MessageContext)
  messageContext;
  
  /**
   * Lifecycle hook - Called when component is inserted into the DOM
   */
  connectedCallback() {
    // Subscribe to store changes
    this.subscription = subscribeToChannel((message) => {
      if (message.type === MESSAGE_TYPES.STORE_UPDATED) {
        this.handleStoreChange(message.payload);
      }
    });
  }

  /**
   * Lifecycle hook - Called when component is removed from the DOM
   */
  disconnectedCallback() {
    // Unsubscribe from the message channel
    if (this.subscription) {
      unsubscribeFromChannel(this.subscription);
    }
  }

  /**
   * Handle store state changes
   * @param {Object} state - New store state
   */
  handleStoreChange(state) {
    // Update component based on store state if needed
    this.isLoading = state.isLoading;
  }

  /**
   * Handle batch size change
   * @param {Event} event - Change event
   */
  handleBatchSizeChange(event) {
    this.batchSize = parseInt(event.detail.value, 10);
    console.log("Batch size changed to:", this.batchSize);
  }

  /**
   * Handle dry run (find only) execution
   */
  handleDryRun() {
    const selectedConfig = this.selectedConfiguration;

    if (!selectedConfig) {
      this.showToast(
        "Warning",
        "Please select a configuration first",
        "warning",
      );
      return;
    }

    this.executeJob(selectedConfig.DeveloperName, true);
  }

  /**
   * Handle merge execution
   */
  handleRunMerge() {
    const selectedConfig = this.selectedConfiguration;

    if (!selectedConfig) {
      this.showToast(
        "Warning",
        "Please select a configuration first",
        "warning",
      );
      return;
    }

    // Use custom confirmation dialog instead of browser confirm
    this.dispatchEvent(
      new CustomEvent("showconfirmation", {
        detail: {
          title: "Confirm Merge",
          message:
            "WARNING: This will merge duplicate records. This action cannot be undone. Continue?",
          callback: this.executeMergeAfterConfirmation.bind(
            this,
            selectedConfig.DeveloperName,
          ),
        },
      }),
    );
  }

  /**
   * Execute merge after confirmation
   * @param {String} settingDeveloperName - Developer name of the configuration
   * @param {Boolean} confirmed - Whether the user confirmed the action
   */
  executeMergeAfterConfirmation(settingDeveloperName, confirmed) {
    if (confirmed) {
      this.executeJob(settingDeveloperName, false);
    }
  }

  /**
   * Execute a batch job
   * @param {String} settingDeveloperName - Developer name of the configuration
   * @param {Boolean} isDryRun - Whether this is a dry run (find only)
   */
  executeJob(settingDeveloperName, isDryRun) {
    console.log(
      `Executing ${isDryRun ? "dry run" : "merge"} job for setting: ${settingDeveloperName}`,
    );

    // Set loading state
    this.isLoading = true;
    store.dispatch(duplicationStore.actions.SET_LOADING, true);

    // Call Apex method
    runDuplicateFinderBatch({
      settingDeveloperName: settingDeveloperName,
      isDryRun: isDryRun,
      batchSize: this.batchSize,
    })
      .then((result) => {
        console.log("Job executed successfully, job ID:", result);

        // Show success message
        this.showToast(
          "Success",
          `${isDryRun ? "Dry run" : "Merge operation"} started successfully (Job ID: ${result})`,
          "success",
        );

        // Notify parent to refresh jobs
        this.dispatchEvent(
          new CustomEvent("jobexecuted", {
            detail: {
              jobId: result,
              isDryRun: isDryRun,
              settingDeveloperName: settingDeveloperName,
            },
          }),
        );
      })
      .catch((error) => {
        console.error("Error executing job:", error);
        this.handleError(
          `Error starting ${isDryRun ? "dry run" : "merge operation"}`,
          error,
        );
      })
      .finally(() => {
        // Clear loading state
        this.isLoading = false;
        store.dispatch(duplicationStore.actions.SET_LOADING, false);
      });
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
    store.dispatch(duplicationStore.actions.ADD_ERROR, {
      message: errorMessage,
      timestamp: new Date().toISOString(),
    });

    this.showToast("Error", errorMessage, "error");
  }

  /**
   * Get current selected configuration from store
   * @returns {Object} Selected configuration or null
   */
  get selectedConfiguration() {
    const state = store.getState();
    return state.selectedConfiguration;
  }

  /**
   * Determine if there's an active configuration selection
   * @returns {Boolean} True if a configuration is selected
   */
  get hasSelectedConfiguration() {
    return !!this.selectedConfiguration;
  }

  /**
   * Determine if buttons should be disabled
   * @returns {Boolean} True if buttons should be disabled
   */
  get isButtonDisabled() {
    return !this.hasSelectedConfiguration || this.isLoading;
  }

  /**
   * Display error state
   * @returns {Boolean} True if there's an error
   */
  get hasError() {
    return this.error !== null;
  }
}
