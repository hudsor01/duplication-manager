/**
 * Test class for DuplicateDataProcessor
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class DuplicateDataProcessorTest {
    
    /**
     * Test processing small data volume directly
     */
    @isTest
    static void testSmallDataVolume() {
        // Create test data
        List<Account> testAccounts = createTestAccounts(5);
        Set<Id> accountIds = new Set<Id>();
        for (Account acc : testAccounts) {
            accountIds.add(acc.Id);
        }
        
        // Create a chain to execute the processor
        DuplicateQueueableChain chain = new DuplicateQueueableChain('Test Chain');
        TestCompletionHandler handler = new TestCompletionHandler();
        chain.setCompletionHandler(handler);
        
        // Add the data processor
        DuplicateDataProcessor processor = new DuplicateDataProcessor('ACCOUNTS', accountIds);
        chain.addStep(processor);
        
        // Execute the chain
        Test.startTest();
        Id jobId = chain.startChain();
        Test.stopTest(); // This forces all async jobs to complete
        
        // Verify completion handler was called
        System.assertEquals(true, handler.completed, 'Completion handler should have been called');
        System.assertEquals(true, handler.success, 'Chain should have completed successfully');
        
        // Verify context values were set
        System.assertEquals(true, chain.getContextValue('processingComplete'), 'Processing complete flag should be set');
        System.assertEquals(5, chain.getContextValue('recordsProcessed'), 'Records processed count should be correct');
    }
    
    /**
     * Test processing large data volume via batch
     */
    @isTest
    static void testLargeDataVolume() {
        // Create test data - over the 200 threshold
        List<Account> testAccounts = createTestAccounts(201);
        Set<Id> accountIds = new Set<Id>();
        for (Account acc : testAccounts) {
            accountIds.add(acc.Id);
        }
        
        // Create a chain to execute the processor
        DuplicateQueueableChain chain = new DuplicateQueueableChain('Test Chain');
        TestCompletionHandler handler = new TestCompletionHandler();
        chain.setCompletionHandler(handler);
        
        // Add the data processor
        DuplicateDataProcessor processor = new DuplicateDataProcessor('ACCOUNTS', accountIds);
        chain.addStep(processor);
        
        // Mock counter for batch executions - used to verify batch was used
        DuplicateBatchProcessor_Test.TestCounter counter = new DuplicateBatchProcessor_Test.TestCounter();
        DuplicateBatchProcessor_Test.setMockCounter(counter);
        
        // Execute the chain
        Test.startTest();
        Id jobId = chain.startChain();
        Test.stopTest(); // This forces all async jobs to complete
        
        // Verify completion handler was called
        System.assertEquals(true, handler.completed, 'Completion handler should have been called');
        System.assertEquals(true, handler.success, 'Chain should have completed successfully');
        
        // Verify context values were set
        System.assertEquals(true, chain.getContextValue('processingComplete'), 'Processing complete flag should be set');
        System.assertEquals(201, chain.getContextValue('recordsProcessed'), 'Records processed count should be correct');
        
        // Verify batch was started
        System.assert(counter.executeBatchCalled, 'Batch should have been executed for large volume');
    }
    
    /**
     * Test different object types
     */
    @isTest
    static void testDifferentObjectTypes() {
        // Create test data for different object types
        List<Account> testAccounts = createTestAccounts(1);
        List<Contact> testContacts = createTestContacts(1);
        
        // Get IDs
        Set<Id> accountIds = new Set<Id>();
        for (Account acc : testAccounts) {
            accountIds.add(acc.Id);
        }
        
        Set<Id> contactIds = new Set<Id>();
        for (Contact con : testContacts) {
            contactIds.add(con.Id);
        }
        
        // Test with accounts
        DuplicateQueueableChain accountChain = new DuplicateQueueableChain('Account Chain');
        DuplicateDataProcessor accountProcessor = new DuplicateDataProcessor('ACCOUNTS', accountIds);
        accountChain.addStep(accountProcessor);
        
        // Test with contacts
        DuplicateQueueableChain contactChain = new DuplicateQueueableChain('Contact Chain');
        DuplicateDataProcessor contactProcessor = new DuplicateDataProcessor('CONTACTS', contactIds);
        contactChain.addStep(contactProcessor);
        
        // Execute the chains
        Test.startTest();
        Id accountJobId = accountChain.startChain();
        Id contactJobId = contactChain.startChain();
        Test.stopTest(); // This forces all async jobs to complete
        
        // Verify context values for both chains
        System.assertEquals(true, accountChain.getContextValue('processingComplete'), 'Account processing complete flag should be set');
        System.assertEquals(1, accountChain.getContextValue('recordsProcessed'), 'Account records processed count should be correct');
        
        System.assertEquals(true, contactChain.getContextValue('processingComplete'), 'Contact processing complete flag should be set');
        System.assertEquals(1, contactChain.getContextValue('recordsProcessed'), 'Contact records processed count should be correct');
    }
    
    /**
     * Helper to create test accounts
     */
    private static List<Account> createTestAccounts(Integer count) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i
            ));
        }
        insert accounts;
        return accounts;
    }
    
    /**
     * Helper to create test contacts
     */
    private static List<Contact> createTestContacts(Integer count) {
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < count; i++) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName = 'Contact ' + i,
                Email = 'test' + i + '@example.com'
            ));
        }
        insert contacts;
        return contacts;
    }
    
    /**
     * Test completion handler
     */
    private class TestCompletionHandler implements DuplicateQueueableChain.CompletionCallback {
        public Boolean completed = false;
        public Boolean success = false;
        
        public void execute(Boolean success) {
            this.completed = true;
            this.success = success;
        }
    }
}