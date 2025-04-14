# Duplication Manager for Salesforce

## Overview

Duplication Manager is a robust Salesforce application for detecting, comparing, and merging duplicate records across your Salesforce org. The solution provides an intuitive Lightning UI and powerful backend processing to streamline your data quality efforts.

![Duplication Manager Dashboard](https://placeholder-for-screenshot.png)

## Key Features

- **Intelligent Matching**: Identify duplicates using configurable field weights and normalization
- **Batch Processing**: Handle large volumes of data efficiently with optimized batch jobs
- **Interactive UI**: Compare duplicates side-by-side with field highlighting
- **Merge Conflict Resolution**: Resolve conflicts with clear visual indicators
- **Detailed Logging**: Track all detection and merge operations
- **Scheduled Jobs**: Automate duplicate detection on a regular schedule
- **Health Check**: Monitor the configuration and performance of your duplicate management

## Getting Started

See [DEPLOY.txt](./DEPLOY.txt) for detailed deployment instructions.

### Deployment Options

1. **GitHub Actions CI/CD Pipeline**:

   - Code is automatically deployed through the CI/CD pipeline
   - See [DEPLOY.txt](./DEPLOY.txt) for GitHub Actions workflow setup
   - Workflows handle deployment to development, integration, and production orgs

2. **Manual Deployment**:

   ```bash
   # Deploy to sandbox
   sf project deploy start --source-dir force-app --target-org your-sandbox-alias --test-level RunLocalTests

   # Deploy to production
   sf project deploy start --source-dir force-app --target-org your-prod-alias --test-level RunSpecifiedTests --tests $(cat tests/production-tests.txt | tr '\n' ' ')
   ```

### Quick Start

1. Deploy the package to your Salesforce org
2. Assign the `Duplicate_Manager_Admin` permission set to users
3. Navigate to the "Duplication Manager" app in the App Launcher
4. Configure duplicate detection rules using the setup screen
5. Run your first duplicate detection job

## Technical Architecture

The application follows a modular design with these key components:

### Batch Processing Framework

The batch processing framework is built on a base class (`DuplicateBaseBatch`) that provides common functionality for all duplicate detection and merging batch jobs. Key batch classes include:

- `DuplicateRecordBatch` - Main batch processor for finding duplicates using custom matching rules
- `DuplicateRuleFinderBatch` - Batch processor that uses Salesforce standard duplicate rules
- `ArchiveOldLogsBatch` - Batch processor for archiving old duplicate merge logs

### Matcher Framework

A flexible matcher framework allows customization of how fields are compared:

- `FieldMatcherInterface` - Common interface for all matchers
- `NameMatcher` - Specialized for matching name fields
- `EmailMatcher` - Specialized for matching email fields
- `AddressMatcher` - Specialized for matching address fields
- `TextMatcher` - General purpose text matching

### Service Layer

Service classes provide the business logic:

- `DuplicateDetectionService` - Core duplicate finding functionality
- `DuplicateMergeService` - Record merging functionality
- `DuplicateSettingsService` - Configuration management
- `DuplicateStatisticsService` - Reporting and analytics

### UI Components

The UI is built with Lightning Web Components (LWC):

- Dashboard for viewing duplicate statistics
- Configuration interface for setting up rules
- Comparison view for reviewing duplicates
- Merge interface for resolving duplicates

## Configuration

### Duplicate Detection Rules

Configure which fields to use for duplicate detection and their relative importance:

```json
{
  "Name": 0.5,
  "Email": 0.8,
  "Phone": 0.6,
  "BillingCity": 0.3,
  "Website": 0.4
}
```

### Master Record Selection

Choose how to determine which record becomes the master during merges:

- **MostComplete**: Use the record with the most populated fields
- **OldestCreated**: Use the record that was created first
- **NewestModified**: Use the most recently modified record

## User Guide

### Running a Duplicate Detection Job

1. Navigate to the "Batch Jobs" tab
2. Select the object to scan (Account, Contact, etc.)
3. Set batch size and filtering criteria
4. Click "Run Detection Job"
5. Monitor job progress in real-time

### Reviewing Duplicates

1. Navigate to the "Dashboard" tab to see summary statistics
2. Click on an object type to view detected duplicate groups
3. Select a duplicate group to view the detailed comparison

### Merging Records

1. From the comparison view, select the master record
2. Review field values and select which values to keep
3. Click "Merge" to combine the records
4. Review the merge log for confirmation

## Best Practices

- Start with small batch sizes (100-200 records) and adjust based on performance
- Consider data volume when scheduling automated jobs
- Use field weights that emphasize unique identifiers (email, phone, etc.)
- Always test on a sandbox org before deploying to production

## License

Copyright © 2025. All rights reserved.
