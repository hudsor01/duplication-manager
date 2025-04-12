/**
 * Simple utility class for duplication management
 */
public class DuplicationUtil {
    /**
     * Check if running in test context
     */
    public static Boolean isTestContext() {
        return Test.isRunningTest();
    }
}
