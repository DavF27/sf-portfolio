/**
 * The BEFORE strategy is expected to be broken. A System.LimitException cannot be caught, even
 * in a test, so the failure is proven by measuring that SOQL consumption grows one-for-one with
 * the volume: any volume above the synchronous limit (100) is therefore guaranteed to fail.
 */
@IsTest
private class LimitsProbeBeforeStrategyTest {
  private static final String DEMO = 'Limits_Probe';

  private static DemoRunService.Request request(Integer volume) {
    DemoRunService.Request request = new DemoRunService.Request(
      DEMO,
      DemoRunService.MODE_BEFORE,
      volume
    );
    request.source = DemoRunService.SOURCE_TEST;
    return request;
  }

  @IsTest
  static void queryCountGrowsWithVolume() {
    System.runAs(DemoTestFactory.demoUser()) {
      Test.startTest();
      DemoRunService.Response small = DemoRunService.run(request(10));
      DemoRunService.Response larger = DemoRunService.run(request(40));
      Test.stopTest();

      Assert.isTrue(small.isSuccess(), small.errorMessage ?? '');
      Assert.areEqual(10, small.metrics.soqlQueries);
      Assert.areEqual(
        40,
        larger.metrics.soqlQueries,
        'One query per unit of volume'
      );
      Integer minimumFailingVolume =
        small.metrics.soqlLimit / (small.metrics.soqlQueries / 10) + 1;
      Assert.areEqual(
        101,
        minimumFailingVolume,
        'BEFORE must break as soon as volume exceeds 100'
      );
      Demo_Setting__mdt setting = DemoCatalog.get(DEMO);
      Assert.isTrue(
        setting.Max_Volume__c >= minimumFailingVolume,
        'The panel must allow a failing volume'
      );
    }
  }

  @IsTest
  static void chaosFailsTheRun() {
    System.runAs(DemoTestFactory.demoUser()) {
      DemoRunService.Request chaotic = request(10);
      chaotic.chaos = true;

      Test.startTest();
      DemoRunService.Response response = DemoRunService.run(chaotic);
      Test.stopTest();

      Assert.isFalse(response.isSuccess());
      Assert.isTrue(
        response.errorMessage.contains('Chaos injected at iteration 5')
      );
    }
  }

  @IsTest
  static void reportsProgressSteps() {
    System.runAs(DemoTestFactory.demoUser()) {
      DemoRunService.Request req = request(30);

      Test.startTest();
      DemoRunService.run(req);
      Test.stopTest();

      Demo_Run__c run = DemoTestFactory.findRun(req.runKey);
      Assert.areEqual(DemoStepHandler.STATUS_SUCCEEDED, run.Status__c);
      Assert.areEqual(5, run.Step_Count__c, 'START + 3 steps + SUCCEEDED');
      Assert.areEqual(30, run.SOQL_Queries__c);
    }
  }
}
