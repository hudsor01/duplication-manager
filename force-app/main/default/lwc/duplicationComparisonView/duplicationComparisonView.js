import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { formatFieldName } from "c/duplicationEnhancedUI";
import {
  subscribeToChannel,
  unsubscribeFromChannel,
  sendMessage,
  MESSAGE_TYPES,
} from "c/duplicationMessageService";
import {
  handleError,
  ERROR_LEVELS,
  ERROR_CATEGORIES,
} from "c/duplicationErrorHandler";

import getRecordsForComparison from "@salesforce/apex/DRCCompare.getRecordsForComparison";
import getFieldsForObject from "@salesforce/apex/DRCFields.getFieldsForObject";
import previewMergeResults from "@salesforce/apex/DMUPreview.previewMergeResults";

export default class DuplicationComparisonView extends LightningElement {
  // API properties
  @api recordIds;
  @api objectApiName;
  @api groupId;

  // Private backing storage for when we need to work with updated values
  _recordIdsValue;
  _objectApiNameValue;
  _groupIdValue;

  @track masterRecordId;
  @track duplicateRecords = [];
  @track fieldGroups = [];
  @track fieldSelections = {};
  @track isLoading = true;
  @track error;

  subscription;

  connectedCallback() {
    // Subscribe to channel messages
    this.subscription = subscribeToChannel(this.handleMessage.bind(this));

    // Load records if IDs are provided
    if (this.recordIds && this.recordIds.length > 0) {
      this.loadRecordsForComparison();
    } else {
      this.isLoading = false;
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
    if (message.type === MESSAGE_TYPES.DUPLICATES_FOUND && message.payload) {
      // Handle updates when record IDs are provided
      if (message.payload.recordIds && message.payload.recordIds.length > 0) {
        // Create new component with updated properties using custom event
        this.dispatchEvent(
          new CustomEvent("recordsupdate", {
            detail: {
              recordIds: message.payload.recordIds,
              objectApiName: message.payload.objectApiName,
              groupId: message.payload.groupId,
            },
          }),
        );

        // Use local variables instead of reassigning @api properties
        const newRecordIds = message.payload.recordIds;
        const newObjectApiName = message.payload.objectApiName;
        const newGroupId = message.payload.groupId;

        // Load records with these values
        this.loadRecordsForComparison(
          newRecordIds,
          newObjectApiName,
          newGroupId,
        );
      }
    }
  }

  /**
   * Load records for comparison
   * @param {Array} recordIdsParam - Optional record IDs to use instead of the component property
   * @param {String} objectApiNameParam - Optional object API name to use instead of the component property
   * @param {String} groupIdParam - Optional group ID to use instead of the component property
   */
  loadRecordsForComparison(recordIdsParam, objectApiNameParam, groupIdParam) {
    this.isLoading = true;
    this.error = null;

    // Use provided parameters or fall back to component properties
    const recordIdsToUse = recordIdsParam || this.recordIds;
    const objectApiNameToUse = objectApiNameParam || this.objectApiName;
    // We'll store the groupId for later use
    if (groupIdParam) {
      this._groupIdValue = groupIdParam;
    }

    // Get records
    getRecordsForComparison({
      recordIds: recordIdsToUse,
      objectApiName: objectApiNameToUse,
    })
      .then((result) => {
        if (result && result.records) {
          // Process records
          this.processRecords(result.records);

          // Get fields for comparison
          return getFieldsForObject({ objectApiName: objectApiNameToUse });
        }
        throw new Error("No records returned for comparison");
      })
      .then((fieldResult) => {
        if (fieldResult && fieldResult.fieldGroups) {
          // Process fields
          this.processFields(fieldResult.fieldGroups);
        }
        this.isLoading = false;
      })
      .catch((error) => {
        this.handleLoadError(error);
      });
  }

  /**
   * Process records for comparison
   */
  processRecords(records) {
    if (!records || records.length === 0) {
      return;
    }

    // Set master record to the first one by default
    this.masterRecordId = records[0].Id;

    // Process duplicate records
    this.duplicateRecords = records
      .filter((record) => record.Id !== this.masterRecordId)
      .map((record) => {
        return {
          id: record.Id,
          name: record.Name || record.Id,
          record: record,
          matchScore: record.MatchScore__c
            ? `${Math.round(record.MatchScore__c * 100)}%`
            : "N/A",
        };
      });
  }

  /**
   * Process fields for comparison
   */
  processFields(fieldGroups) {
    if (!fieldGroups || fieldGroups.length === 0 || !this.duplicateRecords) {
      return;
    }

    // Get master record
    const masterRecord = this.recordIds.includes(this.masterRecordId)
      ? this.duplicateRecords.find((r) => r.id === this.masterRecordId)?.record
      : null;

    if (!masterRecord) {
      return;
    }

    // Process field groups
    this.fieldGroups = fieldGroups
      .map((group) => {
        const processedGroup = {
          label: group.label,
          fields: [],
        };

        // Process fields in the group
        if (group.fields && group.fields.length > 0) {
          processedGroup.fields = group.fields
            .map((field) => {
              const apiName = field.apiName;
              const label = field.label || formatFieldName(apiName);
              const masterValue = this.formatFieldValue(masterRecord[apiName]);

              // Process duplicate values
              const duplicateValues = this.duplicateRecords.map((dupRecord) => {
                const value = this.formatFieldValue(dupRecord.record[apiName]);
                const isDifferent =
                  value !== masterValue && value !== null && value !== "";

                return {
                  id: dupRecord.id,
                  value: value,
                  isDifferent: isDifferent,
                  isSelected: this.fieldSelections[apiName] === dupRecord.id,
                  class: isDifferent ? "field-different" : "",
                };
              });

              // Determine if field has differences
              const hasDifferences = duplicateValues.some(
                (dv) => dv.isDifferent,
              );

              return {
                apiName: apiName,
                label: label,
                masterValue: masterValue,
                masterClass: hasDifferences ? "field-master" : "",
                duplicateValues: duplicateValues,
                hasDifferences: hasDifferences,
              };
            })
            .filter((field) => field.hasDifferences || this.showAllFields);
        }

        return processedGroup;
      })
      .filter((group) => group.fields.length > 0);
  }

  /**
   * Format field value for display
   */
  formatFieldValue(value) {
    if (value === undefined || value === null) {
      return "";
    }

    if (typeof value === "boolean") {
      return value ? "Yes" : "No";
    }

    return String(value);
  }

  /**
   * Handle error in loading data
   */
  handleLoadError(error) {
    this.isLoading = false;

    // Use error handler utility
    this.error = handleError(
      "duplicationComparisonView",
      "loadRecordsForComparison",
      error,
      {
        level: ERROR_LEVELS.ERROR,
        category: ERROR_CATEGORIES.DATA,
        notify: true,
      },
    );

    // Show toast message
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Error Loading Records",
        message: this.error.message,
        variant: "error",
      }),
    );
  }

  /**
   * Handle setting record as master
   */
  handleSetAsMaster(event) {
    const recordId = event.currentTarget.dataset.id;

    if (recordId && recordId !== this.masterRecordId) {
      // Update master record
      this.masterRecordId = recordId;

      // Reset field selections
      this.fieldSelections = {};

      // Refresh view
      this.loadRecordsForComparison();
    }
  }

  /**
   * Handle selecting a value for a field
   */
  handleSelectValue(event) {
    const fieldName = event.currentTarget.dataset.field;
    const recordId = event.currentTarget.dataset.record;

    if (fieldName && recordId) {
      // Update field selection
      this.fieldSelections[fieldName] = recordId;

      // Refresh field groups
      this.processFields(this.fieldGroups);
    }
  }

  /**
   * Handle cancel button click
   */
  handleCancel() {
    // Send cancel message
    sendMessage(MESSAGE_TYPES.VIEW_CHANGE, { view: "list" });

    // Dispatch cancel event
    this.dispatchEvent(new CustomEvent("cancel"));
  }

  /**
   * Handle preview merge button click
   */
  handlePreviewMerge() {
    this.isLoading = true;

    // Create merge preview request
    const previewRequest = {
      masterId: this.masterRecordId,
      duplicateIds: this.duplicateRecords.map((record) => record.id),
      objectApiName: this.objectApiName,
      fieldSelections: this.fieldSelections,
    };

    // Call Apex to preview merge
    previewMergeResults(previewRequest)
      .then((result) => {
        // Send preview message
        sendMessage(MESSAGE_TYPES.MERGE_PREVIEW, {
          previewData: result,
          request: previewRequest,
          groupId: this.groupId,
        });

        // Dispatch preview event
        this.dispatchEvent(
          new CustomEvent("preview", {
            detail: {
              previewData: result,
              request: previewRequest,
            },
          }),
        );

        this.isLoading = false;
      })
      .catch((error) => {
        // Handle error
        this.isLoading = false;

        // Use error handler utility
        const handledError = handleError(
          "duplicationComparisonView",
          "previewMergeResults",
          error,
          {
            level: ERROR_LEVELS.ERROR,
            category: ERROR_CATEGORIES.DATA,
            notify: true,
          },
        );

        // Show toast message
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Error Previewing Merge",
            message: handledError.message,
            variant: "error",
          }),
        );
      });
  }

  /**
   * Check if records are available for comparison
   */
  get hasRecords() {
    return (
      this.recordIds &&
      this.recordIds.length > 0 &&
      this.duplicateRecords.length > 0
    );
  }

  /**
   * Whether to show all fields or only fields with differences
   */
  get showAllFields() {
    return false; // Could be made configurable
  }
}
