/**
 * FC_Exception - Custom exception hierarchy for the ForceCrew framework.
 * All ForceCrew-specific errors extend one of these typed exceptions,
 * allowing callers to handle framework errors distinctly from system exceptions.
 *
 * @group ForceCrew
 */
public virtual class FC_Exception extends Exception {

    /**
     * Thrown when the framework is misconfigured.
     * Examples: blank agent role, missing tasks, duplicate agent roles.
     */
    public class ConfigurationException extends Exception {}

    /**
     * Thrown when an agent cannot be resolved by role within a crew.
     */
    public class AgentNotFoundException extends Exception {}

    /**
     * Thrown when a tool cannot be found, instantiated, or executed.
     */
    public class ToolNotFoundException extends Exception {}

    /**
     * Thrown when the Salesforce Models API returns an error
     * or an unparseable / structurally invalid response.
     */
    public class LLMException extends Exception {}

    /**
     * Thrown when an individual task fails during execution.
     * Wraps the underlying error for crew-level error handling.
     */
    public class TaskExecutionException extends Exception {}

    /**
     * Thrown when the overall crew execution fails unexpectedly.
     */
    public class CrewExecutionException extends Exception {}

    /**
     * Thrown when an agent's ReAct loop or the manager agent exceeds
     * its configured maximum number of iterations without reaching a FINAL_ANSWER.
     */
    public class MaxIterationsException extends Exception {}
}
