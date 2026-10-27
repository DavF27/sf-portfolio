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
}
