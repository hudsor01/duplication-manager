# Duplication Manager Application

This document outlines the structure and component relationships for the Duplication Manager application.

## Component Hierarchy

```
duplicationManagerApp (Main container component)
├── duplicationTabbedInterface
│   ├── duplicationDashboard
│   │   ├── duplicationDashboardCard
│   │   └── duplicationStatsSummary
│   ├── duplicationConfigSelector
│   ├── duplicationBatchController
│   │   ├── duplicationJobProgress
│   │   └── duplicationDryRunResult
│   ├── duplicationJobManager
│   │   └── duplicationManagerJobs
│   ├── duplicationAuditLogs
│   └── duplicationHealthCheck
├── duplicationSideBySideCompare
│   ├── duplicationFieldDifferences
│   └── duplicationMasterPreview
├── duplicationMergeGroups
├── scheduleJobModal
└── duplicationManagerScheduler
```

## Communication Architecture

The application uses Lightning Message Service (LMS) as the primary communication mechanism between components with the `DuplicationChannel_c` message channel.

Some components may still use the legacy `duplicationPubSub` pattern which should be gradually migrated to LMS.

## Data Model

The application uses the following custom objects:

1. **DuplicateFinderSettings\_\_c** - Stores configuration for duplicate detection

   - Key Fields:
     - BatchSize\_\_c
     - IsActive\_\_c
     - MasterRecordStrategy\_\_c
     - MatchFields\_\_c
     - ObjectAPIName\_\_c

2. **DuplicateJobStatistic\_\_c** - Statistics for duplicate jobs

3. **DuplicateMergeLog\_\_c** - Logs of merge operations

4. **DuplicateGroupDetail\_\_c** - Details of duplicate groups

## Implementation Notes

1. Component naming follows the pattern "duplication[ComponentName]"
2. All components use the Lightning Design System (SLDS) for styling
3. State management is handled through the `duplicationStore` component

## Important Notes

- The application requires appropriate permissions for custom objects
- The Lightning Message Service channel (DuplicationChannel_c) must be deployed
- Batch processing can impact Salesforce governor limits; ensure proper optimization
