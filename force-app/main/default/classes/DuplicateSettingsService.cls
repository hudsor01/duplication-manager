/**
 * DuplicateSettingsService
 * @description Service class for handling duplicate settings operations
 */
public with sharing class DuplicateSettingsService {
  /**
   * Gets all active duplicate finder settings
   *
   * @return List of active settings as maps
   */
  public List<Map<String, Object>> getActiveSettings() {
    List<Map<String, Object>> result = new List<Map<String, Object>>();

    try {
      validateMetadataExists();

      // Get all active settings
      String query = buildSettingsQuery();
      List<SObject> settings = executeSettingsQuery(query);

      // Convert SObjects to maps
      result = convertSettingsToMaps(settings);

      // Log if no settings found
      if (settings.isEmpty()) {
        System.debug(
          'No active DuplicateFinderSetting__mdt records found. Make sure IsActive__c is true.'
        );
      }
    } catch (Exception e) {
      handleError(e);
    }

    return result;
  }

  // Private helper methods

  /**
   * Validates that the custom metadata type exists
   */
  private void validateMetadataExists() {
    try {
      Schema.getGlobalDescribe().get('DuplicateFinderSetting__mdt');
    } catch (Exception e) {
      System.debug(
        'ERROR: DuplicateFinderSetting__mdt custom metadata type not found: ' +
        e.getMessage()
      );
      throw new duplicateException(
        'DuplicateFinderSetting__mdt custom metadata type not found. Please deploy it to your org.'
      );
    }
  }

  /**
   * Builds the query for settings
   */
  private String buildSettingsQuery() {
    return 'SELECT MasterLabel, DeveloperName, SObject_API_Name__c, ' +
      'MatchFields__c, MasterRecordStrategy__c, BatchSize__c ' +
      'FROM DuplicateFinderSetting__mdt ' +
      'WHERE IsActive__c = true ' +
      'ORDER BY MasterLabel';
  }

  /**
   * Executes the settings query
   */
  private List<SObject> executeSettingsQuery(String query) {
    System.debug('Executing query: ' + query);
    List<SObject> settings = Database.query(query);
    System.debug('Query returned ' + settings.size() + ' records');

    return settings;
  }

  /**
   * Converts settings SObjects to maps for API response
   */
  private List<Map<String, Object>> convertSettingsToMaps(
    List<SObject> settings
  ) {
    List<Map<String, Object>> result = new List<Map<String, Object>>();

    for (SObject setting : settings) {
      Map<String, Object> settingMap = new Map<String, Object>();

      settingMap.put('MasterLabel', setting.get('MasterLabel'));
      settingMap.put('DeveloperName', setting.get('DeveloperName'));
      settingMap.put('ObjectApiName', setting.get('SObject_API_Name__c'));
      settingMap.put('MatchFields', setting.get('MatchFields__c'));
      settingMap.put(
        'MasterRecordStrategy',
        setting.get('MasterRecordStrategy__c')
      );
      settingMap.put('BatchSize', setting.get('BatchSize__c'));

      result.add(settingMap);
    }

    return result;
  }

  /**
   * Handles exceptions from settings operations
   */
  private void handleError(Exception e) {
    System.debug(
      'Error getting active settings: ' +
        e.getMessage() +
        '\n' +
        e.getStackTraceString()
    );
    throw new duplicateException(
      'Error retrieving active settings: ' + e.getMessage()
    );
  }
}
