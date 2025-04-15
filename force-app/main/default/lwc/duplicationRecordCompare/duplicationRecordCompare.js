import { LightningElement, api, track } from "lwc";
import getRecordsForComparison from "@salesforce/apex/DRCCompare.getRecordsForComparison";

/**
 * Component for side-by-side record comparison
 * Shows differences between records to help with duplicate management
 */
export default class DuplicationRecordCompare extends LightningElement {
  // Private backing properties
  _recordId1;
  _recordId2;
  _objectApiName;
  _group;

  // API properties with getters/setters to avoid reassignments
  @api
  get recordId1() {
    return this._recordId1;
  }
  set recordId1(value) {
    this._recordId1 = value;
  }

  @api
  get recordId2() {
    return this._recordId2;
  }
  set recordId2(value) {
    this._recordId2 = value;
  }

  @api
  get objectApiName() {
    return this._objectApiName;
  }
  set objectApiName(value) {
    this._objectApiName = value;
  }

  @api
  get group() {
    return this._group;
  }
  set group(value) {
    this._group = value;
    // When group changes, load records
    if (value) {
      this.loadRecords();
    }
  }

  @track isLoading = false;
  @track record1 = {};
  @track record2 = {};
  @track fieldData = [];
  @track error;

  // Lifecycle hooks
  connectedCallback() {
    if (this.hasRecords || this.group) {
      this.loadRecords();
    }
  }

  renderedCallback() {
    this.applyDifferenceHighlighting();
  }

  // Update records when group changes - maintained for backward compatibility
  @api
  updateFromGroup(value) {
    // Update the backing property directly instead of using setter
    this._group = value;
    // When group changes, load records
    if (value) {
      this.loadRecords();
    }
  }

  /**
   * Getter to determine if we have records to compare
   */
  get hasRecords() {
    return this.recordId1 && this.recordId2;
  }

  // Using pre-processed data in fieldData to avoid computed property access in templates

  /**
   * Apply highlighting to fields with differences
   * This applies CSS classes programmatically instead of using template expressions
   */
  applyDifferenceHighlighting() {
    // All 'var' declarations must be at the very top of the function scope
    var fieldValues;
    var fieldRows;
    var i;
    var j;
    var k;
    var m;
    var element;
    var fieldId;
    var field;
    var rowElement;
    var rowFieldId;
    var rowField;

    // Early return if no data
    if (!this.fieldData || this.fieldData.length === 0) {
      return;
    }

    // Apply styling to field values
    fieldValues = this.template.querySelectorAll(".field-value");
    for (i = 0; i < fieldValues.length; i++) {
      element = fieldValues[i];
      fieldId = element.dataset.id;

      // Find the field in fieldData
      field = null;
      for (j = 0; j < this.fieldData.length; j++) {
        if (this.fieldData[j].field === fieldId) {
          field = this.fieldData[j];
          break;
        }
      }

      if (field && field.isDifferent) {
        element.classList.add("slds-text-color_error");
      }

      // Add standard classes
      element.classList.add("slds-item_detail", "slds-truncate");
    }

    // Apply styling to table rows
    fieldRows = this.template.querySelectorAll(".field-row");
    for (k = 0; k < fieldRows.length; k++) {
      rowElement = fieldRows[k];
      rowFieldId = rowElement.dataset.id;

      // Find the field in fieldData
      rowField = null;
      for (m = 0; m < this.fieldData.length; m++) {
        if (this.fieldData[m].field === rowFieldId) {
          rowField = this.fieldData[m];
          break;
        }
      }

      if (rowField && rowField.isDifferent) {
        rowElement.classList.add("slds-is-selected");
      }
    }
  }

  /**
   * Load the records for comparison
   */
  @api
  loadRecords() {
    // If we have a group, use its record IDs
    if (this.group) {
      if (this.group.duplicateRecordIds) {
        if (this.group.duplicateRecordIds.length >= 2) {
          this._recordId1 = this.group.duplicateRecordIds[0];
          this._recordId2 = this.group.duplicateRecordIds[1];
        }
      }
    }

    if (!this.hasRecords) {
      return;
    }

    this.isLoading = true;

    // Fetch record data from Apex controller
    // This will be implemented with actual production data
    this.fetchRecordData(this.recordId1, this.recordId2)
      .then((result) => {
        if (result) {
          this.record1 = result.record1;
          this.record2 = result.record2;
          this.fieldData = result.fieldDifferences;
          // Application of styling will happen in renderedCallback
        }
        this.isLoading = false;
      })
      .catch((error) => {
        this.error = error.message
          ? error.message
          : "Error retrieving record data";
        this.isLoading = false;
      });
  }

  /**
   * Fetch record data for comparison
   * @param {String} recordId1 - First record ID
   * @param {String} recordId2 - Second record ID
   * @returns {Promise} Promise with comparison data
   */
  fetchRecordData(recordId1, recordId2) {
    // DRCCompare.getRecordsForComparison takes a list of record IDs
    // Declare all variables at the top of function scope
    var recordIds;

    // Initialize variables
    recordIds = [recordId1, recordId2];

    const params = {
      recordIds: recordIds,
      objectApiName: this.objectApiName
    };

    return getRecordsForComparison(params).then((result) => {
      // Process the response from the Apex controller
      return this.processRecordsResponse(result, recordId1, recordId2);
    });
  }

  /**
   * Process records response from Apex
   * @param {Object} result - Result from Apex call
   * @param {String} recordId1 - First record ID
   * @param {String} recordId2 - Second record ID
   * @returns {Object} Processed data for the component
   */
  processRecordsResponse(result, recordId1, recordId2) {
    // All 'var' declarations must be at the top of the function scope
    var records;
    var record1;
    var record2;
    var fields;
    var fieldDifferences;
    var i;
    var j;
    var fieldName;
    var value1;
    var value2;
    var isDifferent;
    var fieldLabel;

    if (!result || !result.records) {
      return null;
    }

    // Extract records from the result
    records = result.records;
    record1 = null;
    record2 = null;

    // Find each record by ID
    for (i = 0; i < records.length; i++) {
      if (records[i].Id === recordId1) {
        record1 = records[i];
      } else if (records[i].Id === recordId2) {
        record2 = records[i];
      }
    }

    if (!record1 || !record2) {
      return null;
    }

    // Process fields and create formatted data for display
    fields = result.fields || [];
    fieldDifferences = [];

    for (j = 0; j < fields.length; j++) {
      fieldName = fields[j];
      value1 = record1[fieldName];
      value2 = record2[fieldName];
      isDifferent = false;

      // Handle null values
      if (value1 === null) value1 = "";
      if (value2 === null) value2 = "";

      // Convert to string for comparison
      value1 = String(value1);
      value2 = String(value2);

      // Check if values are different
      isDifferent = value1 !== value2;

      // Get a more user-friendly field label
      fieldLabel = this.formatFieldName(fieldName);

      fieldDifferences.push({
        field: fieldName,
        label: fieldLabel,
        value1: value1,
        value2: value2,
        isDifferent: isDifferent
      });
    }

    return {
      record1: record1,
      record2: record2,
      fieldDifferences: fieldDifferences
    };
  }

  /**
   * Format field API name to a more user-friendly label
   * @param {String} fieldName - API name of the field
   * @returns {String} Formatted field name
   */
  formatFieldName(fieldName) {
    // All 'var' declarations must be at the top of the function scope
    var words;
    var i;

    if (!fieldName) return "";

    // Split by underscore or camel case
    words = fieldName.replace(/_/g, " ").split(/(?=[A-Z])/);

    // Capitalize first letter of each word
    for (i = 0; i < words.length; i++) {
      if (words[i].length > 0) {
        words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1);
      }
    }

    return words.join(" ").replace("__c", "");
  }

  /**
   * Refresh the comparison
   */
  @api
  refresh() {
    this.loadRecords();
  }
}
