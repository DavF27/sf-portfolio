@IsTest
private class DemoStepActionTest {
  private static DemoStepAction.Input input(String runKey, String label) {
    DemoStepAction.Input input = new DemoStepAction.Input();
    input.runKey = runKey;
    input.demoName = 'Test_Demo';
    input.mode = DemoRunService.MODE_BEFORE;
    input.label = label;
    input.message = 'Computed by the flow';
    return input;
  }

  @IsTest
  static void foldsInterviewsOfOneBatchIntoOneStep() {
    String runKey = UUID.randomUUID().toString();
    List<DemoStepAction.Input> inputs = new List<DemoStepAction.Input>();
    for (Integer i = 0; i < 200; i++) {
      inputs.add(input(runKey, 'After-save flow'));
    }
    inputs.add(input(null, 'Ignored'));
    inputs.add(null);

    Test.startTest();
    DemoStepAction.publish(inputs);
    DemoStepAction.publish(
      new List<DemoStepAction.Input>{ input(runKey, 'Second batch') }
    );
    Test.stopTest();

    List<Demo_Step__e> events = DemoStepPublisher.publishedEvents;
    Assert.areEqual(2, events.size());
    Assert.areEqual('After-save flow', events[0].Label__c);
    Assert.areEqual(200, events[0].Records_Processed__c);
    Assert.areEqual('Computed by the flow', events[0].Message__c);
    Assert.areEqual(1, events[0].Sequence__c);
    Assert.areEqual(2, events[1].Sequence__c);
  }
}
