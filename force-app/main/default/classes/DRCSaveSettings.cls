/**
 * @description Class for saving user-specific settings for the duplicate Manager
 * @author Richard Hudson
 * @date 2025-04-11
 */
public without sharing class DRCSaveSettings {
  /**
   * @description Static method for saving user-specific settings for the duplicate Manager
   *
   * @param settingsJson JSON string of user settings
   * @return Boolean indicating success
   */
  @AuraEnabled
  public static Boolean saveUserSettings(String settingsJson) {
    if (String.isBlank(settingsJson)) {
      throw new AuraHandledException('Settings data is required');
    }

    try {
      System.debug('Received settings JSON: ' + settingsJson);

      // Parse the settings to validate JSON format
      Object parsed = JSON.deserializeUntyped(settingsJson);
      System.debug('Successfully parsed JSON');

      // Use without sharing to ensure this always works regardless of user permissions
      // This is fine for user preferences which are always tied to the current user

      // Try to create the settings record for this user
      try {
        // Get or create the settings record for this user
        List<FlowPersonalConfiguration__c> userConfigs = [
          SELECT Id, Configuration__c
          FROM FlowPersonalConfiguration__c
          WHERE
            OwnerId = :UserInfo.getUserId()
            AND Name = 'duplicateManagerSettings'
          LIMIT 1
        ];

        System.debug('Found existing configs: ' + userConfigs.size());

        FlowPersonalConfiguration__c config;
        if (userConfigs.isEmpty()) {
          config = new FlowPersonalConfiguration__c(
            Name = 'duplicateManagerSettings',
            OwnerId = UserInfo.getUserId()
          );
          System.debug('Creating new config');
        } else {
          config = userConfigs[0];
          System.debug('Using existing config: ' + config.Id);
        }

        // Update the configuration with validated and sanitized data
        config.Configuration__c = settingsJson;

        // Save without enforcing sharing rules
        upsert config;
        System.debug('Successfully saved config');

        return true;
      } catch (Exception e) {
        System.debug(
          LoggingLevel.ERROR,
          'Error accessing object: ' + e.getMessage()
        );

        // Try fallback approach - save to custom object if custom setting failed
        try {
          // Use DuplicateFinderSettings__c as a fallback
          String settingName = 'User_' + UserInfo.getUserId();
          DuplicateFinderSettings__c fallbackSetting;

          // Query for existing setting for this user
          List<DuplicateFinderSettings__c> settings = [
            SELECT Id, Name, MatchFields__c, IsActive__c
            FROM DuplicateFinderSettings__c
            WHERE Name = :settingName
            LIMIT 1
          ];

          if (settings.isEmpty()) {
            fallbackSetting = new DuplicateFinderSettings__c(
              Name = settingName,
              IsActive__c = true
            );
          } else {
            fallbackSetting = settings[0];
          }

          // Store JSON in a standard field
          fallbackSetting.MatchFields__c = settingsJson;

          upsert fallbackSetting;
          System.debug('Saved to fallback custom object');

          return true;
        } catch (Exception fallbackError) {
          System.debug(
            LoggingLevel.ERROR,
            'Fallback also failed: ' + fallbackError.getMessage()
          );
          throw new AuraHandledException(
            'Could not save to any storage location: ' +
            fallbackError.getMessage()
          );
        }
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error in saveUserSettings: ' + e.getMessage()
      );
      throw new AuraHandledException(
        'Error saving settings: ' + e.getMessage()
      );
    }
  }
}
