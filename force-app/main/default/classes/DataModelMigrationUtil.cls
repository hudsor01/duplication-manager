/**
 * Utility class for migrating from DuplicateFinderSetting__mdt to DuplicationConfiguration__mdt
 *
 * @author Richard Hudson
 * @date April 2025
 */
public class DataModelMigrationUtil {
  /**
   * Generates migration script to convert DuplicateFinderSetting__mdt records to DuplicationConfiguration__mdt
   * Since we can't directly manipulate metadata in Apex, this outputs the necessary metadata XML
   */
  public static void generateMigrationScript() {
    List<DuplicateFinderSetting__mdt> oldSettings = [
      SELECT
        Id,
        DeveloperName,
        MasterLabel,
        BatchSize__c,
        IsActive__c,
        MasterRecordStrategy__c,
        MatchFields__c,
        SObject_API_Name__c
      FROM DuplicateFinderSetting__mdt
    ];

    System.debug(
      'Migration script for DuplicateFinderSetting__mdt to DuplicationConfiguration__mdt:'
    );
    System.debug(
      '======================================================================'
    );

    for (DuplicateFinderSetting__mdt setting : oldSettings) {
      String xmlTemplate =
        '<?xml version="1.0" encoding="UTF-8"?>\n' +
        '<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n' +
        '    <label>{0}</label>\n' +
        '    <protected>false</protected>\n' +
        '    <values>\n' +
        '        <field>BatchSize__c</field>\n' +
        '        <value xsi:type="xsd:double">{1}</value>\n' +
        '    </values>\n' +
        '    <values>\n' +
        '        <field>IsActive__c</field>\n' +
        '        <value xsi:type="xsd:boolean">{2}</value>\n' +
        '    </values>\n' +
        '    <values>\n' +
        '        <field>MasterRecordStrategy__c</field>\n' +
        '        <value xsi:type="xsd:string">{3}</value>\n' +
        '    </values>\n' +
        '    <values>\n' +
        '        <field>MatchFields__c</field>\n' +
        '        <value xsi:type="xsd:string">{4}</value>\n' +
        '    </values>\n' +
        '    <values>\n' +
        '        <field>ObjectApiName__c</field>\n' +
        '        <value xsi:type="xsd:string">{5}</value>\n' +
        '    </values>\n' +
        '    <values>\n' +
        '        <field>MatchThreshold__c</field>\n' +
        '        <value xsi:type="xsd:double">75</value>\n' +
        '    </values>\n' +
        '    <values>\n' +
        '        <field>Version__c</field>\n' +
        '        <value xsi:type="xsd:string">1.0</value>\n' +
        '    </values>\n' +
        '    <values>\n' +
        '        <field>Description__c</field>\n' +
        '        <value xsi:type="xsd:string">Migrated from DuplicateFinderSetting</value>\n' +
        '    </values>\n' +
        '</CustomMetadata>';

      // Get field values, ensuring they're not null
      String matchFields = String.isBlank(setting.MatchFields__c)
        ? ''
        : setting.MatchFields__c;
      String objectApiName = String.isBlank(setting.SObject_API_Name__c)
        ? 'Account'
        : setting.SObject_API_Name__c;
      Decimal batchSize = setting.BatchSize__c != null
        ? setting.BatchSize__c
        : 200;
      String masterStrategy = String.isBlank(setting.MasterRecordStrategy__c)
        ? 'OldestCreated'
        : setting.MasterRecordStrategy__c;
      Boolean isActive = setting.IsActive__c != null
        ? setting.IsActive__c
        : false;

      // Format the XML with actual values
      String formattedXml = String.format(
        xmlTemplate,
        new List<String>{
          setting.MasterLabel,
          String.valueOf(batchSize),
          String.valueOf(isActive),
          masterStrategy,
          matchFields,
          objectApiName
        }
      );

      // Output the formatted XML
      String filename =
        'DuplicationConfiguration.' +
        setting.DeveloperName +
        '.md-meta.xml';
      System.debug('File: ' + filename);
      System.debug(formattedXml);
      System.debug(
        '----------------------------------------------------------------------'
      );
    }

    System.debug(
      'Migration script complete. Create these files in the force-app/main/default/customMetadata directory.'
    );
  }

  /**
   * Updates DuplicateConfig class to use consolidated metadata
   */
  public static void updateDuplicateConfigClass() {
    System.debug(
      'DuplicateConfig class needs to be updated to use DuplicationConfiguration__mdt instead of DuplicateFinderSetting__mdt'
    );
    System.debug(
      'Replace methods that fetch DuplicateFinderSetting__mdt with methods that fetch DuplicationConfiguration__mdt'
    );
  }
}
