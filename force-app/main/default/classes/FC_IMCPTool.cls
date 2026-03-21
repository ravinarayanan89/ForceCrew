/**
 * FC_IMCPTool - Interface for MCP (Model Context Protocol) compatible tools.
 * Extends FC_ITool with schema metadata for automatic tool discovery and documentation.
 *
 * Implement this interface to create structured, self-describing tools that ForceCrew
 * agents can automatically discover, document, and call without additional configuration.
 *
 * Usage:
 *   public class MyQueryTool implements FC_IMCPTool {
 *       public String getName() { return 'QueryAccounts'; }
 *       public String getDescription() { return 'Queries account records from Salesforce.'; }
 *       public List<FC_ToolParameter> getParameters() {
 *           return new List<FC_ToolParameter>{
 *               new FC_ToolParameter.Builder('filter', 'string').description('WHERE clause').build()
 *           };
 *       }
 *       public String execute(Map<String, Object> params) { ... }
 *   }
 *
 *   // Register with an agent via:
 *   FC_Tool tool = FC_Tool.fromMCP(new MyQueryTool());
 *
 * @group ForceCrew
 */
public interface FC_IMCPTool extends FC_ITool {
    /**
     * Returns the unique name of the tool.
     * This is the exact name the LLM will use in TOOL_CALL actions.
     * Use PascalCase with no spaces (e.g., 'QueryRecords', 'SendEmail').
     */
    String getName();

    /**
     * Returns a human-readable description of what the tool does.
     * This is injected into the agent's system prompt so the LLM understands when to use it.
     */
    String getDescription();

    /**
     * Returns the list of parameters this tool accepts.
     * Each parameter defines its name, type, description, and whether it is required.
     * Return an empty list if the tool takes no parameters.
     */
    List<FC_ToolParameter> getParameters();
}
