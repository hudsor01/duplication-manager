/**
 * Constants used throughout the Duplication Manager application
 */

// Status values for duplicate records
export const DUPLICATE_STATUS = {
  NEW: "New",
  REVIEWED: "Reviewed",
  MERGED: "Merged",
  IGNORED: "Ignored",
};

// Types of merge operations
export const MERGE_TYPES = {
  AUTOMATIC: "Automatic",
  MANUAL: "Manual",
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
  PHONETIC: "Phonetic",
};

// Field selection strategies for merges
export const FIELD_SELECTION = {
  MASTER_WINS: "MasterWins",
  MOST_RECENT: "MostRecent",
  NON_BLANK: "NonBlank",
  MANUAL: "Manual",
};

// Batch job sizes
export const BATCH_SIZES = [
  { label: "Small (200 records)", value: 200 },
  { label: "Medium (500 records)", value: 500 },
  { label: "Large (1000 records)", value: 1000 },
  { label: "Very Large (2000 records)", value: 2000 },
];

// Duplicate matching strategies
export const MATCH_STRATEGIES = {
  EXACT: 'exact',
  FUZZY: 'fuzzy',
  PHONETIC: 'phonetic',
  DISTANCE: 'distance',
  CUSTOM: 'custom'
};

// Master record selection strategies
export const MASTER_RECORD_STRATEGIES = {
  MOST_RECENT: 'mostRecent',
  OLDEST: 'oldest',
  MOST_COMPLETE: 'mostComplete',
  MOST_ACTIVITY: 'mostActivity',
  CUSTOM: 'custom'
};

// Chart types for visualization
export const CHART_TYPES = {
  BAR: 'bar',
  LINE: 'line',
  PIE: 'pie',
  DONUT: 'doughnut',
  RADAR: 'radar'
};

// View modes for UI components
export const VIEW_MODES = {
  CARD: 'card',
  TABLE: 'table',
  LIST: 'list',
  COMPACT: 'compact',
  DETAILED: 'detailed'
};

// Object types commonly processed for duplication
export const COMMON_OBJECTS = {
  ACCOUNT: 'Account',
  CONTACT: 'Contact',
  LEAD: 'Lead',
  OPPORTUNITY: 'Opportunity',
  CASE: 'Case',
  CUSTOM_OBJECT: 'CustomObject'
};

// Column definitions for data tables
export const COLUMN_DEFINITIONS = {
  JOB_HISTORY: [
    { label: 'Object', fieldName: 'objectApiName', type: 'text' },
    { label: 'Status', fieldName: 'status', type: 'text' },
    { label: 'Duplicates', fieldName: 'duplicatesFound', type: 'number' },
    { label: 'Merged', fieldName: 'recordsMerged', type: 'number' },
    { label: 'Date', fieldName: 'startTime', type: 'date',
      typeAttributes: {
          year: 'numeric',
          month: 'short',
          day: '2-digit',
          hour: '2-digit',
          minute: '2-digit'
      }
    }
  ],
  SCHEDULED_JOBS: [
    { label: 'Job Name', fieldName: 'name', type: 'text' },
    { label: 'Object', fieldName: 'objectApiName', type: 'text' },
    { label: 'Next Run', fieldName: 'nextFireTime', type: 'date',
      typeAttributes: {
          year: 'numeric',
          month: 'short',
          day: '2-digit',
          hour: '2-digit',
          minute: '2-digit'
      }
    },
    { label: 'Status', fieldName: 'state', type: 'text' }
  ]
};

// Field types for UI rendering
export const FIELD_TYPES = {
  TEXT: 'text',
  NUMBER: 'number',
  BOOLEAN: 'boolean',
  DATE: 'date',
  DATETIME: 'datetime',
  PICKLIST: 'picklist',
  MULTIPICKLIST: 'multipicklist',
  REFERENCE: 'reference',
  EMAIL: 'email',
  PHONE: 'phone',
  URL: 'url',
  CURRENCY: 'currency',
  PERCENT: 'percent',
  TEXTAREA: 'textarea',
  RICHTEXT: 'richtext'
};
