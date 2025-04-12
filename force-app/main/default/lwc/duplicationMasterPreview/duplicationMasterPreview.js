import { LightningElement, api, track, wire } from "lwc";
import { getObjectInfo } from "lightning/uiRecordApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getRecordData from "@salesforce/apex/RecordDataController.getRecordData";

/**
 * Component to display a preview of what the master record will look like after a merge
 */
export default class DuplicationMasterPreview extends LightningElement {
  @api group;
  @api objectApiName;

  // Use private backing property for masterRecordId
  _masterRecordIdValue;

  @api
  get masterRecordId() {
    return this._masterRecordIdValue;
  }

  set masterRecordId(value) {
    this._masterRecordIdValue = value;
    if (this.records?.length > 0) {
      this.generateMasterPreview();
    }
  }

  @track records = [];
  @track fieldInfos = [];
  @track conflictingFields = [];
  @track masterRecord = null;
  @track masterRecordPreview = {};
  @track fieldStatuses = {};

  isLoading = true;
  recordsLoaded = 0;
  expectedRecordCount = 0;
  error = null;
  objectInfo = null;

  // Map to store field values by record ID
  recordFieldValuesByRecordId = {};

  // Default fields to display (can be customized per object)
  defaultFields = {
    Account: [
      "Name",
      "Phone",
      "Website",
      "BillingStreet",
      "BillingCity",
      "BillingState",
      "BillingPostalCode",
    ],
    Contact: ["FirstName", "LastName", "Email", "Phone", "Title", "Department"],
    Lead: ["FirstName", "LastName", "Email", "Phone", "Company", "Title"],
  };

  // Selected fields for display
  selectedFields = [];

  // Removed masterRecordIdProp as it's redundant with our new getter/setter pattern for masterRecordId

  /**
   * Lifecycle hook - Called when component is inserted into the DOM
   */
  connectedCallback() {
    if (this.group && this.objectApiName) {
      // Set the backing property directly instead of using the setter
      if (!this._masterRecordIdValue && this.group.masterRecordId) {
        this._masterRecordIdValue = this.group.masterRecordId;
      }
    }
  }

  /**
   * Lifecycle hook - Called when properties are changed
   */
  renderedCallback() {
    if (
      this.group &&
      this.objectApiName &&
      !this.isLoading &&
      this.recordsLoaded === 0
    ) {
      this.loadRecords();
    }
  }

  /**
   * Wire service to get object metadata
   */
  @wire(getObjectInfo, { objectApiName: "$objectApiName" })
  wiredObjectInfo({ error, data }) {
    if (data) {
      this.objectInfo = data;

      // Get default fields for this object type or use a default set
      this.selectedFields =
        this.defaultFields[this.objectApiName] ||
        Object.keys(data.fields).slice(0, 10); // Get first 10 fields if no defaults

      // Generate field info for display
      this.generateFieldInfos();
    } else if (error) {
      this.handleError("Error loading object information", error);
    }
  }

  /**
   * Generate field infos for display
   */
  generateFieldInfos() {
    if (!this.objectInfo || !this.masterRecordPreview) {
      this.fieldInfos = [];
      return;
    }

    this.fieldInfos = this.selectedFields.map((fieldName) => {
      const value = this.masterRecordPreview[fieldName];
      const fieldInfo = this.objectInfo.fields[fieldName];

      return {
        apiName: fieldName,
        label: fieldInfo ? fieldInfo.label : fieldName,
        value: value ? value.value : null,
        displayValue: value ? value.displayValue : "",
        status: this.fieldStatuses[fieldName] || "unchanged",
        iconName: this.getStatusIcon(fieldName),
        iconVariant: this.getStatusIconVariant(fieldName),
        statusLabel: this.getStatusLabel(fieldName),
      };
    });
  }

  /**
   * Load records for preview
   */
  loadRecords() {
    if (!this.group || !this.group.duplicateRecordIds || !this.objectApiName) {
      return;
    }

    this.isLoading = true;
    this.recordsLoaded = 0;
    this.records = [];
    this.recordFieldValuesByRecordId = {};

    // Use backing property directly instead of the setter
    if (!this._masterRecordIdValue && this.group.masterRecordId) {
      this._masterRecordIdValue = this.group.masterRecordId;
    }

    this.expectedRecordCount = this.group.duplicateRecordIds.length;

    // Load each record
    this.group.duplicateRecordIds.forEach((recordId) => {
      this.loadRecord(recordId);
    });
  }

  /**
   * Load a single record
   * @param {String} recordId - ID of the record to load
   */
  loadRecord(recordId) {
    // Get fields to retrieve
    const fieldsToRetrieve = this.selectedFields.map(
      (field) => `${this.objectApiName}.${field}`,
    );

    getRecordData({
      recordId: recordId,
      fields: fieldsToRetrieve,
    })
      .then((result) => {
        this.processRecordData(result);
      })
      .catch((error) => {
        this.handleError(`Error loading record ${recordId}`, error);
      });
  }

  /**
   * Process record data returned from getRecord
   * @param {Object} recordData - Record data from getRecord
   */
  processRecordData(recordData) {
    if (!recordData || !recordData.id) return;

    // Extract field values
    const recordValues = {
      id: recordData.id,
      fields: {},
    };

    // For each selected field, extract the value
    this.selectedFields.forEach((field) => {
      if (recordData.fields && recordData.fields[field]) {
        recordValues.fields[field] = {
          value: recordData.fields[field].value,
          displayValue:
            recordData.fields[field].displayValue ||
            recordData.fields[field].value,
        };
      } else {
        recordValues.fields[field] = {
          value: null,
          displayValue: "",
        };
      }
    });

    // Store record data by ID
    this.recordFieldValuesByRecordId[recordData.id] = recordValues;

    // Increment counter
    this.recordsLoaded++;

    // Check if all records are loaded
    if (this.recordsLoaded === this.expectedRecordCount) {
      this.finalizeRecordsLoading();
    }
  }

  /**
   * Finalize record loading
   */
  finalizeRecordsLoading() {
    // Convert recordFieldValuesByRecordId to array
    this.records = Object.values(this.recordFieldValuesByRecordId);

    // Mark master record
    this.records = this.records.map((record) => {
      const isMaster = record.id === this.masterRecordId;

      if (isMaster) {
        this.masterRecord = record;
      }

      return {
        ...record,
        isMaster,
      };
    });

    // Generate master preview
    this.generateMasterPreview();

    // Update loading state
    this.isLoading = false;
  }

  /**
   * Generate a preview of what the master record will look like after merge
   */
  generateMasterPreview() {
    if (!this.records || this.records.length === 0 || !this.masterRecordId) {
      return;
    }

    const preview = {};
    const fieldStatuses = {};
    const conflictingFieldsArray = [];

    // Get the master record
    const masterRecord = this.records.find((r) => r.id === this.masterRecordId);

    if (!masterRecord) {
      return;
    }

    // For each field, determine what the final value will be
    this.selectedFields.forEach((field) => {
      let bestValue = null;
      let status = "unchanged";

      // Start with master record value
      if (masterRecord.fields[field] && masterRecord.fields[field].value) {
        bestValue = {
          value: masterRecord.fields[field].value,
          displayValue: masterRecord.fields[field].displayValue,
          sourceRecordId: masterRecord.id,
        };
      }

      // Check if any other record has a non-null value when master is null
      if (!bestValue || !bestValue.value) {
        for (const record of this.records) {
          if (
            record.id !== masterRecord.id &&
            record.fields[field] &&
            record.fields[field].value
          ) {
            bestValue = {
              value: record.fields[field].value,
              displayValue: record.fields[field].displayValue,
              sourceRecordId: record.id,
            };

            status = "filled";
            break;
          }
        }
      }

      // Check for potential conflicts
      const conflictingValues = [];
      this.records.forEach((record) => {
        if (
          record.id !== masterRecord.id &&
          record.fields[field] &&
          record.fields[field].value
        ) {
          const recordValue = record.fields[field].value;
          const recordDisplayValue =
            record.fields[field].displayValue || recordValue.toString();
          const masterValue = masterRecord.fields[field]
            ? masterRecord.fields[field].value
            : null;

          if (recordValue && masterValue && recordValue !== masterValue) {
            conflictingValues.push({
              value: recordValue,
              displayValue: recordDisplayValue,
              recordId: record.id,
            });
          }
        }
      });

      if (conflictingValues.length > 0) {
        status = "conflict";

        // Track conflicts for display
        const fieldLabel = this.objectInfo?.fields?.[field]?.label || field;
        const masterValue = masterRecord.fields[field]
          ? masterRecord.fields[field].displayValue ||
            masterRecord.fields[field].value
          : "";

        // Combine all conflicting values for this field
        const duplicateValues = conflictingValues
          .map((cv) => cv.displayValue)
          .join(", ");

        conflictingFieldsArray.push({
          fieldName: field,
          fieldLabel: fieldLabel,
          masterValue: masterValue,
          duplicateValue: duplicateValues,
        });
      }

      // Store in preview
      preview[field] = bestValue;
      fieldStatuses[field] = status;
    });

    this.masterRecordPreview = preview;
    this.fieldStatuses = fieldStatuses;
    this.conflictingFields = conflictingFieldsArray;

    // Generate field infos for display
    this.generateFieldInfos();
  }

  /**
   * Handle field selection change
   * @param {Event} event - Change event from multi-select picklist
   */
  handleFieldSelection(event) {
    const selectedOptions = event.detail.value;

    if (Array.isArray(selectedOptions) && selectedOptions.length > 0) {
      this.selectedFields = selectedOptions;
      this.generateFieldInfos();

      if (this.recordsLoaded === this.expectedRecordCount) {
        // Reload the records with the new field selection
        this.loadRecords();
      }
    }
  }

  /**
   * Handle error
   * @param {String} message - Error message
   * @param {Error} error - Error object
   */
  handleError(message, error) {
    let errorMessage = message;

    if (error) {
      if (error.body && error.body.message) {
        errorMessage += ": " + error.body.message;
      } else if (error.message) {
        errorMessage += ": " + error.message;
      }
    }

    this.error = errorMessage;
    this.isLoading = false;

    this.dispatchEvent(
      new ShowToastEvent({
        title: "Error",
        message: errorMessage,
        variant: "error",
      }),
    );
  }

  /**
   * Get field options for multi-select picklist
   */
  get fieldOptions() {
    if (!this.objectInfo) return [];

    return Object.keys(this.objectInfo.fields).map((fieldName) => {
      const field = this.objectInfo.fields[fieldName];
      return {
        label: field.label,
        value: fieldName,
      };
    });
  }

  /**
   * Check if there are any records loaded
   */
  get hasRecords() {
    return this.records && this.records.length > 0 && !this.isLoading;
  }

  /**
   * Check if there are any field conflicts
   */
  get hasFieldConflicts() {
    return Object.values(this.fieldStatuses).some(
      (status) => status === "conflict",
    );
  }

  /**
   * Generate note preview content
   */
  get notePreviewContent() {
    if (!this.hasFieldConflicts) {
      return "No conflicts to preserve";
    }

    let noteContent = "Data preserved from merge operation:\n\n";
    noteContent += "== CONFLICTING VALUES ==\n";

    this.conflictingFields.forEach((conflict) => {
      noteContent += `${conflict.fieldLabel}: ${conflict.duplicateValue}\n`;
    });

    return noteContent;
  }

  /**
   * Get status icon for a field
   * @param {String} fieldName - Field API name
   * @returns {String} SLDS icon name
   */
  getStatusIcon(fieldName) {
    const status = this.fieldStatuses[fieldName];

    switch (status) {
      case "conflict":
        return "utility:warning";
      case "filled":
        return "utility:change_record_type";
      default:
        return "utility:check";
    }
  }

  /**
   * Get status icon variant for a field
   * @param {String} fieldName - Field API name
   * @returns {String} SLDS icon variant
   */
  getStatusIconVariant(fieldName) {
    const status = this.fieldStatuses[fieldName];

    switch (status) {
      case "conflict":
        return "warning";
      case "filled":
        return "success";
      default:
        return "success";
    }
  }

  /**
   * Get status label for a field
   * @param {String} fieldName - Field API name
   * @returns {String} Status label
   */
  getStatusLabel(fieldName) {
    const status = this.fieldStatuses[fieldName];

    switch (status) {
      case "conflict":
        return "Conflict - Master record value will be preserved";
      case "filled":
        return "Empty in master - Value filled from duplicate record";
      default:
        return "Unchanged - Master record value will be preserved";
    }
  }
}
