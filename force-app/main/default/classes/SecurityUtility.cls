/**
 * @description Security utility class for enforcing CRUD and FLS checks throughout the application
 *@author Richard Hudson
 * @created 2025-04-09
 */
public with sharing class SecurityUtility {
  /**
   * @description Checks if the current user has access to a specific record
   * @param recordId The ID of the record to check access for
   * @param objectName The API name of the object the record belongs to
   * @return Boolean True if the user has access, false otherwise
   */
  public static Boolean checkUserAccess(Id recordId, String objectName) {
    if (recordId == null || String.isBlank(objectName)) {
      return false;
    }

    try {
      // Check if object exists in schema
      Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
      if (objType == null) {
        return false;
      }

      // Check if user has access to the object
      Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
      if (!objDescribe.isAccessible()) {
        return false;
      }

      // Check record access using UserRecordAccess
      UserRecordAccess access = [
        SELECT RecordId, HasReadAccess
        FROM UserRecordAccess
        WHERE UserId = :UserInfo.getUserId() AND RecordId = :recordId
        LIMIT 1
      ];

      return access.HasReadAccess;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error checking user access: ' + e.getMessage()
      );
      return false;
    }
  }

  /**
   * @description Checks if the current user has permission to manage Apex jobs
   * @return Boolean True if the user has required permissions
   */
  public static Boolean isApexJobSystemPermitted() {
    try {
      // Check for permissions to manage Apex jobs
      Boolean hasPermission =
        FeatureManagement.checkPermission('ManageUsers') ||
        FeatureManagement.checkPermission('ModifyAllData');

      // Fallback to profile-based check if the above isn't reliable in your org context
      if (!hasPermission) {
        Profile userProfile = [
          SELECT Name
          FROM Profile
          WHERE Id = :UserInfo.getProfileId()
          LIMIT 1
        ];
        String profileName = userProfile.Name;
        // Check if profile is System Admin or other appropriate profile
        if (
          profileName.containsIgnoreCase('System Administrator') ||
          profileName.containsIgnoreCase('Admin')
        ) {
          hasPermission = true;
        }
      }

      return hasPermission;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error checking apex job permissions: ' + e.getMessage()
      );
      return false;
    }
  }

  /**
   * @description Checks if the current user has create permission for an object
   * @param objectName The API name of the object to check
   * @return Boolean True if the user can create records, false otherwise
   */
  public static Boolean canCreate(String objectName) {
    if (String.isBlank(objectName)) {
      return false;
    }

    try {
      Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
      if (objType == null) {
        return false;
      }

      return objType.getDescribe().isCreateable();
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error checking create permission: ' + e.getMessage()
      );
      return false;
    }
  }

  /**
   * @description Checks if the current user has read permission for an object
   * @param objectName The API name of the object to check
   * @return Boolean True if the user can read records, false otherwise
   */
  public static Boolean canRead(String objectName) {
    if (String.isBlank(objectName)) {
      return false;
    }

    try {
      Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
      if (objType == null) {
        return false;
      }

      return objType.getDescribe().isAccessible();
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error checking read permission: ' + e.getMessage()
      );
      return false;
    }
  }

  /**
   * @description Checks if the current user has update permission for an object
   * @param objectName The API name of the object to check
   * @return Boolean True if the user can update records, false otherwise
   */
  public static Boolean canUpdate(String objectName) {
    if (String.isBlank(objectName)) {
      return false;
    }

    try {
      Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
      if (objType == null) {
        return false;
      }

      return objType.getDescribe().isUpdateable();
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error checking update permission: ' + e.getMessage()
      );
      return false;
    }
  }

  /**
   * @description Checks if the current user has delete permission for an object
   * @param objectName The API name of the object to check
   * @return Boolean True if the user can delete records, false otherwise
   */
  public static Boolean canDelete(String objectName) {
    if (String.isBlank(objectName)) {
      return false;
    }

    try {
      Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
      if (objType == null) {
        return false;
      }

      return objType.getDescribe().isDeletable();
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error checking delete permission: ' + e.getMessage()
      );
      return false;
    }
  }

  /**
   * @description Checks if the current user has field-level read access to a specific field
   * @param objectName The API name of the object
   * @param fieldName The API name of the field
   * @return Boolean True if the user can read the field, false otherwise
   */
  public static Boolean canReadField(String objectName, String fieldName) {
    if (String.isBlank(objectName) || String.isBlank(fieldName)) {
      return false;
    }

    try {
      Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
      if (objType == null) {
        return false;
      }

      Schema.SObjectField field = objType.getDescribe()
        .fields.getMap()
        .get(fieldName);
      if (field == null) {
        return false;
      }

      return field.getDescribe().isAccessible();
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error checking field read permission: ' + e.getMessage()
      );
      return false;
    }
  }

  /**
   * @description Checks if the current user has field-level update access to a specific field
   * @param objectName The API name of the object
   * @param fieldName The API name of the field
   * @return Boolean True if the user can update the field, false otherwise
   */
  public static Boolean canUpdateField(String objectName, String fieldName) {
    if (String.isBlank(objectName) || String.isBlank(fieldName)) {
      return false;
    }

    try {
      Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
      if (objType == null) {
        return false;
      }

      Schema.SObjectField field = objType.getDescribe()
        .fields.getMap()
        .get(fieldName);
      if (field == null) {
        return false;
      }

      return field.getDescribe().isUpdateable();
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error checking field update permission: ' + e.getMessage()
      );
      return false;
    }
  }

  /**
   * @description Utility method to enforce CRUD check before performing DML
   * @param operation The DML operation (create, read, update, delete)
   * @param objectName The API name of the object
   * @throws SecurityException If the user doesn't have the required permission
   */
  public static void enforceCRUD(String operation, String objectName) {
    if (String.isBlank(operation) || String.isBlank(objectName)) {
      throw new SecurityException('Invalid parameters for CRUD check');
    }

    Boolean hasPermission = false;

    String operationLower = operation.toLowerCase();
    if (operationLower == 'create') {
      hasPermission = canCreate(objectName);
    } else if (operationLower == 'read') {
      hasPermission = canRead(objectName);
    } else if (operationLower == 'update') {
      hasPermission = canUpdate(objectName);
    } else if (operationLower == 'delete') {
      hasPermission = canDelete(objectName);
    } else {
      throw new SecurityException('Invalid operation: ' + operation);
    }

    if (!hasPermission) {
      throw new SecurityException(
        'Insufficient permissions for ' +
          operation +
          ' operation on ' +
          objectName
      );
    }
  }

  /**
   * @description Utility method to enforce field-level security check
   * @param operation The field operation (read, update)
   * @param objectName The API name of the object
   * @param fieldName The API name of the field
   * @throws SecurityException If the user doesn't have the required permission
   */
  public static void enforceFLS(
    String operation,
    String objectName,
    String fieldName
  ) {
    if (
      String.isBlank(operation) ||
      String.isBlank(objectName) ||
      String.isBlank(fieldName)
    ) {
      throw new SecurityException('Invalid parameters for FLS check');
    }

    Boolean hasPermission = false;

    String operationLower = operation.toLowerCase();
    if (operationLower == 'read') {
      hasPermission = canReadField(objectName, fieldName);
    } else if (operationLower == 'update') {
      hasPermission = canUpdateField(objectName, fieldName);
    } else {
      throw new SecurityException('Invalid field operation: ' + operation);
    }

    if (!hasPermission) {
      throw new SecurityException(
        'Insufficient permissions for ' +
          operation +
          ' operation on ' +
          objectName +
          '.' +
          fieldName
      );
    }
  }

  /**
   * @description Custom exception class for security violations
   */
  public class SecurityException extends Exception {
  }
}
