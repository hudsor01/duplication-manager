import { LightningElement, track, wire } from "lwc";
import { MessageContext } from "lightning/messageService";
import { subscribeToChannel, sendMessage, MESSAGE_TYPES } from "c/duplicationMessageService";
import { handleError } from "c/duplicationErrorService";
import {
    getAvailableDuplicateRules,
    getAvailableFields,
    runDuplicate,
    checkJobStatus,
    getRecentDuplicateJobs
} from "c/duplicationDataService";
import { BATCH_SIZES, COMMON_OBJECTS } from "c/duplicationConstants";
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

/**
 * Main component for Duplicate Manager application
 * Provides configuration interface and job control
 * Uses the refactored service architecture
 */
export default class DuplicationManager extends LightningElement {
    // Configuration options
    @track objectOptions = COMMON_OBJECTS;
    @track batchSizeOptions = BATCH_SIZES;

    // Selected configuration
    @track selectedObject = '';
    @track batchSize = 200;
    @track isDryRun = true;
    @track availableFields = [];
    @track selectedAdditionalFields = [];
    @track duplicateRules = [];
    @track selectedDuplicateRuleId = '';

    // Job state
    @track isLoading = false;
    @track currentJobId = null;
    @track jobStatus = null;
    @track recentJobs = [];
    @track statusPollingInterval = null;

    // UI state
    @track showResults = false;
    @track error = null;

    // Subscription for messages
    subscription = null;

    // Message context for LMS
    @wire(MessageContext) messageContext;

    /**
     * Connected callback - setup component
     */
    connectedCallback() {
        // Subscribe to messages
        this.subscription = subscribeToChannel((message) => {
            if (message.type === MESSAGE_TYPES.JOB_STATUS_UPDATED &&
                message.payload && message.payload.jobId === this.currentJobId) {
                this.jobStatus = message.payload;
            } else if (message.type === MESSAGE_TYPES.JOB_COMPLETED &&
                       message.payload && message.payload.jobId === this.currentJobId) {
                this.stopStatusPolling();
                this.loadRecentJobs();
            }
        });

        // Load recent jobs
        this.loadRecentJobs();
    }

    /**
     * Disconnected callback - cleanup
     */
    disconnectedCallback() {
        // Stop status polling
        this.stopStatusPolling();
    }

    /**
     * Handle object selection change
     */
    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.availableFields = [];
        this.selectedAdditionalFields = [];
        this.duplicateRules = [];
        this.selectedDuplicateRuleId = '';

        if (this.selectedObject) {
            this.loadFields();
            this.loadDuplicateRules();
        }
    }

    /**
     * Load available fields for the selected object
     */
    loadFields() {
        this.isLoading = true;

        getAvailableFields(this.selectedObject)
            .then(result => {
                this.availableFields = result;
                this.isLoading = false;
            })
            .catch(error => {
                this.isLoading = false;
                handleError('duplicateManager', 'loadFields', error);
            });
    }

    /**
     * Load available duplicate rules for the selected object
     */
    loadDuplicateRules() {
        this.isLoading = true;

        getAvailableDuplicateRules(this.selectedObject)
            .then(result => {
                this.duplicateRules = result.map(rule => ({
                    label: rule.label,
                    value: rule.id
                }));
                this.isLoading = false;
            })
            .catch(error => {
                this.isLoading = false;
                handleError('duplicateManager', 'loadDuplicateRules', error);
            });
    }

    /**
     * Handle batch size change
     */
    handleBatchSizeChange(event) {
        this.batchSize = parseInt(event.detail.value, 10);
    }

    /**
     * Handle dry run toggle
     */
    handleDryRunChange(event) {
        this.isDryRun = event.target.checked;
    }

    /**
     * Handle selected duplicate rule change
     */
    handleDuplicateRuleChange(event) {
        this.selectedDuplicateRuleId = event.detail.value;
    }

    /**
     * Handle selected additional fields change
     */
    handleAdditionalFieldsChange(event) {
        this.selectedAdditionalFields = event.detail.value;
    }

    /**
     * Start a duplicate job
     */
    startJob() {
        if (!this.validateInputs()) {
            return;
        }

        this.isLoading = true;

        // Create config object for the job
        const config = {
            objectName: this.selectedObject,
            duplicateRuleId: this.selectedDuplicateRuleId,
            additionalFields: this.selectedAdditionalFields,
            batchSize: this.batchSize,
            isDryRun: this.isDryRun
        };

        runDuplicate(config)
            .then(jobId => {
                this.currentJobId = jobId;
                this.loadJobStatus();
                this.startStatusPolling();
                this.showResults = true;
                this.isLoading = false;
            })
            .catch(error => {
                this.isLoading = false;
                handleError('duplicateManager', 'startJob', error);
            });
    }

    /**
     * Load status of current job
     */
    loadJobStatus() {
        if (!this.currentJobId) {
            return;
        }

        checkJobStatus(this.currentJobId)
            .then(result => {
                this.jobStatus = result;

                // Stop polling if job is complete
                if (this.jobStatus.status === 'Completed' ||
                    this.jobStatus.status === 'Failed' ||
                    this.jobStatus.status === 'Aborted') {
                    this.stopStatusPolling();
                    this.loadRecentJobs();
                }
            })
            .catch(error => {
                this.stopStatusPolling();
                handleError('duplicateManager', 'loadJobStatus', error);
            });
    }

    /**
     * Load recent jobs
     */
    loadRecentJobs() {
        getRecentDuplicateJobs()
            .then(result => {
                this.recentJobs = result;
            })
            .catch(error => {
                handleError('duplicateManager', 'loadRecentJobs', error);
            });
    }

    /**
     * Start polling for job status
     */
    startStatusPolling() {
        this.stopStatusPolling();
        this.statusPollingInterval = setInterval(() => {
            this.loadJobStatus();
        }, 5000); // Poll every 5 seconds
    }

    /**
     * Stop polling for job status
     */
    stopStatusPolling() {
        if (this.statusPollingInterval) {
            clearInterval(this.statusPollingInterval);
            this.statusPollingInterval = null;
        }
    }

    /**
     * Validate inputs before starting job
     */
    validateInputs() {
        if (!this.selectedObject) {
            this.showToast('Error', 'Please select an object', 'error');
            return false;
        }

        if (!this.selectedDuplicateRuleId) {
            this.showToast('Error', 'Please select a duplicate rule', 'error');
            return false;
        }

        return true;
    }

    /**
     * Show toast message
     */
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

    /**
     * Navigate to job config tab
     */
    showConfig() {
        this.showResults = false;
    }

    /**
     * Navigate to results tab
     */
    showJobResults() {
        this.showResults = true;
        this.loadRecentJobs();
    }

    /**
     * Start a new run with the same configuration
     */
    runAgain() {
        this.startJob();
    }

    // Computed properties

    /**
     * Get CSS class for config tab
     */
    get configTabClass() {
        return this.showResults ? 'slds-tabs_default__item' : 'slds-tabs_default__item slds-is-active';
    }

    /**
     * Get CSS class for results tab
     */
    get resultsTabClass() {
        return this.showResults ? 'slds-tabs_default__item slds-is-active' : 'slds-tabs_default__item';
    }

    /**
     * Get CSS class for config content
     */
    get configContentClass() {
        return this.showResults ? 'slds-tabs_default__content slds-hide' : 'slds-tabs_default__content slds-show';
    }

    /**
     * Get CSS class for results content
     */
    get resultsContentClass() {
        return this.showResults ? 'slds-tabs_default__content slds-show' : 'slds-tabs_default__content slds-hide';
    }

    /**
     * Check if duplicate rules are available
     */
    get hasDuplicateRules() {
        return this.duplicateRules && this.duplicateRules.length > 0;
    }

    /**
     * Get message for no duplicate rules
     */
    get noDuplicateRulesMessage() {
        return this.selectedObject && !this.hasDuplicateRules ?
            `No active duplicate rules found for ${this.selectedObject}. Please create a duplicate rule first.` : '';
    }

    /**
     * Check if configuration is disabled
     */
    get isConfigDisabled() {
        return this.isLoading;
    }

    /**
     * Check if duplicate rule selection is disabled
     */
    get isDuplicateRuleDisabled() {
        return this.isLoading || !this.hasDuplicateRules;
    }

    /**
     * Check if run button is disabled
     */
    get isRunButtonDisabled() {
        return this.isLoading || !this.selectedObject || !this.selectedDuplicateRuleId;
    }

    /**
     * Get formatted dry run label
     */
    get formattedDryRunLabel() {
        return this.isDryRun ? 'Yes (Test Mode)' : 'No (Live Mode)';
    }

    /**
     * Get formatted status label
     */
    get statusLabel() {
        return this.jobStatus ? this.jobStatus.status : 'N/A';
    }

    /**
     * Get CSS class for status
     */
    get statusClass() {
        if (!this.jobStatus) return '';

        switch(this.jobStatus.status) {
            case 'Completed':
                return 'slds-text-color_success';
            case 'Failed':
            case 'Aborted':
                return 'slds-text-color_error';
            default:
                return 'slds-text-color_default';
        }
    }

    /**
     * Get job columns for data table
     */
    get jobColumns() {
        return [
            { label: 'Object', fieldName: 'ObjectApiName__c', type: 'text' },
            { label: 'Start Time', fieldName: 'JobStartTime__c', type: 'date',
              typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' } },
            { label: 'Status', fieldName: 'Status__c', type: 'text' },
            { label: 'Records Processed', fieldName: 'RecordsProcessed__c', type: 'number' },
            { label: 'Duplicates Found', fieldName: 'DuplicatesFound__c', type: 'number' },
            { label: 'Records Merged', fieldName: 'RecordsMerged__c', type: 'number' },
            { label: 'Dry Run', fieldName: 'IsDryRun__c', type: 'boolean' }
        ];
    }
}
