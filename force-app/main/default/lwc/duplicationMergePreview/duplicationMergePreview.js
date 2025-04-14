import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import {
  subscribeToChannel,
  unsubscribeFromChannel,
  sendMessage
} from "c/duplicationMessageService";
import { MESSAGE_TYPES } from "c/duplicationConstants";
import {
  handleError,
  ERROR_LEVELS,
  ERROR_CATEGORIES
} from "c/duplicationErrorService";
import mergeDuplicateRecords from "@salesforce/apex/DuplicateRecordController.mergeDuplicateRecords";
import createNote from "@salesforce/apex/DRCNote.createNote";

export default class DuplicationMergePreview extends LightningElement {
  @api recordId;

  @track previewData = null;
  @track mergeRequest = null;
  @track showConflictsTab = false;
  @track showNonMergeableTab = false;
  @track activeTab = "preview";
  @track isLoading = false;
  @track error = null;

  subscription;

  connectedCallback() {
    // Subscribe to channel messages
    this.subscription = subscribeToChannel(this.handleMessage.bind(this));
  }

  disconnectedCallback() {
    // Unsubscribe from channel
    if (this.subscription) {
      unsubscribeFromChannel(this.subscription);
    }
  }

  /**
   * Handle messages from LMS channel
   */
  handleMessage(message) {
    if (message.type === MESSAGE_TYPES.MERGE_PREVIEW && message.payload) {
      // Set preview data
      this.previewData = message.payload.previewData;
      this.mergeRequest = message.payload.request;

      // Check if there are conflicts or non-mergeable data
      this.showConflictsTab =
        this.previewData.conflicts && this.previewData.conflicts.length > 0;
      this.showNonMergeableTab =
        this.previewData.nonMergeableData &&
        this.previewData.nonMergeableData.length > 0;

      // Set active tab
      this.activeTab = "preview";
    }
  }

  /**
   * Handle tab switch
   */
  handleTabChange(event) {
    this.activeTab = event.target.value;
  }

  /**
   * Handle confirm merge button click
   */
  handleConfirmMerge() {
    if (!this.mergeRequest) {
      this.showToast("Error", "No merge request data available", "error");
      return;
    }

    this.isLoading = true;
    this.error = null;

    // Execute merge with Apex
    mergeDuplicateRecords({
      masterRecordId: this.mergeRequest.masterId,
      duplicateRecordIds: this.mergeRequest.duplicateIds,
      objectApiName: this.mergeRequest.objectApiName
    })
      .then((result) => {
        if (result.success) {
          // Create note with preserved data if needed
          if (
            this.previewData.nonMergeableData &&
            this.previewData.nonMergeableData.length > 0
          ) {
            return this.createNoteWithPreservedData();
          }
          return { success: true };
        }
        throw new Error(
          "Merge operation failed: " +
            (result.errors ? result.errors.join(", ") : "Unknown error")
        );
      })
      .then(() => {
        // Show success message
        this.showToast("Success", "Records merged successfully", "success");

        // Notify about completion
        sendMessage(MESSAGE_TYPES.DUPLICATES_MERGED, {
          masterId: this.mergeRequest.masterId,
          mergedIds: this.mergeRequest.duplicateIds,
          objectApiName: this.mergeRequest.objectApiName
        });

        // Reset state
        this.previewData = null;
        this.mergeRequest = null;
      })
      .catch((error) => {
        // Handle error
        this.error = handleError(
          "duplicateMergePreview",
          "confirmMerge",
          error,
          {
            level: ERROR_LEVELS.ERROR,
            category: ERROR_CATEGORIES.DATA,
            notify: true
          }
        );

        // Show error toast
        this.showToast("Error", this.error.message, "error");
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  /**
   * Create note with preserved data
   */
  createNoteWithPreservedData() {
    // Format preserved data for note contents
    const noteTitle =
      "Data preserved from merged records - " + new Date().toLocaleString();

    // Generate note body with formatted content of non-mergeable data
    let noteBody =
      "The following data could not be automatically merged and has been preserved in this note:\n\n";

    // Add any conflicting data that was not chosen for the master record
    if (this.previewData.conflicts && this.previewData.conflicts.length > 0) {
      noteBody += "== CONFLICTING VALUES ==\n";
      this.previewData.conflicts.forEach((conflict) => {
        noteBody += `${conflict.fieldLabel}: ${conflict.dupValue} (from duplicate record)\n`;
      });
      noteBody += "\n";
    }

    // Add non-mergeable data (like related records, etc.)
    if (
      this.previewData.nonMergeableData &&
      this.previewData.nonMergeableData.length > 0
    ) {
      noteBody += "== NON-MERGEABLE DATA ==\n";
      this.previewData.nonMergeableData.forEach((data) => {
        noteBody += `${data.fieldLabel}: ${data.value}\n`;
      });
    }

    // If there's a custom note content provided, use it instead
    const finalNoteBody = this.previewData.noteContents || noteBody;

    return createNote({
      parentId: this.mergeRequest.masterId,
      title: noteTitle,
      body: finalNoteBody
    });
  }

  /**
   * Handle cancel button click
   */
  handleCancel() {
    // Reset state
    this.previewData = null;
    this.mergeRequest = null;

    // Notify about cancellation
    sendMessage(MESSAGE_TYPES.VIEW_CHANGE, { view: "list" });
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
   * Get class for tab
   */
  getTabClass(tabName) {
    return this.activeTab === tabName
      ? "slds-tabs_default__item slds-is-active"
      : "slds-tabs_default__item";
  }

  /**
   * Get aria-selected for tab
   */
  getTabSelected(tabName) {
    return this.activeTab === tabName;
  }

  /**
   * Get content class for tab
   */
  getContentClass(tabName) {
    return this.activeTab === tabName
      ? "slds-tabs_default__content slds-show"
      : "slds-tabs_default__content slds-hide";
  }

  /**
   * Tab class getters for specific tabs
   */
  get tabClassPreview() {
    return this.getTabClass("preview");
  }

  get tabClassConflicts() {
    return this.getTabClass("conflicts");
  }

  get tabClassNonMergeable() {
    return this.getTabClass("non-mergeable");
  }

  /**
   * Tab selection getters for specific tabs
   */
  get tabSelectedPreview() {
    return this.getTabSelected("preview");
  }

  get tabSelectedConflicts() {
    return this.getTabSelected("conflicts");
  }

  get tabSelectedNonMergeable() {
    return this.getTabSelected("non-mergeable");
  }

  /**
   * Content class getters for specific tabs
   */
  get contentClassPreview() {
    return this.getContentClass("preview");
  }

  get contentClassConflicts() {
    return this.getContentClass("conflicts");
  }

  get contentClassNonMergeable() {
    return this.getContentClass("non-mergeable");
  }

  /**
   * Get field list for display
   */
  get fieldList() {
    return this.previewData && this.previewData.fieldData
      ? this.previewData.fieldData.filter(
          (field) => field.value !== null && field.value !== ""
        )
      : [];
  }

  /**
   * Get conflicts for display
   */
  get conflicts() {
    return this.previewData && this.previewData.conflicts
      ? this.previewData.conflicts
      : [];
  }

  /**
   * Get non-mergeable data for display
   */
  get nonMergeableData() {
    return this.previewData && this.previewData.nonMergeableData
      ? this.previewData.nonMergeableData
      : [];
  }

  /**
   * Get note contents for display
   */
  get noteContents() {
    if (!this.previewData) return "";

    // If custom note contents already provided, use those
    if (this.previewData.noteContents) {
      return this.previewData.noteContents;
    }

    // Otherwise generate preview of what will be added to the note
    let notePreview = "";

    // Add any conflicting data that was not chosen for the master record
    if (this.previewData.conflicts && this.previewData.conflicts.length > 0) {
      notePreview += "== CONFLICTING VALUES ==\n";
      this.previewData.conflicts.forEach((conflict) => {
        notePreview += `${conflict.fieldLabel}: ${conflict.dupValue} (from duplicate record)\n`;
      });
      notePreview += "\n";
    }

    // Add non-mergeable data (like related records, etc.)
    if (
      this.previewData.nonMergeableData &&
      this.previewData.nonMergeableData.length > 0
    ) {
      notePreview += "== NON-MERGEABLE DATA ==\n";
      this.previewData.nonMergeableData.forEach((data) => {
        notePreview += `${data.fieldLabel}: ${data.value}\n`;
      });
    }

    return notePreview;
  }
}
