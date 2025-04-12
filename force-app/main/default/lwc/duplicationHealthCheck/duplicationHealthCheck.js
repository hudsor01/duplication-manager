import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import checkDuplicateHealth from "@salesforce/apex/DuplicateHealthController.checkHealth";

/**
 * Component for checking the health of duplication settings and objects
 * Supported targets: lightning__AppPage, lightning__RecordPage, lightning__HomePage, lightningCommunity__Page
 */
export default class DuplicationHealthCheck extends LightningElement {
  @api recordId;
  @track isLoading = false;
  @track healthResults;
  @track error;

  // Lightning page region width - works for standard and community pages
  @api flexipageRegionWidth;

  // Community-specific properties
  @api communityName;

  // Configuration properties
  @api configId;
  @api objectApiName;

  runHealthChecks() {
    this.isLoading = true;
    this.error = null;

    checkDuplicateHealth()
      .then((results) => {
        this.healthResults = results;
        this.error = null;
      })
      .catch((error) => {
        this.healthResults = null;
        this.error = error.body ? error.body.message : "Unknown error";
        this.showToast("Error", this.error, "error");
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  // Show toast notification
  showToast(title, message, variant) {
    const evt = new ShowToastEvent({
      title: title,
      message: message,
      variant: variant,
    });
    this.dispatchEvent(evt);
  }

  // Getters for UI
  get hasResults() {
    return this.healthResults && this.healthResults.length > 0;
  }

  get hasError() {
    return this.error !== null && this.error !== undefined;
  }

  get hasIssues() {
    return this.healthResults && this.healthResults.length > 0;
  }

  get healthIssues() {
    if (!this.healthResults) {
      return [];
    }

    // Map health results to include helper properties for the template
    return this.healthResults.map((issue, index) => {
      return {
        ...issue,
        id: issue.id || `issue-${index}`,
        isError: issue.severity === "error",
        isWarning: issue.severity === "warning",
        isInfo: issue.severity === "info" || !issue.severity,
      };
    });
  }

  get errorCount() {
    return this.healthResults
      ? this.healthResults.filter((issue) => issue.severity === "error").length
      : 0;
  }

  get warningCount() {
    return this.healthResults
      ? this.healthResults.filter((issue) => issue.severity === "warning")
          .length
      : 0;
  }

  get infoCount() {
    return this.healthResults
      ? this.healthResults.filter(
          (issue) => issue.severity === "info" || !issue.severity,
        ).length
      : 0;
  }

  get hasErrors() {
    return this.errorCount > 0;
  }

  get hasWarnings() {
    return this.warningCount > 0;
  }
}
