import { LightningElement, api, track, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import mergeDuplicateRecords from "@salesforce/apex/DuplicateRecordController.mergeDuplicateRecords";
import { MessageContext } from "lightning/messageService";
import {
  sendMessage,
  subscribeToChannel,
  unsubscribeFromChannel,
  MESSAGE_TYPES,
} from "c/duplicationMessageService";

export default class DuplicationMergeGroups extends LightningElement {
  @api
  get groups() {
    return this._groupsValue || [];
  }
  set groups(value) {
    this._groupsValue = value;

    // Initialize each group with UI state if values are provided
    if (this._groupsValue && this._groupsValue.length > 0) {
      this._groupsValue = this._groupsValue.map((group) => {
        return {
          ...group,
          isExpanded: false,
          isSelected: false,
          isProcessing: false,
          isMerged: false,
          error: null,
        };
      });
    }
  }

  @api
  get objectApiName() {
    return this._objectApiNameValue;
  }
  set objectApiName(value) {
    this._objectApiNameValue = value;
  }

  @api
  get recordId() {
    return this._recordIdValue;
  }
  set recordId(value) {
    this._recordIdValue = value;
  }

  @api
  get configId() {
    return this._configIdValue;
  }
  set configId(value) {
    this._configIdValue = value;
  }
  @api batchJobId;
  @track isLoading = false;
  @track error;
  @track selectedGroupIds = [];
  @track showComparisonModal = false;
  @track groupForComparison;

  // Store subscriptions
  subscriptions = [];

  // Get message context for LMS
  @wire(MessageContext)
  messageContext;

  // UI States
  @track isMerging = false;
  @track mergeResult;

  /**
   * Get the groups that are selected
   */
  get selectedGroups() {
    return this.groups.filter((group) =>
      this.selectedGroupIds.includes(group.id),
    );
  }

  /**
   * Check if any groups are selected
   */
  get hasSelection() {
    return this.selectedGroupIds.length > 0;
  }

  /**
   * Check if there are any groups available
   */
  get hasGroups() {
    return this.groups && this.groups.length > 0;
  }

  /**
   * Initialize the component
   */
  connectedCallback() {
    // Subscribe to messages
    this.subscribeToMessages();
  }

  /**
   * Clean up when component is disconnected
   */
  disconnectedCallback() {
    // Unsubscribe from all messages
    this.unsubscribeFromMessages();
  }

  /**
   * Subscribe to LMS messages
   */
  subscribeToMessages() {
    // Subscribe to config selection changes
    const configSubscription = subscribeToChannel((message) => {
      if (message.type === MESSAGE_TYPES.CONFIG_SELECTED) {
        // Update configId when configuration is changed
        if (this.configId !== message.payload.configId) {
          this._configIdValue = message.payload.configId;
          this.loadGroups();
        }
      }
    });
    this.subscriptions.push(configSubscription);

    // Subscribe to object type changes
    const objectTypeSubscription = subscribeToChannel((message) => {
      if (message.type === MESSAGE_TYPES.OBJECT_TYPE_CHANGED) {
        // Update objectApiName when object type is changed
        if (this.objectApiName !== message.payload.objectType) {
          this._objectApiNameValue = message.payload.objectType;
          this.resetGroups();
        }
      }
    });
    this.subscriptions.push(objectTypeSubscription);

    // Subscribe to merge operation requests
    const mergeRequestSubscription = subscribeToChannel((message) => {
      if (message.type === MESSAGE_TYPES.MERGE_GROUP_REQUEST) {
        // Handle merge request from another component
        const groupId = message.payload.groupId;
        if (groupId) {
          this.handleMergeGroupRequest(groupId);
        }
      }
    });
    this.subscriptions.push(mergeRequestSubscription);
  }

  /**
   * Unsubscribe from all messages
   */
  unsubscribeFromMessages() {
    this.subscriptions.forEach((subscription) => {
      unsubscribeFromChannel(subscription);
    });
    this.subscriptions = [];
  }

  /**
   * Reset groups when object type changes
   */
  resetGroups() {
    this._groupsValue = [];
    this.selectedGroupIds = [];
    this.error = null;
  }

  /**
   * Load groups for the current configuration
   */
  loadGroups() {
    // Implementation would depend on how groups are fetched
    // This could call an Apex method or dispatch an event
    this.isLoading = true;

    // Notify that we're loading groups
    sendMessage(MESSAGE_TYPES.GROUPS_LOADING, {
      objectType: this.objectApiName,
      configId: this.configId,
    });

    // Use Promise-based approach for delay instead of setTimeout
    // This would be replaced with actual group loading logic
    this.simulateDelay(1000).then(() => {
      this.isLoading = false;

      // Notify that groups are loaded
      sendMessage(MESSAGE_TYPES.GROUPS_LOADED, {
        objectType: this.objectApiName,
        configId: this.configId,
        groupCount: this.groups ? this.groups.length : 0,
      });
    });
  }

  /**
   * Handle merge request from LMS
   */
  handleMergeGroupRequest(groupId) {
    const group = this.groups.find((g) => g.id === groupId);
    if (group && !group.isExcluded) {
      this.mergeGroup(group);
    }
  }

  /**
   * Handler for group selection
   */
  handleGroupSelection(event) {
    const groupId = event.target.dataset.groupId;
    const isChecked = event.target.checked;

    if (isChecked) {
      if (!this.selectedGroupIds.includes(groupId)) {
        this.selectedGroupIds = [...this.selectedGroupIds, groupId];
      }
    } else {
      this.selectedGroupIds = this.selectedGroupIds.filter(
        (id) => id !== groupId,
      );
    }

    // Update group isSelected state
    this._groupsValue = this.groups.map((group) => {
      if (group.id === groupId) {
        return { ...group, isSelected: isChecked };
      }
      return group;
    });
  }

  /**
   * Toggle group expansion
   */
  toggleGroupExpansion(event) {
    const groupId = event.currentTarget.dataset.groupId;

    this._groupsValue = this.groups.map((group) => {
      if (group.id === groupId) {
        return { ...group, isExpanded: !group.isExpanded };
      }
      return group;
    });
  }

  /**
   * Merge selected groups
   */
  mergeSelectedGroups() {
    if (!this.hasSelection) {
      this.showToast(
        "Error",
        "Please select at least one group to merge",
        "error",
      );
      return;
    }

    this.isMerging = true;

    // Notify that bulk merge operation is starting
    sendMessage(MESSAGE_TYPES.BULK_MERGE_STARTING, {
      objectType: this.objectApiName,
      configId: this.configId,
      groupCount: this.selectedGroups.length,
    });

    // Process each selected group sequentially
    this.processNextGroup(0);
  }

  /**
   * Process the next group in the queue
   */
  processNextGroup(index) {
    if (index >= this.selectedGroups.length) {
      // All groups processed
      this.isMerging = false;
      this.showToast("Success", "Merge operation completed", "success");

      // Notify that bulk merge operation is complete
      sendMessage(MESSAGE_TYPES.BULK_MERGE_COMPLETED, {
        objectType: this.objectApiName,
        configId: this.configId,
        groupsProcessed: this.selectedGroups.length,
        success: true,
      });

      return;
    }

    const group = this.selectedGroups[index];

    // Mark group as processing
    this.setGroupProcessingState(group.id, true);

    // Notify that group merge is starting
    sendMessage(MESSAGE_TYPES.GROUP_MERGE_STARTING, {
      groupId: group.id,
      objectType: this.objectApiName,
      recordCount: group.recordCount,
      masterRecordId: group.masterRecordId,
    });

    // Process the group
    this.mergeGroup(group)
      .then((result) => {
        // Mark as merged successfully
        this.setGroupMergedState(group.id, true);

        // Notify that group merge is complete
        sendMessage(MESSAGE_TYPES.GROUP_MERGE_COMPLETED, {
          groupId: group.id,
          objectType: this.objectApiName,
          masterRecordId: group.masterRecordId,
          success: true,
          result: result,
        });

        // Process next group
        this.processNextGroup(index + 1);
      })
      .catch((error) => {
        // Set error state
        const errorMessage = error.message || "An error occurred during merge";
        this.setGroupErrorState(group.id, errorMessage);

        // Notify that group merge failed
        sendMessage(MESSAGE_TYPES.GROUP_MERGE_ERROR, {
          groupId: group.id,
          objectType: this.objectApiName,
          masterRecordId: group.masterRecordId,
          error: errorMessage,
        });

        // Process next group
        this.processNextGroup(index + 1);
      });
  }

  /**
   * Merge a single group
   */
  mergeGroup(group) {
    // Generate a correlation ID for this merge operation
    const correlationId = this.generateUuid();

    // Send message with correlation ID before merge starts
    sendMessage(
      MESSAGE_TYPES.MERGE_OPERATION,
      {
        groupId: group.id,
        objectType: this.objectApiName,
        masterRecordId: group.masterRecordId,
        recordIds: group.duplicateRecordIds,
        status: "starting",
      },
      {
        correlationId: correlationId,
      },
    );

    return mergeDuplicateRecords({
      masterRecordId: group.masterRecordId,
      duplicateRecordIds: group.duplicateRecordIds,
      objectApiName: this.objectApiName,
    })
      .then((result) => {
        // Send success message with same correlation ID
        sendMessage(
          MESSAGE_TYPES.MERGE_OPERATION,
          {
            groupId: group.id,
            objectType: this.objectApiName,
            masterRecordId: group.masterRecordId,
            recordIds: group.duplicateRecordIds,
            status: "completed",
            result: result,
          },
          {
            correlationId: correlationId,
          },
        );

        return result;
      })
      .catch((error) => {
        // Send error message with same correlation ID
        sendMessage(
          MESSAGE_TYPES.MERGE_OPERATION,
          {
            groupId: group.id,
            objectType: this.objectApiName,
            masterRecordId: group.masterRecordId,
            recordIds: group.duplicateRecordIds,
            status: "error",
            error: error.message || "Unknown error",
          },
          {
            correlationId: correlationId,
          },
        );

        throw error;
      });
  }

  /**
   * Generate a UUID for correlation IDs
   */
  generateUuid() {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(
      /[xy]/g,
      function (c) {
        var r = (Math.random() * 16) | 0,
          v = c === "x" ? r : (r & 0x3) | 0x8;
        return v.toString(16);
      },
    );
  }

  /**
   * Set processing state for a group
   */
  setGroupProcessingState(groupId, isProcessing) {
    this._groupsValue = this.groups.map((group) => {
      if (group.id === groupId) {
        return { ...group, isProcessing };
      }
      return group;
    });
  }

  /**
   * Set merged state for a group
   */
  setGroupMergedState(groupId, isMerged) {
    this._groupsValue = this.groups.map((group) => {
      if (group.id === groupId) {
        return { ...group, isMerged, error: null };
      }
      return group;
    });
  }

  /**
   * Set error state for a group
   */
  setGroupErrorState(groupId, errorMessage) {
    this._groupsValue = this.groups.map((group) => {
      if (group.id === groupId) {
        return { ...group, error: errorMessage };
      }
      return group;
    });
  }

  /**
   * Open comparison modal for a group
   */
  openComparisonModal(event) {
    const groupId = event.currentTarget.dataset.groupId;
    const group = this.groups.find((g) => g.id === groupId);

    if (group) {
      this.groupForComparison = { ...group };
      this.showComparisonModal = true;

      // Notify about modal opening via LMS
      sendMessage(MESSAGE_TYPES.COMPARISON_MODAL_OPENED, {
        groupId: groupId,
        objectType: this.objectApiName,
      });
    }
  }

  /**
   * Close comparison modal
   */
  closeComparisonModal() {
    this.showComparisonModal = false;

    // Notify about modal closing via LMS
    if (this.groupForComparison) {
      sendMessage(MESSAGE_TYPES.COMPARISON_MODAL_CLOSED, {
        groupId: this.groupForComparison.id,
        objectType: this.objectApiName,
      });
    }

    this.groupForComparison = null;
  }

  /**
   * Open master preview modal
   */
  openMasterPreviewModal(event) {
    const groupId = event.currentTarget.dataset.groupId;
    const group = this.groups.find((g) => g.id === groupId);

    if (group) {
      this.groupForComparison = { ...group };
      this.showMasterPreviewModal = true;

      // Notify about modal opening via LMS
      sendMessage(MESSAGE_TYPES.MASTER_PREVIEW_MODAL_OPENED, {
        groupId: groupId,
        objectType: this.objectApiName,
        masterRecordId: group.masterRecordId,
      });
    }
  }

  /**
   * Close master preview modal
   */
  closeMasterPreviewModal() {
    this.showMasterPreviewModal = false;

    // Notify about modal closing via LMS
    if (this.groupForComparison) {
      sendMessage(MESSAGE_TYPES.MASTER_PREVIEW_MODAL_CLOSED, {
        groupId: this.groupForComparison.id,
        objectType: this.objectApiName,
      });
    }

    this.groupForComparison = null;
  }

  /**
   * Open note preview modal
   */
  openNotePreviewModal(event) {
    const groupId = event.currentTarget.dataset.groupId;
    const group = this.groups.find((g) => g.id === groupId);

    if (group) {
      this.groupForComparison = { ...group };
      this.showNotePreviewModal = true;

      // Generate note preview content here or fetch from server
      this.notePreviewContent = this.generateNotePreview(group);

      // Notify about modal opening via LMS
      sendMessage(MESSAGE_TYPES.NOTE_PREVIEW_MODAL_OPENED, {
        groupId: groupId,
        objectType: this.objectApiName,
      });
    }
  }

  /**
   * Close note preview modal
   */
  closeNotePreviewModal() {
    this.showNotePreviewModal = false;

    // Notify about modal closing via LMS
    if (this.groupForComparison) {
      sendMessage(MESSAGE_TYPES.NOTE_PREVIEW_MODAL_CLOSED, {
        groupId: this.groupForComparison.id,
        objectType: this.objectApiName,
      });
    }

    this.groupForComparison = null;
  }

  /**
   * Generate note preview content for a group
   */
  generateNotePreview(group) {
    // Simple implementation for now
    return `<p><strong>Merge Note</strong></p>
                <p>The following records were merged:</p>
                <ul>
                    <li>Master Record: ${group.masterRecordId}</li>
                    <li>Duplicate Records: ${group.duplicateRecordIds.join(", ")}</li>
                </ul>
                <p>Object Type: ${group.objectName}</p>
                <p>Match Score: ${group.matchScore}%</p>`;
  }

  /**
   * Simulate a delay using Promises instead of setTimeout
   * @param {Number} ms - Number of milliseconds to delay
   * @returns {Promise} A promise that resolves after the specified delay
   */
  simulateDelay(ms) {
    const startTime = Date.now();

    return new Promise((resolve) => {
      // Function to check if enough time has elapsed
      const checkElapsed = () => {
        const elapsed = Date.now() - startTime;
        if (elapsed >= ms) {
          resolve();
        } else {
          // Not enough time has passed, check again in the next microtask
          Promise.resolve().then(checkElapsed);
        }
      };

      // Start checking
      Promise.resolve().then(checkElapsed);
    });
  }

  /**
   * Show toast notification
   */
  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant,
      }),
    );

    // Also send toast message via LMS for components that might need to know
    sendMessage(MESSAGE_TYPES.TOAST_NOTIFICATION, {
      title,
      message,
      variant,
    });
  }
}
