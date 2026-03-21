/**
 * @group ForceCrew Tests
 */
@IsTest
public class FC_LoggerTest {

    @IsTest
    static void testLogLevels() {
        FC_Logger.clearBuffer();

        FC_Logger.debug('Cat', 'Debug msg');
        FC_Logger.info('Cat', 'Info msg');
        FC_Logger.warn('Cat', 'Warn msg');
        FC_Logger.error('Cat', 'Error msg');

        List<FC_Logger.LogEntry> buffer = FC_Logger.getBuffer();
        Assert.areEqual(4, buffer.size());
        Assert.areEqual(FC_Logger.Level.DEBUG, buffer[0].level);
        Assert.areEqual(FC_Logger.Level.INFO,  buffer[1].level);
        Assert.areEqual(FC_Logger.Level.WARN,  buffer[2].level);
        Assert.areEqual(FC_Logger.Level.ERROR, buffer[3].level);
    }

    @IsTest
    static void testClearBuffer() {
        FC_Logger.clearBuffer();
        FC_Logger.info('Test', 'Hello');
        FC_Logger.clearBuffer();
        Assert.areEqual(0, FC_Logger.getBuffer().size());
    }

    @IsTest
    static void testGetBufferByMinLevel() {
        FC_Logger.clearBuffer();
        FC_Logger.debug('Cat', 'D');
        FC_Logger.info('Cat', 'I');
        FC_Logger.warn('Cat', 'W');
        FC_Logger.error('Cat', 'E');

        List<FC_Logger.LogEntry> warnAndAbove = FC_Logger.getBuffer(FC_Logger.Level.WARN);
        Assert.areEqual(2, warnAndAbove.size());
        Assert.areEqual(FC_Logger.Level.WARN,  warnAndAbove[0].level);
        Assert.areEqual(FC_Logger.Level.ERROR, warnAndAbove[1].level);
    }

    @IsTest
    static void testDebugMode() {
        FC_Logger.clearBuffer();
        FC_Logger.disableDebug();
        Assert.isFalse(FC_Logger.isDebugEnabled());
        FC_Logger.enableDebug();
        Assert.isTrue(FC_Logger.isDebugEnabled());
        FC_Logger.disableDebug();
    }

    @IsTest
    static void testDump() {
        FC_Logger.clearBuffer();
        FC_Logger.info('Cat', 'Hello World');
        String dump = FC_Logger.dump();
        Assert.isTrue(dump.contains('[ForceCrew]'));
        Assert.isTrue(dump.contains('Hello World'));
    }

    @IsTest
    static void testEntryToString() {
        FC_Logger.clearBuffer();
        FC_Logger.warn('TestCat', 'Something wrong');
        FC_Logger.LogEntry entry = FC_Logger.getBuffer()[0];
        String str = entry.toString();
        Assert.isTrue(str.contains('[ForceCrew]'));
        Assert.isTrue(str.contains('WARN'));
        Assert.isTrue(str.contains('TestCat'));
        Assert.isTrue(str.contains('Something wrong'));
    }
}
