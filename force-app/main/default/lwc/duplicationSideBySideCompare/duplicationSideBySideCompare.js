import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getRecordData from "@salesforce/apex/RecordDataController.getRecordData";
// Temporarily comment out the MetadataController import until implementation is complete
// import getObjectInfo from "@salesforce/apex/MetadataController.getObjectInfo";
import mergeDuplicateRecords from "@salesforce/apex/DuplicateRecordController.mergeDuplicateRecords";
// Temporarily comment out the createNote import until implementation is complete
// import createNoteWithConflicts from "@salesforce/apex/DuplicateRecordController.createNote";

export default class DuplicationSideBySideCompare extends LightningElement {
  @api masterRecordId;
  @api duplicateRecordId;
  @api objectApiName;

  @track compareFields = [];
  @track masterRecord;
  @track duplicateRecord;
  @track objectInfo;
  @track nonMergeableData = [];
  @track conflictData = [];

  isLoading = true;
  error;

  // Radio button options
  radioOptions = [{ label: "Use this value", value: "selected" }];

  connectedCallback() {
    if (this.masterRecordId && this.duplicateRecordId && this.objectApiName) {
      this.loadRecordData();
    }
  }

  /**
   * Load record data for comparison
   */
  loadRecordData() {
    this.isLoading = true;

    // Temporarily use hardcoded fields instead of fetching metadata
    // First, get object metadata to know what fields to display
    // getObjectInfo({ objectApiName: this.objectApiName })

    // Use mock object info for now
    Promise.resolve(this.getMockObjectInfo(this.objectApiName))
      .then((result) => {
        this.objectInfo = result;

        // Get fields to display based on object type
        const fieldsToRetrieve = this.getFieldsToRetrieve(result);

        // Load master record and duplicate record in parallel
        return Promise.all([
          this.loadRecord(this.masterRecordId, fieldsToRetrieve),
          this.loadRecord(this.duplicateRecordId, fieldsToRetrieve),
        ]);
      })
      .then(([masterData, duplicateData]) => {
        this.masterRecord = masterData;
        this.duplicateRecord = duplicateData;

        // Build comparison data
        this.buildCompareFields();
      })
      .catch((error) => {
        this.handleError(error);
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  /**
   * Load a single record with specified fields
   * @param {String} recordId - Record ID to load
   * @param {Array} fields - Fields to retrieve
   * @returns {Promise} - Promise resolving to record data
   */
  loadRecord(recordId, fields) {
    return getRecordData({
      recordId: recordId,
      fields: fields,
    });
  }

  /**
   * Get fields to retrieve based on object type
   * @param {Object} objectInfo - Object metadata
   * @returns {Array} - Array of fields to retrieve
   */
  getFieldsToRetrieve(objectInfo) {
    // Get all fields from object info
    const allFields = objectInfo?.fields || {};

    // Filter system fields and get important fields first
    const standardFieldsByObject = {
      Account: [
        "Name",
        "Phone",
        "Website",
        "Industry",
        "BillingStreet",
        "BillingCity",
        "BillingState",
        "BillingPostalCode",
        "BillingCountry",
      ],
      Contact: [
        "FirstName",
        "LastName",
        "Email",
        "Phone",
        "Title",
        "Department",
        "MailingStreet",
        "MailingCity",
        "MailingState",
        "MailingPostalCode",
      ],
      Lead: [
        "FirstName",
        "LastName",
        "Email",
        "Phone",
        "Company",
        "Title",
        "Street",
        "City",
        "State",
        "PostalCode",
      ],
      Opportunity: [
        "Name",
        "StageName",
        "Amount",
        "CloseDate",
        "Type",
        "LeadSource",
      ],
    };

    // Get standard fields for this object, or take first 10 fields
    const standardFields =
      standardFieldsByObject[this.objectApiName] ||
      Object.keys(allFields)
        .filter(
          (field) =>
            !field.startsWith("_") && field !== "Id" && field !== "OwnerId",
        )
        .slice(0, 10);

    // Prefix with object API name for LDS
    return standardFields.map((field) => `${this.objectApiName}.${field}`);
  }

  /**
   * Build comparison fields from record data
   */
  buildCompareFields() {
    if (!this.masterRecord || !this.duplicateRecord || !this.objectInfo) {
      return;
    }

    const fields = [];
    const nonMergeable = [];
    const conflicts = [];

    // Get fields from both records
    const masterFields = this.masterRecord.fields || {};
    const duplicateFields = this.duplicateRecord.fields || {};

    // Combine all field names
    const allFieldNames = [
      ...new Set([
        ...Object.keys(masterFields),
        ...Object.keys(duplicateFields),
      ]),
    ];

    // Build compare fields
    allFieldNames.forEach((fieldName) => {
      // Skip system fields
      if (
        fieldName === "Id" ||
        fieldName === "attributes" ||
        fieldName.startsWith("_")
      ) {
        return;
      }

      const masterField = masterFields[fieldName] || {};
      const duplicateField = duplicateFields[fieldName] || {};

      const masterValue = masterField.value;
      const duplicateValue = duplicateField.value;

      const masterDisplayValue = masterField.displayValue || masterValue;
      const duplicateDisplayValue =
        duplicateField.displayValue || duplicateValue;

      // Get field label from object info
      const fieldInfo = this.objectInfo.fields[fieldName];
      const fieldLabel = fieldInfo ? fieldInfo.label : fieldName;

      // Check if values are different
      const isDifferent =
        masterValue !== duplicateValue &&
        masterValue !== null &&
        duplicateValue !== null;

      // Add to comparison fields
      fields.push({
        fieldName: fieldName,
        label: fieldLabel,
        masterValue: masterDisplayValue || "",
        duplicateValue: duplicateDisplayValue || "",
        isDifferent: isDifferent,
        selected: true, // Default to master record field
        duplicateSelected: false,
        radioName: `${fieldName}-radio`,
      });

      // Track conflicts for note creation
      if (isDifferent) {
        conflicts.push({
          fieldName: fieldName,
          fieldLabel: fieldLabel,
          masterValue: masterDisplayValue || "",
          duplicateValue: duplicateDisplayValue || "",
        });
      }
    });

    // Look for related records or child relationships that can't be merged automatically
    // This would require additional queries in a real implementation
    // For now, just check if we have any child relationships in the object info
    if (
      this.objectInfo.childRelationships &&
      this.objectInfo.childRelationships.length > 0
    ) {
      this.objectInfo.childRelationships.forEach((rel) => {
        nonMergeable.push({
          fieldName: rel.relationshipName,
          fieldLabel: `${rel.childObjectLabel} Records`,
          description: `Related ${rel.childObjectLabel} records will need to be manually reassigned after merge.`,
        });
      });
    }

    // Store everything
    this.compareFields = fields;
    this.nonMergeableData = nonMergeable;
    this.conflictData = conflicts;
  }

  /**
   * Handle error
   * @param {Object} error - Error object
   */
  handleError(error) {
    let errorMessage = "Error loading record data";

    if (error) {
      if (error.body && error.body.message) {
        errorMessage += ": " + error.body.message;
      } else if (error.message) {
        errorMessage += ": " + error.message;
      } else if (typeof error === "string") {
        errorMessage += ": " + error;
      }
    }

    this.error = errorMessage;

    this.dispatchEvent(
      new ShowToastEvent({
        title: "Error",
        message: errorMessage,
        variant: "error",
      }),
    );
  }

  /**
   * Generate note content for conflicts
   * @returns {String} - Formatted note content
   */
  generateNoteContent() {
    const timestamp = new Date().toLocaleString();
    let noteContent = `Data preserved from merge operation on ${timestamp}\n\n`;

    // Add conflicts section
    if (this.conflictData.length > 0) {
      noteContent += "== CONFLICTING VALUES ==\n";
      this.conflictData.forEach((conflict) => {
        // Only include conflicts where master value was chosen (others were already merged)
        const field = this.compareFields.find(
          (f) => f.fieldName === conflict.fieldName,
        );
        if (field && field.selected) {
          noteContent += `${conflict.fieldLabel}: ${conflict.duplicateValue} (from duplicate record)\n`;
        }
      });
      noteContent += "\n";
    }

    // Add non-mergeable data section
    if (this.nonMergeableData.length > 0) {
      noteContent += "== NON-MERGEABLE DATA ==\n";
      this.nonMergeableData.forEach((data) => {
        noteContent += `${data.fieldLabel}: ${data.description}\n`;
      });
      noteContent += "\n";
    }

    return noteContent;
  }

  get hasRecords() {
    return this.compareFields.length > 0 && !this.isLoading;
  }

  get hasConflicts() {
    return this.conflictData.length > 0;
  }

  get hasNonMergeableData() {
    return this.nonMergeableData.length > 0;
  }

  /**
   * Handle field value selection
   */
  handleValueSelection(event) {
    const fieldName = event.target.name.split("-")[0];
    const selectedValue = event.target.value;

    // Update the selected state for this field
    this.compareFields = this.compareFields.map((field) => {
      if (field.fieldName === fieldName) {
        if (selectedValue === "selected") {
          return {
            ...field,
            selected: true,
            duplicateSelected: false,
          };
        }
        return {
          ...field,
          selected: false,
          duplicateSelected: true,
        };
      }
      return field;
    });
  }

  /**
   * Handle select different values button
   */
  handleSelectDifferent() {
    // Select all fields that have different values in the duplicate record
    this.compareFields = this.compareFields.map((field) => {
      if (field.isDifferent) {
        return {
          ...field,
          selected: false,
          duplicateSelected: true,
        };
      }
      return field;
    });
  }

  /**
   * Handle merge selected fields
   */
  handleMergeSelected() {
    if (!this.validateMerge()) {
      return;
    }

    // Build merge request
    const mergeRequest = this.buildMergeRequest();

    this.isLoading = true;

    // Call Apex method to merge records
    mergeDuplicateRecords({
      masterRecordId: mergeRequest.masterRecordId,
      duplicateRecordIds: mergeRequest.duplicateRecordIds,
      objectApiName: mergeRequest.objectApiName
    })
      .then((result) => {
        if (result.success) {
          // Create a note with conflict data if needed
          if (this.hasConflicts || this.hasNonMergeableData) {
            return this.createConflictNote(result.masterRecordId);
          }
          return { success: true };
        }
        throw new Error(
          result.errors
            ? result.errors.join(", ")
            : "Unknown error during merge",
        );
      })
      .then(() => {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Success",
            message: "Records merged successfully",
            variant: "success",
          }),
        );

        // Dispatch event to notify parent component
        this.dispatchEvent(
          new CustomEvent("mergesuccess", {
            detail: {
              masterRecordId: this.masterRecordId,
              mergedRecordIds: [this.duplicateRecordId],
            },
          }),
        );
      })
      .catch((error) => {
        this.handleError(error);
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  /**
   * Validate if merge can proceed
   */
  validateMerge() {
    // Check if required fields are selected
    const requiredFields = this.compareFields.filter(
      (field) =>
        this.objectInfo.fields[field.fieldName]?.required &&
        !field.selected &&
        !field.duplicateSelected,
    );

    if (requiredFields.length > 0) {
      const fieldLabels = requiredFields.map((f) => f.label).join(", ");
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error",
          message: `Required fields must be selected: ${fieldLabels}`,
          variant: "error",
        }),
      );
      return false;
    }

    return true;
  }

  /**
   * Build merge request
   */
  buildMergeRequest() {
    // Get all selected fields
    const masterSelectedFields = this.compareFields
      .filter((field) => field.selected)
      .map((field) => field.fieldName);

    const duplicateSelectedFields = this.compareFields
      .filter((field) => field.duplicateSelected)
      .map((field) => field.fieldName);

    // The actual API doesn't support field-level merging, so we're keeping
    // this simple for the demonstration
    return {
      masterRecordId: this.masterRecordId,
      duplicateRecordIds: [this.duplicateRecordId],
      objectApiName: this.objectApiName,
      // These would be used in a real field-level merge implementation
      masterFields: masterSelectedFields,
      duplicateFields: duplicateSelectedFields,
    };
  }

  /**
   * Create note with conflict data
   */
  createConflictNote(recordId) {
    const targetId = recordId || this.masterRecordId;
    const noteContent = this.generateNoteContent();

    // Mock the note creation instead of calling the Apex method
    console.log('Would create note on record:', targetId);
    console.log('Title: Data preserved from merged records');
    console.log('Content:', noteContent);

    // Return a mock success response
    return Promise.resolve({ success: true });
  }

  /**
   * Get mock object info for development purposes
   * @param {String} objectApiName - API name of the object
   * @returns {Object} Mock object info
   */
  getMockObjectInfo(objectApiName) {
    // Create a basic mock object info
    const mockInfo = {
      apiName: objectApiName,
      label: objectApiName,
      labelPlural: objectApiName + 's',
      fields: {},
      childRelationships: []
    };

    // Add some mock fields based on the object type
    const fieldsByObject = {
      Account: ['Name', 'Phone', 'Website', 'Industry', 'BillingCity'],
      Contact: ['FirstName', 'LastName', 'Email', 'Phone', 'Title'],
      Lead: ['FirstName', 'LastName', 'Company', 'Email', 'Phone'],
      Opportunity: ['Name', 'StageName', 'Amount', 'CloseDate']
    };

    // Get fields for this object or use a generic set
    const fields = fieldsByObject[objectApiName] || ['Name', 'CreatedDate', 'LastModifiedDate'];

    // Create mock field metadata
    fields.forEach(fieldName => {
      mockInfo.fields[fieldName] = {
        apiName: fieldName,
        label: fieldName.replace(/([A-Z])/g, ' $1').trim(),
        type: 'STRING',
        required: fieldName === 'Name',
        updateable: true
      };
    });

    return mockInfo;
  }

  /**
   * Handle cancel button
   */
  handleCancel() {
    // Dispatch cancel event
    this.dispatchEvent(new CustomEvent("cancel"));
  }

  /**
   * Handle merge records button
   */
  handleMergeRecords() {
    this.handleMergeSelected();
  }
}
