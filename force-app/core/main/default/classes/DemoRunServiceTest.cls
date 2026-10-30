@IsTest
private class DemoRunServiceTest {
  @IsTest
  static void afterModeSucceedsAndIsRecorded() {
    DemoTestFactory.registerDefault();
    DemoRunService.Request request = DemoTestFactory.request(
      DemoRunService.MODE_AFTER,
      200
    );

    Test.startTest();
    DemoRunService.Response response = DemoRunService.run(request);
    Test.stopTest();

    Assert.isTrue(response.isSuccess(), response.errorMessage ?? '');
    Assert.areEqual(200, response.result.recordsProcessed);
    Assert.areEqual(1, response.metrics.soqlQueries);
    Assert.areEqual(1, response.metrics.dmlStatements);
    Assert.areEqual(200, response.metrics.dmlRows);

    Demo_Run__c run = DemoTestFactory.findRun(request.runKey);
    Assert.areEqual(DemoStepHandler.STATUS_SUCCEEDED, run.Status__c);
    Assert.areEqual(DemoRunService.MODE_AFTER, run.Mode__c);
    Assert.areEqual(200, run.Records_Processed__c);
    Assert.areEqual(200, run.DML_Rows__c);
    Assert.areEqual(1, run.SOQL_Queries__c);
  }

  @IsTest
  static void beforeModeFailureIsRolledBackAndRecorded() {
    DemoTestFactory.registerDefault();
    DemoRunService.Request request = DemoTestFactory.request(
      DemoRunService.MODE_BEFORE,
      10
    );

    Test.startTest();
    DemoRunService.Response response = DemoRunService.run(request);
    Test.stopTest();

    Assert.isFalse(response.isSuccess());
    Assert.isTrue(response.errorMessage.contains('Expected failure'));
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Demo_Run__c WHERE Demo__c = 'Must be rolled back']
    );
    Demo_Run__c run = DemoTestFactory.findRun(request.runKey);
    Assert.areEqual(DemoStepHandler.STATUS_FAILED, run.Status__c);
    Assert.isTrue(run.Error_Message__c.contains('DemoException'));
  }

  @IsTest
  static void chaosFailsAnOtherwiseHealthyRun() {
    DemoTestFactory.registerDefault();
    DemoRunService.Request request = DemoTestFactory.request(
      DemoRunService.MODE_AFTER,
      5
    );
    request.chaos = true;

    Test.startTest();
    DemoRunService.Response response = DemoRunService.run(request);
    Test.stopTest();

    Assert.isFalse(response.isSuccess());
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Demo_Run__c WHERE Demo__c = 'Strategy output']
    );
    Assert.isTrue(DemoTestFactory.findRun(request.runKey).Chaos__c);
  }

  @IsTest
  static void appliesDefaultsFromSetting() {
    DemoTestFactory.registerDefault();
    DemoRunService.Request request = new DemoRunService.Request(
      DemoTestFactory.DEMO,
      null,
      null
    );

    Test.startTest();
    DemoRunService.validate(request);
    Test.stopTest();

    Assert.areEqual(DemoRunService.MODE_BEFORE, request.mode);
    Assert.areEqual(10, request.volume);
    Assert.areEqual(DemoRunService.SOURCE_PANEL, request.source);
  }

  @IsTest
  static void rejectsInvalidRequests() {
    DemoTestFactory.registerDefault();
    DemoRunService.Request badMode = DemoTestFactory.request('SIDEWAYS', 1);
    DemoRunService.Request badVolume = DemoTestFactory.request(
      DemoRunService.MODE_AFTER,
      501
    );
    DemoRunService.Request badKey = DemoTestFactory.request(
      DemoRunService.MODE_AFTER,
      1
    );
    badKey.runKey = 'x;DROP';

    Test.startTest();
    for (
      DemoRunService.Request request : new List<DemoRunService.Request>{
        null,
        badMode,
        badVolume,
        badKey
      }
    ) {
      try {
        DemoRunService.run(request);
        Assert.fail('Expected DemoException');
      } catch (DemoException e) {
        Assert.isNotNull(e.getMessage());
      }
    }
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Demo_Run__c],
      'Invalid requests must not create runs'
    );
  }

  @IsTest
  static void recordsUncaughtFailureOnBehalfOfCaller() {
    DemoTestFactory.registerDefault();
    DemoRunService.Request request = DemoTestFactory.request(
      DemoRunService.MODE_BEFORE,
      150
    );

    Test.startTest();
    DemoRunService.recordUncaughtFailure(
      request,
      'System.LimitException: Too many SOQL queries: 101'
    );
    Test.stopTest();

    Demo_Run__c run = DemoTestFactory.findRun(request.runKey);
    Assert.areEqual(DemoStepHandler.STATUS_FAILED, run.Status__c);
    Assert.areEqual(101, run.SOQL_Queries__c);
  }

  @IsTest
  static void pendingRunStaysRunningUntilItsJobsReport() {
    DemoTestFactory.registerMonitored();
    DemoRunService.Request request = DemoTestFactory.request(
      DemoRunService.MODE_BEFORE,
      10
    );

    Test.startTest();
    DemoRunService.Response response = DemoRunService.run(request);
    Test.stopTest();

    Assert.areEqual(DemoStepHandler.STATUS_RUNNING, response.status);
    Assert.isTrue(response.result.pending);
    Demo_Run__c run = DemoTestFactory.findRun(request.runKey);
    Assert.areEqual(DemoStepHandler.STATUS_RUNNING, run.Status__c);
    Assert.isNull(run.Finished_At__c);
  }

  @IsTest
  static void monitorClosesAStuckRunWithItsStuckRows() {
    DemoTestFactory.registerMonitored();
    DemoRunService.Request request = DemoTestFactory.request(
      DemoRunService.MODE_BEFORE,
      10
    );
    DemoRunService.run(request);
    DemoResult stuck = new DemoResult(10, 3);
    stuck.failedRows = new List<Integer>{ 3, 4, 5 };
    stuck.message = '3 lines stuck, no error logged';
    DemoTestFactory.inspection = stuck;

    Test.startTest();
    DemoRunService.Response response = DemoRunService.monitor(request);
    Test.stopTest();

    Assert.areEqual(DemoStepHandler.STATUS_FAILED, response.status);
    Assert.areEqual(
      'Detected by monitoring: 3 lines stuck, no error logged',
      response.errorMessage
    );
    Demo_Run__c run = DemoTestFactory.findRun(request.runKey);
    Assert.areEqual(DemoStepHandler.STATUS_FAILED, run.Status__c);
    Assert.areEqual(3, run.Records_Failed__c);
    Demo_Step__e failure = DemoStepPublisher.publishedEvents[
      DemoStepPublisher.publishedEvents.size() - 1
    ];
    Assert.areEqual('3,4,5', failure.Rows_Failed__c);
    Assert.isNull(
      failure.Sequence__c,
      'Monitoring runs in its own transaction'
    );
  }

  @IsTest
  static void monitorReportsWorkInProgressAndFinishedRuns() {
    DemoTestFactory.registerMonitored();
    DemoRunService.Request request = DemoTestFactory.request(
      DemoRunService.MODE_AFTER,
      5
    );
    DemoResult inProgress = new DemoResult(5, 0);
    inProgress.pending = true;

    Test.startTest();
    DemoTestFactory.inspection = inProgress;
    DemoRunService.Response running = DemoRunService.monitor(request);
    DemoTestFactory.inspection = new DemoResult(5, 0);
    DemoRunService.Response finished = DemoRunService.monitor(request);
    Test.stopTest();

    Assert.areEqual(DemoStepHandler.STATUS_RUNNING, running.status);
    Assert.areEqual(DemoStepHandler.STATUS_SUCCEEDED, finished.status);
    Assert.areEqual(
      1,
      DemoStepPublisher.publishedEvents.size(),
      'A run still working is left alone; a finished one is closed'
    );
    Assert.areEqual(
      DemoStepPublisher.PHASE_SUCCEEDED,
      DemoStepPublisher.publishedEvents[0].Phase__c
    );
  }

  @IsTest
  static void monitorRejectsDemosWithoutMonitor() {
    DemoTestFactory.registerDefault();

    Test.startTest();
    try {
      DemoRunService.monitor(
        DemoTestFactory.request(DemoRunService.MODE_AFTER, 1)
      );
      Assert.fail('Expected DemoException');
    } catch (DemoException e) {
      Assert.isTrue(e.getMessage().endsWith('has no monitor'));
    }
    Test.stopTest();
  }
}
