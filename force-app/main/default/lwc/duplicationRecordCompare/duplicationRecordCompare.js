import { LightningElement, api, track } from 'lwc';
import getRecordsForComparison from '@salesforce/apex/DRCCompare.getRecordsForComparison';

/**
 * Component for side-by-side record comparison
 * Shows differences between records to help with duplicate management
 */
export default class DuplicationRecordCompare extends LightningElement {
    @api recordId1;
    @api recordId2;
    @api objectApiName;
    @api group;
    
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

    // Update records when group changes
    @api
    updateFromGroup(value) {
        this._group = value;
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
        if (!this.fieldData || this.fieldData.length === 0) {
            return;
        }
        
        // Apply styling to field values
        var fieldValues = this.template.querySelectorAll('.field-value');
        for (var i = 0; i < fieldValues.length; i++) {
            var element = fieldValues[i];
            var fieldId = element.dataset.id;
            
            // Find the field in fieldData
            var field = null;
            for (var j = 0; j < this.fieldData.length; j++) {
                if (this.fieldData[j].field === fieldId) {
                    field = this.fieldData[j];
                    break;
                }
            }
            
            if (field && field.isDifferent) {
                element.classList.add('slds-text-color_error');
            }
            
            // Add standard classes
            element.classList.add('slds-item_detail', 'slds-truncate');
        }
        
        // Apply styling to table rows
        var fieldRows = this.template.querySelectorAll('.field-row');
        for (var k = 0; k < fieldRows.length; k++) {
            var rowElement = fieldRows[k];
            var rowFieldId = rowElement.dataset.id;
            
            // Find the field in fieldData
            var rowField = null;
            for (var m = 0; m < this.fieldData.length; m++) {
                if (this.fieldData[m].field === rowFieldId) {
                    rowField = this.fieldData[m];
                    break;
                }
            }
            
            if (rowField && rowField.isDifferent) {
                rowElement.classList.add('slds-is-selected');
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
                    this.recordId1 = this.group.duplicateRecordIds[0];
                    this.recordId2 = this.group.duplicateRecordIds[1];
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
            .then(result => {
                if (result) {
                    this.record1 = result.record1;
                    this.record2 = result.record2;
                    this.fieldData = result.fieldDifferences;
                    // Application of styling will happen in renderedCallback
                }
                this.isLoading = false;
            })
            .catch(error => {
                this.error = error.message ? error.message : 'Error retrieving record data';
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
        var recordIds = [recordId1, recordId2];
        
        const params = {
            recordIds: recordIds,
            objectApiName: this.objectApiName
        };
        
        return getRecordsForComparison(params)
            .then(result => {
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
        if (!result || !result.records) {
            return null;
        }
        
        // Extract records from the result
        var records = result.records;
        var record1 = null;
        var record2 = null;
        
        // Find each record by ID
        for (var i = 0; i < records.length; i++) {
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
        var fields = result.fields || [];
        var fieldDifferences = [];
        
        for (var j = 0; j < fields.length; j++) {
            var fieldName = fields[j];
            var value1 = record1[fieldName];
            var value2 = record2[fieldName];
            var isDifferent = false;
            
            // Handle null values
            if (value1 === null) value1 = '';
            if (value2 === null) value2 = '';
            
            // Convert to string for comparison
            value1 = String(value1);
            value2 = String(value2);
            
            // Check if values are different
            isDifferent = value1 !== value2;
            
            // Get a more user-friendly field label
            var fieldLabel = this.formatFieldName(fieldName);
            
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
        if (!fieldName) return '';
        
        // Split by underscore or camel case
        var words = fieldName.replace(/_/g, ' ').split(/(?=[A-Z])/);
        
        // Capitalize first letter of each word
        for (var i = 0; i < words.length; i++) {
            if (words[i].length > 0) {
                words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1);
            }
        }
        
        return words.join(' ').replace('__c', '');
    }

    /**
     * Refresh the comparison
     */
    @api
    refresh() {
        this.loadRecords();
    }
}