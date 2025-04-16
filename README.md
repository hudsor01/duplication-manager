# Duplication Manager for Salesforce

## Overview

Duplication Manager is a robust Salesforce application for detecting, comparing, and merging duplicate records across your Salesforce org. The solution provides an intuitive Lightning UI and powerful backend processing to streamline your data quality efforts.

## Key Features

- **Intelligent Matching**: Identify duplicates using configurable field weights and normalization
- **Batch Processing**: Handle large volumes of data efficiently with optimized batch jobs
- **Interactive UI**: Compare duplicates side-by-side with field highlighting
- **Merge Conflict Resolution**: Resolve conflicts with clear visual indicators
- **Detailed Logging**: Track all detection and merge operations
- **Scheduled Jobs**: Automate duplicate detection on a regular schedule
- **Health Check**: Monitor the configuration and performance of your duplicate management

### Quick Start

1. Deploy the package to your Salesforce org
2. Assign the `Duplicate_Manager_Admin` permission set to users
3. Navigate to the "Duplication Manager" app in the App Launcher
4. Configure duplicate detection rules using the setup screen
5. Run your first duplicate detection job

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

- **Most Recent**: Use the most recently created or modified record
- **Oldest**: Use the record that was created first
- **Most Complete**: Use the record with the most populated fields

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

## Maintenance

For optimal performance:

- Schedule regular archiving of old logs
- Monitor job statistics for performance trends
- Periodically review and refine matching rules

## Best Practices

- Start with small batch sizes (100-200 records) and adjust based on performance
- Consider data volume when scheduling automated jobs
- Use field weights that emphasize unique identifiers (email, phone, etc.)
- Always test on a sandbox org before deploying to production

## Technical Documentation

- **Development Model**: Source-based development with Salesforce DX
- **Lightning Web Components**: Modern UI built with LWC framework
- **Apex Classes**: Enterprise-pattern services and batch processing
- **Custom Objects**: Specialized metadata for duplicate management

## License

This package is proprietary and licensed for use according to the agreement with the vendor.

## Support

For technical support, please contact your Salesforce administrator.
