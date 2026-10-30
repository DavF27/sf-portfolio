@IsTest
private class LineActivationChainJobTest {
  private static LineActivationChainJob firstLink(
    AsyncOrderDemo.Prepared prepared,
    Integer position,
    String runKey
  ) {
    return new LineActivationChainJob(
      prepared.order.Id,
      prepared.bundles[position - 1].Id,
      AsyncDemoTestSupport.lineIds(prepared, position),
      AsyncDemoTestSupport.rows(prepared, position),
      0,
      runKey,
      DemoRunService.MODE_BEFORE,
      5
    );
  }

  @IsTest
  static void eachLinkActivatesOneLineAndEnqueuesTheNext() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      AsyncOrderDemo.Prepared prepared = AsyncDemoTestSupport.prepare(5, false);

      Test.startTest();
      firstLink(prepared, 1, UUID.randomUUID().toString()).execute(null);
      Test.stopTest();

      Assert.areEqual(1, AsyncDemoTestSupport.countLines('Active'));
      Assert.areEqual(1, AsyncChain.deferred.size(), 'Next link enqueued');
      Assert.areEqual('1', DemoStepPublisher.publishedEvents[0].Rows_Done__c);
    }
  }

  @IsTest
  static void lastLinkActivatesTheBundleAndClosesTheRun() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      AsyncOrderDemo.Prepared prepared = AsyncDemoTestSupport.prepare(5, false);

      Test.startTest();
      firstLink(prepared, 1, UUID.randomUUID().toString()).execute(null);
      Integer failures = AsyncDemoTestSupport.runDeferredChain();
      Test.stopTest();

      Assert.areEqual(0, failures);
      Assert.areEqual(5, LineActivationChainJob.executions);
      Assert.areEqual(1, AsyncDemoTestSupport.countBundles('Active'));
    }
  }

  @IsTest
  static void trappedLineThrowsAndEndsTheChain() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      AsyncOrderDemo.Prepared prepared = AsyncDemoTestSupport.prepare(5, true);

      Test.startTest();
      firstLink(prepared, 1, UUID.randomUUID().toString()).execute(null);
      Integer failures = AsyncDemoTestSupport.runDeferredChain();
      Test.stopTest();

      Assert.areEqual(1, failures);
      Assert.areEqual(2, AsyncDemoTestSupport.countLines('Active'));
      Assert.isTrue(AsyncChain.deferred.isEmpty(), 'No link after the failure');
    }
  }
}
