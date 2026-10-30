@IsTest
private class DemoControllerTest {
  @IsTest
  static void listsActiveDemos() {
    DemoTestFactory.registerDefault();

    Test.startTest();
    List<DemoController.DemoDefinition> demos = DemoController.getDemos();
    Test.stopTest();

    Assert.areEqual(1, demos.size());
    Assert.areEqual(DemoTestFactory.DEMO, demos[0].name);
    Assert.areEqual(500, demos[0].maxVolume);
    Assert.isTrue(demos[0].hasSeeder);
  }

  @IsTest
  static void exposesSynchronousLimits() {
    Test.startTest();
    DemoMetrics.Snapshot limitsSnapshot = DemoController.getLimits();
    Test.stopTest();

    Assert.areEqual(Limits.getLimitQueries(), limitsSnapshot.soqlLimit);
    Assert.areEqual(Limits.getLimitCpuTime(), limitsSnapshot.cpuTimeLimit);
    Assert.areEqual(
      Limits.getLimitDmlStatements(),
      limitsSnapshot.dmlStatementsLimit
    );
  }

  @IsTest
  static void runsDemoAndReturnsRecentRuns() {
    System.runAs(DemoTestFactory.demoUser()) {
      DemoTestFactory.registerDefault();
      String runKey = UUID.randomUUID().toString();

      Test.startTest();
      DemoRunService.Response response = DemoController.runDemo(
        DemoTestFactory.DEMO,
        'after',
        3,
        false,
        runKey
      );
      Test.stopTest();

      Assert.areEqual(DemoStepHandler.STATUS_SUCCEEDED, response.status);
      List<Demo_Run__c> runs = DemoController.getRecentRuns(null);
      Demo_Run__c recorded;
      for (Demo_Run__c run : runs) {
        if (run.Run_Key__c == runKey) {
          recorded = run;
        }
      }
      Assert.isNotNull(recorded, 'The run must be listed');
      Assert.areEqual(DemoRunService.SOURCE_PANEL, recorded.Source__c);
      Assert.areEqual(1, DemoController.getRecentRuns(1).size());
    }
  }

  @IsTest
  static void recordsUncaughtFailure() {
    DemoTestFactory.registerDefault();
    String runKey = UUID.randomUUID().toString();

    Test.startTest();
    DemoController.recordUncaughtFailure(
      DemoTestFactory.DEMO,
      'BEFORE',
      150,
      true,
      runKey,
      'Too many SOQL queries: 101'
    );
    Test.stopTest();

    Demo_Run__c run = DemoTestFactory.findRun(runKey);
    Assert.areEqual(DemoStepHandler.STATUS_FAILED, run.Status__c);
    Assert.isTrue(run.Chaos__c);
  }

  @IsTest
  static void seedsAndPurgesData() {
    DemoTestFactory.registerDefault();

    Test.startTest();
    Integer seeded = DemoController.seedData(DemoTestFactory.DEMO, 200);
    Integer purged = DemoController.purgeData(DemoTestFactory.DEMO);
    Test.stopTest();

    Assert.areEqual(200, seeded);
    Assert.areEqual(200, purged);
  }

  @IsTest
  static void wrapsFunctionalErrorsForTheUi() {
    DemoTestFactory.registerDefault();
    Integer failures = 0;

    Test.startTest();
    try {
      DemoController.runDemo(
        'Unknown',
        'AFTER',
        1,
        false,
        UUID.randomUUID().toString()
      );
    } catch (AuraHandledException e) {
      failures++;
      Assert.isTrue(e.getMessage().contains('Unknown or inactive demo'));
    }
    try {
      DemoController.recordUncaughtFailure(
        DemoTestFactory.DEMO,
        'AFTER',
        1,
        false,
        'bad',
        'x'
      );
    } catch (AuraHandledException e) {
      failures++;
    }
    try {
      DemoController.seedData(DemoTestFactory.DEMO, 0);
    } catch (AuraHandledException e) {
      failures++;
    }
    try {
      DemoController.purgeData('Unknown');
    } catch (AuraHandledException e) {
      failures++;
    }
    Test.stopTest();

    Assert.areEqual(4, failures);
  }

  @IsTest
  static void monitorsRunsOfMonitoredDemos() {
    DemoTestFactory.registerMonitored();
    String runKey = UUID.randomUUID().toString();
    DemoTestFactory.inspection = new DemoResult(5, 0);

    Test.startTest();
    List<DemoController.DemoDefinition> demos = DemoController.getDemos();
    DemoRunService.Response response = DemoController.monitorRun(
      DemoTestFactory.DEMO,
      'BEFORE',
      5,
      false,
      runKey
    );
    Test.stopTest();

    Assert.isTrue(demos[0].hasMonitor);
    Assert.isTrue(demos[0].supportsRace);
    Assert.areEqual(DemoStepHandler.STATUS_SUCCEEDED, response.status);
  }

  @IsTest
  static void monitorRunWrapsErrorsForTheUi() {
    DemoTestFactory.registerDefault();

    Test.startTest();
    List<DemoController.DemoDefinition> demos = DemoController.getDemos();
    try {
      DemoController.monitorRun(
        DemoTestFactory.DEMO,
        'AFTER',
        1,
        false,
        UUID.randomUUID().toString()
      );
      Assert.fail('Expected AuraHandledException');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().endsWith('has no monitor'));
    }
    Test.stopTest();

    Assert.isFalse(demos[0].hasMonitor);
    Assert.isFalse(demos[0].supportsRace);
  }
}
