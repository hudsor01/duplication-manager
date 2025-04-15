import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { MessageContext } from "lightning/messageService";
import getActiveSettings from "@salesforce/apex/DuplicateRecordController.getActiveSettings";
import getFieldsForObject from "@salesforce/apex/DuplicateRecordController.getFieldsForObject";
import runDuplicateFinderBatch from "@salesforce/apex/DuplicateRecordController.runDuplicateFinderBatch";
import store from "c/duplicationStore";
import { duplicationStore } from "c/duplicationStore";
import {
  subscribeToChannel,
  unsubscribeFromChannel,
  sendMessage
} from "c/duplicationMessageService";
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

  // Custom field selection properties
  useCustomConfig = false;
  availableFields = [];
  selectedFields = [];
  originalMatchFields = [];
  loadingFields = false;
  customMatchFields = "";

  // Enhanced UX properties
  fieldSearchTerm = "";
  currentFieldFilter = "all";
  fieldTypeMap = {
    EMAIL: "Email",
    PHONE: "Phone",
    STRING: "Text",
    TEXTAREA: "Text",
    DATETIME: "Date",
    DATE: "Date",
    CURRENCY: "Number",
    DOUBLE: "Number",
    INTEGER: "Number",
    PERCENT: "Number",
    BOOLEAN: "Boolean",
    REFERENCE: "Lookup",
    PICKLIST: "Picklist",
    ADDRESS: "Address",
    URL: "URL",
    ID: "ID"
  };

  // Get message context for LMS
  @wire(MessageContext)
  messageContext;

  /**
   * Lifecycle hook - Called when component is inserted into the DOM
   */
  connectedCallback() {
    // Subscribe to store changes
    this.subscription = subscribeToChannel((message) => {
      // Check message type from imported constants
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
    this.isLoading = false;

    if (data) {
      try {
        // Process configuration data
        const configs = Array.isArray(data) ? data : [];

        // Update store with configurations
        try {
          if (
            duplicationStore.actions &&
            duplicationStore.actions.SET_CONFIGURATIONS
          ) {
            store.dispatch(
              duplicationStore.actions.SET_CONFIGURATIONS,
              configs
            );
          }
        } catch (storeError) {
          this.handleError("Error dispatching to store:", storeError);
        }

        // Generate options for dropdown
        this.configOptions = this.generateConfigOptions(configs);
        this.configsLoaded = true;

        if (configs.length === 0) {
          // Add detailed troubleshooting information to the error message
          this.handleError("No active settings found", {
            message:
              'Please verify that DuplicateFinderSetting__mdt custom metadata type is deployed to your org with IsActive__c=true records. You can deploy it using right-click -> "Deploy Source to Org" in VS Code.'
          });
        }
      } catch (e) {
        this.handleError("Error processing settings data", e);
      }
    } else if (error) {
      this.handleError("Error loading settings", error);
    }
  }

  /**
   * Generate dropdown options from configurations
   * @param {Array} configs - Configuration objects
   * @returns {Array} Formatted options for dropdown
   */
  generateConfigOptions(configs) {
    if (!configs || !Array.isArray(configs) || configs.length === 0) {
      return [];
    }

    try {
      const options = configs
        .map((config) => {
          if (!config.DeveloperName || !config.MasterLabel) {
            return null;
          }

          return {
            label: `${config.MasterLabel || "Unknown"} (${config.ObjectApiName || "Unknown"})`,
            value: config.DeveloperName,
            description: this.getConfigDescription(config),
            config: config
          };
        })
        .filter((option) => option !== null);

      return options;
    } catch (error) {
      this.handleError("Error generating configuration options", error);
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

      if (configId) {
        // Find the selected configuration
        const selectedConfig = this.configOptions.find(
          (option) => option.value === configId
        )?.config;

        if (selectedConfig) {
          this.selectedConfigId = configId;
          this.useCustomConfig = false;
          this.customMatchFields = "";
          this.resetFieldSelections();

          // If we have a valid object API name, load available fields
          if (selectedConfig.ObjectApiName) {
            this.loadAvailableFields(selectedConfig.ObjectApiName);
          }

          // Store original match fields for later reference
          if (selectedConfig.MatchFields) {
            this.originalMatchFields = selectedConfig.MatchFields.split(
              ","
            ).map((field) => field.trim());
          } else {
            this.originalMatchFields = [];
          }

          // Update store with selected configuration
          try {
            if (
              duplicationStore.actions &&
              duplicationStore.actions.SELECT_CONFIGURATION
            ) {
              store.dispatch(
                duplicationStore.actions.SELECT_CONFIGURATION,
                selectedConfig
              );
            }
          } catch (error) {
            this.handleError("Error selecting configuration", error);
          }
        } else {
          this.showToast(
            "Warning",
            "Selected configuration could not be found",
            "warning"
          );
        }
      } else {
        // Clear selection
        this.selectedConfigId = "";
        this.useCustomConfig = false;
        this.customMatchFields = "";
        this.availableFields = [];
        this.originalMatchFields = [];

        try {
          if (
            duplicationStore.actions &&
            duplicationStore.actions.SELECT_CONFIGURATION
          ) {
            store.dispatch(duplicationStore.actions.SELECT_CONFIGURATION, null);
          }
        } catch (error) {
          this.handleError("Error clearing configuration", error);
        }
      }
    } catch (error) {
      this.handleError("Error changing configuration", error);
    }
  }

  /**
   * Load available fields for the selected object
   * @param {String} objectApiName - API name of the object
   */
  loadAvailableFields(objectApiName) {
    if (!objectApiName) return;

    this.loadingFields = true;

    getFieldsForObject({ objectApiName })
      .then((result) => {
        if (result && result.fieldGroups) {
          // Combine all field groups into one list
          let allFields = [];
          result.fieldGroups.forEach((group) => {
            if (group.fields && Array.isArray(group.fields)) {
              allFields = [...allFields, ...group.fields];
            }
          });

          // Process fields to match original field selection with enhanced properties
          this.availableFields = allFields.map((field) => {
            // Get a user-friendly type label
            const typeLabel = this.fieldTypeMap[field.type] || field.type;

            return {
              apiName: field.apiName,
              label: field.label,
              fullLabel: `${field.label} (${field.apiName})`,
              type: field.type,
              typeLabel: typeLabel,
              selected: this.originalMatchFields.includes(field.apiName),
              isContact: this.isContactField(field.apiName, field.type),
              isAddress: this.isAddressField(field.apiName, field.type),
              isText: this.isTextField(field.type)
            };
          });

          // Sort fields by label
          this.availableFields.sort((a, b) => {
            return a.label.localeCompare(b.label);
          });

          // Initialize selected fields from original match fields
          this.selectedFields = [...this.originalMatchFields];

          // Dispatch event to notify parent that fields have loaded
          this.dispatchEvent(
            new CustomEvent("fieldsloaded", {
              detail: {
                fieldsCount: this.availableFields.length,
                selectedCount: this.selectedFields.length
              }
            })
          );
        }
      })
      .catch((error) => {
        this.handleError("Error loading fields for object", error);
      })
      .finally(() => {
        this.loadingFields = false;
      });
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
        (c) => c.DeveloperName === configId
      );

      if (config) {
        this.selectedConfigId = configId;
        try {
          if (
            duplicationStore.actions &&
            duplicationStore.actions.SELECT_CONFIGURATION
          ) {
            store.dispatch(
              duplicationStore.actions.SELECT_CONFIGURATION,
              config
            );
          }
        } catch (error) {
          this.handleError("Error selecting recent configuration", error);
        }
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

    this.error = { message: errorMessage };

    // Add to store errors
    try {
      if (duplicationStore.actions && duplicationStore.actions.ADD_ERROR) {
        store.dispatch(duplicationStore.actions.ADD_ERROR, {
          message: errorMessage,
          timestamp: new Date().toISOString()
        });
      }
    } catch (storeError) {
      // Silently handle storage error
      // Error handler - removed console.error
    }

    this.showToast("Error", errorMessage, "error");
  }

  /**
   * Handle toggling custom configuration mode
   * @param {Event} event - Change event
   */
  handleCustomConfigChange(event) {
    this.useCustomConfig = event.target.checked;

    if (this.useCustomConfig) {
      // If turning on custom config and we don't have fields loaded yet
      const selectedConfig = this.selectedConfiguration;
      if (
        selectedConfig &&
        selectedConfig.ObjectApiName &&
        this.availableFields.length === 0
      ) {
        this.loadAvailableFields(selectedConfig.ObjectApiName);
      }
    } else {
      // If turning off custom config, reset to original settings
      this.customMatchFields = "";
      this.resetFieldSelections();
    }
  }

  /**
   * Handle field selection in custom config mode
   * @param {Event} event - Change event
   */
  handleFieldSelection(event) {
    const fieldName = event.target.dataset.field;
    const isChecked = event.target.checked;

    // Update the availableFields array
    this.availableFields = this.availableFields.map((field) => {
      if (field.apiName === fieldName) {
        field.selected = isChecked;
      }
      return field;
    });

    // Update the selectedFields array
    if (isChecked) {
      if (!this.selectedFields.includes(fieldName)) {
        this.selectedFields.push(fieldName);
      }
    } else {
      this.selectedFields = this.selectedFields.filter(
        (field) => field !== fieldName
      );
    }
  }

  /**
   * Reset field selections to original config
   */
  resetFieldSelections() {
    if (this.availableFields.length === 0) return;

    this.availableFields = this.availableFields.map((field) => {
      field.selected = this.originalMatchFields.includes(field.apiName);
      return field;
    });

    this.selectedFields = [...this.originalMatchFields];
  }

  /**
   * Handle reset to default fields
   */
  handleResetFields() {
    this.resetFieldSelections();
    this.customMatchFields = "";

    this.showToast(
      "Success",
      "Field selection reset to original configuration",
      "success"
    );
  }

  /**
   * Run duplicate finder immediately after customizing fields
   */
  handleFindDuplicatesNow() {
    // First apply the custom config
    if (this.selectedFields.length === 0) {
      this.showToast(
        "Error",
        "Please select at least one field for matching",
        "error"
      );
      return;
    }

    this.customMatchFields = this.selectedFields.join(", ");

    // Create a modified configuration
    const originalConfig = this.selectedConfiguration;
    if (!originalConfig) return;

    const customConfig = { ...originalConfig };
    customConfig.MatchFields = this.customMatchFields;

    // Set as loading
    this.isLoading = true;

    // Update store with custom configuration
    try {
      if (
        duplicationStore.actions &&
        duplicationStore.actions.SELECT_CONFIGURATION
      ) {
        store.dispatch(
          duplicationStore.actions.SELECT_CONFIGURATION,
          customConfig
        );
      }

      // Run a dry run immediately
      const batchSize = 200; // Default batch size

      // Call the batch job with the custom config
      runDuplicateFinderBatch({
        configId: customConfig.DeveloperName,
        isDryRun: true, // Always use dry run for safety
        batchSize: batchSize
      })
        .then((result) => {
          // Show success toast with job ID
          this.showToast(
            "Success",
            "Finding duplicates with custom configuration (Job ID: " +
              result +
              ")",
            "success"
          );

          // Switch to job progress view to see results
          sendMessage(MESSAGE_TYPES.VIEW_CHANGE, {
            view: "batchjobs"
          });

          // Refresh metrics
          sendMessage(MESSAGE_TYPES.REFRESH_METRICS, {});
        })
        .catch((error) => {
          // Handle errors
          // Error handler - removed console.error

          let errorMessage = "Error running duplicate finder";
          if (error.body && error.body.message) {
            errorMessage += ": " + error.body.message;
          }

          this.showToast("Error", errorMessage, "error");
        })
        .finally(() => {
          this.isLoading = false;
        });
    } catch (error) {
      this.handleError("Error finding duplicates", error);
      this.isLoading = false;
    }
  }

  /**
   * Apply custom field configuration
   */
  handleApplyCustomConfig() {
    if (this.selectedFields.length === 0) {
      this.showToast(
        "Error",
        "Please select at least one field for matching",
        "error"
      );
      return;
    }

    // Create custom match fields string
    this.customMatchFields = this.selectedFields.join(", ");

    // Create a modified configuration
    const originalConfig = this.selectedConfiguration;
    if (!originalConfig) return;

    const customConfig = { ...originalConfig };
    customConfig.MatchFields = this.customMatchFields;

    // Update store with modified configuration
    try {
      if (
        duplicationStore.actions &&
        duplicationStore.actions.SELECT_CONFIGURATION
      ) {
        store.dispatch(
          duplicationStore.actions.SELECT_CONFIGURATION,
          customConfig
        );

        // Send custom message to let components know config is ready to use
        sendMessage(MESSAGE_TYPES.CONFIG_UPDATED, {
          configId: customConfig.DeveloperName,
          objectApiName: customConfig.ObjectApiName,
          configName: customConfig.MasterLabel,
          customFields: this.customMatchFields,
          isCustomConfig: true
        });

        // Don't automatically change tabs - let user decide where to go
        // This message will just cause a refresh of components
        sendMessage(MESSAGE_TYPES.REFRESH_METRICS, {});

        this.showToast(
          "Success",
          "Custom field configuration applied! Go to 'Batch Jobs' tab to run the job.",
          "success"
        );
      }
    } catch (error) {
      this.handleError("Error applying custom configuration", error);
    }
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
   * Check if custom field panel should be shown
   * @returns {Boolean} True if custom field panel should be shown
   */
  get showCustomFieldPanel() {
    return this.hasSelectedConfiguration && this.useCustomConfig;
  }

  /**
   * Check if apply button should be disabled
   * @returns {Boolean} True if apply button should be disabled
   */
  get isApplyDisabled() {
    return this.selectedFields.length === 0;
  }

  /**
   * Get display version of match fields (custom or original)
   * @returns {String} Match fields to display
   */
  get displayMatchFields() {
    if (this.useCustomConfig && this.customMatchFields) {
      return this.customMatchFields;
    }

    return this.selectedConfiguration?.MatchFields || "";
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
      "Step 5: Refresh this page"
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

  /**
   * Handler for viewing documentation about the duplication detection algorithm
   */
  handleViewDocs() {
    // Create and dispatch a toast notification with the documentation information
    const evt = new ShowToastEvent({
      title: "Duplication Detection Documentation",
      message:
        "The detailed documentation for the fuzzy matching algorithm is available in the Help section. Click the Help icon in the top right corner of the page.",
      variant: "info",
      mode: "sticky"
    });
    this.dispatchEvent(evt);
  }

  /**
   * Get filtered fields based on current search and filter
   */
  get filteredFields() {
    if (!this.availableFields || this.availableFields.length === 0) {
      return [];
    }

    let filtered = [...this.availableFields];

    // Apply text search if any
    if (this.fieldSearchTerm) {
      const lowercaseSearch = this.fieldSearchTerm.toLowerCase();
      filtered = filtered.filter(
        (field) =>
          field.label.toLowerCase().includes(lowercaseSearch) ||
          field.apiName.toLowerCase().includes(lowercaseSearch)
      );
    }

    // Apply type filter
    if (this.currentFieldFilter !== "all") {
      if (this.currentFieldFilter === "standard") {
        filtered = filtered.filter((field) => !field.apiName.endsWith("__c"));
      } else if (this.currentFieldFilter === "text") {
        filtered = filtered.filter((field) => field.isText);
      } else if (this.currentFieldFilter === "contact") {
        filtered = filtered.filter((field) => field.isContact);
      } else if (this.currentFieldFilter === "address") {
        filtered = filtered.filter((field) => field.isAddress);
      }
    }

    return filtered;
  }

  /**
   * Check if there are no fields to show after filtering
   */
  get noFieldsToShow() {
    return this.filteredFields.length === 0 && !this.isLoadingFields;
  }

  /**
   * Get the count of all fields
   */
  get totalFieldsCount() {
    return this.availableFields.length;
  }

  /**
   * Get the count of selected fields
   */
  get selectedFieldsCount() {
    return this.selectedFields.length;
  }

  /**
   * Checks if a field is a contact information field
   */
  isContactField(apiName, type) {
    const lowercaseApi = apiName.toLowerCase();
    return (
      type === "EMAIL" ||
      type === "PHONE" ||
      lowercaseApi.includes("email") ||
      lowercaseApi.includes("phone") ||
      lowercaseApi.includes("mobile") ||
      lowercaseApi.includes("fax") ||
      lowercaseApi.includes("contact")
    );
  }

  /**
   * Checks if a field is an address field
   */
  isAddressField(apiName, type) {
    const lowercaseApi = apiName.toLowerCase();
    return (
      type === "ADDRESS" ||
      lowercaseApi.includes("street") ||
      lowercaseApi.includes("city") ||
      lowercaseApi.includes("state") ||
      lowercaseApi.includes("country") ||
      lowercaseApi.includes("zip") ||
      lowercaseApi.includes("postal")
    );
  }

  /**
   * Checks if a field is a text/string field
   */
  isTextField(type) {
    return (
      type === "STRING" ||
      type === "TEXTAREA" ||
      type === "PICKLIST" ||
      type === "NAME"
    );
  }

  /**
   * Handles field search
   */
  handleFieldSearch(event) {
    this.fieldSearchTerm = event.target.value;
  }

  /**
   * Field filter handlers
   */
  handleFilterAll() {
    this.currentFieldFilter = "all";
    this.updateActiveFilterButton("filter-all-btn");
  }

  handleFilterStandard() {
    this.currentFieldFilter = "standard";
    this.updateActiveFilterButton("filter-standard-btn");
  }

  handleFilterText() {
    this.currentFieldFilter = "text";
    this.updateActiveFilterButton("filter-text-btn");
  }

  handleFilterContact() {
    this.currentFieldFilter = "contact";
    this.updateActiveFilterButton("filter-contact-btn");
  }

  handleFilterAddress() {
    this.currentFieldFilter = "address";
    this.updateActiveFilterButton("filter-address-btn");
  }

  /**
   * Updates the active filter button styling
   */
  updateActiveFilterButton(activeClassName) {
    // Remove active class from all filter buttons
    const filterButtons = this.template.querySelectorAll(
      ".field-type-filters .slds-button"
    );
    filterButtons.forEach((button) => {
      button.classList.remove("active-filter");
    });

    // Add active class to the selected button
    const activeButton = this.template.querySelector(`.${activeClassName}`);
    if (activeButton) {
      activeButton.classList.add("active-filter");
    }
  }

  /**
   * Handle selecting all fields
   */
  handleSelectAll() {
    // Get the currently filtered fields
    const fieldsToSelect = this.filteredFields;

    // Select all filtered fields
    fieldsToSelect.forEach((field) => {
      field.selected = true;
    });

    // Update the selected fields array
    this.selectedFields = this.availableFields
      .filter((field) => field.selected)
      .map((field) => field.apiName);

    // Show confirmation toast
    this.showToast(
      "Success",
      `Selected ${fieldsToSelect.length} fields`,
      "success"
    );
  }

  /**
   * Handle clearing all field selections
   */
  handleClearAll() {
    // Get the currently filtered fields
    const fieldsToClear = this.filteredFields;

    // Clear selection for all filtered fields
    fieldsToClear.forEach((field) => {
      field.selected = false;
    });

    // Update the selected fields array
    this.selectedFields = this.availableFields
      .filter((field) => field.selected)
      .map((field) => field.apiName);

    // Show confirmation toast
    this.showToast(
      "Success",
      `Cleared selection for ${fieldsToClear.length} fields`,
      "success"
    );
  }

  /**
   * Cancel custom configuration
   */
  handleCancelCustomConfig() {
    // Reset field selection
    this.resetFieldSelections();

    // Exit custom config mode
    this.useCustomConfig = false;
    this.customMatchFields = "";

    // Show confirmation toast
    this.showToast("Info", "Custom configuration canceled", "info");
  }
}
