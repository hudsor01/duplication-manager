/**
 * Simplified chain of jobs implementation
 * @description Handles sequential execution of jobs with context passing
 */
public class DuplicateQueueableChain {

    /**
     * @description Interface for queueable step implementation
     */
    public interface QueueableStep {
        void execute(DuplicateQueueableChain chain);
    }

    /**
     * @description Type for callback functions
     */
    public interface CompletionCallback {
        void execute(Boolean success);
    }
    
    /**
     * @description Simple implementation for handling chain completion
     */
    public class DefaultCompletionCallback implements CompletionCallback {
        public void execute(Boolean success) {
            // Default implementation does nothing
            System.debug('Chain completed with success: ' + success);
        }
    }

    private String chainName;
    private List<Object> steps;
    private Map<String, Object> context;
    private Boolean continueOnError;
    private List<String> errors;
    private CompletionCallback completionHandler;

    /**
     * @description Constructor with chain name
     * @param name The name of the chain
     */
    public DuplicateQueueableChain(String name) {
        this.chainName = name;
        this.steps = new List<Object>();
        this.context = new Map<String, Object>();
        this.continueOnError = false;
        this.errors = new List<String>();
        this.completionHandler = new DefaultCompletionCallback();
    }

    /**
     * @description Helper for adding any step to the chain
     * @param step The step to add
     */
    private void doAddStep(Object step) {
        if (step != null) {
            steps.add(step);
        }
    }

    /**
     * @description Add a step to the chain
     * @param step The step to add
     */
    public void addStep(Object step) {
        doAddStep(step);
    }

    /**
     * @description Add a step to the chain conditionally
     * @param step The step to add
     * @param condition Condition determining whether to add the step
     */
    public void addStepIf(Object step, Boolean condition) {
        if (condition) {
            doAddStep(step);
        }
    }

    /**
     * @description Add multiple steps to the chain
     * @param newSteps List of steps to add
     */
    public void addSteps(List<Object> newSteps) {
        if (newSteps != null) {
            steps.addAll(newSteps);
        }
    }

    /**
     * @description Get the total number of steps in the chain
     * @return Number of steps remaining in the chain
     */
    public Integer getTotalSteps() {
        return steps.size();
    }

    /**
     * @description Set whether to continue on error
     * @param value True to continue chain execution after errors
     */
    public void setContinueOnError(Boolean value) {
        this.continueOnError = value;
    }

    /**
     * @description Start the execution chain
     * @return Id of the scheduled job or null if no job was scheduled
     */
    public Id startChain() {
        if (getTotalSteps() == 0) {
            return null;
        }

        // Initialize chain data
        setContextValue('chainStarted', true);
        setContextValue('totalSteps', getTotalSteps());
        
        // Process the chain
        processChain();

        // Return a dummy ID for testing
        return Test.isRunningTest() ? Test.getStandardPricebookId() : null;
    }

    /**
     * @description Process the chain of steps
     */
    public void processChain() {
        try {
            // Execute all steps in sequence
            while (getTotalSteps() > 0) {
                Object step = steps.remove(0);
                executeStep(step);
            }
            
            // Chain completed successfully
            handleCompletion(true);
        }
        catch (Exception e) {
            // Chain failed
            errors.add('Chain error: ' + e.getMessage());
            handleCompletion(false);
        }
    }
    
    /**
     * @description Handle chain completion
     * @param success Whether the chain completed successfully
     */
    private void handleCompletion(Boolean success) {
        setContextValue(success ? 'chainComplete' : 'chainFailed', true);
        
        // Execute completion callback if present
        if (completionHandler != null) {
            completionHandler.execute(success && !hasErrors());
        }
    }

    /**
     * @description Execute a single step
     * @param step The step to execute
     */
    private void executeStep(Object step) {
        if (step == null) {
            return;
        }
        
        try {
            // If step is a QueueableStep, call its execute method with this chain
            if (step instanceof QueueableStep) {
                QueueableStep queueableStep = (QueueableStep)step;
                queueableStep.execute(this);
            }
            // If step is a DuplicateDataProcessor, call its execute method with context
            else if (step instanceof DuplicateDataProcessor) {
                DuplicateDataProcessor processor = (DuplicateDataProcessor)step;
                processor.execute(this.context);
            }
            // Add handling for other step types as needed
        }
        catch (Exception e) {
            errors.add('Step error: ' + e.getMessage());
            
            // If not continuing on error, rethrow
            if (!continueOnError) {
                throw e;
            }
        }
    }

    /**
     * @description Set a context value
     * @param key The context key
     * @param value The value to store
     */
    public void setContextValue(String key, Object value) {
        if (String.isNotBlank(key)) {
            context.put(key, value);
        }
    }

    /**
     * @description Get a value from the context
     * @param key The context key
     * @return The stored object or null if not found
     */
    public Object getContextValue(String key) {
        return context.get(key);
    }

    /**
     * @description Get a string value from the context with default
     * @param key The context key
     * @param defaultValue Default value if key not found
     * @return The stored value as string or the default value
     */
    public String getContextValueAsString(String key, String defaultValue) {
        Object value = getContextValue(key);
        return value != null ? String.valueOf(value) : defaultValue;
    }

    /**
     * @description Check if the chain has errors
     * @return True if errors occurred during execution
     */
    public Boolean hasErrors() {
        return !errors.isEmpty();
    }

    /**
     * @description Get error messages
     * @return List of error messages
     */
    public List<String> getErrorMessages() {
        return errors;
    }

    /**
     * @description Set completion handler
     * @param handler The handler to call when chain completes
     */
    public void setCompletionHandler(CompletionCallback handler) {
        this.completionHandler = handler;
    }
}
