import { LightningElement, track, wire, api } from "lwc";
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
  // API properties passed from parent components
  @api height = 800;
  @api useSafeArea = false; // Default to false, will be set to true by parent
  
  @track activeTab = "dashboard";
  @track showSettings = false;
  @track selectedRecordIds = [];
  @track selectedObjectApiName = "";
  @track selectedGroupId = "";
  @track isLoading = false;
  
  // Track tab information
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

  @track metrics = {
    duplicatesFound: 0,
    recordsMerged: 0,
    duplicatesTrend: 0,
    mergesTrend: 0,
    currentMonthMerges: 0
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

  subscription = null;
  _resizeHandler = null;
  _resizeTimeout = null;

  connectedCallback() {
    // Set default loading state
    this.isLoading = false;

    // Subscribe to channel messages
    this.subscription = subscribeToChannel(this.handleMessage.bind(this));

    // Load metrics from database
    this.loadMetrics();

    // Always default to dashboard tab on initial load for consistency
    this.activeTab = "dashboard";
    
    // Update tab states based on active tab
    this.updateTabStates();
    
    // DISABLED: Resize listener causes severe browser freezing
    /* 
    this._resizeHandler = this.handleResize.bind(this);
    window.addEventListener('resize', this._resizeHandler, {passive: true});
    */
  }
  
  /**
   * Handle window resize events with throttling
   * Using setTimeout instead of requestAnimationFrame to prevent Safari issues
   */
  handleResize() {
    // Use setTimeout instead of requestAnimationFrame to avoid Safari issues
    if (this._resizeTimeout) {
      clearTimeout(this._resizeTimeout);
    }
    
    // Use a longer timeout to reduce frequency of updates
    this._resizeTimeout = setTimeout(() => {
      // Just update the container height - no other DOM manipulation
      this.updateContainerHeight();
    }, 250); // 250ms throttle
  }
  
  /**
   * Update container height only - completely removed dynamic height calculations
   * to prevent Safari/Chrome freezing during resize operations
   */
  updateContainerHeight() {
    // DISABLED: Dynamic height calculations cause severe browser freezing
    // Instead, we'll use fixed CSS in the component
    
    // No dynamic height adjustments - safer approach
    return;
    
    /* Original implementation - removed to prevent freezing
    try {
      const rootElement = this.template.querySelector(
        ".slds-grid.slds-grid_vertical.slds-grid_frame"
      );
      if (rootElement) {
        // Simple height adjustment
        rootElement.style.minHeight = `${window.innerHeight}px`;
      }
    } catch (error) {
      // Silent error handling
    }
    */
  }

  disconnectedCallback() {
    // Unsubscribe from channel
    if (this.subscription) {
      unsubscribeFromChannel(this.subscription);
      this.subscription = null;
    }
    
    // DISABLED: Resize listener cleanup not needed since we disabled it
    /*
    if (this._resizeHandler) {
      window.removeEventListener('resize', this._resizeHandler);
      this._resizeHandler = null;
    }
    */
    
    // Clear any pending timeouts
    if (this._resizeTimeout) {
      clearTimeout(this._resizeTimeout);
      this._resizeTimeout = null;
    }
  }

  /**
   * After component renders, ensure container height is set
   * Using direct approach instead of requestAnimationFrame to prevent Safari freezing
   */
  renderedCallback() {
    // Avoid requestAnimationFrame which can cause issues in Safari
    // Use basic timeout instead with a small delay
    setTimeout(() => {
      // Just update the container height - no DOM manipulation for tabs
      this.updateContainerHeight();
    }, 50);
  }

  /**
   * Update all tab states based on active tab
   */
  updateTabStates() {
    this.tabs = this.tabs.map((tab) => {
      const isActive = tab.name === this.activeTab;
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
  }
  
  /**
   * Activate a tab by name - simplified version
   */
  activateTab(tabName) {
    // Default to dashboard if tabName is invalid
    if (!tabName || !this.tabs.some((tab) => tab.name === tabName)) {
      tabName = "dashboard";
    }

    // Set the active tab
    this.activeTab = tabName;
    
    // Update tab states based on the new active tab
    this.updateTabStates();
    
    // Dispatch event for child components
    this.dispatchEvent(new CustomEvent("tabactivated", {
      detail: { tabName: tabName },
      bubbles: false
    }));
  }

  @wire(getUserSettings)
  wiredSettings({ error, data }) {
    if (data) {
      this.userSettings = { ...this.userSettings, ...data };
    } else if (error) {
      // Try loading from localStorage as fallback
      try {
        const localSettings = localStorage.getItem(
          "duplicationManagerSettings"
        );
        if (localSettings) {
          const parsedSettings = JSON.parse(localSettings);
          this.userSettings = { ...this.userSettings, ...parsedSettings };
        }
      } catch (localError) {
        // Fail silently
      }
    }
  }

  /**
   * Handle messages from the message channel
   */
  handleMessage(message) {
    if (!message) return;
    
    if (message.type === MESSAGE_TYPES.DUPLICATES_FOUND && message.payload) {
      // Set selected record data for comparison
      this.selectedRecordIds = message.payload.recordIds || [];
      this.selectedObjectApiName = message.payload.objectApiName || "";
      this.selectedGroupId = message.payload.groupId || "";

      // Navigate to batch jobs tab
      this.activateTab("batchjobs");

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
        this.activateTab(view);
      }
    } else if (message.type === MESSAGE_TYPES.CHANGE_TAB && message.payload) {
      // Handle tab change requests
      if (message.payload.tabName) {
        // Navigate to the requested tab
        const tabName =
          message.payload.tabName === "compare"
            ? "batchjobs"
            : message.payload.tabName;
        this.activateTab(tabName);

        // If we have additional object information, store it
        if (message.payload.objectApiName) {
          this.selectedObjectApiName = message.payload.objectApiName;

          // If this is a merge view request, also send a RECORDS_SELECTED message
          if (message.payload.showMergeView) {
            sendMessage(MESSAGE_TYPES.QUICK_MERGE_DUPLICATES, {
              objectName: message.payload.objectApiName,
              source: "container"
            });
          }
        }
      }
    } else if (message.type === MESSAGE_TYPES.REFRESH_METRICS) {
      // Refresh metrics data
      this.loadMetrics();
    }
  }

  /**
   * Handle tab click
   */
  handleTabClick(event) {
    try {
      const tabName = event.currentTarget.dataset.id;
      if (tabName === this.activeTab) {
        return;
      }

      // Activate the clicked tab
      this.activateTab(tabName);
    } catch (error) {
      // Handle errors silently
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
      // Handle errors silently
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
   * Save settings safely
   */
  saveSettings() {
    // Capture current settings to send to server
    const settingsToSave = { ...this.userSettings };

    try {
      // Close the modal immediately
      this.showSettings = false;

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

      // Send to server using Apex
      saveUserSettings({ settingsJson: simplifiedJson })
        .then((result) => {
          // Success handling
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
          } catch (localError) {
            // Handle local storage errors silently
          }
        });
    } catch (error) {
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
   * Handle schedule new job button click
   */
  handleScheduleNewJob() {
    // First switch to the correct tab
    this.activateTab("jobs");

    // Then send a message to the job manager to open the schedule dialog
    sendMessage(MESSAGE_TYPES.OPEN_SCHEDULE_JOB, {
      source: "container"
    });

    // Show feedback that the action was triggered
    this.showToast("Schedule Job", "Opening job scheduling dialog", "info");
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
          // Store the base metrics
          this.metrics = { ...result };

          // Calculate additional metrics for display in different views
          if (this.metrics.recordsMerged) {
            // Calculate current month as ~60% of total for last 30 days
            const thisMonthEstimate = Math.round(
              this.metrics.recordsMerged * 0.6
            );
            this.metrics.currentMonthMerges = thisMonthEstimate;
          }
        }
      })
      .catch((error) => {
        this.showToast(
          "Error",
          "Could not load metrics: " + (error.message || "Unknown error"),
          "warning"
        );
      });
  }
}