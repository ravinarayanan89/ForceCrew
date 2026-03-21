/**
 * FC_ToolParameter - Metadata for a single parameter in a tool's schema.
 * Used by FC_IMCPTool implementations and injected into the agent's system prompt
 * so the LLM understands how to call each tool correctly.
 *
 * Usage:
 *   FC_ToolParameter param = new FC_ToolParameter.Builder('query', 'string')
 *       .description('The SOQL query to execute')
 *       .required()
 *       .build();
 *
 * @group ForceCrew
 */
public class FC_ToolParameter {

    /** Supported JSON Schema types */
    public static final String TYPE_STRING  = 'string';
    public static final String TYPE_INTEGER = 'integer';
    public static final String TYPE_NUMBER  = 'number';
    public static final String TYPE_BOOLEAN = 'boolean';
    public static final String TYPE_ARRAY   = 'array';
    public static final String TYPE_OBJECT  = 'object';

    public String  name         { get; private set; }
    public String  paramType    { get; private set; }
    public String  description  { get; private set; }
    public Boolean required     { get; private set; }
    public Object  defaultValue { get; private set; }

    private FC_ToolParameter() {}

    // ─── Builder ─────────────────────────────────────────────────────────────

    public class Builder {
        private FC_ToolParameter param;

        /**
         * @param name      The parameter name (used as the JSON key)
         * @param paramType JSON Schema type — use FC_ToolParameter.TYPE_* constants
         */
        public Builder(String name, String paramType) {
            if (String.isBlank(name)) {
                throw new FC_Exception.ConfigurationException(
                    'ToolParameter name cannot be blank'
                );
            }
            param           = new FC_ToolParameter();
            param.name      = name;
            param.paramType = String.isNotBlank(paramType) ? paramType : TYPE_STRING;
            param.required  = false;
        }

        public Builder description(String descText) {
            param.description = descText;
            return this;
        }

        /** Marks this parameter as required (LLM must supply a value). */
        public Builder required() {
            param.required = true;
            return this;
        }

        public Builder defaultValue(Object val) {
            param.defaultValue = val;
            return this;
        }

        public FC_ToolParameter build() {
            return param;
        }
    }

    // ─── Schema ──────────────────────────────────────────────────────────────

    /**
     * Returns a JSON Schema-compatible map for this parameter.
     * This map is embedded inside the tool's schema that is injected into the LLM's system prompt.
     */
    public Map<String, Object> toSchema() {
        Map<String, Object> schema = new Map<String, Object>{
            'type'        => paramType,
            'description' => description != null ? description : ''
        };
        if (defaultValue != null) {
            schema.put('default', defaultValue);
        }
        return schema;
    }
}
