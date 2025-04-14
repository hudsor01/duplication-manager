/**
 * Constants used throughout the duplicate Manager application
 */

// Status values for duplicate records
export const DUPLICATE_STATUS = {
  NEW: "New",
  REVIEWED: "Reviewed",
  MERGED: "Merged",
  IGNORED: "Ignored"
};

// Types of merge operations
export const MERGE_TYPES = {
  AUTOMATIC: "Automatic",
  MANUAL: "Manual"
};

// Status values for jobs
export const JOB_STATUS = {
  SCHEDULED: "Scheduled",
  RUNNING: "Running",
  COMPLETED: "Completed",
  FAILED: "Failed",
  QUEUED: "Queued",
  PROCESSING: "Processing",
  HOLDING: "Holding",
  PREPARING: "Preparing",
  ABORTED: "Aborted"
};

// Message types for LMS communication
export const MESSAGE_TYPES = {
  // Storage events
  STORE_UPDATED: "STORE_UPDATED",
  STORE_SECTION_UPDATED: "STORE_SECTION_UPDATED",

  // Job events
  JOB_STARTING: "JOB_STARTING",
  JOB_STARTED: "JOB_STARTED",
  JOB_COMPLETED: "JOB_COMPLETED",
  JOB_ERROR: "JOB_ERROR",
  JOB_STATUS_UPDATED: "JOB_STATUS_UPDATED",

  // Statistics events
  STATISTICS_LOADING: "STATISTICS_LOADING",
  STATISTICS_LOADED: "STATISTICS_LOADED",
  STATISTICS_LOAD_ERROR: "STATISTICS_LOAD_ERROR",

  // Duplicate groups events
  DUPLICATE_GROUP_SELECTED: "DUPLICATE_GROUP_SELECTED",
  GROUPS_LOADING: "GROUPS_LOADING",
  GROUPS_LOADED: "GROUPS_LOADED",
  DUPLICATE_GROUPS_ERROR: "DUPLICATE_GROUPS_ERROR",

  // Duplicate view events
  DUPLICATES_FOUND: "DUPLICATES_FOUND",
  MERGE_PREVIEW: "MERGE_PREVIEW",
  DUPLICATES_MERGED: "DUPLICATES_MERGED",
  MERGE_RECORD_SELECTED: "MERGE_RECORD_SELECTED",
  MASTER_RECORD_CHANGED: "MASTER_RECORD_CHANGED",
  FIELD_SELECTION_CHANGED: "FIELD_SELECTION_CHANGED",

  // Merge events
  MERGE_STARTED: "MERGE_STARTED",
  MERGE_COMPLETED: "MERGE_COMPLETED",
  MERGE_ERROR: "MERGE_ERROR",
  MERGE_OPERATION: "MERGE_OPERATION",
  MERGE_GROUP_REQUEST: "MERGE_GROUP_REQUEST",

  // Merge process events
  GROUP_MERGE_STARTING: "GROUP_MERGE_STARTING",
  GROUP_MERGE_COMPLETED: "GROUP_MERGE_COMPLETED",
  GROUP_MERGE_ERROR: "GROUP_MERGE_ERROR",
  BULK_MERGE_STARTING: "BULK_MERGE_STARTING",
  BULK_MERGE_COMPLETED: "BULK_MERGE_COMPLETED",

  // Modal events
  COMPARISON_MODAL_OPENED: "COMPARISON_MODAL_OPENED",
  COMPARISON_MODAL_CLOSED: "COMPARISON_MODAL_CLOSED",
  MASTER_PREVIEW_MODAL_OPENED: "MASTER_PREVIEW_MODAL_OPENED",
  MASTER_PREVIEW_MODAL_CLOSED: "MASTER_PREVIEW_MODAL_CLOSED",
  NOTE_PREVIEW_MODAL_OPENED: "NOTE_PREVIEW_MODAL_OPENED",
  NOTE_PREVIEW_MODAL_CLOSED: "NOTE_PREVIEW_MODAL_CLOSED",

  // UI state events
  REFRESH_STARTED: "REFRESH_STARTED",
  REFRESH_STATISTICS: "REFRESH_STATISTICS",
  TIME_RANGE_CHANGED: "TIME_RANGE_CHANGED",
  CONFIG_SELECTED: "CONFIG_SELECTED",
  OBJECT_TYPE_CHANGED: "OBJECT_TYPE_CHANGED",
  SELECTION_CHANGED: "SELECTION_CHANGED",
  FIELDS_SELECTED: "FIELDS_SELECTED",
  CHANGE_TAB: "CHANGE_TAB",
  VIEW_CHANGE: "VIEW_CHANGE",

  // Notification events
  TOAST_NOTIFICATION: "TOAST_NOTIFICATION",

  // UI control events
  OPEN_SETTINGS: "OPEN_SETTINGS",
  OPEN_QUICK_FIND: "OPEN_QUICK_FIND",
  OPEN_QUICK_MERGE: "OPEN_QUICK_MERGE",
  QUICK_FIND_DUPLICATES: "QUICK_FIND_DUPLICATES",
  QUICK_MERGE_DUPLICATES: "QUICK_MERGE_DUPLICATES",

  // Error events
  ERROR_OCCURRED: "ERROR_OCCURRED",
  ERROR_CLEARED: "ERROR_CLEARED"
};

// Time range options for filtering
export const TIME_RANGES = {
  TODAY: "TODAY",
  YESTERDAY: "YESTERDAY",
  THIS_WEEK: "THIS_WEEK",
  LAST_WEEK: "LAST_WEEK",
  THIS_MONTH: "THIS_MONTH",
  LAST_MONTH: "LAST_MONTH",
  LAST_30_DAYS: "LAST_30_DAYS",
  LAST_60_DAYS: "LAST_60_DAYS",
  LAST_90_DAYS: "LAST_90_DAYS",
  THIS_YEAR: "THIS_YEAR",
  LAST_7_DAYS: "LAST_7_DAYS",
  THIS_QUARTER: "THIS_QUARTER",
  LAST_QUARTER: "LAST_QUARTER",
  LAST_YEAR: "LAST_YEAR",
  ALL: "ALL"
};

// Match types for duplicate detection
export const MATCH_TYPES = {
  EXACT: "Exact",
  FUZZY: "Fuzzy",
  PHONETIC: "Phonetic"
};

// Field selection strategies for merges
export const FIELD_SELECTION = {
  MASTER_WINS: "MasterWins",
  MOST_RECENT: "MostRecent",
  NON_BLANK: "NonBlank",
  MANUAL: "Manual"
};

// Batch job sizes
export const BATCH_SIZES = [
  { label: "Small (200 records)", value: 200 },
  { label: "Medium (500 records)", value: 500 },
  { label: "Large (1000 records)", value: 1000 },
  { label: "Very Large (2000 records)", value: 2000 }
];

// Duplicate matching strategies
export const MATCH_STRATEGIES = {
  EXACT: "exact",
  FUZZY: "fuzzy",
  PHONETIC: "phonetic",
  DISTANCE: "distance",
  CUSTOM: "custom"
};

// Master record selection strategies
export const MASTER_RECORD_STRATEGIES = {
  MOST_RECENT: "mostRecent",
  OLDEST: "oldest",
  MOST_COMPLETE: "mostComplete",
  MOST_ACTIVITY: "mostActivity",
  CUSTOM: "custom"
};

// Chart types for visualization
export const CHART_TYPES = {
  BAR: "bar",
  LINE: "line",
  PIE: "pie",
  DONUT: "doughnut",
  RADAR: "radar"
};

// View modes for UI components
export const VIEW_MODES = {
  CARD: "card",
  TABLE: "table",
  LIST: "list",
  COMPACT: "compact",
  DETAILED: "detailed"
};

// Object types commonly processed for duplicate
export const COMMON_OBJECTS = [
  { label: "Account", value: "Account" },
  { label: "Contact", value: "Contact" },
  { label: "Lead", value: "Lead" },
  { label: "Opportunity", value: "Opportunity" },
  { label: "Case", value: "Case" }
];

// Column definitions for data tables
export const COLUMN_DEFINITIONS = {
  JOB_HISTORY: [
    { label: "Object", fieldName: "objectApiName", type: "text" },
    { label: "Status", fieldName: "status", type: "text" },
    { label: "Duplicates", fieldName: "duplicatesFound", type: "number" },
    { label: "Merged", fieldName: "recordsMerged", type: "number" },
    {
      label: "Date",
      fieldName: "startTime",
      type: "date",
      typeAttributes: {
        year: "numeric",
        month: "short",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit"
      }
    }
  ],
  SCHEDULED_JOBS: [
    { label: "Job Name", fieldName: "name", type: "text" },
    { label: "Object", fieldName: "objectApiName", type: "text" },
    {
      label: "Next Run",
      fieldName: "nextFireTime",
      type: "date",
      typeAttributes: {
        year: "numeric",
        month: "short",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit"
      }
    },
    { label: "Status", fieldName: "state", type: "text" }
  ]
};

// Field types for UI rendering
export const FIELD_TYPES = {
  TEXT: "text",
  NUMBER: "number",
  BOOLEAN: "boolean",
  DATE: "date",
  DATETIME: "datetime",
  PICKLIST: "picklist",
  MULTIPICKLIST: "multipicklist",
  REFERENCE: "reference",
  EMAIL: "email",
  PHONE: "phone",
  URL: "url",
  CURRENCY: "currency",
  PERCENT: "percent",
  TEXTAREA: "textarea",
  RICHTEXT: "richtext"
};
