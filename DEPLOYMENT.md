# Duplication Manager - Production Deployment Guide

## Overview

The Duplication Manager is an enterprise-ready Salesforce solution for detecting and merging duplicate records across standard and custom objects. This deployment guide provides step-by-step instructions for successfully deploying the Duplication Manager to a production Salesforce environment.

## Prerequisites

- Salesforce CLI installed and authenticated to the target org
- Admin access to the target Salesforce org
- Backup of any existing duplication detection configurations
- At least 2 GB of storage space in the target org

## Deployment Checklist

### Step 1: Prepare the Target Org

1. **Back up existing duplication rules**:
   ```bash
   sfdx force:data:soql:query -q "SELECT Id, DeveloperName FROM DuplicateRule" -u [targetOrg] > existing_rules.json
   ```

2. **Check target org limitations**:
   - Verify API limits
   - Check scheduled job slots availability 
   - Ensure storage space availability

3. **Validate deployment package**:
   ```bash
   sfdx force:mdapi:deploy -c -d force-app/main/default -u [targetOrg]
   ```

### Step 2: Deploy Metadata Components

Deploy the components in the following order to ensure proper dependency resolution:

1. **Custom Objects and Fields**:
   ```bash
   sfdx force:mdapi:deploy -d force-app/main/default/objects -u [targetOrg]
   ```

2. **Apex Classes**:
   ```bash
   sfdx force:mdapi:deploy -d force-app/main/default/classes -u [targetOrg]
   ```

3. **Lightning Components**:
   ```bash
   sfdx force:mdapi:deploy -d force-app/main/default/lwc -u [targetOrg]
   sfdx force:mdapi:deploy -d force-app/main/default/aura -u [targetOrg]
   ```

4. **Tabs, FlexiPages, and Applications**:
   ```bash
   sfdx force:mdapi:deploy -d force-app/main/default/tabs -u [targetOrg]
   sfdx force:mdapi:deploy -d force-app/main/default/flexipages -u [targetOrg]
   sfdx force:mdapi:deploy -d force-app/main/default/applications -u [targetOrg]
   ```

5. **Permission Sets**:
   ```bash
   sfdx force:mdapi:deploy -d force-app/main/default/permissionsets -u [targetOrg]
   ```

### Step 3: Post-Deployment Configuration

1. **Assign Permission Sets**:
   - Assign the `Duplicate_Manager_Admin` permission set to admin users:
   ```bash
   sfdx force:user:permset:assign -n Duplicate_Manager_Admin -u [targetOrg]
   ```

2. **Configure Custom Metadata**:
   - Load predefined duplicate detection rules from the `DuplicateFinderSetting__mdt` records
   ```bash
   sfdx force:mdapi:deploy -d force-app/main/default/customMetadata -u [targetOrg]
   ```

3. **Set up Scheduled Jobs**:
   - Schedule the ArchiveOldLogsScheduler to run weekly:
   ```apex
   String CRON_EXP = '0 0 0 ? * SUN';
   System.schedule('Archive Old Logs - Weekly Sunday', CRON_EXP, new ArchiveOldLogsScheduler());
   ```

4. **Initialize Configuration Settings**:
   - For each supported object (Account, Contact, Lead), verify and activate the configurations
   - Adjust match thresholds based on data quality (recommended starting point: 75%)

5. **Set Tab Visibility**:
   - Ensure the Duplicate Manager tab is visible in the application

### Step 4: Testing

1. **Validation Testing**:
   - Verify all tabs are accessible
   - Confirm permissions are correctly assigned
   - Test loading the main Duplication Manager page

2. **Functional Testing**:
   - Run a small batch job on test records
   - Verify duplicate detection works as expected
   - Test the merge functionality with controlled test data
   - Validate that the batch jobs complete successfully

3. **Performance Testing**:
   - Monitor job execution times
   - Test with progressively larger batch sizes to determine optimal settings

### Step 5: User Setup

1. **Assign Permissions**:
   - Assign the `Duplicate_Manager_Admin` permission set to all users who will manage duplicates

2. **User Training**:
   - Provide training on duplicate detection workflow
   - Explain the merge process and resolution options
   - Document any custom configurations specific to your organization

## Configuration Options

### Batch Size Optimization

The default batch size is 200 records. Adjust this based on your data volume:

- **Small orgs** (< 10,000 records per object): 200-500 records per batch
- **Medium orgs** (< 100,000 records per object): 100-200 records per batch
- **Large orgs** (> 100,000 records per object): 50-100 records per batch

Edit the batch size in the custom metadata settings:

1. Navigate to Setup > Custom Metadata Types
2. Find the DuplicateFinderSetting__mdt records
3. Edit each record to set the appropriate batch size

### Match Field Configuration

Configure which fields to use for duplicate matching:

1. Edit the `MatchFields__c` field in each `DuplicateFinderSetting__mdt` record
2. Use JSON format to specify fields and weights:
   ```json
   {
     "Name": 0.5,
     "Email__c": 0.8,
     "Phone": 0.6,
     "BillingCity": 0.3,
     "Website": 0.4
   }
   ```
3. The weights should sum to approximately 1.0

### Master Record Strategy

Set the strategy for determining which record becomes the master:

- `MOST_RECENT`: Uses the most recently created record as master
- `OLDEST`: Uses the oldest record as master
- `MOST_COMPLETE`: Uses the record with the most non-null fields

## Troubleshooting

### Common Issues

1. **Deployment Failures**:
   - Check API version compatibility
   - Verify all dependencies are included in the deployment
   - Look for validation rule violations

2. **Permission Issues**:
   - Verify the permission set includes all necessary classes and objects
   - Check field-level security settings

3. **Job Failures**:
   - Check for SOQL limits in batch jobs
   - Verify heap size limits are not exceeded
   - Adjust batch size if necessary

### Support Resources

- Review the error logs in the `DeduplicationFailure__c` object
- Monitor job progress in the Scheduled Jobs tab
- Use the Health Check feature to diagnose configuration issues

## Maintenance

### Regular Maintenance Tasks

1. **Archive Old Logs**:
   - Confirm the ArchiveOldLogsBatch runs weekly
   - Periodically clean up archived logs older than 90 days

2. **Monitor Job Performance**:
   - Review job statistics to identify performance trends
   - Adjust batch size settings as data volume grows

3. **Refinement of Matching Rules**:
   - Periodically review false positives/negatives
   - Adjust field weights to improve matching accuracy

## Recent Code Improvements

The following enhancements were recently made to the codebase:

1. **Enhanced Conflict Documentation**:
   - Added comprehensive note creation for merge conflicts
   - Detailed field-by-field documentation of merged values
   - Preserved data from duplicate records in notes

2. **Improved Match Algorithm**:
   - Added weighted field matching for more accurate duplicate detection
   - Enhanced string similarity calculation with Levenshtein distance
   - Added field-specific weight configuration

3. **Security Enhancements**:
   - Added WITH SECURITY_ENFORCED to all SOQL queries
   - Added explicit CRUD/FLS checks before DML operations
   - Improved error handling and logging

4. **Code Organization**:
   - Standardized naming conventions across all components
   - Removed redundant application definitions
   - Simplified deployment structure

## Security Considerations

The Duplication Manager implements several security best practices:

1. **Apex Security**:
   - All classes use `with sharing` to enforce sharing rules
   - CRUD/FLS checks are implemented before DML operations
   - SOQL injection prevention with proper input validation

2. **Access Controls**:
   - Permission sets control access to functionality
   - Field-level security is respected for all field access
   - Only authorized users can merge records

## Appendix

### Key Objects

- `DuplicateFinderSettings__c`: Custom settings for duplicate rules
- `DuplicateGroupDetail__c`: Stores groups of duplicate records
- `DuplicateJobStatistic__c`: Job performance metrics
- `DuplicateMergeLog__c`: Record of merge operations
- `DuplicateRunResult__c`: Results of duplicate detection runs

### Important Apex Classes

- `DuplicateDetectionService`: Core service for finding duplicates
- `DuplicateMergeService`: Handles record merging logic
- `DuplicateRecordBatch`: Batch job for processing records
- `DuplicateRecordController`: Main controller for UI operations