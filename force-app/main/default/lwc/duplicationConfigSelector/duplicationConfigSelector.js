import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { MessageContext } from "lightning/messageService";
import getActiveSettings from "@salesforce/apex/DuplicateRecordController.getActiveSettings";
import store from "c/duplicationStore";
import { duplicationStore } from "c/duplicationStore";
import { subscribeToChannel, unsubscribeFromChannel } from "c/duplicationMessageService";
import { MESSAGE_TYPES } from "c/duplicationConstants";

/**
 * Component for selecting and previewing duplicate detection configurations
 * @component
 */
export default class DuplicationConfigSelector extends LightningElement {
  isLoading = true;
  error = null;
  selectedConfigId = "";

  // Holds the list of configuration options for the dropdown
  configOptions = [];

  // Tracks if configurations are loaded
  configsLoaded = false;

  // Holds recently used configurations
  recentConfigurations = [];

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

    // Initialize from store
    const state = store.getState();
    this.recentConfigurations = state.recentConfigurations || [];

    if (state.selectedConfiguration) {
      this.selectedConfigId = state.selectedConfiguration.DeveloperName;
    }
  }

  /**
   * Lifecycle hook - Called when component is removed from the DOM
   */
  disconnectedCallback() {
    // Unsubscribe from channel
    if (this.subscription) {
      unsubscribeFromChannel(this.subscription);
    }
  }

  /**
   * Handle store state changes
   * @param {Object} state - New store state
   */
  handleStoreChange(state) {
    if (state.selectedConfiguration) {
      this.selectedConfigId = state.selectedConfiguration.DeveloperName;
    }
    this.recentConfigurations = state.recentConfigurations || [];
  }

  /**
   * Wire method to get active configuration settings
   */
  @wire(getActiveSettings)
  wiredSettings({ error, data }) {
    console.log("configSelector.wiredSettings called, data:", data);
    this.isLoading = false;

    if (data) {
      try {
        // Process configuration data
        const configs = Array.isArray(data) ? data : [];

        // Update store with configurations
        store.dispatch(duplicationStore.actions.SET_CONFIGURATIONS, configs);

        // Generate options for dropdown
        this.configOptions = this.generateConfigOptions(configs);
        this.configsLoaded = true;

        console.log("Configurations loaded:", configs.length);

        if (configs.length === 0) {
          console.warn("No active duplicate finder settings found in the org");
          // Add detailed troubleshooting information to the error message
          this.handleError("No active settings found", {
            message:
              'Please verify that DuplicateFinderSetting__mdt custom metadata type is deployed to your org with IsActive__c=true records. You can deploy it using right-click -> "Deploy Source to Org" in VS Code.',
          });
        }
      } catch (e) {
        console.error("Error processing settings data:", e);
        this.handleError("Error processing settings data", e);
      }
    } else if (error) {
      console.error("Error in wiredSettings:", error);
      this.handleError("Error loading settings", error);
    }
  }

  /**
   * Generate dropdown options from configurations
   * @param {Array} configs - Configuration objects
   * @returns {Array} Formatted options for dropdown
   */
  generateConfigOptions(configs) {
    console.log(
      "Generating config options, configs count:",
      configs?.length || 0,
    );

    if (!configs || !Array.isArray(configs) || configs.length === 0) {
      console.warn("No configurations available for dropdown");
      return [];
    }

    try {
      const options = configs
        .map((config) => {
          if (!config.DeveloperName || !config.MasterLabel) {
            console.warn("Configuration is missing required fields:", config);
            return null;
          }

          return {
            label: `${config.MasterLabel || "Unknown"} (${config.ObjectApiName || "Unknown"})`,
            value: config.DeveloperName,
            description: this.getConfigDescription(config),
            config: config,
          };
        })
        .filter((option) => option !== null);

      console.log("Generated options:", options.length);
      return options;
    } catch (error) {
      console.error("Error generating configuration options:", error);
      return [];
    }
  }

  /**
   * Get descriptive text for a configuration
   * @param {Object} config - Configuration object
   * @returns {String} Description of the configuration
   */
  getConfigDescription(config) {
    if (!config) return "";

    const parts = [];

    if (config.ObjectApiName) {
      parts.push(`Object: ${config.ObjectApiName}`);
    }

    if (config.MatchFields) {
      parts.push(`Match Fields: ${config.MatchFields}`);
    }

    if (config.MasterRecordStrategy) {
      parts.push(`Strategy: ${config.MasterRecordStrategy}`);
    }

    return parts.join(" | ");
  }

  /**
   * Handle configuration selection change
   * @param {Event} event - Change event
   */
  handleConfigChange(event) {
    try {
      const configId = event.detail.value;
      console.log("Configuration selection changed to:", configId);

      if (configId) {
        // Find the selected configuration
        const selectedConfig = this.configOptions.find(
          (option) => option.value === configId,
        )?.config;

        if (selectedConfig) {
          console.log("Selected configuration:", selectedConfig);
          this.selectedConfigId = configId;

          // Update store with selected configuration
          store.dispatch(
            duplicationStore.actions.SELECT_CONFIGURATION,
            selectedConfig,
          );
        } else {
          console.warn("Could not find configuration with id:", configId);
          this.showToast(
            "Warning",
            "Selected configuration could not be found",
            "warning",
          );
        }
      } else {
        // Clear selection
        this.selectedConfigId = "";
        store.dispatch(duplicationStore.actions.SELECT_CONFIGURATION, null);
        console.log("Configuration selection cleared");
      }
    } catch (error) {
      console.error("Error in handleConfigChange:", error);
      this.handleError("Error changing configuration", error);
    }
  }

  /**
   * Handle selection of a recent configuration
   * @param {Event} event - Click event
   */
  handleRecentSelection(event) {
    const configId = event.currentTarget.dataset.id;
    if (configId) {
      // Find the configuration in the store
      const state = store.getState();
      const config = state.configurations.find(
        (c) => c.DeveloperName === configId,
      );

      if (config) {
        this.selectedConfigId = configId;
        store.dispatch(duplicationStore.actions.SELECT_CONFIGURATION, config);
      }
    }
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
   * Get current selected configuration
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
   * Determine if there are recent configurations
   * @returns {Boolean} True if there are recent configurations
   */
  get hasRecentConfigurations() {
    return this.recentConfigurations && this.recentConfigurations.length > 0;
  }

  /**
   * Check if configurations have been loaded
   * @returns {Boolean} True if configurations are loaded
   */
  get hasConfigurations() {
    return this.configsLoaded && this.configOptions.length > 0;
  }

  /**
   * Display deployment guide modal
   */
  handleViewGuide() {
    const message = [
      "Step 1: Navigate to the customMetadata folder in VS Code",
      'Step 2: Right-click on the folder and select "Deploy Source to Org"',
      "Step 3: Verify deployment in Setup > Custom Metadata Types > Duplicate Finder Setting",
      'Step 4: Ensure at least one record has "Is Active" checked',
      "Step 5: Refresh this page",
    ].join("\n");

    this.showToast("Deployment Instructions", message, "info");
  }

  /**
   * Display error state
   * @returns {Boolean} True if there's an error
   */
  get hasError() {
    return this.error !== null;
  }
}
