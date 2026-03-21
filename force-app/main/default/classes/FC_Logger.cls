/**
 * FC_Logger - Structured in-memory logger for the ForceCrew framework.
 *
 * Buffers log entries for the current transaction. Debug mode is off by default;
 * enable it via FC_Logger.enableDebug() or FC_Crew.Builder.verbose(true).
 *
 * WARN and ERROR entries are always written to System.debug regardless of debug mode.
 *
 * @group ForceCrew
 */
public class FC_Logger {

    public enum Level { DEBUG, INFO, WARN, ERROR }

    private static final String  PREFIX       = '[ForceCrew]';
    private static List<LogEntry> buffer      = new List<LogEntry>();
    private static Boolean        debugMode   = false;

    // ─── Log Entry ────────────────────────────────────────────────────────────

    public class LogEntry {
        public Level  level     { get; set; }
        public String category  { get; set; }
        public String message   { get; set; }
        public Long   timestamp { get; set; }

        public LogEntry(Level level, String category, String message) {
            this.level     = level;
            this.category  = category;
            this.message   = message;
            this.timestamp = DateTime.now().getTime();
        }

        public override String toString() {
            return PREFIX + ' [' + level.name() + '] [' + category + '] ' + message;
        }
    }

    // ─── Configuration ────────────────────────────────────────────────────────

    public static void enableDebug() {
        debugMode = true;
    }

    public static void disableDebug() {
        debugMode = false;
    }

    public static Boolean isDebugEnabled() {
        return debugMode;
    }

    // ─── Logging Methods ──────────────────────────────────────────────────────

    public static void debug(String category, String message) {
        log(Level.DEBUG, category, message);
    }

    public static void info(String category, String message) {
        log(Level.INFO, category, message);
    }

    public static void warn(String category, String message) {
        log(Level.WARN, category, message);
    }

    public static void error(String category, String message) {
        log(Level.ERROR, category, message);
    }

    private static void log(Level level, String category, String message) {
        LogEntry entry = new LogEntry(level, category, message);
        buffer.add(entry);
        if (debugMode || level == FC_Logger.Level.WARN || level == FC_Logger.Level.ERROR) {
            System.debug(entry.toString());
        }
    }

    // ─── Buffer Access ────────────────────────────────────────────────────────

    /** Returns a copy of the current log buffer. */
    public static List<LogEntry> getBuffer() {
        return buffer.clone();
    }

    /** Returns entries filtered by minimum severity level. */
    public static List<LogEntry> getBuffer(Level minLevel) {
        List<LogEntry> filtered = new List<LogEntry>();
        for (LogEntry entry : buffer) {
            if (entry.level.ordinal() >= minLevel.ordinal()) {
                filtered.add(entry);
            }
        }
        return filtered;
    }

    public static void clearBuffer() {
        buffer.clear();
    }

    /** Returns the log buffer as a newline-separated string (useful for debugging). */
    public static String dump() {
        List<String> lines = new List<String>();
        for (LogEntry entry : buffer) {
            lines.add(entry.toString());
        }
        return String.join(lines, '\n');
    }
}
