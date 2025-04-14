# Developer Guide for Duplication Manager

This guide provides an overview of the Duplication Manager application architecture and key components for developers who are maintaining or extending the codebase.

## Architecture Overview

The Duplication Manager follows a layered architecture with clear separation of concerns:

1. **UI Layer** - Lightning Web Components (LWC)
2. **Service Layer** - JavaScript services and Apex controller
3. **Business Logic Layer** - Apex services and utilities
4. **Data Access Layer** - Apex data operations
5. **Batch Processing Layer** - Apex batch jobs

## Key Design Patterns

### Factory Pattern

The `DuplicationMatcherRegistry` uses the Factory pattern to create and provide specialized matchers based on field types.

### Template Method Pattern

The `DuplicationBaseBatch` defines a template for batch processes, with specific steps implemented by subclasses.

### Service Layer Pattern

Services like `DuplicationServicesUtil`, `DuplicationStatisticsService`, and `DuplicationMergeService` encapsulate business logic.

### Observer Pattern

The `duplicationMessageService` implements an observer pattern for loosely coupled component communication.

## Core Components

### Apex Classes

- **DuplicationBaseBatch**: Abstract base class for batch processes
- **DuplicationBatch**: Implementation of batch process for finding duplicates
- **DuplicationController**: Main controller for LWC components
- **DuplicationMatcherRegistry**: Factory for field matchers
- **DuplicationServicesUtil**: Common utility methods
- **DuplicationStatisticsService**: Statistics generation and processing
- **DuplicationGroupService**: Duplicate group management
- **DuplicationMergeService**: Merge operations and conflict resolution

### LWC Components

- **duplicationErrorService**: Centralized error handling
- **duplicationDataService**: Data access and caching
- **duplicationMessageService**: Component communication
- **duplicationConstants**: Shared constants and configurations
- **duplicationManager**: Main UI component
- **duplicationUtils**: Utility functions
- **Additional UI components**

## Workflows

### Duplicate Detection Flow

1. User configures and starts job via `duplicationManager`
2. Request processed by `DuplicationController`
3. `DuplicationBatch` job is started
4. Batch job identifies duplicates using `DuplicationMatcherRegistry`
5. Results stored in job statistics object
6. UI components retrieve and display results

### Merge Flow

1. User selects records to merge
2. `DuplicationMergeService` handles the merge operation
3. Conflicts identified and preserved
4. Merge logs created for audit trail

## Extending the Application

### Adding a New Matcher

1. Create a new class implementing `FieldMatcherInterface`
2. Implement `calculateMatchScore()` and `canHandleField()` methods
3. Register the matcher in `DuplicationMatcherRegistry`

### Adding Support for a New Object

The application should automatically support any Salesforce object with duplicate rules. For custom handling:

1. Add the object to the `COMMON_OBJECTS` constant
2. Implement any special field handling needed

### Adding New UI Features

1. For new UI components, extend existing patterns
2. Use the service layer for data access
3. Use the message service for communication with other components
4. Follow naming conventions and coding standards

## Testing

- Each major component has a corresponding test class
- Batch components have specialized tests
- UI components have Jest tests

## Deployment

See DEPLOYMENT.md for detailed deployment instructions.

## Best Practices

1. **Use the service layer**: Don't bypass services to access data directly
2. **Follow naming conventions**: Use `Duplication` prefix consistently
3. **Maintain separation of concerns**: Keep UI, business logic, and data access separate
4. **Document public methods**: Ensure all public methods have clear documentation
5. **Write tests**: Maintain high test coverage for all components
6. **Use built-in patterns**: Leverage the existing architecture patterns when extending

## Performance Considerations

1. Batch size configuration is important for large orgs
2. Consider using a dry run for large data volumes
3. Avoid creating excessive ContentNote records
4. Use appropriate indexing for custom objects

## Security Considerations

1. Field level security is enforced in the controller
2. Error messages are sanitized to prevent information disclosure
3. Permission set controls access to the application
