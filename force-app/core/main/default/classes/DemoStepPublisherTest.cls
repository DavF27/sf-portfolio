@IsTest
private class DemoStepPublisherTest {
  private static DemoRunService.Request newRequest() {
    DemoTestFactory.registerDefault();
    return DemoTestFactory.request(DemoRunService.MODE_AFTER, 10);
  }

  @IsTest
  static void publishesLifecycleWithIncreasingSequence() {
    DemoRunService.Request request = newRequest();
    DemoStepPublisher publisher = new DemoStepPublisher(
      request,
      new DemoMetrics()
    );

    Test.startTest();
    publisher.start();
    publisher.step('Half way', 5, 0);
    publisher.succeed(new DemoResult(10, 0));
    Test.stopTest();

    List<Demo_Step__e> events = DemoStepPublisher.publishedEvents;
    Assert.areEqual(3, events.size());
    Assert.areEqual(DemoStepPublisher.PHASE_START, events[0].Phase__c);
    Assert.areEqual(DemoStepPublisher.PHASE_STEP, events[1].Phase__c);
    Assert.areEqual(DemoStepPublisher.PHASE_SUCCEEDED, events[2].Phase__c);
    Assert.areEqual(3, events[2].Sequence__c);
    Assert.areEqual(request.runKey, events[2].Run_Key__c);
    Assert.areEqual(10, events[2].Records_Processed__c);
    Assert.areEqual(Limits.getLimitQueries(), events[2].SOQL_Limit__c);
    Assert.areEqual(Limits.getLimitDmlStatements(), events[2].DML_Limit__c);
    Assert.areEqual(
      0,
      events[2].SOQL_Queries__c,
      'Publishing must not count as demo work'
    );
    Assert.areEqual(
      0,
      events[2].DML_Statements__c,
      'Publishing must not count as demo work'
    );
  }

  @IsTest
  static void capsProgressStepsButNeverTerminalEvents() {
    DemoStepPublisher publisher = new DemoStepPublisher(
      newRequest(),
      new DemoMetrics()
    );

    Test.startTest();
    for (Integer i = 0; i < 200; i++) {
      publisher.step('Step ' + i, i, 0);
    }
    publisher.fail('Boom', null);
    Test.stopTest();

    List<Demo_Step__e> events = DemoStepPublisher.publishedEvents;
    Assert.areEqual(DemoStepPublisher.MAX_PROGRESS_STEPS + 1, events.size());
    Assert.areEqual(
      DemoStepPublisher.PHASE_FAILED,
      events[events.size() - 1].Phase__c
    );
    Assert.areEqual('Boom', events[events.size() - 1].Message__c);
  }

  @IsTest
  static void uncaughtFailureHasNoMetricsNorSequence() {
    DemoRunService.Request request = newRequest();

    Test.startTest();
    DemoStepPublisher.publishUncaughtFailure(
      request,
      'System.LimitException: Too many SOQL queries: 101'
    );
    Test.stopTest();

    Demo_Step__e event = DemoStepPublisher.publishedEvents[0];
    Assert.areEqual(DemoStepPublisher.PHASE_FAILED, event.Phase__c);
    Assert.isNull(event.Sequence__c);
    Assert.isNull(event.SOQL_Queries__c);
  }

  @IsTest
  static void publishersOfTheSameRunShareOneSequence() {
    DemoRunService.Request request = newRequest();
    DemoStepPublisher triggerPublisher = new DemoStepPublisher(request, null);
    DemoStepPublisher flowPublisher = new DemoStepPublisher(request, null);

    Test.startTest();
    triggerPublisher.step('Before trigger', 1, 0);
    flowPublisher.step('After-save flow', 1, 0, 'Computed');
    triggerPublisher.step('After trigger', 1, 0);
    Test.stopTest();

    List<Demo_Step__e> events = DemoStepPublisher.publishedEvents;
    Assert.areEqual(1, events[0].Sequence__c);
    Assert.areEqual(2, events[1].Sequence__c);
    Assert.areEqual('Computed', events[1].Message__c);
    Assert.areEqual(3, events[2].Sequence__c);
  }
}
