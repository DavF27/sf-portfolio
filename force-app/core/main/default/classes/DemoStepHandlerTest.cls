@IsTest
private class DemoStepHandlerTest {
  private static Demo_Step__e event(
    String runKey,
    String phase,
    Integer sequence
  ) {
    return new Demo_Step__e(
      Run_Key__c = runKey,
      Demo__c = DemoTestFactory.DEMO,
      Mode__c = DemoRunService.MODE_BEFORE,
      Source__c = DemoRunService.SOURCE_TEST,
      Volume__c = 50,
      Phase__c = phase,
      Sequence__c = sequence
    );
  }

  @IsTest
  static void foldsLifecycleIntoOneRun() {
    String runKey = UUID.randomUUID().toString();
    Demo_Step__e start = event(runKey, DemoStepPublisher.PHASE_START, 1);
    Demo_Step__e step = event(runKey, DemoStepPublisher.PHASE_STEP, 2);
    step.SOQL_Queries__c = 40;
    step.Records_Processed__c = 25;
    Demo_Step__e done = event(runKey, DemoStepPublisher.PHASE_SUCCEEDED, 3);
    done.SOQL_Queries__c = 12; // lower value must not overwrite the peak
    done.Records_Processed__c = 50;
    done.Duration_Ms__c = 321;

    Test.startTest();
    EventBus.publish(new List<Demo_Step__e>{ start, step, done });
    Test.stopTest();

    Demo_Run__c run = DemoTestFactory.findRun(runKey);
    Assert.areEqual(DemoStepHandler.STATUS_SUCCEEDED, run.Status__c);
    Assert.areEqual(40, run.SOQL_Queries__c);
    Assert.areEqual(50, run.Records_Processed__c);
    Assert.areEqual(3, run.Step_Count__c);
    Assert.areEqual(321, run.Duration_Ms__c);
    Assert.areEqual(DemoRunService.SOURCE_TEST, run.Source__c);
    Assert.isNotNull(run.Started_At__c);
    Assert.isNotNull(run.Finished_At__c);
  }

  @IsTest
  static void uncaughtLimitFailureRecordsPlatformReportedValue() {
    String runKey = UUID.randomUUID().toString();
    Demo_Step__e step = event(runKey, DemoStepPublisher.PHASE_STEP, 2);
    step.SOQL_Queries__c = 90;
    Demo_Step__e failure = event(runKey, DemoStepPublisher.PHASE_FAILED, null);
    failure.Message__c = 'System.LimitException: Too many SOQL queries: 101';

    Test.startTest();
    EventBus.publish(step);
    Test.getEventBus().deliver();
    EventBus.publish(failure);
    Test.stopTest();

    Demo_Run__c run = DemoTestFactory.findRun(runKey);
    Assert.areEqual(DemoStepHandler.STATUS_FAILED, run.Status__c);
    Assert.areEqual(101, run.SOQL_Queries__c);
    Assert.isTrue(run.Error_Message__c.contains('Too many SOQL queries'));
    Assert.isNotNull(
      run.Duration_Ms__c,
      'Duration is derived from timestamps when not reported'
    );
  }

  @IsTest
  static void keepsMeasuredDurationOnUncaughtFailure() {
    String runKey = UUID.randomUUID().toString();
    Demo_Step__e step = event(runKey, DemoStepPublisher.PHASE_STEP, 2);
    step.Duration_Ms__c = 187;
    Demo_Step__e failure = event(runKey, DemoStepPublisher.PHASE_FAILED, null);
    failure.Message__c = 'System.LimitException: Too many SOQL queries: 101';

    Test.startTest();
    EventBus.publish(step);
    Test.getEventBus().deliver();
    EventBus.publish(failure);
    Test.stopTest();

    Assert.areEqual(
      187,
      DemoTestFactory.findRun(runKey).Duration_Ms__c,
      'Second-precision timestamps must not override a measured duration'
    );
  }

  @IsTest
  static void firstTerminalStatusWins() {
    String runKey = UUID.randomUUID().toString();
    Demo_Step__e failure = event(runKey, DemoStepPublisher.PHASE_FAILED, null);
    failure.Message__c = 'Too many DML statements: 151';

    Test.startTest();
    EventBus.publish(event(runKey, DemoStepPublisher.PHASE_SUCCEEDED, 2));
    Test.getEventBus().deliver();
    EventBus.publish(failure);
    Test.stopTest();

    Demo_Run__c run = DemoTestFactory.findRun(runKey);
    Assert.areEqual(DemoStepHandler.STATUS_SUCCEEDED, run.Status__c);
    Assert.isNull(run.Error_Message__c);
  }

  @IsTest
  static void parsesDmlLimitMessages() {
    Demo_Run__c statements = new Demo_Run__c();
    Demo_Step__e failure = event(
      'k-statements',
      DemoStepPublisher.PHASE_FAILED,
      null
    );
    failure.Message__c = 'Too many DML statements: 151';
    Demo_Run__c rows = new Demo_Run__c();
    Demo_Step__e rowsFailure = event(
      'k-rows',
      DemoStepPublisher.PHASE_FAILED,
      null
    );
    rowsFailure.Message__c = 'Too many DML rows: 10001';
    Demo_Run__c other = new Demo_Run__c();
    Demo_Step__e otherFailure = event(
      'k-other',
      DemoStepPublisher.PHASE_FAILED,
      null
    );
    otherFailure.Message__c = 'Apex CPU time limit exceeded';

    Test.startTest();
    DemoStepHandler.apply(statements, failure);
    DemoStepHandler.apply(rows, rowsFailure);
    DemoStepHandler.apply(other, otherFailure);
    Test.stopTest();

    Assert.areEqual(151, statements.DML_Statements__c);
    Assert.areEqual(10001, rows.DML_Rows__c);
    Assert.isNull(other.SOQL_Queries__c);
    Assert.areEqual(DemoStepHandler.STATUS_FAILED, other.Status__c);
  }

  @IsTest
  static void handles200RunsInOneDelivery() {
    List<Demo_Step__e> events = new List<Demo_Step__e>();
    for (Integer i = 0; i < 200; i++) {
      Demo_Step__e step = event(
        'bulk-key-' + i,
        DemoStepPublisher.PHASE_SUCCEEDED,
        1
      );
      step.Records_Processed__c = i;
      events.add(step);
    }
    events.add(event(null, DemoStepPublisher.PHASE_STEP, 1));

    Test.startTest();
    EventBus.publish(events);
    Test.stopTest();

    Assert.areEqual(
      200,
      [SELECT COUNT() FROM Demo_Run__c WHERE Run_Key__c LIKE 'bulk-key-%']
    );
    Assert.areEqual(
      199,
      DemoTestFactory.findRun('bulk-key-199').Records_Processed__c
    );
  }
}
