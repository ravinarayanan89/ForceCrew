/**
 * FC_CrewExecutor - Orchestrates the execution of an FC_Crew.
 *
 * Routes execution to the appropriate strategy based on the crew's process type:
 *
 * SEQUENTIAL:
 *   Tasks run in declaration order. Outputs from completed tasks are accumulated
 *   in a context map and passed to subsequent tasks via their buildPrompt() method.
 *   If failFast=true (default), any task failure aborts the crew immediately.
 *   If failFast=false, failed tasks are logged and execution continues.
 *
 * HIERARCHICAL:
 *   Delegates to FC_ManagerAgent, which uses an LLM to dynamically assign tasks
 *   to agents and synthesise results across multiple rounds.
 *
 * @group ForceCrew
 */
public with sharing class FC_CrewExecutor {

    private FC_Crew crew;

    public FC_CrewExecutor(FC_Crew crew) {
        this.crew = crew;
    }

    // ─── Entry Point ──────────────────────────────────────────────────────────

    public FC_CrewResult execute(Map<String, Object> inputs) {
        FC_CrewResult result   = new FC_CrewResult(crew.getName());
        Long          startMs  = DateTime.now().getTime();

        FC_Logger.info('FC_CrewExecutor',
            'Starting crew "' + crew.getName() + '" ['
            + FC_Process.getLabel(crew.getProcess()) + ']'
        );

        try {
            switch on crew.getProcess() {
                when SEQUENTIAL    { executeSequential(result, inputs); }
                when HIERARCHICAL  { executeHierarchical(result, inputs); }
            }

            // The crew's final output is the last successful task's output
            String finalOutput = result.getLastTaskOutput();
            if (String.isBlank(finalOutput)) {
                finalOutput = 'All crew tasks completed.';
            }
            result.complete(finalOutput, DateTime.now().getTime() - startMs);

            FC_Logger.info('FC_CrewExecutor',
                'Crew "' + crew.getName() + '" completed. '
                + 'Tasks: ' + result.successfulTaskCount() + '/' + result.taskResults.size()
                + ' | Tool calls: ' + result.totalToolCalls()
            );

        } catch (Exception e) {
            FC_Logger.error('FC_CrewExecutor',
                'Crew "' + crew.getName() + '" failed: ' + e.getMessage());
            result.fail(e.getMessage(), DateTime.now().getTime() - startMs);
        }

        return result;
    }

    // ─── Sequential ───────────────────────────────────────────────────────────

    private void executeSequential(FC_CrewResult crewResult, Map<String, Object> inputs) {
        // Seed task output map with any provided inputs so tasks can reference them as context
        Map<String, String> taskOutputs = new Map<String, String>();
        if (inputs != null) {
            for (String key : inputs.keySet()) {
                Object val = inputs.get(key);
                taskOutputs.put(key, val != null ? String.valueOf(val) : '');
            }
        }

        for (FC_Task task : crew.getTasks()) {
            FC_Agent         agent    = resolveAgent(task);
            FC_AgentExecutor executor = new FC_AgentExecutor(agent);

            FC_Logger.info('FC_CrewExecutor',
                'Sequential: task "' + task.name + '" → agent "' + agent.role + '"');

            FC_TaskResult taskResult = executor.execute(task, taskOutputs);
            crewResult.addTaskResult(taskResult);

            if (taskResult.success) {
                taskOutputs.put(task.name, taskResult.output);
            } else {
                FC_Logger.warn('FC_CrewExecutor',
                    'Task "' + task.name + '" failed: ' + taskResult.errorMessage);
                if (crew.isFailFast()) {
                    throw new FC_Exception.TaskExecutionException(
                        'Task "' + task.name + '" failed: ' + taskResult.errorMessage
                    );
                }
            }
        }
    }

    // ─── Hierarchical ─────────────────────────────────────────────────────────

    private void executeHierarchical(FC_CrewResult crewResult, Map<String, Object> inputs) {
        FC_ManagerAgent manager = new FC_ManagerAgent(crew);
        manager.execute(crewResult, inputs);
    }

    // ─── Agent Resolution ─────────────────────────────────────────────────────

    private FC_Agent resolveAgent(FC_Task task) {
        if (String.isNotBlank(task.assignedAgentRole)) {
            FC_Agent agent = crew.getAgent(task.assignedAgentRole);
            if (agent == null) {
                throw new FC_Exception.AgentNotFoundException(
                    'No agent with role "' + task.assignedAgentRole
                    + '" found in crew "' + crew.getName() + '".'
                );
            }
            return agent;
        }

        // Fall back to first agent
        List<FC_Agent> agents = crew.getAgents();
        if (agents.isEmpty()) {
            throw new FC_Exception.ConfigurationException(
                'Crew "' + crew.getName() + '" has no agents.'
            );
        }
        FC_Logger.warn('FC_CrewExecutor',
            'Task "' + task.name + '" has no assigned agent. Defaulting to "' + agents[0].role + '".');
        return agents[0];
    }
}
