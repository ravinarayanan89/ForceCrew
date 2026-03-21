/**
 * FC_ITool - Base interface for all ForceCrew tools.
 * Implement this interface to create a tool that can be used by ForceCrew agents.
 *
 * Usage:
 *   public class MyTool implements FC_ITool {
 *       public String execute(Map<String, Object> params) {
 *           // ... tool logic
 *           return JSON.serialize(new Map<String,Object>{'success'=>true,'result'=>'...'});
 *       }
 *   }
 *
 * @group ForceCrew
 */
public interface FC_ITool {
    /**
     * Executes the tool with the given parameters.
     * @param params Map of parameter names to values (deserialized from LLM JSON)
     * @return JSON string result — must always include a 'success' boolean key
     */
    String execute(Map<String, Object> params);
}
