/**
 * Test class for DuplicateQueueableChain
 *
 * @author Richard Hudson
 * @date April 2025
 */
@isTest
private class DuplicateQueueableChainTest {
  /**
   * Test basic chain functionality
   */
  @isTest
  static void testBasicChain() {
    // Create test steps
    TestQueueableStep step1 = new TestQueueableStep('Step 1');
    TestQueueableStep step2 = new TestQueueableStep('Step 2');

    // Create chain
    DuplicateQueueableChain chain = new DuplicateQueueableChain('Test Chain');
    chain.addStep(step1);
    chain.addStep(step2);

    // Set test completion handler
    TestCompletionHandler handler = new TestCompletionHandler();
    chain.setCompletionHandler(handler);

    // Start the chain and execute it synchronously in tests
    Test.startTest();
    Id jobId = chain.startChain();
    Test.stopTest(); // This forces all queueable jobs to complete

    // Verify steps were executed
    System.assertEquals(
      true,
      step1.executed,
      'Step 1 should have been executed'
    );
    System.assertEquals(
      true,
      step2.executed,
      'Step 2 should have been executed'
    );

    // Verify completion handler was called
    System.assertEquals(
      true,
      handler.completed,
      'Completion handler should have been called'
    );
    System.assertEquals(
      true,
      handler.success,
      'Chain should have completed successfully'
    );
  }

  /**
   * Test chain with error handling
   */
  @isTest
  static void testChainWithError() {
    // Create test steps with one that throws an error
    TestQueueableStep step1 = new TestQueueableStep('Step 1');
    ErrorStep errorStep = new ErrorStep('Error Step');
    TestQueueableStep step3 = new TestQueueableStep('Step 3');

    // Create chain that continues on error
    DuplicateQueueableChain chain = new DuplicateQueueableChain(
      'Error Test Chain'
    );
    chain.addStep(step1);
    chain.addStep(errorStep);
    chain.addStep(step3);
    chain.setContinueOnError(true);

    // Set test completion handler
    TestCompletionHandler handler = new TestCompletionHandler();
    chain.setCompletionHandler(handler);

    // Start the chain and execute it synchronously in tests
    Test.startTest();
    Id jobId = chain.startChain();
    Test.stopTest(); // This forces all queueable jobs to complete

    // Verify steps were executed
    System.assertEquals(
      true,
      step1.executed,
      'Step 1 should have been executed'
    );
    System.assertEquals(
      true,
      errorStep.executed,
      'Error step should have been executed'
    );
    System.assertEquals(
      true,
      step3.executed,
      'Step 3 should have been executed despite error'
    );

    // Verify completion handler was called
    System.assertEquals(
      true,
      handler.completed,
      'Completion handler should have been called'
    );
    System.assertEquals(
      false,
      handler.success,
      'Chain should have completed with errors'
    );

    // Verify error was recorded
    System.assertEquals(
      true,
      chain.hasErrors(),
      'Chain should have recorded errors'
    );
    System.assertEquals(
      1,
      chain.getErrorMessages().size(),
      'Chain should have one error message'
    );
  }

  /**
   * Test chain with error but not continuing
   */
  @isTest
  static void testChainStoppingOnError() {
    // Create test steps with one that throws an error
    TestQueueableStep step1 = new TestQueueableStep('Step 1');
    ErrorStep errorStep = new ErrorStep('Error Step');
    TestQueueableStep step3 = new TestQueueableStep('Step 3');

    // Create chain that stops on error (default behavior)
    DuplicateQueueableChain chain = new DuplicateQueueableChain(
      'Stop On Error Chain'
    );
    chain.addStep(step1);
    chain.addStep(errorStep);
    chain.addStep(step3);

    // Set test completion handler
    TestCompletionHandler handler = new TestCompletionHandler();
    chain.setCompletionHandler(handler);

    // Start the chain and execute it synchronously in tests
    Test.startTest();
    Id jobId = chain.startChain();
    Test.stopTest(); // This forces all queueable jobs to complete

    // Verify steps were executed
    System.assertEquals(
      true,
      step1.executed,
      'Step 1 should have been executed'
    );
    System.assertEquals(
      true,
      errorStep.executed,
      'Error step should have been executed'
    );
    System.assertEquals(
      false,
      step3.executed,
      'Step 3 should NOT have been executed after error'
    );

    // Verify completion handler was called
    System.assertEquals(
      true,
      handler.completed,
      'Completion handler should have been called'
    );
    System.assertEquals(
      false,
      handler.success,
      'Chain should have completed with errors'
    );

    // Verify error was recorded
    System.assertEquals(
      true,
      chain.hasErrors(),
      'Chain should have recorded errors'
    );
    System.assertEquals(
      1,
      chain.getErrorMessages().size(),
      'Chain should have one error message'
    );
  }

  /**
   * Test conditional step execution
   */
  @isTest
  static void testConditionalSteps() {
    // Create test steps
    TestQueueableStep step1 = new TestQueueableStep('Step 1');
    TestQueueableStep conditionalStep = new TestQueueableStep(
      'Conditional Step'
    );
    TestQueueableStep step3 = new TestQueueableStep('Step 3');

    // Create chain with conditional step
    DuplicateQueueableChain chain = new DuplicateQueueableChain(
      'Conditional Chain'
    );
    chain.addStep(step1);
    chain.addStepIf(conditionalStep, false); // Should not be added
    chain.addStep(step3);

    // Start the chain and execute it synchronously in tests
    Test.startTest();
    Id jobId = chain.startChain();
    Test.stopTest(); // This forces all queueable jobs to complete

    // Verify steps were executed
    System.assertEquals(
      true,
      step1.executed,
      'Step 1 should have been executed'
    );
    System.assertEquals(
      false,
      conditionalStep.executed,
      'Conditional step should NOT have been executed'
    );
    System.assertEquals(
      true,
      step3.executed,
      'Step 3 should have been executed'
    );

    // Verify total steps
    System.assertEquals(
      2,
      chain.getTotalSteps(),
      'Chain should have only 2 steps'
    );
  }

  /**
   * Test context values
   */
  @isTest
  static void testContextValues() {
    // Create test context aware step
    ContextAwareStep contextStep = new ContextAwareStep();

    // Create chain
    DuplicateQueueableChain chain = new DuplicateQueueableChain(
      'Context Chain'
    );
    chain.addStep(contextStep);

    // Set initial context value
    chain.setContextValue('test_key', 'test_value');

    // Start the chain and execute it synchronously in tests
    Test.startTest();
    Id jobId = chain.startChain();
    Test.stopTest(); // This forces all queueable jobs to complete

    // Verify context values
    System.assertEquals(
      'test_value',
      chain.getContextValue('test_key'),
      'Context value should be retrievable'
    );
    System.assertEquals(
      'step_added_value',
      chain.getContextValue('step_key'),
      'Step should have added context value'
    );

    // Test getting string value with default
    System.assertEquals(
      'default',
      chain.getContextValueAsString('nonexistent_key', 'default'),
      'Default value should be returned for missing key'
    );
  }

  /**
   * Test multiple steps added at once
   */
  @isTest
  static void testAddMultipleSteps() {
    // Create test steps
    TestQueueableStep step1 = new TestQueueableStep('Step 1');

    List<DuplicateQueueableChain.QueueableStep> steps = new List<DuplicateQueueableChain.QueueableStep>();
    // Add the step

    // Create chain and add steps
    DuplicateQueueableChain chain = new DuplicateQueueableChain(
      'Multiple Steps Chain'
    );
    chain.addStep(step1);
    chain.addSteps(steps);

    // Verify total steps
    System.assertEquals(1, chain.getTotalSteps(), 'Chain should have 1 step');

    // Start the chain and execute it synchronously in tests
    Test.startTest();
    Id jobId = chain.startChain();
    Test.stopTest(); // This forces all queueable jobs to complete

    // Verify all steps were executed
    System.assertEquals(
      true,
      step1.executed,
      'Step 1 should have been executed'
    );
  }

  /**
   * Test empty chain
   */
  @isTest
  static void testEmptyChain() {
    // Create chain with no steps
    DuplicateQueueableChain chain = new DuplicateQueueableChain('Empty Chain');

    // Start the chain
    Test.startTest();
    Id jobId = chain.startChain();
    Test.stopTest();

    // Verify no job was created
    System.assertEquals(null, jobId, 'Empty chain should not enqueue a job');
  }

  // ***** Helper classes for testing *****

  /**
   * Test QueueableStep implementation
   */
  public class TestQueueableStep implements DuplicateQueueableChain.QueueableStep {
    public String name;
    public Boolean executed = false;

    public TestQueueableStep(String name) {
      this.name = name;
    }

    public void execute(DuplicateQueueableChain chain) {
      this.executed = true;
      // Add the name to the chain context
      chain.setContextValue('executed_' + name, true);
    }
  }

  /**
   * Test QueueableStep that throws an error
   */
  public class ErrorStep implements DuplicateQueueableChain.QueueableStep {
    public String name;
    public Boolean executed = false;

    public ErrorStep(String name) {
      this.name = name;
    }

    public void execute(DuplicateQueueableChain chain) {
      this.executed = true;
      // Throw an error
      throw new TestException('Test exception from ' + name);
    }
  }

  /**
   * Test QueueableStep that works with context
   */
  public class ContextAwareStep implements DuplicateQueueableChain.QueueableStep {
    public void execute(DuplicateQueueableChain chain) {
      // Read and verify existing context value
      String value = (String) chain.getContextValue('test_key');
      System.assertEquals(
        'test_value',
        value,
        'Context value should be correct'
      );

      // Add new context value
      chain.setContextValue('step_key', 'step_added_value');
    }
  }

  /**
   * Test completion handler
   */
  public class TestCompletionHandler implements DuplicateQueueableChain.CompletionCallback {
    public Boolean completed = false;
    public Boolean success = false;

    public void execute(Boolean success) {
      this.completed = true;
      this.success = success;
    }
  }

  /**
   * Custom exception for testing
   */
  public class TestException extends Exception {
  }
}
