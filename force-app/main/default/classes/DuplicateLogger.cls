/**
 * Centralized logging utility for the Duplication Manager application
 * Provides consistent logging across the application with proper error handling
 * 
 * @author Richard Hudson
 * @date April 2025
 */
public without sharing class DuplicateLogger {
    
    // Logging levels
    public enum LogLevel {
        DEBUG,
        INFO,
        WARN,
        ERROR,
        FATAL
    }
    
    // Custom setting to control logging behavior
    private static final Boolean ENABLE_LOGGING = true; // Should be configurable via custom metadata or settings
    private static final Boolean LOG_TO_DATABASE = true; // Whether to store logs in custom object
    private static final LogLevel MIN_LOG_LEVEL = LogLevel.INFO; // Minimum level to log in production
    
    /**
     * Log a debug message (only in non-production or when debug enabled)
     * @param source The class or component logging the message
     * @param message The message to log
     */
    public static void debug(String source, String message) {
        log(LogLevel.DEBUG, source, message, null);
    }
    
    /**
     * Log an informational message
     * @param source The class or component logging the message
     * @param message The message to log
     */
    public static void info(String source, String message) {
        log(LogLevel.INFO, source, message, null);
    }
    
    /**
     * Log a warning message
     * @param source The class or component logging the message
     * @param message The message to log
     */
    public static void warn(String source, String message) {
        log(LogLevel.WARN, source, message, null);
    }
    
    /**
     * Log an error message
     * @param source The class or component logging the message
     * @param message The message to log
     * @param ex The exception, if any
     */
    public static void error(String source, String message, Exception ex) {
        log(LogLevel.ERROR, source, message, ex);
    }
    
    /**
     * Log an error message without an exception
     * @param source The class or component logging the message
     * @param message The message to log
     */
    public static void error(String source, String message) {
        log(LogLevel.ERROR, source, message, null);
    }
    
    /**
     * Log a fatal error message
     * @param source The class or component logging the message
     * @param message The message to log
     * @param ex The exception, if any
     */
    public static void fatal(String source, String message, Exception ex) {
        log(LogLevel.FATAL, source, message, ex);
    }
    
    /**
     * Main logging method that handles all log levels
     * @param level The log level
     * @param source The source of the log
     * @param message The message to log
     * @param ex The exception, if any
     */
    private static void log(LogLevel level, String source, String message, Exception ex) {
        // Skip logging if below minimum level
        if (level.ordinal() < MIN_LOG_LEVEL.ordinal() && !Test.isRunningTest()) {
            return;
        }
        
        // Append exception details if present
        String fullMessage = message;
        if (ex != null) {
            fullMessage += '\nException: ' + ex.getMessage();
            fullMessage += '\nStack trace: ' + ex.getStackTraceString();
        }
        
        // Log to debug logs if enabled
        if (ENABLE_LOGGING) {
            // Map our log levels to Salesforce LoggingLevel
            LoggingLevel sfLevel;
            if (level == LogLevel.DEBUG) {
                sfLevel = LoggingLevel.DEBUG;
            } else if (level == LogLevel.INFO) {
                sfLevel = LoggingLevel.INFO;
            } else if (level == LogLevel.WARN) {
                sfLevel = LoggingLevel.WARN;
            } else if (level == LogLevel.ERROR) {
                sfLevel = LoggingLevel.ERROR;
            } else if (level == LogLevel.FATAL) {
                sfLevel = LoggingLevel.ERROR;
            } else {
                sfLevel = LoggingLevel.INFO;
            }
            
            // Log to system debug logs (using source as prefix)
            String logEntry = '[' + source + '] ' + fullMessage;
            System.debug(sfLevel, logEntry);
        }
        
        // Store in database for ERROR and FATAL levels
        if (LOG_TO_DATABASE && (level == LogLevel.ERROR || level == LogLevel.FATAL)) {
            logToDatabase(level, source, fullMessage, ex);
        }
    }
    
    /**
     * Log to database for persistent storage of errors
     * @param level The log level
     * @param source The source of the log
     * @param message The message to log
     * @param ex The exception, if any
     */
    private static void logToDatabase(LogLevel level, String source, String message, Exception ex) {
        try {
            // Use DeduplicationLog__c as the logging object
            DeduplicationLog__c logEntry = new DeduplicationLog__c(
                ObjectApiName__c = source,
                ExecutionTime__c = System.now(),
                ConfigurationName__c = level.name(),
                InitiatedBy__c = UserInfo.getUserId()
            );
            
            // Truncate message if too long for field
            if (message.length() > 131072) { // 128KB limit for long text area
                message = message.substring(0, 131072);
            }
            
            // Store the message in an appropriate field (assuming CustomDescription__c is a long text area)
            // This would need to be updated based on the actual field structure
            // For now assuming we're using existing fields for a different purpose
            logEntry.RecordIdsJSON__c = message;
            
            // Add exception details if available
            if (ex != null) {
                // Save type and stack trace if fields exist
                // logEntry.ExceptionType__c = ex.getTypeName();
                // logEntry.StackTrace__c = ex.getStackTraceString();
            }
            
            // Check security before inserting
            if (Schema.SObjectType.DeduplicationLog__c.isCreateable()) {
                insert logEntry;
            }
        } catch (Exception e) {
            // If we can't log to database, at least log to debug logs
            System.debug(LoggingLevel.ERROR, 'Failed to write log to database: ' + e.getMessage());
        }
    }
    
    /**
     * Utility method to prepare an exception for logging
     * @param ex The exception to prepare
     * @return Formatted exception details
     */
    public static String formatException(Exception ex) {
        return 'Type: ' + ex.getTypeName() + 
               ', Message: ' + ex.getMessage() + 
               ', Line: ' + ex.getLineNumber() + 
               ', Stack: ' + ex.getStackTraceString();
    }
}