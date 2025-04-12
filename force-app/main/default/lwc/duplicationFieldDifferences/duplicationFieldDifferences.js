import { LightningElement, api, track } from "lwc";

/**
 * Component to display field differences between duplicate records
 * @component
 */
export default class DuplicationFieldDifferences extends LightningElement {
  @api records = [];
  @api fieldInfos = [];
  @api masterRecordId;

  @track fieldDifferences = [];

  /**
   * Lifecycle hook - Called when properties change
   */
  renderedCallback() {
    this.calculateFieldDifferences();
  }

  /**
   * Calculate field differences between records
   */
  calculateFieldDifferences() {
    if (!this.records || !this.fieldInfos) return;

    const differences = [];

    // For each field, check if there are different values
    this.fieldInfos.forEach((field) => {
      const fieldName = field.apiName;
      const values = new Set();

      // Collect all unique values for this field
      this.records.forEach((record) => {
        if (record.fields && record.fields[fieldName]) {
          values.add(record.fields[fieldName].value);
        }
      });

      // If there's more than one unique value, we have differences
      if (values.size > 1) {
        // Get the master record value
        let masterValue = "";
        const masterRecord = this.records.find(
          (r) => r.id === this.masterRecordId,
        );
        if (
          masterRecord &&
          masterRecord.fields &&
          masterRecord.fields[fieldName]
        ) {
          masterValue =
            masterRecord.fields[fieldName].displayValue ||
            masterRecord.fields[fieldName].value;
        }

        // Get other values (different from master)
        const otherValues = [];
        this.records.forEach((record) => {
          if (
            record.id !== this.masterRecordId &&
            record.fields &&
            record.fields[fieldName]
          ) {
            const value =
              record.fields[fieldName].displayValue ||
              record.fields[fieldName].value;
            if (value !== masterValue && value) {
              otherValues.push(value);
            }
          }
        });

        // Add to differences
        differences.push({
          field: fieldName,
          fieldLabel: field.label,
          masterValue: masterValue,
          otherValues: otherValues,
          valueCount: values.size,
        });
      }
    });

    this.fieldDifferences = differences;
  }

  /**
   * Check if there are field differences
   */
  get hasDifferences() {
    return this.fieldDifferences.length > 0;
  }
}
