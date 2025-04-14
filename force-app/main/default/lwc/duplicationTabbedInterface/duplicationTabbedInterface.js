import { LightningElement, api, track, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import runDuplicateDetection from "@salesforce/apex/DuplicateRecordJobController.runDuplicateDetection";
import { MessageContext } from "lightning/messageService";
import {
  sendMessage,
  subscribeToChannel,
  unsubscribeFromChannel
} from "c/duplicationMessageService";
import { MESSAGE_TYPES } from "c/duplicationConstants";
import {
  handleError,
  ERROR_LEVELS,
  ERROR_CATEGORIES
} from "c/duplicationErrorService";

export default class DuplicationTabbedInterface extends LightningElement {
  @api recordId;
  @api tabsetName;
  @track selectedObjectType = "Account";
  @track selectedConfigId;
  @track isLoading = false;
  @track currentTab = "dashboard";
  @track jobId;
  @track selectedFields = [];

  // State for the comparison view
  @track hideCompareTab = true;
  @track hideMergePreviewTab = true;
  @track compareRecordIds = [];
  @track masterRecordId;
  @track selectedGroupId;

  // Active tab value
  @track activeTab = "dashboard";

  // Get the message context for LMS
  @wire(MessageContext)
  messageContext;

  // Store subscriptions
  subscriptions = [];

  // Object type options
  objectTypeOptions = [
    { label: "Accounts", value: "Account" },
    { label: "Contacts", value: "Contact" },
    { label: "Leads", value: "Lead" },
    { label: "Custom Objects", value: "Custom" }
  ];

  // Lifecycle hooks
  connectedCallback() {
    // Subscribe to messages
    this.subscribeToMessages();
  }

  disconnectedCallback() {
    // Unsubscribe from all messages
    this.unsubscribeFromMessages();
  }

  // Subscribe to LMS messages
  subscribeToMessages() {
    // Subscribe to job completion events
    const jobSubscription = subscribeToChannel((message) => {
      if (message.type === MESSAGE_TYPES.JOB_COMPLETED) {
        this.handleJobCompleted(message.payload);
      }
    });
    this.subscriptions.push(jobSubscription);

    // Subscribe to field selection changes
    const fieldSubscription = subscribeToChannel((message) => {
      if (message.type === MESSAGE_TYPES.FIELDS_SELECTED) {
        this.selectedFields = message.payload.fields;
      }
    });
    this.subscriptions.push(fieldSubscription);

    // Subscribe to tab change requests
    const tabSubscription = subscribeToChannel((message) => {
      if (message.type === MESSAGE_TYPES.CHANGE_TAB) {
        this.handleTabChangeRequest(message.payload);
      }
    });
    this.subscriptions.push(tabSubscription);

    // Subscribe to duplicate group selection
    const groupSubscription = subscribeToChannel((message) => {
      if (message.type === MESSAGE_TYPES.DUPLICATE_GROUP_SELECTED) {
        this.handleGroupSelected(message.payload);
      }
    });
    this.subscriptions.push(groupSubscription);

    // Subscribe to duplicates found message
    const duplicatesFoundSubscription = subscribeToChannel((message) => {
      if (message.type === MESSAGE_TYPES.DUPLICATES_FOUND) {
        this.handleDuplicatesFound(message.payload);
      }
    });
    this.subscriptions.push(duplicatesFoundSubscription);

    // Subscribe to merge preview message
    const mergePreviewSubscription = subscribeToChannel((message) => {
      if (message.type === MESSAGE_TYPES.MERGE_PREVIEW) {
        this.handleMergePreview(message.payload);
      }
    });
    this.subscriptions.push(mergePreviewSubscription);

    // Subscribe to view change message
    const viewChangeSubscription = subscribeToChannel((message) => {
      if (message.type === MESSAGE_TYPES.VIEW_CHANGE) {
        this.handleViewChange(message.payload);
      }
    });
    this.subscriptions.push(viewChangeSubscription);

    // Subscribe to duplicates merged message
    const duplicatesMergedSubscription = subscribeToChannel((message) => {
      if (message.type === MESSAGE_TYPES.DUPLICATES_MERGED) {
        this.handleDuplicatesMerged(message.payload);
      }
    });
    this.subscriptions.push(duplicatesMergedSubscription);
  }

  // Unsubscribe from all messages
  unsubscribeFromMessages() {
    this.subscriptions.forEach((subscription) => {
      unsubscribeFromChannel(subscription);
    });
    this.subscriptions = [];
  }

  // Handle job completed event
  handleJobCompleted(payload) {
    if (payload && payload.success) {
      this.showToast(
        "Success",
        "Duplicate detection job completed successfully",
        "success"
      );
      this.refreshJobProgress();

      // Update the job ID
      if (payload.jobId) {
        this.jobId = payload.jobId;
      }

      // Navigate to duplicate groups tab
      this.activateTab("duplicate-groups");
    } else {
      this.showToast(
        "Error",
        "Duplicate detection job failed: " +
          (payload.errorMessage || "Unknown error"),
        "error"
      );
    }
  }

  // Handle tab change request
  handleTabChangeRequest(payload) {
    if (payload && payload.tabName) {
      this.activateTab(payload.tabName);
    }
  }

  // Handle group selection
  handleGroupSelected(payload) {
    if (payload) {
      this.selectedGroupId = payload.groupId;
    }
  }

  // Handle duplicates found event
  handleDuplicatesFound(payload) {
    if (payload && payload.recordIds && payload.recordIds.length > 0) {
      this.compareRecordIds = payload.recordIds;
      this.selectedGroupId = payload.groupId;
      this.hideCompareTab = false;
      this.activateTab("compare");
    }
  }

  // Handle merge preview event
  handleMergePreview(payload) {
    if (payload && payload.previewData) {
      this.masterRecordId = payload.request.masterId;
      this.hideMergePreviewTab = false;
      this.activateTab("preview");
    }
  }

  // Handle view change event
  handleViewChange(payload) {
    if (payload && payload.view) {
      switch (payload.view) {
        case "list":
          this.activateTab("duplication-groups");
          break;
        case "compare":
          if (!this.hideCompareTab) {
            this.activateTab("compare");
          }
          break;
        case "preview":
          if (!this.hideMergePreviewTab) {
            this.activateTab("preview");
          }
          break;
        default:
          // Use the requested view as tab name
          this.activateTab(payload.view);
      }
    }
  }

  // Handle duplicates merged event
  handleDuplicatesMerged(payload) {
    if (payload) {
      // Reset states after merge
      this.hideMergePreviewTab = true;

      // Navigate back to duplicate groups
      this.activateTab("duplication-groups");

      // Show success message
      this.showToast("Success", "Records merged successfully", "success");

      // Refresh duplicate groups component
      const groupsComponent = this.template.querySelector(
        "c-duplication-merge-groups"
      );
      if (groupsComponent) {
        groupsComponent.refreshGroups();
      }
    }
  }

  // Activate a specific tab
  activateTab(tabName) {
    this.currentTab = tabName;
    this.activeTab = tabName;

    // Find the tabset and activate the tab
    const tabset = this.template.querySelector("lightning-tabset");
    if (tabset) {
      // NOTE: This may need to be adjusted based on the structure of lightning-tabset
      // Some implementations may require additional handling
      const tabs = tabset.querySelectorAll("lightning-tab");
      if (tabs) {
        tabs.forEach((tab) => {
          if (
            tab.value === tabName ||
            tab.label.toLowerCase().replace(/\s+/g, "-") === tabName
          ) {
            tab.classList.add("slds-is-active");
          } else {
            tab.classList.remove("slds-is-active");
          }
        });
      }
    }
  }

  handleObjectTypeChange(event) {
    this.selectedObjectType = event.detail.value;
    this.selectedConfigId = null;

    // Reset comparison states
    this.hideCompareTab = true;
    this.hideMergePreviewTab = true;
    this.compareRecordIds = [];
    this.masterRecordId = null;

    // Notify child components via custom event
    this.dispatchEvent(
      new CustomEvent("objecttypechange", {
        detail: {
          objectType: this.selectedObjectType
        }
      })
    );

    // Also publish via LMS for other components
    sendMessage(MESSAGE_TYPES.OBJECT_TYPE_CHANGED, {
      objectType: this.selectedObjectType
    });
  }

  handleConfigSelect(event) {
    this.selectedConfigId = event.detail.configId;

    // Publish config selection via LMS
    sendMessage(MESSAGE_TYPES.CONFIG_SELECTED, {
      configId: this.selectedConfigId,
      objectType: this.selectedObjectType
    });
  }

  handleRunDuplicateDetection() {
    if (!this.selectedConfigId) {
      this.showToast("Error", "Please select a configuration first", "error");
      return;
    }

    const objectApiName = this.selectedObjectType;
    const fieldApiNames = this.selectedFields;
    const batchSize = 200;

    this.isLoading = true;

    // Notify that job is starting
    sendMessage(MESSAGE_TYPES.JOB_STARTING, {
      objectType: objectApiName,
      configId: this.selectedConfigId
    });

    runDuplicateDetection({
      objectApiName: objectApiName,
      fieldApiNames: fieldApiNames,
      batchSize: batchSize
    })
      .then((result) => {
        this.jobId = result;

        // Notify about job started with the jobId
        sendMessage(MESSAGE_TYPES.JOB_STARTED, {
          jobId: this.jobId,
          objectType: objectApiName,
          configId: this.selectedConfigId
        });

        // Navigate to job progress tab
        this.activateTab("dashboard");

        // Show toast notification
        this.showToast(
          "Success",
          "Duplicate detection job started successfully",
          "success"
        );
      })
      .catch((error) => {
        this.handleError(error);

        // Notify about job failure
        sendMessage(MESSAGE_TYPES.JOB_ERROR, {
          error: error.message || "Unknown error",
          objectType: objectApiName
        });
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  handleError(error) {
    // Error in duplicate process

    // Use the error handler utility
    const handledError = handleError(
      "duplicationTabbedInterface",
      "handleRunDuplicateDetection",
      error,
      {
        level: ERROR_LEVELS.ERROR,
        category: ERROR_CATEGORIES.OPERATION,
        notify: true
      }
    );

    // Show toast notification
    this.showToast("Error", handledError.message, "error");
  }

  refreshJobProgress() {
    const jobProgress = this.template.querySelector(
      "c-duplication-job-progress"
    );
    if (jobProgress) {
      jobProgress.refreshJobs();
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: title,
        message: message,
        variant: variant
      })
    );
  }

  get isRunButtonDisabled() {
    return !this.selectedConfigId || this.isLoading;
  }
}
