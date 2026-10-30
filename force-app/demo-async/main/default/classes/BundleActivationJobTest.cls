@IsTest
private class BundleActivationJobTest {
  private static BundleActivationJob job(
    AsyncOrderDemo.Prepared prepared,
    String runKey
  ) {
    return new BundleActivationJob(
      prepared.order.Id,
      prepared.bundles[0],
      AsyncDemoTestSupport.lineIds(prepared, 1),
      AsyncDemoTestSupport.rows(prepared, 1),
      runKey,
      DemoRunService.MODE_AFTER,
      5
    );
  }

  @IsTest
  static void activatesTheWholeBundleInOneUpdate() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      AsyncOrderDemo.Prepared prepared = AsyncDemoTestSupport.prepare(5, false);

      Test.startTest();
      System.enqueueJob(job(prepared, UUID.randomUUID().toString()));
      Test.stopTest();

      Assert.areEqual(5, AsyncDemoTestSupport.countLines('Active'));
      Assert.areEqual(1, AsyncDemoTestSupport.countBundles('Active'));
      Boolean bundleStep = false;
      for (Demo_Step__e event : DemoStepPublisher.publishedEvents) {
        bundleStep |= event.Rows_Done__c == '1,2,3,4,5';
      }
      Assert.isTrue(bundleStep, 'The panel lights the 5 rows at once');
    }
  }

  @IsTest
  static void trappedLineRollsTheBundleBackAndTheFinalizerLogsIt() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      AsyncOrderDemo.Prepared prepared = AsyncDemoTestSupport.prepare(5, true);

      Test.startTest();
      System.enqueueJob(job(prepared, UUID.randomUUID().toString()));
      AsyncDemoTestSupport.stopTestTolerating();

      Assert.areEqual(0, AsyncDemoTestSupport.countLines('Active'));
      Order_Bundle_Demo__c bundle = [
        SELECT Status__c, Failure__c
        FROM Order_Bundle_Demo__c
      ];
      Assert.areEqual(AsyncOrderDemo.STATUS_FAILED, bundle.Status__c);
      Assert.isTrue(bundle.Failure__c.contains('Unit price'));
    }
  }
}
