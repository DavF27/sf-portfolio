@IsTest
private class RenewalNoticeStrategyTest {
  @IsTest
  static void afterRunIsClosedByItsBatch() {
    System.runAs(BatchDemoTestSupport.runner()) {
      DemoRunService.Request request = BatchDemoTestSupport.request(
        DemoRunService.MODE_AFTER,
        200
      );

      Test.startTest();
      DemoRunService.Response response = DemoRunService.run(request);
      Test.stopTest();
      Test.getEventBus().deliver();

      Assert.areEqual(DemoStepHandler.STATUS_RUNNING, response.status);
      Assert.isNotNull(response.result.asyncJobId);
      Assert.isTrue(response.result.message.contains('10 renewals selected'));
      Demo_Run__c run = DemoTestFactory.findRun(request.runKey);
      Assert.areEqual(DemoStepHandler.STATUS_SUCCEEDED, run.Status__c);
      Assert.areEqual(1, run.Async_Executions__c);
    }
  }

  @IsTest
  static void beforeRunsWithBatchSizeOne() {
    System.runAs(BatchDemoTestSupport.runner()) {
      // One record: an Apex test can only run one execute().
      DemoRunService.Request request = BatchDemoTestSupport.request(
        DemoRunService.MODE_BEFORE,
        1
      );

      Test.startTest();
      DemoRunService.Response response = DemoRunService.run(request);
      Test.stopTest();
      Test.getEventBus().deliver();

      Assert.isTrue(response.result.message.startsWith('Batch size 1'));
      Demo_Run__c run = DemoTestFactory.findRun(request.runKey);
      Assert.areEqual(DemoStepHandler.STATUS_SUCCEEDED, run.Status__c);
      Assert.areEqual(1, run.Async_Executions__c);
    }
  }

  @IsTest
  static void refusesToStartUnderThePreviousBatchOfTheLane() {
    System.runAs(BatchDemoTestSupport.runner()) {
      Test.startTest();
      DemoRunService.run(
        BatchDemoTestSupport.request(DemoRunService.MODE_AFTER, 20)
      );
      DemoRunService.Response second = DemoRunService.run(
        BatchDemoTestSupport.request(DemoRunService.MODE_AFTER, 20)
      );
      Test.stopTest();

      Assert.areEqual(DemoStepHandler.STATUS_FAILED, second.status);
      Assert.isTrue(
        second.errorMessage.contains('previous AFTER batch is still running'),
        second.errorMessage
      );
    }
  }

  @IsTest
  static void chaosStopsBeforeTheBatchStarts() {
    System.runAs(BatchDemoTestSupport.runner()) {
      DemoRunService.Request request = BatchDemoTestSupport.request(
        DemoRunService.MODE_AFTER,
        20
      );
      request.chaos = true;

      Test.startTest();
      DemoRunService.Response response = DemoRunService.run(request);
      Test.stopTest();

      Assert.areEqual(DemoStepHandler.STATUS_FAILED, response.status);
      Assert.areEqual(0, [SELECT COUNT() FROM AsyncApexJob]);
    }
  }
}
