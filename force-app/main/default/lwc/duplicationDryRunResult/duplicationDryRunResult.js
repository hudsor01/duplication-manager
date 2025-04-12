import { LightningElement, api, track } from "lwc";
import getDuplicateRunResults from "@salesforce/apex/DuplicateRecordController.getDuplicateRunResults";

export default class DuplicationDryRunResult extends LightningElement {
  @api batchJobId;
  @api objectApiName;
  @api recordId;
  @api configId;
  @track results;
  @track isLoading = true;
  @track error;

  // Pagination
  @track pageSize = 10;
  @track pageNumber = 1;
  @track totalPages = 0;
  @track totalRecords = 0;

  connectedCallback() {
    this.loadResults();
  }

  loadResults() {
    this.isLoading = true;
    getDuplicateRunResults({
      batchJobId: this.batchJobId,
      pageSize: this.pageSize,
      pageNumber: this.pageNumber,
    })
      .then((result) => {
        this.results = result;
        this.totalPages = result.pagination.totalPages;
        this.totalRecords = result.pagination.totalRecords;
        this.error = undefined;
      })
      .catch((error) => {
        this.error = error.message || "An error occurred loading the results";
        this.results = undefined;
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  // Navigation methods
  nextPage() {
    if (this.pageNumber < this.totalPages) {
      this.pageNumber++;
      this.loadResults();
    }
  }

  prevPage() {
    if (this.pageNumber > 1) {
      this.pageNumber--;
      this.loadResults();
    }
  }

  // Getters for UI display
  get hasResults() {
    return (
      this.results && this.results.groups && this.results.groups.length > 0
    );
  }

  get summary() {
    return this.results ? this.results.summary : null;
  }

  get groups() {
    return this.hasResults ? this.results.groups : [];
  }

  get hasPrevious() {
    return this.pageNumber > 1;
  }

  get hasNext() {
    return this.pageNumber < this.totalPages;
  }

  get paginationText() {
    return `Page ${this.pageNumber} of ${this.totalPages}`;
  }

  // Add hasBatchJobId getter for the template
  get hasBatchJobId() {
    return this.results && this.results.dryRunResults && this.results.dryRunResults.BatchJobId__c;
  }
}
