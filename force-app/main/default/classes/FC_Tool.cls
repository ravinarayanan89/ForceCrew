/**
 * FC_Tool - Wraps an FC_ITool or FC_IMCPTool with the metadata needed for agent use.
 *
 * Every tool registered on an FC_Agent must be an FC_Tool instance.
 * FC_Tool holds the implementation, name, description, and parameter schema,
 * and generates the tool definition injected into the agent's system prompt.
 *
 * Factory methods:
 *   FC_Tool.fromMCP(new MyMCPTool())                         — from an FC_IMCPTool
 *   FC_Tool.from('ToolName', 'Description', new MyTool())   — from any FC_ITool
 *   FC_Tool.fromClassName('MyMCPTool')                       — via reflection (FC_IMCPTool only)
 *
 * @group ForceCrew
 */
public class FC_Tool {

    private String              toolName;
    private String              description;
    private List<FC_ToolParameter> parameters;
    private FC_ITool            implementation;
    private String              sourceClassName;

    private FC_Tool() {}

    // ─── Factory Methods ──────────────────────────────────────────────────────

    /**
     * Creates an FC_Tool from an FC_IMCPTool implementation.
     * Name, description, and parameters are sourced directly from the interface.
     */
    public static FC_Tool fromMCP(FC_IMCPTool mcpTool) {
        if (mcpTool == null) {
            throw new FC_Exception.ConfigurationException('FC_IMCPTool instance cannot be null');
        }
        FC_Tool tool       = new FC_Tool();
        tool.toolName      = mcpTool.getName();
        tool.description   = mcpTool.getDescription() != null ? mcpTool.getDescription() : '';
        tool.parameters    = mcpTool.getParameters() != null
                             ? mcpTool.getParameters()
                             : new List<FC_ToolParameter>();
        tool.implementation = mcpTool;
        return tool;
    }

    /**
     * Creates an FC_Tool from a plain FC_ITool with explicit metadata.
     */
    public static FC_Tool create(String name, String description, FC_ITool impl) {
        return create(name, description, new List<FC_ToolParameter>(), impl);
    }

    /**
     * Creates an FC_Tool from a plain FC_ITool with explicit metadata and parameter schema.
     */
    public static FC_Tool create(
        String name,
        String description,
        List<FC_ToolParameter> parameters,
        FC_ITool impl
    ) {
        if (String.isBlank(name)) {
            throw new FC_Exception.ConfigurationException('Tool name cannot be blank');
        }
        if (impl == null) {
            throw new FC_Exception.ConfigurationException('Tool implementation cannot be null');
        }
        FC_Tool tool      = new FC_Tool();
        tool.toolName     = name;
        tool.description  = description != null ? description : '';
        tool.parameters   = parameters  != null ? parameters  : new List<FC_ToolParameter>();
        tool.implementation = impl;
        return tool;
    }

    /**
     * Creates an FC_Tool by instantiating a class by name via reflection.
     * The class must implement FC_IMCPTool (schema is auto-derived).
     *
     * @param className Fully qualified Apex class name (e.g., 'MyQueryTool')
     */
    public static FC_Tool fromClassName(String className) {
        if (String.isBlank(className)) {
            throw new FC_Exception.ConfigurationException('className cannot be blank');
        }
        Type t = Type.forName(className);
        if (t == null) {
            throw new FC_Exception.ToolNotFoundException('Tool class not found: ' + className);
        }
        Object instance = t.newInstance();
        if (instance instanceof FC_IMCPTool) {
            FC_Tool tool = fromMCP((FC_IMCPTool) instance);
            tool.sourceClassName = className;
            return tool;
        }
        if (instance instanceof FC_ITool) {
            throw new FC_Exception.ConfigurationException(
                'Class "' + className + '" implements FC_ITool but not FC_IMCPTool. '
                + 'Use FC_Tool.from(name, description, impl) to register it manually.'
            );
        }
        throw new FC_Exception.ToolNotFoundException(
            'Class "' + className + '" does not implement FC_ITool or FC_IMCPTool'
        );
    }

    /** Returns the Apex class name used when this tool was registered via fromClassName(). Null otherwise. */
    public String getSourceClassName() {
        return sourceClassName;
    }

    // ─── Getters ──────────────────────────────────────────────────────────────

    public String getName() {
        return toolName;
    }

    public String getDescription() {
        return description;
    }

    public List<FC_ToolParameter> getParameters() {
        return parameters;
    }

    // ─── Execution ────────────────────────────────────────────────────────────

    /**
     * Executes the tool. Any uncaught exception is caught and returned as a
     * JSON error object so the agent loop can relay the error to the LLM.
     */
    public String execute(Map<String, Object> params) {
        if (implementation == null) {
            throw new FC_Exception.ToolNotFoundException(
                'No implementation registered for tool: ' + toolName
            );
        }
        try {
            FC_Logger.debug('FC_Tool', 'Executing "' + toolName + '" params=' + JSON.serialize(params));
            String result = implementation.execute(params != null ? params : new Map<String, Object>());
            FC_Logger.debug('FC_Tool', 'Result from "' + toolName + '": ' + result);
            return result;
        } catch (Exception e) {
            FC_Logger.error('FC_Tool', 'Tool "' + toolName + '" threw: ' + e.getMessage());
            return JSON.serialize(new Map<String, Object>{
                'success' => false,
                'error'   => e.getMessage()
            });
        }
    }

    // ─── Schema ───────────────────────────────────────────────────────────────

    /**
     * Returns the tool definition map that is serialised into the agent's system prompt.
     * Follows an OpenAI-style function schema structure that the LLM understands.
     */
    public Map<String, Object> toDefinition() {
        Map<String, Object> props          = new Map<String, Object>();
        List<String>        requiredParams = new List<String>();

        for (FC_ToolParameter param : parameters) {
            props.put(param.name, param.toSchema());
            if (param.required) {
                requiredParams.add(param.name);
            }
        }

        return new Map<String, Object>{
            'name'        => toolName,
            'description' => description,
            'parameters'  => new Map<String, Object>{
                'type'       => 'object',
                'properties' => props,
                'required'   => requiredParams
            }
        };
    }
}
