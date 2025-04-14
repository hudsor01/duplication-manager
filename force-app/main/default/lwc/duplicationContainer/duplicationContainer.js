import { LightningElement, track, wire } from "lwc";
import {
  subscribeToChannel,
  unsubscribeFromChannel,
  sendMessage,
  MESSAGE_TYPES,
} from "c/duplicationMessageService";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getUserSettings from "@salesforce/apex/DuplicateRecordController.getUserSettings";
import saveUserSettings from "@salesforce/apex/DuplicateRecordController.saveUserSettings";
import getDuplicateStatistics from "@salesforce/apex/DuplicateRecordStatisticsController.getDuplicateStatistics";

export default class duplicationContainer extends LightningElement {
  @track tabs = [
    {
      name: "dashboard",
      label: "Dashboard",
      icon: "utility:chart",
      selected: true,
      tabindex: 0,
      class: "slds-tabs_default__item slds-is-active",
      customClass: "slds-tabs_default__item slds-is-active custom-tab active",
    },
    {
      name: "batchjobs",
      label: "Batch Jobs",
      icon: "utility:recycle",
      selected: false,
      tabindex: -1,
      class: "slds-tabs_default__item",
      customClass: "slds-tabs_default__item custom-tab",
    },
    {
      name: "compare",
      label: "Compare",
      icon: "utility:side_by_side",
      selected: false,
      tabindex: -1,
      class: "slds-tabs_default__item",
      customClass: "slds-tabs_default__item custom-tab",
    },
    {
      name: "jobs",
      label: "Scheduled Jobs",
      icon: "utility:clock",
      selected: false,
      tabindex: -1,
      class: "slds-tabs_default__item",
      customClass: "slds-tabs_default__item custom-tab",
    },
    {
      name: "logs",
      label: "Audit Logs",
      icon: "utility:list",
      selected: false,
      tabindex: -1,
      class: "slds-tabs_default__item",
      customClass: "slds-tabs_default__item custom-tab",
    },
  ];

  @track activeTab = "dashboard";
  @track showSettings = false;
  @track selectedRecordIds = [];
  @track selectedObjectApiName = "";
  @track selectedGroupId = "";

  @track metrics = {
    duplicatesFound: 0,
    recordsMerged: 0,
    duplicatesTrend: 0,
    mergesTrend: 0,
  };

  @track userSettings = {
    showAllFields: false,
    autoRefresh: true,
    defaultBatchSize: 200,
    timeRange: "LAST_30_DAYS",
    notificationsEnabled: true,
    defaultView: "dashboard",
  };

  displayOptions = [
    { label: "Show all fields in comparison view", value: "showAllFields" },
    { label: "Auto-refresh job status", value: "autoRefresh" },
  ];

  timeRangeOptions = [
    { label: "Today", value: "TODAY" },
    { label: "Yesterday", value: "YESTERDAY" },
    { label: "This Week", value: "THIS_WEEK" },
    { label: "This Month", value: "THIS_MONTH" },
    { label: "Last Month", value: "LAST_MONTH" },
    { label: "Last 30 Days", value: "LAST_30_DAYS" },
    { label: "This Year", value: "THIS_YEAR" },
    { label: "All Time", value: "ALL_TIME" },
  ];

  viewOptions = [
    { label: "Dashboard", value: "dashboard" },
    { label: "Batch Jobs", value: "batchjobs" },
    { label: "Scheduled Jobs", value: "jobs" },
    { label: "Audit Logs", value: "logs" },
  ];

  notificationOptions = [
    { label: "Job completion notifications", value: "notificationsEnabled" },
  ];

  subscription;

  connectedCallback() {
    // Subscribe to channel messages
    this.subscription = subscribeToChannel(this.handleMessage.bind(this));

    // Load metrics from database
    this.loadMetrics();

    // Apply initial settings
    this.applyInitialSettings();
  }

  applyInitialSettings() {
    // Apply default view from user settings if available
    if (
      this.userSettings?.defaultView &&
      this.userSettings.defaultView !== "dashboard"
    ) {
      // Use Promise instead of setTimeout
      Promise.resolve().then(() => {
        this.switchTab(this.userSettings.defaultView);
      });
    }
  }

  @wire(getUserSettings)
  wiredSettings({ error, data }) {
    if (data) {
      this.userSettings = { ...this.userSettings, ...data };
      this.applyInitialSettings();
    } else if (error) {
      // Error loading user settings
      this.showToast(
        "Error",
        "Could not load user settings: " +
          (error.body?.message || error.message || "Unknown error"),
        "error",
      );
    }
  }

  disconnectedCallback() {
    // Unsubscribe from channel
    if (this.subscription) {
      unsubscribeFromChannel(this.subscription);
    }
  }

  /**
   * Handle messages from the message channel
   */
  handleMessage(message) {
    // Message received in container

    if (message.type === MESSAGE_TYPES.DUPLICATES_FOUND && message.payload) {
      // Set selected record data for comparison
      this.selectedRecordIds = message.payload.recordIds || [];
      this.selectedObjectApiName = message.payload.objectApiName || "";
      this.selectedGroupId = message.payload.groupId || "";

      // Show loading state
      this.showLoading("compare");

      // Switch to compare tab using Promise instead of setTimeout
      Promise.resolve().then(() => {
        this.switchTab("compare");
        this.hideLoading();
      });
    } else if (message.type === MESSAGE_TYPES.VIEW_CHANGE && message.payload) {
      // Switch to the requested view
      if (message.payload.view) {
        this.showLoading(message.payload.view);
        Promise.resolve().then(() => {
          this.switchTab(message.payload.view);
          this.hideLoading();
        });
      }
    } else if (message.type === MESSAGE_TYPES.REFRESH_METRICS) {
      // Refresh metrics data
      this.loadMetrics();
    }
  }

  /**
   * Show loading state for a specific tab
   */
  showLoading(tabName) {
    const contentEl = this.template.querySelector(
      `[aria-labelledby="${tabName}-tab"]`,
    );
    if (contentEl) {
      contentEl.classList.add("tab-content-hide");
      contentEl.classList.remove("tab-content-show");
    }
  }

  /**
   * Hide loading state
   */
  hideLoading() {
    const contentEl = this.template.querySelector(
      `[aria-labelledby="${this.activeTab}-tab"]`,
    );
    if (contentEl) {
      contentEl.classList.add("tab-content-show");
      contentEl.classList.remove("tab-content-hide");
    }
  }

  /**
   * Handle tab click
   */
  handleTabClick(event) {
    const tabName = event.currentTarget.dataset.id;
    this.showLoading(tabName);
    Promise.resolve().then(() => {
      this.switchTab(tabName);
      this.hideLoading();
    });
  }

  /**
   * Switch to a specific tab
   */
  switchTab(tabName) {
    // Reset all tabs
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
          : "slds-tabs_default__item custom-tab",
      };
    });

    // Set active tab
    this.activeTab = tabName;
  }

  /**
   * Get CSS class for tab content
   */
  getTabContentClass(tabName) {
    return this.activeTab === tabName
      ? "slds-tabs_default__content slds-show tab-content-container tab-content-show"
      : "slds-tabs_default__content slds-hide tab-content-container tab-content-hide";
  }

  /**
   * Handle refresh button click
   */
  handleRefresh() {
    // Show loading animation
    this.showLoading(this.activeTab);

    // Publish refresh message
    sendMessage(MESSAGE_TYPES.VIEW_CHANGE, {
      action: "refresh",
      view: this.activeTab,
    });

    // Reload metrics if on dashboard
    if (this.activeTab === "dashboard") {
      this.loadMetrics();
    }

    // Hide loading using Promise instead of setTimeout
    Promise.resolve().then(() => {
      this.hideLoading();
    });
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
    saveUserSettings({ settingsJson: JSON.stringify(this.userSettings) })
      .then((result) => {
        if (result) {
          this.showToast("Success", "Settings saved successfully", "success");

          // Apply settings to current session
          this.applySettings();
          this.showSettings = false;
        }
      })
      .catch((error) => {
        this.showToast(
          "Error",
          "Error saving settings: " +
            (error.body?.message || error.message || "Unknown error"),
          "error",
        );
      });
  }

  /**
   * Show toast notification
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
        configName: config.name,
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
   * Check if compare tab is active
   */
  get isCompareTab() {
    return this.activeTab === "compare";
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
      "notificationsEnabled",
    );
  }

  /**
   * Apply settings to current session
   */
  applySettings() {
    // Broadcast settings change
    sendMessage(MESSAGE_TYPES.CONFIG_CHANGED, {
      settings: this.userSettings,
    });

    // Apply default view if needed
    if (
      this.activeTab === "dashboard" &&
      this.userSettings.defaultView !== "dashboard"
    ) {
      this.switchTab(this.userSettings.defaultView);
    }

    // Refresh metrics with new time range
    this.loadMetrics();
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
          "Could not load metrics: " +
            (error.body?.message || error.message || "Unknown error"),
          "warning",
        );
      });
  }
}
