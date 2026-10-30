@IsTest
private class AsyncOrderStrategyTest {
  private static final String ACTIVE = AsyncOrderDemo.STATUS_ACTIVE;
  private static final String PENDING = AsyncOrderDemo.STATUS_PENDING;

  @IsTest
  static void beforeActivatesEveryLineWithOneChainedJobPerLine() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      DemoRunService.Request request = AsyncDemoTestSupport.request(
        DemoRunService.MODE_BEFORE,
        20,
        false
      );

      Test.startTest();
      DemoRunService.Response response = DemoRunService.run(request);
      Test.stopTest();
      Test.getEventBus().deliver();
      Integer failures = AsyncDemoTestSupport.runDeferredChain();

      Assert.areEqual(DemoStepHandler.STATUS_RUNNING, response.status);
      Assert.areEqual(0, failures);
      Assert.areEqual(
        20,
        LineActivationChainJob.executions,
        'One job per line'
      );
      Assert.areEqual(20, AsyncDemoTestSupport.countLines(ACTIVE));
      Assert.areEqual(4, AsyncDemoTestSupport.countBundles(ACTIVE));
      Demo_Step__e last = DemoStepPublisher.publishedEvents[
        DemoStepPublisher.publishedEvents.size() - 1
      ];
      Assert.areEqual(DemoStepPublisher.PHASE_SUCCEEDED, last.Phase__c);
    }
  }

  /** BEFORE is expected to be broken: this test passes by proving the chain stops without any signal. */
  @IsTest
  static void beforeChaosStopsAChainSilentlyAndMonitoringFindsIt() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      DemoRunService.Request request = AsyncDemoTestSupport.request(
        DemoRunService.MODE_BEFORE,
        20,
        true
      );
      Integer trapped = AsyncOrderDemo.trapRow(20);

      Test.startTest();
      DemoRunService.run(request);
      Test.stopTest();
      Integer failures = AsyncDemoTestSupport.runDeferredChain();

      Assert.areEqual(1, failures, 'The trapped line fails its job');
      // 3 complete bundles (15 lines) + the 2 lines before the trapped one.
      Assert.areEqual(17, AsyncDemoTestSupport.countLines(ACTIVE));
      for (Demo_Step__e event : DemoStepPublisher.publishedEvents) {
        Assert.areNotEqual(
          DemoStepPublisher.PHASE_SUCCEEDED,
          event.Phase__c,
          'Nobody closes the run'
        );
        Assert.areNotEqual(DemoStepPublisher.PHASE_FAILED, event.Phase__c);
      }
      Assert.areEqual(
        1,
        AsyncDemoTestSupport.countBundles(AsyncOrderDemo.STATUS_ACTIVATING),
        'The bundle stays half activated'
      );

      DemoRunService.Response monitored = DemoRunService.monitor(request);
      Assert.areEqual(DemoStepHandler.STATUS_FAILED, monitored.status);
      Assert.areEqual(
        new List<Integer>{ trapped, trapped + 1, trapped + 2 },
        monitored.result.failedRows
      );
      Assert.isTrue(
        monitored.errorMessage.contains('3 lines stuck'),
        monitored.errorMessage
      );
    }
  }

  @IsTest
  static void afterActivates100LinesWithOneJobPerBundle() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      DemoRunService.Request request = AsyncDemoTestSupport.request(
        DemoRunService.MODE_AFTER,
        100,
        false
      );

      Test.startTest();
      DemoRunService.Response response = DemoRunService.run(request);
      Test.stopTest();
      Test.getEventBus().deliver();

      Assert.areEqual(DemoStepHandler.STATUS_RUNNING, response.status);
      Assert.areEqual(100, AsyncDemoTestSupport.countLines(ACTIVE));
      Assert.areEqual(20, AsyncDemoTestSupport.countBundles(ACTIVE));
      Assert.areEqual(
        20,
        [
          SELECT COUNT()
          FROM AsyncApexJob
          WHERE ApexClass.Name = 'BundleActivationJob'
        ],
        'One job per bundle instead of one per line'
      );
      Assert.areEqual(0, LineActivationChainJob.executions);
      Demo_Run__c run = DemoTestFactory.findRun(request.runKey);
      Assert.areEqual(DemoStepHandler.STATUS_SUCCEEDED, run.Status__c);
      Assert.areEqual(0, run.Records_Failed__c);
    }
  }

  /**
   * One bundle only: in Apex tests, Test.stopTest() stops running the queue after a failing job, while
   * in an org every bundle job runs independently (proven by the CI run of the demo).
   */
  @IsTest
  static void afterChaosFailsTheBundleExplicitlyAndLeavesNothingStuck() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      DemoRunService.Request request = AsyncDemoTestSupport.request(
        DemoRunService.MODE_AFTER,
        5,
        true
      );

      Test.startTest();
      DemoRunService.run(request);
      AsyncDemoTestSupport.stopTestTolerating();
      Test.getEventBus().deliver();

      Order_Bundle_Demo__c failed = [
        SELECT Status__c, Failure__c
        FROM Order_Bundle_Demo__c
      ];
      Assert.areEqual(AsyncOrderDemo.STATUS_FAILED, failed.Status__c);
      Assert.isTrue(
        failed.Failure__c.contains('Unit price must be greater than zero'),
        failed.Failure__c
      );
      Assert.areEqual(
        0,
        AsyncDemoTestSupport.countLines(ACTIVE),
        'Rolled back as a whole'
      );
      Assert.areEqual(5, AsyncDemoTestSupport.countLines(PENDING));
      Assert.areEqual(
        0,
        AsyncDemoTestSupport.countBundles(AsyncOrderDemo.STATUS_ACTIVATING)
      );

      Demo_Run__c run = DemoTestFactory.findRun(request.runKey);
      Assert.areEqual(DemoStepHandler.STATUS_SUCCEEDED, run.Status__c);
      Assert.areEqual(5, run.Records_Failed__c);

      DemoRunService.Response monitored = DemoRunService.monitor(request);
      Assert.areEqual(0, monitored.result.recordsFailed, 'Nothing stuck');
    }
  }

  @IsTest
  static void monitorWaitsWhileJobsAreQueued() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      DemoRunService.Request request = AsyncDemoTestSupport.request(
        DemoRunService.MODE_AFTER,
        10,
        false
      );

      Test.startTest();
      DemoRunService.run(request);
      DemoRunService.Response monitored = DemoRunService.monitor(request);
      Test.stopTest();

      Assert.areEqual(DemoStepHandler.STATUS_RUNNING, monitored.status);
      Assert.isTrue(monitored.result.pending);
    }
  }

  @IsTest
  static void refusesToStartUnderTheJobsOfThePreviousRun() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      Test.startTest();
      DemoRunService.run(
        AsyncDemoTestSupport.request(DemoRunService.MODE_AFTER, 10, false)
      );
      DemoRunService.Response second = DemoRunService.run(
        AsyncDemoTestSupport.request(DemoRunService.MODE_BEFORE, 10, false)
      );
      Test.stopTest();

      Assert.areEqual(DemoStepHandler.STATUS_FAILED, second.status);
      Assert.isTrue(
        second.errorMessage.contains(
          'previous run still has 2 activation job(s)'
        ),
        second.errorMessage
      );
    }
  }

  @IsTest
  static void monitorRejectsUnknownRuns() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      Test.startTest();
      try {
        DemoRunService.monitor(
          AsyncDemoTestSupport.request(DemoRunService.MODE_AFTER, 5, false)
        );
        Assert.fail('Expected DemoException');
      } catch (DemoException e) {
        Assert.isTrue(e.getMessage().startsWith('No order found'));
      }
      Test.stopTest();
    }
  }
}
