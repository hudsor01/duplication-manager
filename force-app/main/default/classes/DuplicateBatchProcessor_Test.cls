/**
 * @description Test utilities for batch processing
 *
 * @author Richard Hudson
 * @date April 2025
 */
public class DuplicateBatchProcessor_Test {
    /**
     * @description Test counter implementation for tracking batch execution
     */
    public class TestCounter {
        public Integer count = 0;
        public Boolean executeBatchCalled = false;
        public void increment() {
            count++;
        }
        public void incrementExecuteBatchCount() {
            executeBatchCalled = true;
            count++;
        }
    }
    // Static variable to hold mock counter
    private static TestCounter mockCounter;
    /**
     * @description Set mock counter for testing
     * @param counter The test counter instance to use for tracking
     */
    public static void setMockCounter(TestCounter counter) {
        mockCounter = counter;
    }
    /**
     * @description Get mock counter for testing
     * @return The currently set test counter instance
     */
    public static TestCounter getMockCounter() {
        return mockCounter;
    }
}
