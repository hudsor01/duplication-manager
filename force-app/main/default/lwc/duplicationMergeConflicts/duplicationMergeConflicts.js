/**
 * Component for displaying and resolving merge conflicts
 * Allows users to select values from conflicting records
 *
 * @author Richard Hudson
 * @since April 2025
 */
import { LightningElement, api, track } from "lwc";
import { fieldNameToLabel } from "c/duplicationUtils";

export default class DuplicationMergeConflicts extends LightningElement {
  /**
   * @api
   * @description Master record to keep
   * @type {Object}
   */
  @api masterRecord;

  /**
   * @api
   * @description Duplicate records to merge
   * @type {Array}
   */
  @api duplicateRecords = [];

  /**
   * @api
   * @description Object API name
   * @type {String}
   */
  @api objectApiName;

  /**
   * @api
   * @description Fields to display
   * @type {Array}
   */
  @api
  get fields() {
    return this._fieldsValue || [];
  }
  set fields(value) {
    this._fieldsValue = value;
  }

  // Tracked properties for component state
  @track isLoading = false;
  @track conflicts = [];
  @track error;
  @track fieldSelections = {};

  // Private properties
  _recordMap = {};
  _isInitialized = false;

  /**
   * Lifecycle hook - Component connected to DOM
   */
  connectedCallback() {
    this.initialize();
  }

  /**
   * Lifecycle hook - Handle property changes
   * @param {Object} changedProperties - Properties that changed
   */
  renderedCallback() {
    if (
      !this._isInitialized &&
      this.masterRecord &&
      this.duplicateRecords.length > 0
    ) {
      this.initialize();
    }
  }

  /**
   * Initialize component
   */
  initialize() {
    if (!this.masterRecord || !this.duplicateRecords.length) {
      return;
    }

    try {
      this.isLoading = true;

      // Map records by ID for easy access
      this._recordMap = {
        [this.masterRecord.Id]: this.masterRecord,
      };

      this.duplicateRecords.forEach((record) => {
        this._recordMap[record.Id] = record;
      });

      // Build list of fields if not provided
      if (!this.fields || !this.fields.length) {
        this.buildFieldList();
      }

      // Identify conflicts
      this.identifyConflicts();

      this._isInitialized = true;
    } catch (error) {
      this.handleError(error);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * Build a list of fields from records
   */
  buildFieldList() {
    const allFields = new Set();

    // Add fields from master record
    Object.keys(this.masterRecord).forEach((field) => {
      if (field !== "Id" && field !== "attributes") {
        allFields.add(field);
      }
    });

    // Add fields from duplicates
    this.duplicateRecords.forEach((record) => {
      Object.keys(record).forEach((field) => {
        if (field !== "Id" && field !== "attributes") {
          allFields.add(field);
        }
      });
    });

    // Set the backing property instead of API property
    this._fieldsValue = Array.from(allFields);
  }

  /**
   * Identify conflicts between records
   */
  identifyConflicts() {
    this.conflicts = [];
    this.fieldSelections = {};

    // Check each field for conflicts
    this.fields.forEach((field) => {
      const masterValue = this.masterRecord[field];
      const valueOptions = [];

      // Add master value
      if (masterValue !== undefined) {
        valueOptions.push({
          value: this.formatValue(masterValue),
          recordId: this.masterRecord.Id,
          recordName: this.getRecordName(this.masterRecord),
          isMaster: true,
        });

        // Default selection to master value
        this.fieldSelections[field] = this.masterRecord.Id;
      }

      // Check duplicate records for different values
      this.duplicateRecords.forEach((record) => {
        const duplicateValue = record[field];

        // Only consider values that are different from master
        if (
          duplicateValue !== undefined &&
          (masterValue === undefined ||
            this.formatValue(duplicateValue) !== this.formatValue(masterValue))
        ) {
          valueOptions.push({
            value: this.formatValue(duplicateValue),
            recordId: record.Id,
            recordName: this.getRecordName(record),
            isMaster: false,
          });

          // If master doesn't have a value, default to this one
          if (masterValue === undefined && !this.fieldSelections[field]) {
            this.fieldSelections[field] = record.Id;
          }
        }
      });

      // If we have more than one value, it's a conflict
      if (valueOptions.length > 1) {
        this.conflicts.push({
          field: field,
          fieldLabel: fieldNameToLabel(field),
          values: valueOptions,
        });
      }
    });

    // Sort conflicts by field label
    this.conflicts.sort((a, b) => {
      return a.fieldLabel.localeCompare(b.fieldLabel);
    });
  }

  /**
   * Format a value for display
   * @param {any} value - Value to format
   * @returns {String} Formatted value
   */
  formatValue(value) {
    if (value === null || value === undefined) {
      return "(empty)";
    }

    if (typeof value === "boolean") {
      return value ? "True" : "False";
    }

    if (value instanceof Date) {
      return value.toLocaleString();
    }

    return String(value);
  }

  /**
   * Get a display name for a record
   * @param {Object} record - Record to get name for
   * @returns {String} Record name
   */
  getRecordName(record) {
    if (record.Name) {
      return record.Name;
    }

    if (record.FirstName && record.LastName) {
      return `${record.FirstName} ${record.LastName}`;
    }

    return record.Id;
  }

  /**
   * Handle value selection change
   * @param {Event} event - Change event
   */
  handleValueSelection(event) {
    const field = event.target.dataset.field;
    const recordId = event.target.value;

    this.fieldSelections[field] = recordId;

    // Dispatch change event
    this.dispatchSelectionChanged();
  }

  /**
   * Check if a value is selected for a field
   * @param {String} field - Field API name
   * @param {String} recordId - Record ID
   * @returns {Boolean} True if value is selected
   */
  isValueSelected(field, recordId) {
    return this.fieldSelections[field] === recordId;
  }

  /**
   * Get CSS class for value option
   * @param {String} field - Field API name
   * @param {Object} valueOption - Value option
   * @returns {String} CSS class
   */
  getValueOptionClass(field, valueOption) {
    const baseClass =
      "slds-col slds-size_12-of-12 slds-var-p-around_x-small value-option";
    const isSelected = this.isValueSelected(field, valueOption.recordId);
    const isMaster = valueOption.isMaster;

    if (isSelected) {
      return `${baseClass} selected`;
    }

    if (isMaster) {
      return `${baseClass} master-value`;
    }

    return baseClass;
  }

  /**
   * Get unique ID for a value option
   * @param {String} field - Field API name
   * @param {String} recordId - Record ID
   * @returns {String} Unique ID
   */
  getValueId(field, recordId) {
    return `${field}-${recordId}`;
  }

  /**
   * Dispatch selection changed event
   */
  dispatchSelectionChanged() {
    // Convert selections to field -> value map
    const fieldValues = {};

    Object.keys(this.fieldSelections).forEach((field) => {
      const recordId = this.fieldSelections[field];
      const record = this._recordMap[recordId];

      if (record) {
        fieldValues[field] = record[field];
      }
    });

    // Create and dispatch the event
    const selectionEvent = new CustomEvent("selectionchange", {
      detail: {
        selections: this.fieldSelections,
        fieldValues: fieldValues,
      },
    });
    this.dispatchEvent(selectionEvent);
  }

  /**
   * @api
   * @description Get current field selections
   * @returns {Object} Map of field to selected record ID
   */
  @api
  getSelections() {
    return { ...this.fieldSelections };
  }

  /**
   * @api
   * @description Get field values from selections
   * @returns {Object} Map of field to selected value
   */
  @api
  getFieldValues() {
    const fieldValues = {};

    Object.keys(this.fieldSelections).forEach((field) => {
      const recordId = this.fieldSelections[field];
      const record = this._recordMap[recordId];

      if (record) {
        fieldValues[field] = record[field];
      }
    });

    return fieldValues;
  }

  /**
   * @api
   * @description Select all values from master record
   */
  @api
  selectAllMaster() {
    this.conflicts.forEach((conflict) => {
      const masterValue = conflict.values.find((v) => v.isMaster);
      if (masterValue) {
        this.fieldSelections[conflict.field] = masterValue.recordId;
      }
    });

    this.dispatchSelectionChanged();
  }

  /**
   * @api
   * @description Select all non-null values
   */
  @api
  selectAllNonNull() {
    this.conflicts.forEach((conflict) => {
      // Find first non-null value, prioritizing master
      const masterValue = conflict.values.find((v) => v.isMaster);
      if (masterValue && masterValue.value !== "(empty)") {
        this.fieldSelections[conflict.field] = masterValue.recordId;
      } else {
        const nonNullValue = conflict.values.find((v) => v.value !== "(empty)");
        if (nonNullValue) {
          this.fieldSelections[conflict.field] = nonNullValue.recordId;
        }
      }
    });

    this.dispatchSelectionChanged();
  }

  /**
   * @api
   * @description Select most recent values
   */
  @api
  selectMostRecent() {
    // This is a simplified version - in a real implementation,
    // we would need to check LastModifiedDate or similar field
    this.conflicts.forEach((conflict) => {
      // Check if we have a value from master record
      const masterValue = conflict.values.find((v) => v.isMaster);

      // Currently just use master, but in a real implementation would compare dates
      if (masterValue) {
        this.fieldSelections[conflict.field] = masterValue.recordId;
      } else if (conflict.values.length > 0) {
        this.fieldSelections[conflict.field] = conflict.values[0].recordId;
      }
    });

    this.dispatchSelectionChanged();
  }

  /**
   * Handle error
   * @param {Object} error - Error object
   */
  handleError(error) {
    let errorMessage = "Error processing merge conflicts";

    if (error.body && error.body.message) {
      errorMessage += ": " + error.body.message;
    } else if (error.message) {
      errorMessage += ": " + error.message;
    }

    this.error = {
      message: errorMessage,
      timestamp: new Date().toISOString(),
    };

    console.error(errorMessage, error);
  }

  /**
   * Check if component has conflicts
   * @returns {Boolean} True if conflicts exist
   */
  get hasConflicts() {
    return this.conflicts && this.conflicts.length > 0;
  }

  /**
   * Check if component has an error
   * @returns {Boolean} True if component has an error
   */
  get hasError() {
    return !!this.error;
  }

  /**
   * Get count of conflicts
   * @returns {String} Count of conflicts with label
   */
  get conflictsCount() {
    const count = this.conflicts?.length || 0;
    return count + (count === 1 ? " field conflict" : " field conflicts");
  }
}
