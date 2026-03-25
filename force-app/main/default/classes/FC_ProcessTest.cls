/**
 * @group ForceCrew Tests
 */
@IsTest
public class FC_ProcessTest {

    @IsTest
    static void testGetLabelSequential() {
        Assert.areEqual('Sequential', FC_Process.getLabel(FC_Process.Type.SEQUENTIAL));
    }

    @IsTest
    static void testGetLabelHierarchical() {
        Assert.areEqual('Hierarchical', FC_Process.getLabel(FC_Process.Type.HIERARCHICAL));
    }

    @IsTest
    static void testGetDescriptionSequential() {
        String descriptionText = FC_Process.getDescription(FC_Process.Type.SEQUENTIAL);
        Assert.isTrue(String.isNotBlank(descriptionText));
        Assert.isTrue(descriptionText.toLowerCase().contains('order'));
    }

    @IsTest
    static void testGetDescriptionHierarchical() {
        String descriptionText = FC_Process.getDescription(FC_Process.Type.HIERARCHICAL);
        Assert.isTrue(String.isNotBlank(descriptionText));
        Assert.isTrue(descriptionText.toLowerCase().contains('manager'));
    }

    @IsTest
    static void testGetLabelFallbackOnNull() {
        // Ensures the 'when else' branch is covered.
        Assert.areEqual('Unknown', FC_Process.getLabel(null));
    }

    @IsTest
    static void testGetDescriptionFallbackOnNull() {
        // Ensures the 'when else' branch is covered.
        Assert.areEqual('', FC_Process.getDescription(null));
    }
}
