/**
 * Test utility class with helper methods for test data creation and manipulation
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
public class TestUtility {
  /**
   * Creates a test Account record
   * @param name Name for the Account
   * @param doInsert Whether to insert the record
   * @return The created Account
   */
  public static Account createTestAccount(String name, Boolean doInsert) {
    Account acc = new Account(
      Name = name,
      Phone = '555-123-4567',
      Website = 'www.example.com'
    );

    if (doInsert) {
      insert acc;
    }

    return acc;
  }

  /**
   * Creates multiple test Account records
   * @param count Number of accounts to create
   * @param namePrefix Prefix for account names
   * @param doInsert Whether to insert the records
   * @return List of created accounts
   */
  public static List<Account> createTestAccounts(
    Integer count,
    String namePrefix,
    Boolean doInsert
  ) {
    List<Account> accounts = new List<Account>();

    for (Integer i = 0; i < count; i++) {
      accounts.add(
        new Account(
          Name = namePrefix + ' ' + i,
          Phone = '555-123-' + String.valueOf(1000 + i).substring(1), // Format: 555-123-xxxx
          Website = 'www.example' + i + '.com'
        )
      );
    }

    if (doInsert) {
      insert accounts;
    }

    return accounts;
  }

  /**
   * Creates a test Contact record
   * @param firstName First name
   * @param lastName Last name
   * @param accountId Account ID to relate to (optional)
   * @param doInsert Whether to insert the record
   * @return The created Contact
   */
  public static Contact createTestContact(
    String firstName,
    String lastName,
    Id accountId,
    Boolean doInsert
  ) {
    Contact con = new Contact(
      FirstName = firstName,
      LastName = lastName,
      Email = firstName.toLowerCase() +
        '.' +
        lastName.toLowerCase() +
        '@example.com',
      Phone = '555-987-6543'
    );

    if (accountId != null) {
      con.AccountId = accountId;
    }

    if (doInsert) {
      insert con;
    }

    return con;
  }

  /**
   * Creates multiple test Contact records
   * @param count Number of contacts to create
   * @param lastNamePrefix Prefix for contact last names
   * @param accountId Optional account ID to assign to all contacts
   * @param doInsert Whether to insert the records
   * @return List of created contacts
   */
  public static List<Contact> createTestContacts(
    Integer count,
    String lastNamePrefix,
    Id accountId,
    Boolean doInsert
  ) {
    List<Contact> contacts = new List<Contact>();

    for (Integer i = 0; i < count; i++) {
      Contact con = new Contact(
        FirstName = 'Test' + i,
        LastName = lastNamePrefix + i,
        Email = 'test' +
          i +
          '.' +
          lastNamePrefix.toLowerCase() +
          i +
          '@example.com',
        Phone = '555-987-' + String.valueOf(1000 + i).substring(1) // Format: 555-987-xxxx
      );

      if (accountId != null) {
        con.AccountId = accountId;
      }

      contacts.add(con);
    }

    if (doInsert) {
      insert contacts;
    }

    return contacts;
  }

  /**
   * Creates a test Lead record
   * @param firstName First name
   * @param lastName Last name
   * @param company Company name
   * @param doInsert Whether to insert the record
   * @return The created Lead
   */
  public static Lead createTestLead(
    String firstName,
    String lastName,
    String company,
    Boolean doInsert
  ) {
    Lead lead = new Lead(
      FirstName = firstName,
      LastName = lastName,
      Company = company,
      Email = firstName.toLowerCase() +
        '.' +
        lastName.toLowerCase() +
        '@example.com',
      Phone = '555-456-7890'
    );

    if (doInsert) {
      insert lead;
    }

    return lead;
  }

  /**
   * Creates multiple test Lead records
   * @param count Number of leads to create
   * @param lastNamePrefix Prefix for lead last names
   * @param companyPrefix Prefix for company names
   * @param doInsert Whether to insert the records
   * @return List of created leads
   */
  public static List<Lead> createTestLeads(
    Integer count,
    String lastNamePrefix,
    String companyPrefix,
    Boolean doInsert
  ) {
    List<Lead> leads = new List<Lead>();

    for (Integer i = 0; i < count; i++) {
      leads.add(
        new Lead(
          FirstName = 'Test' + i,
          LastName = lastNamePrefix + i,
          Company = companyPrefix + ' Inc. ' + i,
          Email = 'test' +
            i +
            '.' +
            lastNamePrefix.toLowerCase() +
            i +
            '@example.com',
          Phone = '555-456-' + String.valueOf(1000 + i).substring(1) // Format: 555-456-xxxx
        )
      );
    }

    if (doInsert) {
      insert leads;
    }

    return leads;
  }

  /**
   * Creates a DuplicateGroupDetail__c record for testing
   * @param objectName API name of the object
   * @param masterRecordId ID of the master record
   * @param duplicateIds List of duplicate record IDs
   * @param matchScore Match score
   * @return The created DuplicateGroupDetail__c
   */
  public static DuplicateGroupDetail__c createTestDuplicateGroup(
    String objectName,
    Id masterRecordId,
    List<Id> duplicateIds,
    Decimal matchScore
  ) {
    // Create a unique key based on timestamp and random number
    String groupKey =
      String.valueOf(Datetime.now().getTime()) +
      String.valueOf(Math.round(Math.random() * 1000));

    DuplicateGroupDetail__c groupDetail = new DuplicateGroupDetail__c(
      GroupKey__c = groupKey,
      ObjectName__c = objectName,
      RecordCount__c = duplicateIds.size() + 1, // Include master
      MasterRecordId__c = masterRecordId,
      MatchScore__c = matchScore,
      DuplicateRecordIds__c = String.join(duplicateIds, ',')
    );

    insert groupDetail;
    return groupDetail;
  }

  /**
   * Creates mock custom settings for testing
   */
  public static void createTestCustomSettings() {
    // Create test DuplicateFinderSettings__c (custom setting)
    DuplicateFinderSettings__c accountSettings = new DuplicateFinderSettings__c(
      Name = 'Account_Standard',
      ObjectAPIName__c = 'Account',
      MatchFields__c = 'Name,Phone,Website',
      BatchSize__c = 200,
      IsActive__c = true,
      MasterRecordStrategy__c = 'MostRecent'
    );

    insert accountSettings;

    DuplicateFinderSettings__c contactSettings = new DuplicateFinderSettings__c(
      Name = 'Contact_Standard',
      ObjectAPIName__c = 'Contact',
      MatchFields__c = 'FirstName,LastName,Email,Phone',
      BatchSize__c = 200,
      IsActive__c = true,
      MasterRecordStrategy__c = 'MostComplete'
    );

    insert contactSettings;
  }

  /**
   * Creates a run result for testing
   * @param batchJobId Batch job ID
   * @param objectApiName Object API name
   * @param configName Configuration name
   * @param isDryRun Whether it's a dry run
   * @return The created DuplicateRunResult__c
   */
  public static DuplicateRunResult__c createTestRunResult(
    String batchJobId,
    String objectApiName,
    String configName,
    Boolean isDryRun
  ) {
    DuplicateRunResult__c result = new DuplicateRunResult__c(
      BatchJobId__c = batchJobId,
      ObjectApiName__c = objectApiName,
      ConfigurationName__c = configName,
      IsDryRun__c = isDryRun,
      Status__c = 'Completed',
      RecordsProcessed__c = 100,
      DuplicatesFound__c = 10,
      RecordsMerged__c = isDryRun ? 0 : 8,
      JobCompletionTime__c = Datetime.now()
    );

    insert result;
    return result;
  }

  /**
   * Creates a job statistic for testing
   * @param batchJobId Batch job ID
   * @param objectApiName Object API name
   * @param configName Configuration name
   * @param isDryRun Whether it's a dry run
   * @return The created DuplicateJobStatistic__c
   */
  public static DuplicateJobStatistic__c createTestJobStatistic(
    String batchJobId,
    String objectApiName,
    String configName,
    Boolean isDryRun
  ) {
    DuplicateJobStatistic__c stat = new DuplicateJobStatistic__c(
      BatchJobId__c = batchJobId,
      ObjectApiName__c = objectApiName,
      ConfigurationName__c = configName,
      IsDryRun__c = isDryRun,
      Status__c = 'Completed',
      RecordsProcessed__c = 100,
      DuplicatesFound__c = 10,
      RecordsMerged__c = isDryRun ? 0 : 8,
      JobStartTime__c = Datetime.now().addHours(-1),
      JobCompletionTime__c = Datetime.now()
    );

    insert stat;
    return stat;
  }
}
