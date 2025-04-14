import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

// Import methods from Apex
import findDuplicatesApex from "@salesforce/apex/DuplicateFinderController.findDuplicates";
import getRecentJobsApex from "@salesforce/apex/DuplicateFinderController.getRecentJobs";

// Constants
const BATCH_SIZES = [
  { label: "50 Records", value: "50" },
  { label: "100 Records", value: "100" },
  { label: "200 Records", value: "200" },
  { label: "500 Records", value: "500" },
  { label: "1000 Records", value: "1000" }
];

const OBJECTS = [
  { label: "Account", value: "Account" },
  { label: "Contact", value: "Contact" },
  { label: "Lead", value: "Lead" }
];

export default class DuplicationFinder extends LightningElement {
  @track selectedObject = "";
  @track batchSize = "200";
  @track isDryRun = true;
  @track isLoading = false;
  @track showResults = false;
  @track recentJobs = [];

  // Results
  @track recordsProcessed = 0;
  @track duplicatesFound = 0;
  @track recordsMerged = 0;

  get objectOptions() {
    return OBJECTS;
  }

  get batchSizeOptions() {
    return BATCH_SIZES;
  }

  get isButtonDisabled() {
    return !this.selectedObject || this.isLoading;
  }

  get jobColumns() {
    return [
      { label: "Object", fieldName: "ObjectApiName__c", type: "text" },
      {
        label: "Start Time",
        fieldName: "JobStartTime__c",
        type: "date",
        typeAttributes: {
          year: "numeric",
          month: "short",
          day: "2-digit",
          hour: "2-digit",
          minute: "2-digit"
        }
      },
      { label: "Status", fieldName: "Status__c", type: "text" },
      {
        label: "Records Processed",
        fieldName: "RecordsProcessed__c",
        type: "number"
      },
      {
        label: "Duplicates Found",
        fieldName: "DuplicatesFound__c",
        type: "number"
      },
      {
        label: "Records Merged",
        fieldName: "RecordsMerged__c",
        type: "number"
      },
      { label: "Dry Run", fieldName: "IsDryRun__c", type: "boolean" }
    ];
  }

  connectedCallback() {
    this.loadRecentJobs();
  }

  loadRecentJobs() {
    getRecentJobsApex()
      .then((result) => {
        this.recentJobs = result;
      })
      .catch((error) => {
        console.error("Error loading recent jobs", error);
      });
  }

  handleObjectChange(event) {
    this.selectedObject = event.detail.value;
    this.showResults = false;
  }

  handleBatchSizeChange(event) {
    this.batchSize = event.detail.value;
  }

  handleDryRunChange(event) {
    this.isDryRun = event.target.checked;
  }

  resetForm() {
    this.selectedObject = "";
    this.batchSize = "200";
    this.isDryRun = true;
    this.showResults = false;
  }

  findDuplicates() {
    if (!this.selectedObject) {
      this.showToast("Error", "Please select an object", "error");
      return;
    }

    this.isLoading = true;
    this.showResults = false;

    // Call Apex method
    findDuplicatesApex({
      objectName: this.selectedObject,
      batchSize: parseInt(this.batchSize, 10),
      isDryRun: this.isDryRun
    })
      .then((result) => {
        this.recordsProcessed = result.recordsProcessed || 0;
        this.duplicatesFound = result.duplicatesFound || 0;
        this.recordsMerged = result.recordsMerged || 0;
        this.showResults = true;

        // Refresh the recent jobs list
        this.loadRecentJobs();

        this.showToast(
          "Success",
          `Processed ${this.recordsProcessed} records, found ${this.duplicatesFound} duplicates${this.isDryRun ? " (Dry Run)" : ""}`,
          "success"
        );
      })
      .catch((error) => {
        console.error("Error finding duplicates:", error);
        this.showToast(
          "Error",
          error.body?.message || "An error occurred while finding duplicates",
          "error"
        );
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: title,
        message: message,
        variant: variant
      })
    );
  }
}
