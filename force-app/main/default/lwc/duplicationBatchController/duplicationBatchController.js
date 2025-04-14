import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { MessageContext } from "lightning/messageService";
import runDuplicateFinderBatch from "@salesforce/apex/DuplicateRecordController.runDuplicateFinderBatch";
import store from "c/duplicationStore";
import { duplicationStore } from "c/duplicationStore";
import {
  subscribeToChannel,
  unsubscribeFromChannel
} from "c/duplicationMessageService";
import { MESSAGE_TYPES } from "c/duplicationConstants";

/**
 * Component for controlling batch operations for duplicate management
 * @component
 */
export default class DuplicationBatchController extends LightningElement {
  isLoading = false;
  error = null;
  batchSize = 200; // Default batch size
  runMode = "dryRun"; // Default to dry run mode
  batchSizeOptions = [
    { label: "50 Records", value: 50 },
    { label: "100 Records", value: 100 },
    { label: "200 Records", value: 200 },
    { label: "500 Records", value: 500 },
    { label: "1000 Records", value: 1000 }
  ];

  // Get message context for LMS
  @wire(MessageContext)
  messageContext;

  /**
   * Lifecycle hook - Called when component is inserted into the DOM
   */
  connectedCallback() {
    // Set initial state
    this.isLoading = false;
    this.error = null;

    // Subscribe to store changes
    this.subscription = subscribeToChannel((message) => {
      if (message.type === MESSAGE_TYPES.STORE_UPDATED) {
        this.handleStoreChange(message.payload);
      }
    });

    // Safety timeout using Promise to ensure we don't get stuck in loading state
    this.safetyPromise = this.createSafetyTimeout(5000);
  }

  /**
   * Lifecycle hook - Called when component is removed from the DOM
   */
  disconnectedCallback() {
    // Unsubscribe from the message channel
    if (this.subscription) {
      unsubscribeFromChannel(this.subscription);
    }

    // Cancel any pending safety timeout
    this.safetyPromise = null;
  }

  /**
   * Creates a safety system with manual timeout to avoid loading state getting stuck
   * @returns {Promise} Promise that resolves immediately but triggers a loading reset
   */
  createSafetyTimeout() {
    // Create a promise that resolves immediately
    return Promise.resolve().then(() => {
      // Store current loading state
      const initialLoadingState = this.isLoading;
      
      // Set a simple timeout to forcibly reset loading state after 5 seconds
      // This is a safety mechanism in case the normal flow fails
      setTimeout(() => {
        if (this.isLoading && initialLoadingState) {
          // Safety mechanism triggered - reset loading state
          this.isLoading = false;
          
          // Also reset the store loading state
          store.dispatch(duplicationStore.actions.SET_LOADING, false);
        }
      }, 5000);
    });
  }

  /**
   * Get a unique ID for the component's root template
   */
  get templateRootId() {
    if (!this._templateId) {
      // Generate a simple ID based on component instance
      this._templateId = `batch_controller_${Date.now()}`;
    }
    return this._templateId;
  }

  /**
   * Handle store state changes
   * @param {Object} state - New store state
   */
  handleStoreChange(state) {
    try {
      // Update component based on store state if needed
      if (state && typeof state === "object") {
        this.isLoading = !!state.isLoading;
      } else {
        // If we receive invalid state, ensure loading is false
        this.isLoading = false;
      }
    } catch (error) {
      // Reset loading on error and track the issue silently
      this.isLoading = false;
    }
  }

  /**
   * Handle batch size change
   * @param {Event} event - Change event
   */
  handleBatchSizeChange(event) {
    this.batchSize = parseInt(event.detail.value, 10);
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
        "warning"
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
        "warning"
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
            selectedConfig.DeveloperName
          )
        }
      })
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
    // Execute job based on selected configuration and mode

    // Set loading state
    this.isLoading = true;
    store.dispatch(duplicationStore.actions.SET_LOADING, true);

    // Call Apex method
    runDuplicateFinderBatch({
      configId: settingDeveloperName,
      isDryRun: isDryRun,
      batchSize: this.batchSize
    })
      .then((result) => {
        // Job executed successfully, show success message
        this.showToast(
          "Success",
          `${isDryRun ? "Dry run" : "Merge operation"} started successfully (Job ID: ${result})`,
          "success"
        );

        // Notify parent to refresh jobs
        this.dispatchEvent(
          new CustomEvent("jobexecuted", {
            detail: {
              jobId: result,
              isDryRun: isDryRun,
              settingDeveloperName: settingDeveloperName
            }
          })
        );
      })
      .catch((error) => {
        // Handle error through proper error handling method
        this.handleError(
          `Error starting ${isDryRun ? "dry run" : "merge operation"}`,
          error
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

    // Set error state for component
    this.error = { message: errorMessage };

    // Add to store errors
    store.dispatch(duplicationStore.actions.ADD_ERROR, {
      message: errorMessage,
      timestamp: new Date().toISOString()
    });

    this.showToast("Error", errorMessage, "error");
  }

  /**
   * Get current selected configuration from store
   * @returns {Object} Selected configuration or null
   */
  get selectedConfiguration() {
    try {
      const state = store.getState();
      return state?.selectedConfiguration || null;
    } catch (error) {
      // In case of error, safely return null
      return null;
    }
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

  /**
   * Handle run mode change
   * @param {Event} event - Change event
   */
  handleRunModeChange(event) {
    this.runMode = event.target.value;

    // Show toast to clearly indicate mode change
    const modeLabel = this.isDryRunMode ? "Dry Run" : "Live Merge";
    const variant = this.isDryRunMode ? "info" : "warning";
    const message = this.isDryRunMode
      ? "Switched to Dry Run mode - this will identify duplicates without modifying data."
      : "Switched to Live Merge mode - this will permanently merge duplicate records.";

    this.showToast(`Mode: ${modeLabel}`, message, variant);
  }

  /**
   * Check if currently in dry run mode
   * @returns {Boolean} True if in dry run mode
   */
  get isDryRunMode() {
    return this.runMode === "dryRun";
  }
}
