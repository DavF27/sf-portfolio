@IsTest
private class LimitsProbeAfterStrategyTest {
  private static final String DEMO = 'Limits_Probe';

  @IsTest
  static void maxVolumeUsesOneQuery() {
    System.runAs(DemoTestFactory.demoUser()) {
      DemoRunService.Request request = new DemoRunService.Request(
        DEMO,
        DemoRunService.MODE_AFTER,
        150
      );
      request.source = DemoRunService.SOURCE_TEST;

      Test.startTest();
      DemoRunService.Response response = DemoRunService.run(request);
      Test.stopTest();

      Assert.isTrue(response.isSuccess(), response.errorMessage ?? '');
      Assert.areEqual(1, response.metrics.soqlQueries);
      Assert.areEqual(150, response.result.recordsProcessed);
      Assert.areEqual(
        1,
        DemoTestFactory.findRun(request.runKey).SOQL_Queries__c
      );
    }
  }

  @IsTest
  static void volume200StillUsesOneQuery() {
    System.runAs(DemoTestFactory.demoUser()) {
      DemoRunService.Request request = new DemoRunService.Request(
        DEMO,
        DemoRunService.MODE_AFTER,
        200
      );
      Test.startTest();
      DemoMetrics metrics = new DemoMetrics();
      DemoContext context = new DemoContext(
        request,
        metrics,
        new DemoStepPublisher(request, metrics)
      );
      DemoResult result = new LimitsProbeAfterStrategy().execute(context);
      DemoMetrics.Snapshot snapshot = metrics.snapshot();
      Test.stopTest();

      Assert.areEqual(200, result.recordsProcessed);
      Assert.areEqual(1, snapshot.soqlQueries);
    }
  }

  @IsTest
  static void chaosFailsTheRun() {
    System.runAs(DemoTestFactory.demoUser()) {
      DemoRunService.Request request = new DemoRunService.Request(
        DEMO,
        DemoRunService.MODE_AFTER,
        1
      );
      request.chaos = true;

      Test.startTest();
      DemoRunService.Response response = DemoRunService.run(request);
      Test.stopTest();

      Assert.isFalse(response.isSuccess());
      Assert.isTrue(
        response.errorMessage.contains('Chaos injected at iteration 1')
      );
    }
  }
}
