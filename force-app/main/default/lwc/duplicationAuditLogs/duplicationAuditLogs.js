import { LightningElement, api, track, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getMergeJobLogs from "@salesforce/apex/DuplicateRecordLogController.getMergeJobLogs";
import { refreshApex } from "@salesforce/apex";
// import userId from '@salesforce/user/Id';

/**
 * Component for displaying merge job audit logs
 * @component
 */
export default class DuplicationAuditLogs extends LightningElement {
  @api objectApiName;
  @api configId;
  @api recordLimit = 10;

  @track logs = [];
  @track columns = [];
  @track filters = {};
  @track selectedLog;
  @track pagination = {
    pageSize: 10,
    currentPage: 1,
    totalRecords: 0,
    totalPages: 1,
  };

  isLoading = true;
  hasLogs = false;
  error = null;
  showLogDetailsModal = false;
  wiredLogsResult;

  connectedCallback() {
    this.initializeColumns();
    this.initializeFilters();
  }

  /**
   * Wire service to get merge job logs
   */
  @wire(getMergeJobLogs, {
    objectApiName: "$objectApiName",
    configId: "$configId",
    pageSize: "$pagination.pageSize",
    pageNumber: "$pagination.currentPage",
    filters: "$filtersAsJson",
  })
  wiredLogs(result) {
    this.wiredLogsResult = result;
    this.isLoading = true;

    if (result.data) {
      this.processLogData(result.data);
      this.error = null;
    } else if (result.error) {
      this.handleError("Error loading audit logs", result.error);
    }

    this.isLoading = false;
  }

  /**
   * Process log data returned from the wire service
   * @param {Object} data - Log data
   */
  processLogData(data) {
    if (!data) return;

    try {
      this.logs = data.records || [];
      this.hasLogs = this.logs.length > 0;

      // Update pagination
      if (data.pagination) {
        this.pagination = { ...data.pagination };
      }
    } catch (error) {
      this.handleError("Error processing log data", error);
    }
  }

  /**
   * Initialize datatable columns
   */
  initializeColumns() {
    this.columns = [
      {
        label: "Date/Time",
        fieldName: "executionTime",
        type: "date",
        typeAttributes: {
          year: "numeric",
          month: "short",
          day: "2-digit",
          hour: "2-digit",
          minute: "2-digit",
        },
        sortable: true,
      },
      {
        label: "User",
        fieldName: "userName",
        type: "text",
        sortable: true,
      },
      {
        label: "Object",
        fieldName: "objectApiName",
        type: "text",
        sortable: true,
      },
      {
        label: "Configuration",
        fieldName: "configName",
        type: "text",
        sortable: true,
      },
      {
        label: "Records Merged",
        fieldName: "recordsMerged",
        type: "number",
        sortable: true,
      },
      {
        label: "Actions",
        type: "button",
        typeAttributes: {
          label: "View Details",
          name: "view_details",
          title: "View Details",
          variant: "brand",
          iconName: "utility:preview",
          iconPosition: "left",
        },
      },
    ];
  }

  /**
   * Initialize filters
   */
  initializeFilters() {
    this.filters = {
      dateRange: "ALL",
      users: [],
      objectTypes: [],
    };

    // If objectApiName is provided as prop, add to filters
    if (this.objectApiName) {
      this.filters.objectTypes = [this.objectApiName];
    }

    // If configId is provided as prop, add to filters
    if (this.configId) {
      this.filters.configIds = [this.configId];
    }
  }

  /**
   * Handle row action from datatable
   * @param {Event} event - Row action event
   */
  handleRowAction(event) {
    const action = event.detail.action;
    const row = event.detail.row;

    switch (action.name) {
      case "view_details":
        this.viewLogDetails(row);
        break;
      default:
        break;
    }
  }

  /**
   * View log details
   * @param {Object} log - Log to view
   */
  viewLogDetails(log) {
    this.selectedLog = log;
    this.showLogDetailsModal = true;
  }

  /**
   * Close log details modal
   */
  closeDetailsModal() {
    this.showLogDetailsModal = false;
    this.selectedLog = null;
  }

  /**
   * Handle filter change
   * @param {Event} event - Filter change event
   */
  handleFilterChange(event) {
    const filterName = event.target.dataset.filter;
    const value = event.target.value;

    if (filterName) {
      this.filters = { ...this.filters, [filterName]: value };
      this.resetPagination();
    }
  }

  /**
   * Handle date range filter change
   * @param {Event} event - Date range change event
   */
  handleDateRangeChange(event) {
    const range = event.target.value;
    this.filters.dateRange = range;
    this.resetPagination();
  }

  /**
   * Reset pagination to first page
   */
  resetPagination() {
    this.pagination.currentPage = 1;
  }

  /**
   * Refresh logs
   */
  refreshLogs() {
    this.isLoading = true;

    return refreshApex(this.wiredLogsResult).finally(() => {
      this.isLoading = false;
    });
  }

  /**
   * Handle error
   * @param {String} message - Error message
   * @param {Error} error - Error object
   */
  handleError(message, error) {
    let errorMessage = message;

    if (error) {
      if (error.body && error.body.message) {
        errorMessage += ": " + error.body.message;
      } else if (error.message) {
        errorMessage += ": " + error.message;
      }
    }

    this.error = errorMessage;
    this.isLoading = false;

    this.dispatchEvent(
      new ShowToastEvent({
        title: "Error",
        message: errorMessage,
        variant: "error",
      }),
    );
  }

  /**
   * Handle previous page click
   */
  handlePreviousPage() {
    if (this.pagination.currentPage > 1) {
      this.pagination = {
        ...this.pagination,
        currentPage: this.pagination.currentPage - 1,
      };
    }
  }

  /**
   * Handle next page click
   */
  handleNextPage() {
    if (this.pagination.currentPage < this.pagination.totalPages) {
      this.pagination = {
        ...this.pagination,
        currentPage: this.pagination.currentPage + 1,
      };
    }
  }

  /**
   * Handle page size change
   * @param {Event} event - Page size change event
   */
  handlePageSizeChange(event) {
    const pageSize = parseInt(event.target.value, 10);

    if (!isNaN(pageSize) && pageSize > 0) {
      this.pagination = {
        ...this.pagination,
        pageSize,
        currentPage: 1,
      };
    }
  }

  /**
   * Formatted date range options
   */
  get dateRangeOptions() {
    return [
      { label: "All Time", value: "ALL" },
      { label: "Today", value: "TODAY" },
      { label: "Yesterday", value: "YESTERDAY" },
      { label: "This Week", value: "THIS_WEEK" },
      { label: "This Month", value: "THIS_MONTH" },
      { label: "Last Month", value: "LAST_MONTH" },
      { label: "This Year", value: "THIS_YEAR" },
    ];
  }

  /**
   * Get filters as JSON for wire service
   */
  get filtersAsJson() {
    return JSON.stringify(this.filters);
  }

  /**
   * Check if it's the first page
   */
  get isFirstPage() {
    return this.pagination.currentPage <= 1;
  }

  /**
   * Check if it's the last page
   */
  get isLastPage() {
    return this.pagination.currentPage >= this.pagination.totalPages;
  }

  /**
   * Get pagination label
   */
  get paginationLabel() {
    return `Page ${this.pagination.currentPage} of ${this.pagination.totalPages}`;
  }

  /**
   * Get page size options
   */
  get pageSizeOptions() {
    return [
      { label: "10 records", value: "10" },
      { label: "25 records", value: "25" },
      { label: "50 records", value: "50" },
      { label: "100 records", value: "100" },
    ];
  }
}
