# ForceCrew

**crewAI for Salesforce — Native multi-agent AI orchestration in Apex**

ForceCrew is an open-source framework that brings the [crewAI]([https://github.com/crewAIInc/crewAI](https://github.com/crewAIInc/crewAI)) programming model to the Salesforce platform. Build teams of collaborating AI agents powered by the **Salesforce Models API** — no HTTP callouts, no Named Credentials, no external dependencies.

```apex

FC_CrewResult result = new FC_Crew.Builder('Revenue Intelligence')

    .agent(analyst).agent(writer)

    .task(dataTask).task(summaryTask)

    .verbose(true)

    .build()

    .kickoff();

System.debug(result.finalOutput);

```

---

## Table of Contents

1. [Why ForceCrew](#why-forcecrew)

2. [Architecture Overview](#architecture-overview)

3. [Installation](#installation)

4. [Core Concepts](#core-concepts)

   - [Crew](#crew)

   - [Agent](#agent)

   - [Task](#task)

   - [Tool](#tool)

5. [Choosing Your LLM Model](#choosing-your-llm-model)

6. [Quick Start](#quick-start)

7. [Execution Modes](#execution-modes)

   - [Sequential](#sequential-mode)

   - [Hierarchical](#hierarchical-mode)

8. [Calling from Apex](#calling-from-apex)

9. [Calling from LWC](#calling-from-lwc)

   - [Full Transaction](#full-transaction-lwc)

   - [Step-by-Step (Governor-Limit Safe)](#step-by-step-lwc)

10. [Async Execution (Queueable)](#async-execution-queueable)

11. [Building Custom Tools](#building-custom-tools)

12. [Logging & Observability](#logging--observability)

13. [Error Handling](#error-handling)

14. [API Reference](#api-reference)

15. [Class Inventory](#class-inventory)

16. [Testing](#testing)

17. [Requirements](#requirements)

---

## Why ForceCrew

Salesforce's native Models API gives you access to powerful LLMs but leaves the agentic layer entirely up to you. ForceCrew fills that gap with a production-ready framework that mirrors crewAI's mental model so Salesforce developers can build multi-agent solutions without reinventing the wheel.

| crewAI (Python) | ForceCrew (Apex) |

|-----------------|-----------------|

| `Crew` | `FC_Crew` |

| `Agent` | `FC_Agent` |

| `Task` | `FC_Task` |

| `Tool` | `FC_Tool` / `FC_IMCPTool` |

| `Process.sequential` | `FC_Process.Type.SEQUENTIAL` |

| `Process.hierarchical` | `FC_Process.Type.HIERARCHICAL` |

**Key advantages:**

- **100% native** — runs entirely inside your Salesforce org using `aiplatform.ModelsAPI`

- **No external dependencies** — no Named Credentials, no Remote Site Settings, no secrets to manage

- **Governor-limit aware** — step-by-step execution mode lets LWC drive the loop across transactions

- **Production patterns** — Builder constructors, typed exceptions, structured logging, async Queueable chaining

- **LWC-ready** — AuraEnabled controller with serialisable DTOs for real-time UI integration

---

## Architecture Overview

```

┌─────────────────────────────────────────────────────────────────┐

│                        Entry Points                             │

│                                                                 │

│  Apex Code           LWC Component         Async/Background     │

│  ForceCrew.runAgent  FC_CrewController      FC_CrewQueueable    │

│  FC_Crew.kickoff()   @AuraEnabled methods   Queueable chain     │

└──────────┬───────────────────┬──────────────────┬──────────────┘

           │                   │                  │

           └───────────────────▼──────────────────┘

                               │

                    ┌──────────▼──────────┐

                    │   FC_CrewExecutor   │

                    │  (Routes execution) │

                    └────────┬────────────┘

                             │

              ┌──────────────┴──────────────┐

              │                             │

    ┌─────────▼─────────┐       ┌───────────▼────────────┐

    │    SEQUENTIAL      │       │     HIERARCHICAL        │

    │                   │       │                         │

    │  Task 1 → Task 2  │       │  FC_ManagerAgent        │

    │  (context chain)  │       │  (LLM orchestrator)     │

    └─────────┬─────────┘       └───────────┬─────────────┘

              │                             │

              └──────────────┬──────────────┘

                             │

                  ┌──────────▼──────────┐

                  │  FC_AgentExecutor   │

                  │  (ReAct loop)       │

                  │                     │

                  │  think → act → loop │

                  └──────────┬──────────┘

                             │

              ┌──────────────┴──────────────┐

              │                             │

    ┌─────────▼─────────┐       ┌───────────▼──────────┐

    │  FC_ModelsAPI      │       │  FC_Tool.execute()   │

    │  Service           │       │  (your tool impl)    │

    │  (LLM calls)       │       │                      │

    └───────────────────┘       └──────────────────────┘

```

### ReAct Loop (How Agents Think)

Each agent runs a **Reason + Act** loop until it has a final answer:

```

System Prompt (role + tools schema)

         │

         ▼

   User Task Prompt ──► LLM Call

                              │

              ┌───────────────┴───────────────┐

              │                               │

       { action: "TOOL_CALL" }       { action: "FINAL_ANSWER" }

              │                               │

       Execute Tool                      Return result

              │                               │

       Add result to history                  │

              │                               │

         Loop ◄                               │

                                              ▼

                                       FC_TaskResult

```

---

## Installation

### Prerequisites

- Salesforce DX CLI `sf` or `sfdx`)

- Salesforce org with **Einstein AI features enabled** (required for `aiplatform.ModelsAPI`)

- API version **62.0 or higher**

### Deploy to Scratch Org

```bash

# Clone the repository

git clone [https://github.com/your-org/forcecrew.git](https://github.com/your-org/forcecrew.git)

cd forcecrew

# Authenticate to your Dev Hub

sf org login web --set-default-dev-hub

# Create scratch org

sf org create scratch --definition-file config/project-scratch-def.json --alias forcecrew-dev --set-default

# Push source

sf project deploy start

# Run tests

sf apex run test --synchronous --result-format human

```

### Deploy to Sandbox / Production

```bash

# Authenticate

sf org login web --alias my-sandbox

# Deploy

sf project deploy start --target-org my-sandbox

```

### FC_CrewRun__c Custom Object (for Backend Async Only)

Only needed if you use `FC_CrewQueueable` from a **trigger, scheduled job, or batch process**. Not required for LWC — use the [Step-by-Step pattern](#step-by-step-lwc--recommended-for-complex-tasks) instead.

`FC_CrewRun__c` is included in the repo and deploys automatically with `sf project deploy start`. No manual setup needed.

---

## Core Concepts

### Crew

A **Crew** is the top-level container. It holds agents, tasks, and the execution strategy. Think of it as the team manager that coordinates everyone.

```apex

FC_Crew crew = new FC_Crew.Builder('My Crew')

    .process(FC_Process.Type.SEQUENTIAL)   // default; or HIERARCHICAL

    .agent(agentA)

    .agent(agentB)

    .task(task1)

    .task(task2)

    .verbose(true)                          // enables debug logging

    .failFast(true)                         // abort on first task failure

    .build();

FC_CrewResult result = crew.kickoff();

// or with runtime inputs (injected into task descriptions)

FC_CrewResult result = crew.kickoff(new Map<String, Object>{ 'quarter' => 'Q1 2025' });

```

### Agent

An **Agent** is an AI persona with a role, goal, backstory, and a set of tools. The role must be unique within a crew.

```apex

FC_Agent analyst = new FC_Agent.Builder('Data Analyst')

    .goal('Query Salesforce data and surface actionable insights')

    .backstory('You are an expert in Salesforce reporting and SOQL.')

    .tool(FC_Tool.fromMCP(new FC_SampleSOQLTool()))

    .tool(FC_Tool.fromMCP(new FC_SampleDescribeTool()))

    .maxIterations(10)                      // ReAct loop limit (default: 10)

    .llmModel(FC_ModelsAPIService.MODEL_CLAUDE_OPUS45)

    .build();

```

### Task

A **Task** is a unit of work. Tasks can be chained so that later tasks receive the output of earlier ones as context.

```apex

FC_Task dataTask = new FC_Task.Builder('Pull Account Data')

    .description('Query the top 10 Accounts by AnnualRevenue in the APAC region.')

    .expectedOutput('A JSON array of {Name, AnnualRevenue} objects.')

    .assignToAgent('Data Analyst')

    .build();

FC_Task summaryTask = new FC_Task.Builder('Write Summary')

    .description('Summarise the account data into 3 executive bullets.')

    .expectedOutput('Three concise bullet points suitable for a VP presentation.')

    .assignToAgent('Writer')

    .withContext('Pull Account Data')       // receives output of previous task

    .build();

```

If a task is not assigned to an agent, ForceCrew assigns it to the first available agent in sequential mode, or lets the manager agent decide in hierarchical mode.

### Tool

A **Tool** is a callable function the agent can invoke. ForceCrew supports three styles:

**1. FC_IMCPTool (recommended)** — self-describing tool, safest to use everywhere including async:

```apex

public class MyAccountTool implements FC_IMCPTool {

    public String getName()        { return 'GetAccountRevenue'; }

    public String getDescription() { return 'Returns annual revenue for a given Account name.'; }

    public List<FC_ToolParameter> getParameters() {

        return new List<FC_ToolParameter>{

            new FC_ToolParameter.Builder('accountName', FC_ToolParameter.TYPE_STRING)

                .description('The exact name of the Account record.')

                .required()

                .build()

        };

    }

    public String execute(Map<String, Object> params) {

        String name = (String) params.get('accountName');

        List<Account> accs = [SELECT AnnualRevenue FROM Account WHERE Name = :name LIMIT 1];

        if (accs.isEmpty()) return JSON.serialize(new Map<String,Object>{ 'success' => false, 'error' => 'Not found' });

        return JSON.serialize(new Map<String,Object>{ 'success' => true, 'revenue' => accs[0].AnnualRevenue });

    }

}

// Register with an agent

FC_Tool myTool = FC_Tool.fromMCP(new MyAccountTool());

```

**2. FC_ITool (minimal)** — for simple tools where you control the name/description separately:

```apex

public class SimpleTool implements FC_ITool {

    public String execute(Map<String, Object> params) {

        return JSON.serialize(new Map<String, Object>{ 'success' => true, 'result' => 'done' });

    }

}

FC_Tool tool = FC_Tool.from('DoSomething', 'Does something useful', new SimpleTool());

```

**3. Class-name instantiation** — required for async/queueable crews:

```apex

// Tool class must implement FC_IMCPTool and have a no-arg constructor

FC_Tool tool = FC_Tool.fromClassName('MyAccountTool');

```

**Tool return contract:** Every tool's `execute()` must return a valid JSON string with at minimum a `"success"` key (Boolean). Agents read this output and can see errors.

---

## Choosing Your LLM Model

All model identifiers are defined as constants on `FC_ModelsAPIService`. Always reference these constants — never hard-code the raw string.

All constants live on `FC_ModelsAPIService`. Use `MODEL_DEFAULT` when you want the framework default, which is `MODEL_CLAUDE_OPUS45`.

| Constant | Provider | Notes |

|----------|----------|-------|

| `MODEL_DEFAULT` | — | Alias for `MODEL_CLAUDE_OPUS45`; used when `.llmModel()` is not called |

| `MODEL_CLAUDE_OPUS45` | Claude / Bedrock | ⭐ Default — strongest reasoning, best for complex tasks |

| `MODEL_CLAUDE_SONNET45` | Claude / Bedrock | Fast and capable; good balance for most tasks |

| `MODEL_CLAUDE_HAIKU45` | Claude / Bedrock | Fastest Claude; good for high-volume simple tasks |

| `MODEL_GPT4O` | OpenAI / Geo-aware | Strong general-purpose model |

| `MODEL_GPT41` | OpenAI / Geo-aware | Next-gen GPT-4 class |

| `MODEL_GPT5` | OpenAI / Geo-aware | Highest-capability OpenAI model |

| `MODEL_O3` | OpenAI / Geo-aware | Deep reasoning; slower but thorough |

| `MODEL_GEMINI3_PRO` | Google / Vertex | Strong multimodal reasoning |

| `MODEL_GEMINI25_FLASH` | Google / Vertex | Fast and cost-effective Gemini |

| `MODEL_NOVA_PRO` | Amazon / Bedrock | Amazon's flagship Nova model |

See the [API Reference](#api-reference) for the full constant list.

### Set model per agent

Use `.llmModel()` on `FC_Agent.Builder`. Each agent in a crew can use a different model.

```apex

FC_Agent analyst = new FC_Agent.Builder('Data Analyst')

    .goal('Analyse Salesforce pipeline data.')

    .llmModel(FC_ModelsAPIService.MODEL_CLAUDE_OPUS45)    // high-capability tasks

    .build();

FC_Agent summariser = new FC_Agent.Builder('Summariser')

    .goal('Write concise executive summaries.')

    .llmModel(FC_ModelsAPIService.MODEL_CLAUDE_HAIKU45)   // fast, cost-effective

    .build();

```

If `.llmModel()` is not called, the agent defaults to `MODEL_DEFAULT` (`MODEL_CLAUDE_OPUS45`).

### Set model for the manager (hierarchical mode)

In hierarchical mode the manager agent is created internally by ForceCrew. Set its model via `.managerLlmModel()` on `FC_Crew.Builder`.

```apex

new FC_Crew.Builder('My Hierarchical Crew')

    .process(FC_Process.Type.HIERARCHICAL)

    .managerLlmModel(FC_ModelsAPIService.MODEL_CLAUDE_OPUS45)   // manager needs strong reasoning

    .agent(researcher)

    .agent(writer)

    .task(gatherTask)

    .task(writeTask)

    .build()

    .kickoff();

```

If `.managerLlmModel()` is not called, the manager also defaults to `MODEL_DEFAULT` (`MODEL_CLAUDE_OPUS45`).

---

## Quick Start

### Single Agent, One Task

```apex

// The simplest possible usage — one agent, one task

String answer = ForceCrew.runAgent(

    'SOQL Expert',                                          // role

    'Query Salesforce data accurately and concisely.',      // goal

    'You have deep knowledge of SOQL and Salesforce objects.', // backstory

    new List<FC_Tool>{ FC_Tool.fromMCP(new FC_SampleSOQLTool()) }, // tools

    'How many open Opportunities are there in the org?',    // task description

    'A plain English sentence with the count.'              // expected output

);

System.debug(answer);

```

### Two Agents, Two Tasks (Sequential)

```apex

FC_Agent analyst = new FC_Agent.Builder('Analyst')

    .goal('Query and analyse Salesforce data.')

    .tool(FC_Tool.fromMCP(new FC_SampleSOQLTool()))

    .build();

FC_Agent writer = new FC_Agent.Builder('Writer')

    .goal('Produce clear, concise summaries for business stakeholders.')

    .build();

FC_Task fetchTask = new FC_Task.Builder('Fetch Opportunities')

    .description('Get the top 5 Opportunities by Amount that are Closed Won this year.')

    .expectedOutput('JSON array of {Name, Amount, CloseDate}.')

    .assignToAgent('Analyst')

    .build();

FC_Task writeTask = new FC_Task.Builder('Write Report')

    .description('Write a 2-paragraph executive summary of the opportunity data.')

    .expectedOutput('Two paragraphs suitable for a board report.')

    .assignToAgent('Writer')

    .withContext('Fetch Opportunities')

    .build();

FC_CrewResult result = new FC_Crew.Builder('Sales Report Crew')

    .agent(analyst)

    .agent(writer)

    .task(fetchTask)

    .task(writeTask)

    .verbose(true)

    .build()

    .kickoff();

if (result.success) {

    System.debug('Final output: ' + result.finalOutput);

} else {

    System.debug('Error: ' + result.errorMessage);

}

```

---

## Execution Modes

### Sequential Mode

Tasks execute in **declaration order**. Each task's output is available as context to all subsequent tasks that declare it via `.withContext()`.

```

Task 1 ──► output ──► Task 2 ──► output ──► Task 3

                        ▲                      ▲

                    (context               (context

                    from T1)               from T1,T2)

```

```apex

new FC_Crew.Builder('My Sequential Crew')

    .process(FC_Process.Type.SEQUENTIAL)    // this is the default

    // ...

    .build();

```

### Hierarchical Mode

A **Manager Agent** (an LLM) dynamically decides which agent executes which task and in what order. The manager issues `DELEGATE` directives and adapts based on intermediate results.

```

          FC_ManagerAgent (LLM)

          /         |         \

    Agent A      Agent B      Agent C

    Task 1       Task 3       Task 2   ← order decided at runtime

```

```apex

new FC_Crew.Builder('My Hierarchical Crew')

    .process(FC_Process.Type.HIERARCHICAL)

    .managerLlmModel(FC_ModelsAPIService.MODEL_CLAUDE_OPUS45)

    .agent(researcher)

    .agent(analyst)

    .agent(writer)

    .task(gatherDataTask)

    .task(analyseTask)

    .task(writeFinalTask)

    .build()

    .kickoff();

```

The manager uses this JSON protocol internally:

```json

// Assign a task

{ "action": "DELEGATE", "task": "Gather Data", "agent": "Researcher", "instruction": "Focus on APAC region" }

// Done

{ "action": "FINAL_ANSWER", "summary": "All tasks completed successfully." }

```

---

## Calling from Apex

### Synchronous (Full Transaction)

```apex

// Standard crew execution

FC_CrewResult result = new FC_Crew.Builder('...')

    .agent(...).task(...)

    .build()

    .kickoff();

// With runtime inputs (available as context in task descriptions)

FC_CrewResult result = crew.kickoff(

    new Map<String, Object>{ 'region' => 'EMEA', 'quarter' => 'Q2' }

);

// Inspect results

result.success                  // Boolean

result.finalOutput              // String — last successful task's output

result.totalExecutionTimeMs     // Long

result.totalToolCalls()         // Integer — sum across all tasks

result.successfulTaskCount()    // Integer

for (FC_TaskResult tr : result.taskResults) {

    System.debug(tr.taskName + ': ' + tr.output);

    System.debug('Tool calls: ' + tr.toolCallCount());

    for (FC_StepResult step : tr.steps) {

        if (step.stepType == FC_StepResult.StepType.TOOL_CALL) {

            System.debug('Called: ' + step.toolName + ' → ' + step.toolResult);

        }

    }

}

```

### Reading Logs After Execution

```apex

// Get all log entries

List<FC_Logger.LogEntry> entries = FC_Logger.getBuffer();

// Filter by level

List<FC_Logger.LogEntry> errors = FC_Logger.getBuffer(FC_Logger.Level.WARN);

// Dump to string

String logDump = FC_Logger.dump();

System.debug(logDump);

```

---

## Calling from LWC

ForceCrew provides `FC_CrewController` — an `@AuraEnabled` Apex controller with two integration patterns.

### Choosing the Right LWC Pattern

| Scenario | Recommended Pattern |

|---|---|

| Single agent, 1-3 tool calls expected | Full Transaction `runCrewFromConfig` / `runSingleAgent`) |

| Multi-agent crew or many ReAct steps | **Step-by-Step** `initAgentStep` + `runAgentStep`) |

| Backend trigger / scheduled job | Queueable — write result back to a record |

| Long batch processing, no UI | Batch Apex |

> **Why not Platform Events for LWC?** Platform Events are capped at **250,000 deliveries/day org-wide**. For a framework used frequently across multiple users or automations, this limit is hit quickly. The step-by-step pattern uses plain `@AuraEnabled` calls with no event consumption and is the preferred approach for all LWC integrations.

### Full Transaction (LWC)

**Best for:** Short tasks that complete within a single Apex transaction (≤ 3 LLM calls expected).

```javascript

// myAgentComponent.js

import { LightningElement } from 'lwc';

import runSingleAgent from '@salesforce/apex/FC_CrewController.runSingleAgent';

import runCrewFromConfig from '@salesforce/apex/FC_CrewController.runCrewFromConfig';

export default class MyAgentComponent extends LightningElement {

    // Single agent shortcut

    async runSingleAgent() {

        const result = await runSingleAgent({

            agentRole: 'SOQL Expert',

            goal: 'Query Salesforce data accurately.',

            backstory: 'You are a Salesforce reporting specialist.',

            toolClasses: ['FC_SampleSOQLTool'],    // class names — no-arg constructor required

            taskDescription: 'Count all open Opportunities.',

            expectedOutput: 'A number.'

        });

        console.log(result.finalOutput);

        console.log(result.totalToolCalls);

        console.log(result.logs);                  // array of log strings

    }

    // Full crew from JSON config

    async runCrew() {

        const crewConfig = {

            crewName: 'Revenue Crew',

            process: 'SEQUENTIAL',

            verbose: true,

            failFast: true,

            agents: [

                {

                    role: 'Analyst',

                    goal: 'Analyse revenue data.',

                    backstory: 'Expert in Salesforce reporting.',

                    toolClassNames: ['FC_SampleSOQLTool'],

                    maxIterations: 10,

                    llmModel: 'sfdc_ai__DefaultGPT4Omni'

                }

            ],

            tasks: [

                {

                    name: 'Revenue Query',

                    description: 'Get total Closed Won revenue this quarter.',

                    expectedOutput: 'A dollar amount.',

                    assignedAgentRole: 'Analyst',

                    contextTaskNames: []

                }

            ]

        };

        const result = await runCrewFromConfig({ crewConfigJson: JSON.stringify(crewConfig) });

        console.log(result.success, result.finalOutput);

    }

}

```

**CrewResultDTO shape returned to LWC:**

```javascript

{

    success: true,

    crewName: 'Revenue Crew',

    finalOutput: 'Total Closed Won revenue is $4.2M.',

    errorMessage: null,

    executionTimeMs: 8432,

    taskCount: 1,

    successfulTasks: 1,

    totalToolCalls: 2,

    tasks: [

        {

            taskName: 'Revenue Query',

            agentRole: 'Analyst',

            output: 'Total Closed Won revenue is $4.2M.',

            success: true,

            executionTimeMs: 8100,

            toolCallCount: 2,

            steps: [

                { stepType: 'TOOL_CALL', thought: '...', toolName: 'QueryRecords', toolResult: '...' },

                { stepType: 'FINAL_ANSWER', thought: '...', answer: 'Total Closed Won revenue is $4.2M.' }

            ]

        }

    ],

    logs: ['[ForceCrew] [INFO] [Crew] Starting crew: Revenue Crew', '...']

}

```

### Step-by-Step (LWC) — Recommended for Complex Tasks

**Best for:** Multi-agent crews, tasks with many tool calls, or any ReAct loop that might exceed governor limits in a single transaction.

Each `runAgentStep` call is a **separate Apex transaction** — governor limits reset on every call. The LWC JS holds the conversation state `FC_StepRequest`) between calls. No Platform Events, no Queueable, no polling required.

#### Single Agent, Step-by-Step

```javascript

// myStepComponent.js

import initAgentStep from '@salesforce/apex/FC_CrewController.initAgentStep';

import runAgentStep from '@salesforce/apex/FC_CrewController.runAgentStep';

export default class MyStepComponent extends LightningElement {

    steps = [];

    finalAnswer = '';

    isRunning = false;

    async runStepByStep() {

        this.isRunning = true;

        this.steps = [];

        const agentConfig = {

            role: 'Analyst',

            goal: 'Query and analyse data.',

            backstory: 'Expert Salesforce developer.',

            toolClasses: ['FC_SampleSOQLTool', 'FC_SampleDescribeTool'],

            maxIterations: 10

        };

        const taskConfig = {

            name: 'Analysis Task',

            description: 'Find the 5 accounts with the most open opportunities.',

            expectedOutput: 'A ranked list with account name and opportunity count.',

            assignToAgent: 'Analyst'

        };

        // Step 1: Initialise (no LLM call — just builds prompts and state)

        let state = await initAgentStep({

            agentConfigJson: JSON.stringify(agentConfig),

            taskConfigJson: JSON.stringify(taskConfig),

            priorOutputsJson: null

        });

        // Steps 2..N: One LLM call per Apex transaction

        while (!state.isComplete && !state.errorMessage) {

            state = await runAgentStep({

                agentConfigJson: JSON.stringify(agentConfig),

                stepRequestJson: JSON.stringify(state)   // JS owns the memory

            });

            // Render intermediate steps in UI as they happen

            if (state.lastStepJson) {

                this.steps = [...this.steps, JSON.parse(state.lastStepJson)];

            }

        }

        this.finalAnswer = state.finalAnswer;

        this.isRunning = false;

    }

}

```

#### Multi-Agent Crew, JS-Driven

For multi-agent crews, JS manages the `taskOutputs` map between agents. Each agent runs its own step loop and passes its result to the next.

```javascript

async runMultiAgentCrew() {

    const tasks = [

        {

            agentConfig: { role: 'Researcher', goal: '...', backstory: '...', toolClasses: ['FC_SampleSOQLTool'] },

            taskConfig:  { name: 'Gather Data', description: '...', expectedOutput: '...', assignToAgent: 'Researcher' }

        },

        {

            agentConfig: { role: 'Writer', goal: '...', backstory: '...', toolClasses: [] },

            taskConfig:  { name: 'Write Report', description: '...', expectedOutput: '...', assignToAgent: 'Writer', contextTasks: ['Gather Data'] }

        }

    ];

    const taskOutputs = {};   // JS holds inter-task context — replaces FC_CrewExecutor's taskOutputs map

    for (const { agentConfig, taskConfig } of tasks) {

        let state = await initAgentStep({

            agentConfigJson:  JSON.stringify(agentConfig),

            taskConfigJson:   JSON.stringify(taskConfig),

            priorOutputsJson: JSON.stringify(taskOutputs)   // prior task results injected as context

        });

        while (!state.isComplete && !state.errorMessage) {

            state = await runAgentStep({

                agentConfigJson: JSON.stringify(agentConfig),

                stepRequestJson: JSON.stringify(state)

            });

            if (state.lastStepJson) {

                this.steps = [...this.steps, JSON.parse(state.lastStepJson)];

            }

        }

        // Store output for the next agent

        taskOutputs[[taskConfig.name](http://taskConfig.name)] = state.finalAnswer;

    }

    this.finalAnswer = taskOutputs[tasks[tasks.length - 1].[taskConfig.name](http://taskConfig.name)];

}

```

**State object (FC_StepRequest) passed between calls:**

```javascript

{

    historyJson: '...',        // serialised conversation history

    agentRole: 'Analyst',

    taskName: 'Analysis Task',

    isComplete: false,         // true when FINAL_ANSWER reached

    finalAnswer: null,         // populated when isComplete = true

    iterationCount: 3,

    maxIterations: 10,

    errorMessage: null,

    lastStepJson: '{ "stepType": "TOOL_CALL", "toolName": "QueryRecords", ... }'

}

```

---

## Async Execution (Queueable)

**Use this for backend-only flows** — triggers, scheduled jobs, or batch processes where there is no UI waiting for a result. The crew runs in a Queueable chain and writes its result back to `FC_CrewRun__c` when complete. Query that record to check status or read the output.

> For LWC integrations, use the [Step-by-Step pattern](#step-by-step-lwc--recommended-for-complex-tasks) instead.

### Setup

Create the **FC_CrewRun__c** custom object:

| Field | Type | Size |

|-------|------|------|

| `CrewName__c` | Text | 255 |

| `Status__c` | Picklist | Pending, Running, Completed, Failed |

| `CrewConfigJson__c` | Long Text Area | 131,072 |

| `TaskOutputsJson__c` | Long Text Area | 131,072 |

| `FinalOutput__c` | Long Text Area | 32,768 |

| `ErrorMessage__c` | Text | 1,024 |

| `CorrelationId__c` | Text | 255 |

### Enqueue a Crew

```apex

FC_Crew crew = new FC_Crew.Builder('Background Analysis')

    .agent(new FC_Agent.Builder('Analyst')

        .goal('Deep data analysis.')

        .tool(FC_Tool.fromClassName('FC_SampleSOQLTool'))  // IMPORTANT: use fromClassName for async

        .build())

    .task(new FC_Task.Builder('Heavy Analysis')

        .description('Analyse 6 months of pipeline data and identify trends.')

        .expectedOutput('A structured trend report.')

        .assignToAgent('Analyst')

        .build())

    .build();

// Returns the FC_CrewRun__c record Id

Id runId = FC_CrewQueueable.enqueue(crew, new Map<String, Object>(), 'my-correlation-id-001');

```

> **Important:** Tools in async crews must be registered via `FC_Tool.fromClassName('ClassName')`. Tools registered with `FC_Tool.from(name, desc, new MyTool())` hold object references that cannot be serialised across Queueable jobs.

### Checking Results

After enqueuing, query `FC_CrewRun__c` to check status:

```apex

FC_CrewRun__c run = [

    SELECT Status__c, FinalOutput__c, ErrorMessage__c

    FROM FC_CrewRun__c

    WHERE Id = :runId

];

if (run.Status__c == 'Completed') {

    System.debug(run.FinalOutput__c);

} else if (run.Status__c == 'Failed') {

    System.debug(run.ErrorMessage__c);

}

```

---

## Building Custom Tools

### Implementing FC_IMCPTool (Recommended)

```apex

public class SalesforceMetricsTool implements FC_IMCPTool {

    public String getName() {

        return 'GetSalesMetrics';

    }

    public String getDescription() {

        return 'Returns key sales metrics for a given time period and region.';

    }

    public List<FC_ToolParameter> getParameters() {

        return new List<FC_ToolParameter>{

            new FC_ToolParameter.Builder('startDate', FC_ToolParameter.TYPE_STRING)

                .description('Start date in YYYY-MM-DD format.')

                .required()

                .build(),

            new FC_ToolParameter.Builder('endDate', FC_ToolParameter.TYPE_STRING)

                .description('End date in YYYY-MM-DD format.')

                .required()

                .build(),

            new FC_ToolParameter.Builder('region', FC_ToolParameter.TYPE_STRING)

                .description('Region filter: APAC, EMEA, AMER, or ALL.')

                .defaultValue('ALL')

                .build()

        };

    }

    public String execute(Map<String, Object> params) {

        try {

            String startDate = (String) params.get('startDate');

            String endDate   = (String) params.get('endDate');

            String region    = params.containsKey('region') ? (String) params.get('region') : 'ALL';

            // Your Salesforce logic here

            AggregateResult[] results = [

                SELECT COUNT(Id) total, SUM(Amount) revenue

                FROM Opportunity

                WHERE CloseDate >= :Date.valueOf(startDate)

                AND CloseDate <= :Date.valueOf(endDate)

                AND StageName = 'Closed Won'

            ];

            return JSON.serialize(new Map<String, Object>{

                'success'  => true,

                'region'   => region,

                'total'    => results[0].get('total'),

                'revenue'  => results[0].get('revenue')

            });

        } catch (Exception e) {

            return JSON.serialize(new Map<String, Object>{

                'success' => false,

                'error'   => e.getMessage()

            });

        }

    }

}

```

### Registering Tools

```apex

// Option A: fromMCP (synchronous crews only — holds object reference)

FC_Tool tool = FC_Tool.fromMCP(new SalesforceMetricsTool());

// Option B: fromClassName (works in synchronous AND async crews)

FC_Tool tool = FC_Tool.fromClassName('SalesforceMetricsTool');

// Option C: from() with explicit metadata (for FC_ITool implementations)

FC_Tool tool = FC_Tool.from(

    'GetSalesMetrics',

    'Returns key sales metrics for a given time period and region.',

    new List<FC_ToolParameter>{ /* parameters */ },

    new SalesforceMetricsTool()

);

```

### Tool Return Contract

All tools **must** return a JSON string. The `"success"` key is required:

```apex

// Success

return JSON.serialize(new Map<String, Object>{

    'success' => true,

    'data'    => myData

});

// Failure (agent will see this and can retry or adjust)

return JSON.serialize(new Map<String, Object>{

    'success' => false,

    'error'   => 'Record not found for ID: ' + recordId

});

```

ForceCrew wraps `FC_Tool.execute()` in a try-catch, so uncaught exceptions are also returned as error JSON rather than crashing the agent.

---

## Logging & Observability

FC_Logger provides an in-memory structured log buffer across an entire crew execution.

```apex

// Enable debug logging (also controlled via FC_Crew.Builder.verbose(true))

FC_Logger.enableDebug();

// Run your crew...

FC_CrewResult result = crew.kickoff();

// Read logs

List<FC_Logger.LogEntry> entries = FC_Logger.getBuffer();

for (FC_Logger.LogEntry entry : entries) {

    // entry.level     — DEBUG, INFO, WARN, ERROR

    // entry.category  — e.g. 'Crew', 'Agent', 'Tool', 'LLM'

    // entry.message

    // entry.timestamp — [Datetime.now](http://Datetime.now)().getTime()

    System.debug(entry.toString());

    // → '[ForceCrew] [INFO] [Crew] Starting crew: Revenue Intelligence'

}

// Filter to warnings and above

List<FC_Logger.LogEntry> issues = FC_Logger.getBuffer(FC_Logger.Level.WARN);

// Dump everything as a newline-separated string

System.debug(FC_Logger.dump());

// Clear between runs

FC_Logger.clearBuffer();

```

Logs are also included in the `CrewResultDTO.logs` array returned to LWC.

---

## Error Handling

ForceCrew uses a typed exception hierarchy so you can handle specific failure modes:

```apex

public class FC_Exception {

    // Thrown when crew/agent/task is misconfigured

    public class ConfigurationException extends Exception {}

    // Thrown when a task names an agent role that doesn't exist in the crew

    public class AgentNotFoundException extends Exception {}

    // Thrown when a tool cannot be found, instantiated, or executed

    public class ToolNotFoundException extends Exception {}

    // Thrown when the Models API call fails or returns an unparseable response

    public class LLMException extends Exception {}

    // Thrown when a single task fails (if failFast=true, propagates to crew)

    public class TaskExecutionException extends Exception {}

    // Thrown when the entire crew fails

    public class CrewExecutionException extends Exception {}

    // Thrown when an agent or manager exceeds maxIterations without FINAL_ANSWER

    public class MaxIterationsException extends Exception {}

}

```

**Example:**

```apex

try {

    FC_CrewResult result = crew.kickoff();

    if (!result.success) {

        System.debug('Crew failed: ' + result.errorMessage);

    }

} catch (FC_Exception.ConfigurationException e) {

    System.debug('Bad crew config: ' + e.getMessage());

} catch (FC_Exception.LLMException e) {

    System.debug('LLM error: ' + e.getMessage());

} catch (FC_Exception.MaxIterationsException e) {

    System.debug('Agent looped too long: ' + e.getMessage());

}

```

When `failFast = false` (set on the Crew builder), individual task failures are recorded in `FC_TaskResult.errorMessage` but execution continues to the next task.

---

## API Reference

### FC_Crew.Builder

| Method | Description |

|--------|-------------|

| `Builder(String name)` | Required. Crew name. |

| `.process(FC_Process.Type)` | `SEQUENTIAL` (default) or `HIERARCHICAL` |

| `.agent(FC_Agent)` | Add an agent. Role must be unique. |

| `.agents(List<FC_Agent>)` | Add multiple agents. |

| `.task(FC_Task)` | Add a task. Name must be unique. |

| `.tasks(List<FC_Task>)` | Add multiple tasks. |

| `.verbose(Boolean)` | Enable debug logging. |

| `.failFast(Boolean)` | Abort on first failure (default: true). |

| `.managerLlmModel(String)` | LLM for manager in hierarchical mode. |

| `.build()` | Validate configuration and return `FC_Crew`. |

### FC_Agent.Builder

| Method | Description |

|--------|-------------|

| `Builder(String role)` | Required. Unique role within the crew. |

| `.goal(String)` | Agent's objective. |

| `.backstory(String)` | Agent's persona and expertise. |

| `.tool(FC_Tool)` | Add a tool. |

| `.tools(List<FC_Tool>)` | Add multiple tools. |

| `.maxIterations(Integer)` | ReAct loop limit (default: 10). |

| `.verbose(Boolean)` | Enable debug logging. |

| `.allowDelegation(Boolean)` | Used in hierarchical mode. |

| `.llmModel(String)` | Override default LLM model. |

| `.build()` | Return `FC_Agent`. |

### FC_Task.Builder

| Method | Description |

|--------|-------------|

| `Builder(String name)` | Required. Unique task name. |

| `.description(String)` | What the agent should do. |

| `.expectedOutput(String)` | Format/content of the expected result. |

| `.assignToAgent(String)` | Agent role to run this task. |

| `.withContext(String)` | Receive output of a named prior task. |

| `.withContextFrom(List<String>)` | Receive outputs from multiple prior tasks. |

| `.build()` | Return `FC_Task`. |

### FC_ToolParameter.Builder

| Method | Description |

|--------|-------------|

| `Builder(String name, String type)` | Name and type `TYPE_STRING`, `TYPE_INTEGER`, etc.) |

| `.description(String)` | Human-readable description for the LLM. |

| `.required()` | Mark as required. |

| `.defaultValue(Object)` | Default value if not provided. |

| `.build()` | Return `FC_ToolParameter`. |

**Type constants:** `TYPE_STRING`, `TYPE_INTEGER`, `TYPE_NUMBER`, `TYPE_BOOLEAN`, `TYPE_ARRAY`, `TYPE_OBJECT`

### FC_ModelsAPIService Model Constants

`MODEL_DEFAULT` points to `MODEL_CLAUDE_OPUS45` and is used when no model is explicitly set.

**OpenAI GPT (Geo-aware)**

| Constant | Raw model name |

|----------|---------------|

| `MODEL_GPT4O` | `sfdc_ai__DefaultGPT4Omni` |

| `MODEL_GPT4O_MINI` | `sfdc_ai__DefaultGPT4OmniMini` |

| `MODEL_GPT41` | `sfdc_ai__DefaultGPT41` |

| `MODEL_GPT41_MINI` | `sfdc_ai__DefaultGPT41Mini` |

| `MODEL_GPT5` | `sfdc_ai__DefaultGPT5` |

| `MODEL_GPT5_MINI` | `sfdc_ai__DefaultGPT5Mini` |

| `MODEL_O3` | `sfdc_ai__DefaultO3` |

| `MODEL_O4_MINI` | `sfdc_ai__DefaultO4Mini` |

**Anthropic Claude on Amazon Bedrock**

| Constant | Raw model name |

|----------|---------------|

| `MODEL_CLAUDE_OPUS45` ⭐ default | `sfdc_ai__DefaultBedrockAnthropicClaude45Opus` |

| `MODEL_CLAUDE_SONNET45` | `sfdc_ai__DefaultBedrockAnthropicClaude45Sonnet` |

| `MODEL_CLAUDE_SONNET4` | `sfdc_ai__DefaultBedrockAnthropicClaude4Sonnet` |

| `MODEL_CLAUDE_HAIKU45` | `sfdc_ai__DefaultBedrockAnthropicClaude45Haiku` |

**Google Gemini on Vertex AI**

| Constant | Raw model name |

|----------|---------------|

| `MODEL_GEMINI3_PRO` | `sfdc_ai__DefaultVertexAIGeminiPro30` |

| `MODEL_GEMINI3_FLASH` | `sfdc_ai__DefaultVertexAIGemini30Flash` |

| `MODEL_GEMINI25_PRO` | `sfdc_ai__DefaultVertexAIGeminiPro25` |

| `MODEL_GEMINI25_FLASH` | `sfdc_ai__DefaultVertexAIGemini25Flash001` |

| `MODEL_GEMINI25_FLASH_LITE` | `sfdc_ai__DefaultVertexAIGemini25FlashLite001` |

**Amazon Nova on Bedrock**

| Constant | Raw model name |

|----------|---------------|

| `MODEL_NOVA_PRO` | `sfdc_ai__DefaultBedrockAmazonNovaPro` |

| `MODEL_NOVA_LITE` | `sfdc_ai__DefaultBedrockAmazonNovaLite` |

### FC_CrewController @AuraEnabled Methods

| Method | Description |

|--------|-------------|

| `runCrewFromConfig(String crewConfigJson)` | Execute full crew from JSON config. Returns `CrewResultDTO`. |

| `runSingleAgent(role, goal, backstory, toolClasses, taskDesc, expectedOutput)` | Single-agent shortcut. Returns `CrewResultDTO`. |

| `initAgentStep(agentConfigJson, taskConfigJson, priorOutputsJson)` | Initialize step loop (no LLM call). Returns `FC_StepRequest`. |

| `runAgentStep(agentConfigJson, stepRequestJson)` | Run one ReAct step. Returns updated `FC_StepRequest`. |

| `enqueueCrewAsync(crewConfigJson, correlationId)` | Enqueue for async background execution. Returns `FC_CrewRun__c` Id. |

| `getFrameworkInfo()` | Returns version and health info string. |

---

## Class Inventory

| Class | Category | Description |

|-------|----------|-------------|

| `ForceCrew` | Facade | Entry-point convenience methods and `VERSION` constant |

| `FC_Crew` | Core | Crew builder, validator, and `kickoff()` |

| `FC_Agent` | Core | Agent builder, system prompt generation |

| `FC_Task` | Core | Task builder, context-aware prompt generation |

| `FC_CrewExecutor` | Execution | Routes to sequential or hierarchical strategy |

| `FC_AgentExecutor` | Execution | Full-transaction ReAct loop |

| `FC_AgentExecutorStep` | Execution | Single-step ReAct execution for LWC |

| `FC_ManagerAgent` | Execution | LLM manager for hierarchical mode |

| `FC_Tool` | Tools | Tool wrapper with factory methods |

| `FC_ITool` | Tools | Minimal tool interface |

| `FC_IMCPTool` | Tools | Self-describing tool interface (recommended) |

| `FC_ToolParameter` | Tools | JSON Schema parameter builder |

| `FC_SampleSOQLTool` | Sample Tools | Execute SOQL queries |

| `FC_SampleDescribeTool` | Sample Tools | Describe Salesforce object metadata |

| `FC_ModelsAPIService` | LLM | Salesforce Models API wrapper |

| `FC_Memory` | LLM | Conversation history buffer with auto-trimming |

| `FC_ChatMessage` | LLM | Chat message value object (system/user/assistant) |

| `FC_CrewController` | Integration | AuraEnabled LWC bridge |

| `FC_CrewQueueable` | Integration | Async Queueable chain for background execution |

| `FC_CrewResult` | DTOs | Aggregated crew execution result |

| `FC_TaskResult` | DTOs | Single task execution result |

| `FC_StepResult` | DTOs | Single ReAct loop step result |

| `FC_StepRequest` | DTOs | Serialisable state for step-by-step execution |

| `FC_Logger` | Utilities | In-memory structured log buffer |

| `FC_Exception` | Utilities | Custom exception hierarchy |

| `FC_Process` | Utilities | Process type enum and labels |

---

## Testing

ForceCrew ships with 19 test classes covering all framework components.

```bash

# Run all tests

sf apex run test --synchronous --result-format human

# Run specific test class

sf apex run test --class-names FC_CrewTest --synchronous

```

**Test classes included:**

| Test Class | Coverage |

|------------|----------|

| `FC_CrewTest` | Crew builder validation, duplicate detection, kickoff |

| `FC_AgentTest` | Agent builder, system prompt generation |

| `FC_TaskTest` | Task builder, context injection into prompts |

| `FC_ToolTest` | Tool registration, schema generation, safe execution |

| `FC_ToolParameterTest` | Parameter schema validation |

| `FC_MemoryTest` | History buffer, auto-trimming, context injection |

| `FC_LoggerTest` | Log levels, buffer management, filtering |

| `FC_StepRequestTest` | JSON serialisation/deserialisation round-trips |

| `FC_AgentExecutorStepTest` | Step-by-step state transitions |

| `FC_CrewQueueableTest` | Async enqueuing, config serialisation |

| `FC_CrewResultTest` | Result aggregation, tool call counts |

| `FC_SampleToolsTest` | SOQL and describe tool execution |

---

## Requirements

| Requirement | Detail |

|-------------|--------|

| Salesforce API version | 62.0 or higher |

| Einstein AI features | Must be enabled in your org |

| Apex governor limits | Models API calls count against org limits |

| Async crews | FC_CrewRun__c custom object must be created |

| Tool serialisation | Async crews require `FC_Tool.fromClassName()` — no inline instances |

---

## Contributing

1. Fork the repo and create a feature branch

2. Add test coverage for any new public methods

3. Follow the `FC`_ prefix and Builder pattern conventions

4. Run `sf apex run test --synchronous` before submitting a PR

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

*ForceCrew is not affiliated with Salesforce, Inc. or crewAI, Inc. Salesforce, Einstein, and Models API are trademarks of Salesforce, Inc.*

