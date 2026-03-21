/**
 * FC_Process - Defines and documents the available crew execution process types.
 *
 * SEQUENTIAL  — Tasks execute in the order they were added to the crew.
 *               Each task may optionally receive the outputs of prior tasks as context.
 *               Best for linear workflows with clear data dependencies.
 *
 * HIERARCHICAL — A manager LLM dynamically delegates tasks to the most appropriate
 *                agent, adapting based on intermediate results. Enables flexible,
 *                non-linear orchestration.
 *                Requires managerLlmModel to be set on the crew.
 *
 * @group ForceCrew
 */
public class FC_Process {

    public enum Type {
        SEQUENTIAL,
        HIERARCHICAL
    }

    /** Returns the human-readable label for a process type. */
    public static String getLabel(Type processType) {
        switch on processType {
            when SEQUENTIAL    { return 'Sequential'; }
            when HIERARCHICAL  { return 'Hierarchical'; }
            when else          { return 'Unknown'; }
        }
    }

    /** Returns the description for a process type. */
    public static String getDescription(Type processType) {
        switch on processType {
            when SEQUENTIAL {
                return 'Tasks execute in order. Outputs from prior tasks are passed as context to subsequent tasks.';
            }
            when HIERARCHICAL {
                return 'A manager LLM dynamically delegates tasks to agents based on their roles and goals.';
            }
            when else {
                return '';
            }
        }
    }
}
