import { LightningElement, api, track } from "lwc";
import getDuplicateRunResults from "@salesforce/apex/DuplicateRecordController.getDuplicateRunResults";

export default class duplicationDryRunResult extends LightningElement {
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
      pageNumber: this.pageNumber
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
    return (
      this.results &&
      this.results.dryRunResults &&
      this.results.dryRunResults.BatchJobId__c
    );
  }

  // Dry run results
  get dryRunResults() {
    return this.results ? this.results.dryRunResults : null;
  }

  // Format match score for display
  get formattedMatchScore() {
    if (!this.dryRunResults || !this.dryRunResults.AverageMatchScore__c) {
      return "0%";
    }

    const score = Number(this.dryRunResults.AverageMatchScore__c);
    return `${Math.round(score * 100)}%`;
  }

  // Check if we have results to show
  get showResults() {
    return this.results && this.results.dryRunResults;
  }

  // Check if we should show empty state
  get showEmptyState() {
    return !this.isLoading && !this.showResults;
  }

  // Check if we should show draft banner
  get showDraftBanner() {
    // This would need to be implemented based on your draft job storage
    return false;
  }

  // Format date for draft job
  get draftJobDate() {
    // This would need to be implemented based on your draft job storage
    return new Date().toLocaleDateString();
  }

  /**
   * Handle the Run Merge button click
   */
  handleRunMerge() {
    // Fire an event to let parent component know a merge was requested
    const mergeEvent = new CustomEvent("mergerequest", {
      detail: {
        jobId: this.dryRunResults.BatchJobId__c,
        objectApiName: this.dryRunResults.ObjectApiName__c,
        configId: this.configId
      }
    });
    this.dispatchEvent(mergeEvent);
  }

  /**
   * Handle refresh button click
   */
  handleRefresh() {
    this.loadResults();
  }

  /**
   * Handle Save Draft button click
   */
  handleSaveDraft() {
    // Fire an event to let parent component know to save this as a draft
    const draftEvent = new CustomEvent("savedraft", {
      detail: {
        jobId: this.dryRunResults.BatchJobId__c,
        objectApiName: this.dryRunResults.ObjectApiName__c,
        configId: this.configId,
        timestamp: new Date().toISOString()
      }
    });
    this.dispatchEvent(draftEvent);
  }

  /**
   * Handle Load Draft button click
   */
  handleLoadDraft() {
    const loadEvent = new CustomEvent("loaddraft");
    this.dispatchEvent(loadEvent);
  }

  /**
   * Handle Clear Draft button click
   */
  handleClearDraft() {
    const clearEvent = new CustomEvent("cleardraft");
    this.dispatchEvent(clearEvent);
  }
}
