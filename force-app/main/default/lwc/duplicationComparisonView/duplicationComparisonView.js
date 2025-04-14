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
  ERROR_CATEGORIES,
} from "c/duplicationErrorService";

import getRecordsForComparison from "@salesforce/apex/DuplicateRecordController.getRecordsForComparison";
import getFieldsForObject from "@salesforce/apex/DuplicateRecordController.getFieldsForObject";
import previewMergeResults from "@salesforce/apex/DMUPreview.previewMergeResults";
// Removed getMergeableFields since it doesn't exist

/**
 * Unified comparison component for comparing and selecting fields to merge
 * between duplicate records. Handles all aspects of the record comparison workflow
 * including field selection, setting master record, and preview generation.
 *
 * @author Richard Hudson
 * @since 2025-04-13
 */
export default class DuplicationComparisonView extends LightningElement {
  // API properties
  @api recordIds;
  @api objectApiName;
  @api groupId;
  @api showAllFields = false;

  // Tracking properties
  @track masterRecordId;
  @track duplicateRecords = [];
  @track fieldGroups = [];
  @track fieldSelections = {};
  @track isLoading = true;
  @track error;
  @track viewMode = "comparison"; // comparison, details, preview
  @track nonMergeableData = [];
  @track selectedFields = [];
  @track recordsById = {};

  // Private backing properties
  _recordIdsValue;
  _objectApiNameValue;
  _groupIdValue;
  _fieldDefinitions = {};

  // Messaging subscription
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
   * Handle messages from the message service
   */
  handleMessage(message) {
    if (message.type === MESSAGE_TYPES.DUPLICATES_FOUND && message.payload) {
      // Handle updates when record IDs are provided
      if (message.payload.recordIds && message.payload.recordIds.length > 0) {
        // Dispatch event for any parent components
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
    } else if (message.type === MESSAGE_TYPES.VIEW_CHANGE && message.payload) {
      // Handle view change requests
      if (message.payload.view === "list") {
        this.handleCancel();
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

    // Store values in backing properties
    this._recordIdsValue = recordIdsToUse;
    this._objectApiNameValue = objectApiNameToUse;
    if (groupIdParam) {
      this._groupIdValue = groupIdParam;
    }

    // Execute all data loading in parallel for performance
    Promise.all([
      // Get records for comparison
      getRecordsForComparison({
        recordIds: recordIdsToUse,
        objectApiName: objectApiNameToUse,
      }),

      // Get fields for comparison
      getFieldsForObject({
        objectApiName: objectApiNameToUse
      })
    ])
      .then(([recordResult, fieldResult]) => {
        // Process records
        if (recordResult && recordResult.records) {
          this.processRecords(recordResult.records);
        } else {
          throw new Error("No records returned for comparison");
        }

        // Process fields
        if (fieldResult && fieldResult.fieldGroups) {
          this._fieldDefinitions = fieldResult.fields || {};
          this.processFields(fieldResult.fieldGroups);
        }

        // Initialize non-mergeable field data
        this.initNonMergeableFieldData();

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

    // Create a map of records by ID for easy access
    this.recordsById = {};
    records.forEach(record => {
      this.recordsById[record.Id] = record;
    });

    // Set master record to the first one with highest match score by default
    // or use the previously selected master record if it's still in the list
    if (!this.masterRecordId || !records.find(r => r.Id === this.masterRecordId)) {
      // Find record with highest match score
      const sortedRecords = [...records].sort((a, b) => {
        const scoreA = a.MatchScore__c || 0;
        const scoreB = b.MatchScore__c || 0;
        return scoreB - scoreA;
      });

      this.masterRecordId = sortedRecords[0].Id;
    }

    // Process duplicate records (all records except master)
    this.duplicateRecords = records
      .filter((record) => record.Id !== this.masterRecordId)
      .map((record) => {
        return {
          id: record.Id,
          name: this.getRecordName(record),
          record: record,
          matchScore: record.MatchScore__c
            ? `${Math.round(record.MatchScore__c * 100)}%`
            : "N/A",
          rawScore: record.MatchScore__c || 0
        };
      });

    // Sort by match score
    this.duplicateRecords.sort((a, b) => b.rawScore - a.rawScore);
  }

  /**
   * Process fields for comparison
   */
  processFields(fieldGroups) {
    if (!fieldGroups || fieldGroups.length === 0 || !this.masterRecordId) {
      return;
    }

    // Get master record
    const masterRecord = this.recordsById[this.masterRecordId];
    if (!masterRecord) {
      return;
    }

    // Process field groups
    this.fieldGroups = fieldGroups
      .map((group) => {
        const processedGroup = {
          label: group.label,
          fields: [],
          hasExpandedFields: false
        };

        // Process fields in the group
        if (group.fields && group.fields.length > 0) {
          processedGroup.fields = group.fields
            .map((field) => {
              const apiName = field.apiName;
              const label = field.label || this.formatFieldName(apiName);
              const masterValue = this.formatFieldValue(masterRecord[apiName]);

              // Process duplicate values
              const duplicateValues = this.duplicateRecords.map((dupRecord) => {
                const value = this.formatFieldValue(dupRecord.record[apiName]);
                const isDifferent =
                  value !== masterValue &&
                  value !== null &&
                  value !== "" &&
                  masterValue !== null &&
                  masterValue !== "";

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

              // Define field metadata for rendering
              const fieldInfo = {
                apiName: apiName,
                label: label,
                masterValue: masterValue,
                masterClass: hasDifferences ? "field-master" : "",
                duplicateValues: duplicateValues,
                hasDifferences: hasDifferences,
                isMergeable: field.isMergeable !== false, // Default to true if not specified
                isRequired: field.isRequired === true,
                isReadOnly: field.isReadOnly === true,
                fieldType: field.type || "STRING"
              };

              // If this field has differences, mark the group as having expanded fields
              if (hasDifferences) {
                processedGroup.hasExpandedFields = true;
              }

              return fieldInfo;
            })
            .filter((field) => field.hasDifferences || this.showAllFields);
        }

        return processedGroup;
      })
      .filter((group) => group.fields.length > 0);

    // Sort groups to put those with differences first
    this.fieldGroups.sort((a, b) => {
      if (a.hasExpandedFields && !b.hasExpandedFields) return -1;
      if (!a.hasExpandedFields && b.hasExpandedFields) return 1;
      return 0;
    });
  }

  /**
   * Initialize non-mergeable field data
   */
  initNonMergeableFieldData() {
    // Initialize with empty data since we don't have getMergeableFields anymore
    this.nonMergeableData = [];
  }

  /**
   * Get a display name for a record
   */
  getRecordName(record) {
    if (!record) return '';

    if (record.Name) {
      return record.Name;
    } else if (record.FirstName && record.LastName) {
      return `${record.FirstName} ${record.LastName}`;
    } else if (record.LastName) {
      return record.LastName;
    } else if (record.Subject) {
      return record.Subject;
    } else {
      return record.Id;
    }
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

    if (value instanceof Date) {
      return value.toLocaleString();
    }

    return String(value);
  }

  /**
   * Format field API name to a more user-friendly label
   */
  formatFieldName(fieldName) {
    if (!fieldName) return '';

    // Split by underscore or camel case
    const words = fieldName.replace(/_/g, ' ').split(/(?=[A-Z])/);

    // Capitalize first letter of each word
    for (let i = 0; i < words.length; i++) {
      if (words[i].length > 0) {
        words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1);
      }
    }

    return words.join(' ').replace('__c', '');
  }

  /**
   * Handle error in loading data
   */
  handleLoadError(error) {
    this.isLoading = false;

    // Use error handler utility
    this.error = handleError(
      "duplicateComparisonView",
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
      this.refreshComparisonView();
    }
  }

  /**
   * Refresh the comparison view with current data but without reloading from server
   */
  refreshComparisonView() {
    this.isLoading = true;

    // Move the master record to the recordsById
    if (this.masterRecordId) {
      // If master is in duplicate records, move it back to records by ID
      const masterIndex = this.duplicateRecords.findIndex(r => r.id === this.masterRecordId);
      if (masterIndex >= 0) {
        const masterDuplicate = this.duplicateRecords[masterIndex];
        this.recordsById[masterDuplicate.id] = masterDuplicate.record;

        // Remove from duplicates
        this.duplicateRecords.splice(masterIndex, 1);
      }

      // Add previous master to duplicates if it's not already there
      const previousMaster = this.recordsById[this.masterRecordId];
      if (previousMaster && !this.duplicateRecords.find(r => r.id === previousMaster.Id)) {
        this.duplicateRecords.push({
          id: previousMaster.Id,
          name: this.getRecordName(previousMaster),
          record: previousMaster,
          matchScore: previousMaster.MatchScore__c
            ? `${Math.round(previousMaster.MatchScore__c * 100)}%`
            : "N/A",
          rawScore: previousMaster.MatchScore__c || 0
        });
      }
    }

    // Process fields with current data
    this.processFields(this.fieldGroups);

    // Sort duplicates by score
    this.duplicateRecords.sort((a, b) => b.rawScore - a.rawScore);

    this.isLoading = false;
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

      // Send a message that a field selection changed
      sendMessage(MESSAGE_TYPES.FIELD_SELECTION_CHANGED, {
        field: fieldName,
        selectedRecordId: recordId,
        masterRecordId: this.masterRecordId
      });
    }
  }

  /**
   * Select all values from a specific record
   */
  handleSelectAllFromRecord(event) {
    const recordId = event.currentTarget.dataset.id;

    if (!recordId) return;

    // Update all field selections to use this record
    this.fieldGroups.forEach(group => {
      group.fields.forEach(field => {
        if (field.hasDifferences) {
          this.fieldSelections[field.apiName] = recordId;
        }
      });
    });

    // Refresh the view
    this.processFields(this.fieldGroups);

    // Notify of bulk selection
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Selection Updated",
        message: "All fields updated to use values from the selected record",
        variant: "success"
      })
    );
  }

  /**
   * Handle selecting all non-empty values
   */
  handleSelectNonEmpty() {
    // For each field that has differences, select the non-empty value
    let changedCount = 0;

    this.fieldGroups.forEach(group => {
      group.fields.forEach(field => {
        if (field.hasDifferences) {
          // Get master value
          const masterValue = field.masterValue;

          // Check if master value is empty
          const isMasterEmpty = masterValue === null || masterValue === "";

          if (isMasterEmpty) {
            // Find first non-empty duplicate value
            const nonEmptyDuplicate = field.duplicateValues.find(
              dv => dv.value !== null && dv.value !== ""
            );

            if (nonEmptyDuplicate) {
              this.fieldSelections[field.apiName] = nonEmptyDuplicate.id;
              changedCount++;
            }
          }
        }
      });
    });

    // Refresh the view
    this.processFields(this.fieldGroups);

    // Notify of selection
    if (changedCount > 0) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Selection Updated",
          message: `${changedCount} empty fields updated with non-empty values`,
          variant: "success"
        })
      );
    } else {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "No Changes Made",
          message: "No empty fields were found that could be updated",
          variant: "info"
        })
      );
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
          "duplicateComparisonView",
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
   * Check if we have any field differences
   */
  get hasDifferences() {
    return this.fieldGroups.some(group =>
      group.fields.some(field => field.hasDifferences)
    );
  }

  /**
   * Get the count of differences
   */
  get differencesCount() {
    let count = 0;

    this.fieldGroups.forEach(group => {
      group.fields.forEach(field => {
        if (field.hasDifferences) {
          count++;
        }
      });
    });

    return count;
  }

  /**
   * Get master record display name
   */
  get masterRecordName() {
    return this.masterRecordId ?
      this.getRecordName(this.recordsById[this.masterRecordId]) :
      'No master record selected';
  }

  /**
   * Check if we have non-mergeable data
   */
  get hasNonMergeableData() {
    return this.nonMergeableData.length > 0;
  }

  /**
   * Get the match score of the current master record
   */
  get masterRecordMatchScore() {
    const record = this.recordsById[this.masterRecordId];
    if (record && record.MatchScore__c) {
      return `${Math.round(record.MatchScore__c * 100)}%`;
    }
    return 'N/A';
  }
}
