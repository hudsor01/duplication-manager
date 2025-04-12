import { LightningElement, api, track, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import runDuplicateDetection from "@salesforce/apex/DuplicateRecordJobController.runDuplicateDetection";
import { MessageContext } from "lightning/messageService";
import {
  sendMessage,
  subscribeToChannel,
  unsubscribeFromChannel,
  MESSAGE_TYPES,
} from "c/duplicationMessageService";

export default class DuplicationTabbedInterface extends LightningElement {
  @api recordId;
  @api tabsetName;
  @track selectedObjectType = "Account";
  @track selectedConfigId;
  @track isLoading = false;
  @track currentTab = "dashboard";
  @track jobId;
  @track selectedFields = [];

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
    { label: "Custom Objects", value: "Custom" },
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
        "success",
      );
      this.refreshJobProgress();
    } else {
      this.showToast(
        "Error",
        "Duplicate detection job failed: " +
          (payload.errorMessage || "Unknown error"),
        "error",
      );
    }
  }

  // Handle tab change request
  handleTabChangeRequest(payload) {
    if (payload && payload.tabName) {
      this.currentTab = payload.tabName;

      // Find and activate the correct tab
      const tabset = this.template.querySelector("lightning-tabset");
      if (tabset) {
        // Implementation depends on how the tabset is structured
        // May need to use custom events or imperative APIs
      }
    }
  }

  handleObjectTypeChange(event) {
    this.selectedObjectType = event.detail.value;
    this.selectedConfigId = null;

    // Notify child components via custom event
    this.dispatchEvent(
      new CustomEvent("objecttypechange", {
        detail: {
          objectType: this.selectedObjectType,
        },
      }),
    );

    // Also publish via LMS for other components
    sendMessage(MESSAGE_TYPES.OBJECT_TYPE_CHANGED, {
      objectType: this.selectedObjectType,
    });
  }

  handleConfigSelect(event) {
    this.selectedConfigId = event.detail.configId;

    // Publish config selection via LMS
    sendMessage(MESSAGE_TYPES.CONFIG_SELECTED, {
      configId: this.selectedConfigId,
      objectType: this.selectedObjectType,
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
      configId: this.selectedConfigId,
    });

    runDuplicateDetection({
      objectApiName: objectApiName,
      fieldApiNames: fieldApiNames,
      batchSize: batchSize,
    })
      .then((result) => {
        this.jobId = result;

        // Notify about job started with the jobId
        sendMessage(MESSAGE_TYPES.JOB_STARTED, {
          jobId: this.jobId,
          objectType: objectApiName,
          configId: this.selectedConfigId,
        });

        // Navigate to job progress tab
        this.currentTab = "progress";

        // Request tab change for other components
        sendMessage(MESSAGE_TYPES.CHANGE_TAB, {
          tabName: "progress",
        });
      })
      .catch((error) => {
        this.handleError(error);

        // Notify about job failure
        sendMessage(MESSAGE_TYPES.JOB_ERROR, {
          error: error.message || "Unknown error",
          objectType: objectApiName,
        });
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  handleError(error) {
    console.error("Error in duplication process:", error);
    let errorMessage = "Unknown error";

    if (typeof error === "string") {
      errorMessage = error;
    } else if (error.message) {
      errorMessage = error.message;
    } else if (error.body && error.body.message) {
      errorMessage = error.body.message;
    }

    this.showToast("Error", errorMessage, "error");
  }

  refreshJobProgress() {
    const jobProgress = this.template.querySelector(
      "c-duplication-job-progress",
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
        variant: variant,
      }),
    );
  }

  get isRunButtonDisabled() {
    return !this.selectedConfigId || this.isLoading;
  }
}
