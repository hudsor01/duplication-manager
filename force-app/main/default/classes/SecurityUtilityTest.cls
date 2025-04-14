@isTest
private class SecurityUtilityTest {
  @testSetup
  static void setupTestData() {
    // Create test account
    Account testAccount = new Account(Name = 'Test Account');
    insert testAccount;
  }

  @isTest
  static void testCheckUserAccess_ValidAccess() {
    // Get the test account
    Account testAccount = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Account'
      LIMIT 1
    ];

    Test.startTest();
    Boolean hasAccess = SecurityUtility.checkUserAccess(
      testAccount.Id,
      'Account'
    );
    Test.stopTest();

    // User should have access to the record they created
    System.assert(hasAccess, 'User should have access to their own record');
  }

  @isTest
  static void testCheckUserAccess_InvalidObject() {
    Test.startTest();
    Boolean hasAccess = SecurityUtility.checkUserAccess(
      '001000000000000',
      'InvalidObject'
    );
    Test.stopTest();

    // Should return false for invalid object
    System.assertEquals(
      false,
      hasAccess,
      'Should return false for invalid object'
    );
  }

  @isTest
  static void testCheckUserAccess_NullRecordId() {
    Test.startTest();
    Boolean hasAccess = SecurityUtility.checkUserAccess(null, 'Account');
    Test.stopTest();

    // Should return false for null recordId
    System.assertEquals(
      false,
      hasAccess,
      'Should return false for null recordId'
    );
  }

  @isTest
  static void testIsApexJobSystemPermitted() {
    Test.startTest();
    Boolean hasPermission = SecurityUtility.isApexJobSystemPermitted();
    Test.stopTest();

    // In test context, running user is typically admin
    System.assertEquals(
      true,
      hasPermission,
      'Test user should have permission to manage jobs'
    );
  }

  @isTest
  static void testCanCreate() {
    Test.startTest();
    Boolean canCreateAccount = SecurityUtility.canCreate('Account');
    Boolean cannotCreateInvalid = SecurityUtility.canCreate('InvalidObject');
    Boolean cannotCreateNull = SecurityUtility.canCreate(null);
    Test.stopTest();

    System.assertEquals(
      true,
      canCreateAccount,
      'Should be able to create Account'
    );
    System.assertEquals(
      false,
      cannotCreateInvalid,
      'Should not be able to create invalid object'
    );
    System.assertEquals(
      false,
      cannotCreateNull,
      'Should not be able to create null object'
    );
  }

  @isTest
  static void testCanRead() {
    Test.startTest();
    Boolean canReadAccount = SecurityUtility.canRead('Account');
    Boolean cannotReadInvalid = SecurityUtility.canRead('InvalidObject');
    Boolean cannotReadNull = SecurityUtility.canRead(null);
    Test.stopTest();

    System.assertEquals(true, canReadAccount, 'Should be able to read Account');
    System.assertEquals(
      false,
      cannotReadInvalid,
      'Should not be able to read invalid object'
    );
    System.assertEquals(
      false,
      cannotReadNull,
      'Should not be able to read null object'
    );
  }
}
