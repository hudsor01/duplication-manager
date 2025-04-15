import { LightningElement, track, wire } from "lwc";
import {
  subscribeToChannel,
  unsubscribeFromChannel,
  sendMessage
} from "c/duplicationMessageService";
import { MESSAGE_TYPES } from "c/duplicationConstants";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { NavigationMixin } from "lightning/navigation";
import getUserSettings from "@salesforce/apex/DuplicateRecordController.getUserSettings";
import saveUserSettings from "@salesforce/apex/DRCSaveSettings.saveUserSettings";
import getDuplicateStatistics from "@salesforce/apex/DuplicateRecordStatisticsController.getDuplicateStatistics";

export default class duplicationContainer extends NavigationMixin(
  LightningElement
) {
  @track tabs = [
    {
      name: "dashboard",
      label: "Dashboard",
      icon: "utility:dashboard",
      selected: true,
      tabindex: 0,
      class: "slds-tabs_default__item slds-is-active",
      customClass: "slds-tabs_default__item slds-is-active custom-tab active"
    },
    {
      name: "batchjobs",
      label: "Batch Jobs",
      icon: "utility:refresh",
      selected: false,
      tabindex: -1,
      class: "slds-tabs_default__item",
      customClass: "slds-tabs_default__item custom-tab"
    },
    {
      name: "jobs",
      label: "Scheduled Jobs",
      icon: "utility:event",
      selected: false,
      tabindex: -1,
      class: "slds-tabs_default__item",
      customClass: "slds-tabs_default__item custom-tab"
    },
    {
      name: "logs",
      label: "Audit Logs",
      icon: "utility:record",
      selected: false,
      tabindex: -1,
      class: "slds-tabs_default__item",
      customClass: "slds-tabs_default__item custom-tab"
    }
  ];

  @track activeTab = "dashboard";
  @track showSettings = false;
  @track selectedRecordIds = [];
  @track selectedObjectApiName = "";
  @track selectedGroupId = "";
  @track isLoading = false;

  @track metrics = {
    duplicatesFound: 0,
    recordsMerged: 0,
    duplicatesTrend: 0,
    mergesTrend: 0
  };

  @track userSettings = {
    showAllFields: false,
    autoRefresh: true,
    defaultBatchSize: 200,
    timeRange: "LAST_30_DAYS",
    notificationsEnabled: true,
    defaultView: "dashboard"
  };

  displayOptions = [
    { label: "Show all fields in comparison view", value: "showAllFields" },
    { label: "Auto-refresh job status", value: "autoRefresh" }
  ];

  timeRangeOptions = [
    { label: "Today", value: "TODAY" },
    { label: "Yesterday", value: "YESTERDAY" },
    { label: "This Week", value: "THIS_WEEK" },
    { label: "This Month", value: "THIS_MONTH" },
    { label: "Last Month", value: "LAST_MONTH" },
    { label: "Last 30 Days", value: "LAST_30_DAYS" },
    { label: "This Year", value: "THIS_YEAR" },
    { label: "All Time", value: "ALL_TIME" }
  ];

  viewOptions = [
    { label: "Dashboard", value: "dashboard" },
    { label: "Batch Jobs", value: "batchjobs" },
    { label: "Scheduled Jobs", value: "jobs" },
    { label: "Audit Logs", value: "logs" }
  ];

  notificationOptions = [
    { label: "Job completion notifications", value: "notificationsEnabled" }
  ];

  subscription;

  connectedCallback() {
    console.log("Container component connected");

    // Set default loading state
    this.isLoading = false;

    // Subscribe to channel messages
    this.subscription = subscribeToChannel(this.handleMessage.bind(this));

    // Load metrics from database
    this.loadMetrics();

    // Always default to dashboard tab on initial load for consistency
    this.activeTab = "dashboard";

    // Navigate to the dashboard tab
    this.navigateToTab("dashboard");
    console.log("Initial navigation to dashboard");
  }

  /**
   * After component renders, ensure tabs are set up correctly
   */
  renderedCallback() {
    // If we have an active tab set but it's not properly displayed, fix it
    const activePanel = this.template.querySelector(
      `[data-tab="${this.activeTab}"]`
    );
    if (activePanel && activePanel.classList.contains("slds-hide")) {
      console.log(
        "Tab panel hidden but should be visible, fixing in renderedCallback:",
        this.activeTab
      );
      // Use direct navigation instead of setTimeout
      this.navigateToTab(this.activeTab);
    }
  }

  // New simpler method to activate tabs
  forceTabActivation(tabName) {
    try {
      // Default to dashboard if tabName is invalid
      if (!tabName || !this.tabs.some((tab) => tab.name === tabName)) {
        console.warn("Invalid tab name, defaulting to dashboard:", tabName);
        tabName = "dashboard";
      }

      console.log("Activating tab:", tabName);

      // Simply set the active tab - let the getters and renderedCallback handle the UI
      this.activeTab = tabName;

      // Update all tab selection states
      this.tabs = this.tabs.map((tab) => {
        const isActive = tab.name === tabName;
        return {
          ...tab,
          selected: isActive,
          tabindex: isActive ? 0 : -1,
          class: isActive
            ? "slds-tabs_default__item slds-is-active"
            : "slds-tabs_default__item",
          customClass: isActive
            ? "slds-tabs_default__item slds-is-active custom-tab active"
            : "slds-tabs_default__item custom-tab"
        };
      });

      // Add refresh to the page to ensure tab content updates properly
      window.dispatchEvent(new CustomEvent("refreshView"));
    } catch (error) {
      console.error("Error in forceTabActivation:", error);
      // Try to reset to dashboard as a fallback
      this.activeTab = "dashboard";
    }
  }

  @wire(getUserSettings)
  wiredSettings({ error, data }) {
    if (data) {
      this.userSettings = { ...this.userSettings, ...data };
    } else if (error) {
      console.error("Error loading user settings from server:", error);

      // Try loading from localStorage as fallback
      try {
        const localSettings = localStorage.getItem(
          "duplicationManagerSettings"
        );
        if (localSettings) {
          const parsedSettings = JSON.parse(localSettings);
          console.log("Loaded settings from localStorage:", parsedSettings);
          this.userSettings = { ...this.userSettings, ...parsedSettings };
        }
      } catch (localError) {
        console.error("Error loading from localStorage:", localError);
      }
    }
  }

  disconnectedCallback() {
    // Unsubscribe from channel
    if (this.subscription) {
      unsubscribeFromChannel(this.subscription);
      this.subscription = null;
    }
  }

  /**
   * Handle messages from the message channel
   */
  handleMessage(message) {
    if (message.type === MESSAGE_TYPES.DUPLICATES_FOUND && message.payload) {
      // Set selected record data for comparison
      this.selectedRecordIds = message.payload.recordIds || [];
      this.selectedObjectApiName = message.payload.objectApiName || "";
      this.selectedGroupId = message.payload.groupId || "";

      // Since we removed the compare tab, stay on current tab and show data in the expanded view
      // Or send to batch jobs tab where we'll show comparison data
      this.navigateToTab("batchjobs");

      // Publish a message to notify components about the selected records
      sendMessage(MESSAGE_TYPES.RECORDS_SELECTED, {
        recordIds: this.selectedRecordIds,
        objectApiName: this.selectedObjectApiName,
        groupId: this.selectedGroupId
      });
    } else if (message.type === MESSAGE_TYPES.VIEW_CHANGE && message.payload) {
      // Switch to the requested view
      if (message.payload.view) {
        // If view is "compare", redirect to "batchjobs" since we removed the compare tab
        const view =
          message.payload.view === "compare"
            ? "batchjobs"
            : message.payload.view;
        this.navigateToTab(view);
      }
    } else if (message.type === MESSAGE_TYPES.REFRESH_METRICS) {
      // Refresh metrics data
      this.loadMetrics();
    }
  }

  /**
   * Navigate to a tab with improved reliability
   * @param {String} tabName - Name of the tab to navigate to
   */
  navigateToTab(tabName) {
    // Validate the tab name
    if (!this.tabs.some((tab) => tab.name === tabName)) {
      console.warn("Invalid tab name, defaulting to dashboard:", tabName);
      tabName = "dashboard";
    }

    console.log("Navigating to tab:", tabName);

    try {
      // Store the active tab name
      this.activeTab = tabName;

      // Update the tab states
      this.tabs = this.tabs.map((tab) => {
        const isActive = tab.name === tabName;
        return {
          ...tab,
          selected: isActive,
          tabindex: isActive ? 0 : -1,
          class: isActive
            ? "slds-tabs_default__item slds-is-active"
            : "slds-tabs_default__item",
          customClass: isActive
            ? "slds-tabs_default__item slds-is-active custom-tab active"
            : "slds-tabs_default__item custom-tab"
        };
      });

      // Force a rerender by using multiple techniques
      this.isLoading = true;

      try {
        // Find all tab panels
        const allPanels = this.template.querySelectorAll('[role="tabpanel"]');

        // First, hide all panels
        allPanels.forEach((panel) => {
          panel.classList.add("slds-hide");
          panel.classList.remove("slds-show");
          panel.setAttribute("aria-hidden", "true");
          panel.style.display = "none";
        });

        // Then show the active panel
        const activePanel = this.template.querySelector(
          `[data-tab="${tabName}"]`
        );
        if (activePanel) {
          activePanel.classList.remove("slds-hide");
          activePanel.classList.add("slds-show");
          activePanel.setAttribute("aria-hidden", "false");
          activePanel.style.display = "block";
          console.log("Successfully activated panel for tab:", tabName);
        } else {
          console.error("Could not find panel for tab:", tabName);
        }

        // Remove loading state
        this.isLoading = false;

        // Dispatch an event to notify child components
        this.dispatchEvent(
          new CustomEvent("tabchange", {
            detail: { tab: tabName }
          })
        );

        // Force layout recalculation
        window.dispatchEvent(new CustomEvent("resize"));
      } catch (innerError) {
        console.error("Error in tab navigation handler:", innerError);
        this.isLoading = false;
      }
    } catch (error) {
      console.error("Error navigating to tab:", error);
      this.isLoading = false;
    }
  }

  /**
   * Handle tab click
   */
  handleTabClick(event) {
    try {
      const tabName = event.currentTarget.dataset.id;
      console.log("Tab clicked:", tabName);

      if (tabName === this.activeTab) {
        return;
      }

      // Use the more reliable navigation method
      this.navigateToTab(tabName);

      // Log success
      console.log("Tab switched to:", tabName);
    } catch (error) {
      console.error("Error in tab click handler:", error);
    }
  }

  /**
   * Get CSS class for tab content - simple version
   */
  getTabContentClass(tabName) {
    return this.activeTab === tabName
      ? "slds-tabs_default__content slds-show"
      : "slds-tabs_default__content slds-hide";
  }

  get dashboardTabClass() {
    return this.getTabContentClass("dashboard");
  }

  get batchjobsTabClass() {
    return this.getTabContentClass("batchjobs");
  }

  get compareTabClass() {
    return this.getTabContentClass("compare");
  }

  get jobsTabClass() {
    return this.getTabContentClass("jobs");
  }

  get logsTabClass() {
    return this.getTabContentClass("logs");
  }

  /**
   * Handle refresh button click
   */
  handleRefresh() {
    try {
      console.log("Refresh clicked for tab:", this.activeTab);

      // Publish refresh message
      sendMessage(MESSAGE_TYPES.VIEW_CHANGE, {
        action: "refresh",
        view: this.activeTab
      });

      // Reload metrics if on dashboard
      if (this.activeTab === "dashboard") {
        this.loadMetrics();
      }
    } catch (error) {
      console.error("Error in refresh handler:", error);
    }
  }

  /**
   * Handle settings button click
   */
  handleSettings() {
    this.showSettings = true;
  }

  /**
   * Close settings modal
   */
  closeSettings() {
    this.showSettings = false;
  }

  /**
   * Save settings
   */
  saveSettings() {
    // Capture current settings to send to server
    const settingsToSave = { ...this.userSettings };

    try {
      // Log settings being saved
      console.log("Saving settings:", settingsToSave);

      // Close the modal immediately to avoid Lightning Modal issues
      this.showSettings = false;

      // Execute in next microtask to ensure the modal is fully closed
      Promise.resolve().then(() => {
        // Convert settings to JSON
        let settingsJson;
        try {
          settingsJson = JSON.stringify(settingsToSave);
          console.log("Settings JSON:", settingsJson);
        } catch (jsonError) {
          console.error("Error stringifying settings:", jsonError);
          this.showToast("Error", "Could not process settings data", "error");
          return;
        }

        // Simplify the settings JSON to make storage easier
        const simplifiedSettings = {
          showAllFields: this.userSettings.showAllFields || false,
          autoRefresh: this.userSettings.autoRefresh || true,
          defaultBatchSize: this.userSettings.defaultBatchSize || 200,
          timeRange: this.userSettings.timeRange || "LAST_30_DAYS",
          notificationsEnabled: this.userSettings.notificationsEnabled || true,
          defaultView: this.userSettings.defaultView || "dashboard"
        };

        // Convert the simplified settings to JSON
        const simplifiedJson = JSON.stringify(simplifiedSettings);

        console.log("Sending simplified settings JSON:", simplifiedJson);

        // Send to server using Apex
        saveUserSettings({ settingsJson: simplifiedJson })
          .then((result) => {
            // Success handling
            console.log("Settings saved successfully, result:", result);
            if (result) {
              this.showToast(
                "Success",
                "Settings saved successfully",
                "success"
              );
            }
          })
          .catch((error) => {
            // Error handling with more detailed logging
            console.error("Server error saving settings:", error);
            let errorMessage = "Unable to save settings";

            if (error && error.body) {
              if (error.body.message) {
                errorMessage += ": " + error.body.message;
              } else if (error.body.exceptionType) {
                errorMessage += ": " + error.body.exceptionType;
              }
            }

            this.showToast("Error", errorMessage, "error");

            // Store settings locally as fallback
            try {
              localStorage.setItem(
                "duplicationManagerSettings",
                simplifiedJson
              );
              console.log("Saved settings to localStorage as fallback");
            } catch (localError) {
              console.error("Could not save to localStorage:", localError);
            }
          });
      });
    } catch (error) {
      console.error("Unexpected error in saveSettings function:", error);
      this.showSettings = false;
      this.showToast("Error", "Unexpected error occurred", "error");
    }
  }

  /**
   * Show toast notification
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
   * Handle help button click
   */
  handleHelp() {
    window.open("/apex/duplicateHelp", "_blank");
  }

  /**
   * Handle configuration selected
   */
  handleConfigSelected(event) {
    const config = event.detail;

    // Send message about selected configuration
    if (config) {
      sendMessage(MESSAGE_TYPES.CONFIG_SELECTED, {
        configId: config.id,
        objectApiName: config.objectApiName,
        configName: config.name
      });

      // Refresh the relevant views
      this.handleRefresh();
    }
  }

  /**
   * Check if dashboard tab is active
   */
  get isDashboardTab() {
    return this.activeTab === "dashboard";
  }

  /**
   * Check if batch jobs tab is active
   */
  get isBatchJobsTab() {
    return this.activeTab === "batchjobs";
  }

  /**
   * Check if we have records selected for comparison
   */
  get hasSelectedRecords() {
    return this.selectedRecordIds && this.selectedRecordIds.length > 0;
  }

  /**
   * Dynamic class for the batch controller column
   */
  get batchControllerColumnClass() {
    return this.hasSelectedRecords
      ? "slds-col slds-size_4-of-12"
      : "slds-col slds-size_9-of-12";
  }

  /**
   * Dynamic class for the sidebar column
   */
  get sidebarColumnClass() {
    return this.hasSelectedRecords
      ? "slds-col slds-size_4-of-12"
      : "slds-col slds-size_3-of-12";
  }

  /**
   * Check if jobs tab is active
   */
  get isJobsTab() {
    return this.activeTab === "jobs";
  }

  /**
   * Check if logs tab is active
   */
  get isLogsTab() {
    return this.activeTab === "logs";
  }

  /**
   * Get selected display options as array
   */
  get selectedDisplayOptions() {
    const options = [];
    if (this.userSettings.showAllFields) options.push("showAllFields");
    if (this.userSettings.autoRefresh) options.push("autoRefresh");
    return options;
  }

  /**
   * Get selected notification options as array
   */
  get selectedNotificationOptions() {
    const options = [];
    if (this.userSettings.notificationsEnabled)
      options.push("notificationsEnabled");
    return options;
  }

  /**
   * Handle batch size change
   */
  handleBatchSizeChange(event) {
    this.userSettings.defaultBatchSize = event.detail.value;
  }

  /**
   * Handle display options change
   */
  handleDisplayOptionsChange(event) {
    const selectedOptions = event.detail.value;
    this.userSettings.showAllFields = selectedOptions.includes("showAllFields");
    this.userSettings.autoRefresh = selectedOptions.includes("autoRefresh");
  }

  /**
   * Handle time range change
   */
  handleTimeRangeChange(event) {
    this.userSettings.timeRange = event.detail.value;

    // Refresh metrics with new time range if on dashboard
    if (this.isDashboardTab) {
      this.loadMetrics();
    }
  }

  /**
   * Handle default view change
   */
  handleDefaultViewChange(event) {
    this.userSettings.defaultView = event.detail.value;
  }

  /**
   * Handle notification options change
   */
  handleNotificationOptionsChange(event) {
    const selectedOptions = event.detail.value;
    this.userSettings.notificationsEnabled = selectedOptions.includes(
      "notificationsEnabled"
    );
  }

  /**
   * Load metrics from database
   */
  loadMetrics() {
    getDuplicateStatistics({ timeRange: this.userSettings.timeRange })
      .then((result) => {
        if (result) {
          this.metrics = result;
        }
      })
      .catch((error) => {
        console.error("Error loading metrics:", error);
        this.showToast(
          "Error",
          "Could not load metrics: " + (error.message || "Unknown error"),
          "warning"
        );
      });
  }
}
