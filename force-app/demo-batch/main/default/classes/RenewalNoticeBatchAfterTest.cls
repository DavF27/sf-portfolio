@IsTest
private class RenewalNoticeBatchAfterTest {
  @IsTest
  static void queriesOnlyTheDueRenewalsInOneExecution() {
    System.runAs(BatchDemoTestSupport.runner()) {
      BatchDemoTestSupport.prepare(RenewalDemo.LANE_AFTER, 200);
      String runKey = UUID.randomUUID().toString();

      Test.startTest();
      Database.executeBatch(
        new RenewalNoticeBatchAfter(runKey, DemoRunService.MODE_AFTER, 200),
        RenewalNoticeBatchAfter.BATCH_SIZE
      );
      Test.stopTest();
      Test.getEventBus().deliver();

      Assert.areEqual(
        10,
        BatchDemoTestSupport.notifiedKeys(RenewalDemo.LANE_AFTER).size()
      );
      Demo_Run__c run = DemoTestFactory.findRun(runKey);
      Assert.areEqual(DemoStepHandler.STATUS_SUCCEEDED, run.Status__c);
      Assert.areEqual(
        1,
        run.Async_Executions__c,
        'One execution instead of 200'
      );
      Assert.areEqual(
        200,
        run.Records_Processed__c,
        'The whole stock is covered'
      );
    }
  }

  @IsTest
  static void notifiesExactlyTheRenewalsTheApexFilterWouldPick() {
    System.runAs(BatchDemoTestSupport.runner()) {
      BatchDemoTestSupport.prepare(RenewalDemo.LANE_BEFORE, 200);
      BatchDemoTestSupport.prepare(RenewalDemo.LANE_AFTER, 200);

      Test.startTest();
      BatchDemoTestSupport.runOneByOne(
        new RenewalNoticeBatchBefore(
          UUID.randomUUID().toString(),
          DemoRunService.MODE_BEFORE,
          200
        )
      );
      Database.executeBatch(
        new RenewalNoticeBatchAfter(
          UUID.randomUUID().toString(),
          DemoRunService.MODE_AFTER,
          200
        ),
        RenewalNoticeBatchAfter.BATCH_SIZE
      );
      Test.stopTest();

      Set<String> before = BatchDemoTestSupport.notifiedKeys(
        RenewalDemo.LANE_BEFORE
      );
      Assert.areEqual(10, before.size());
      Assert.areEqual(
        before,
        BatchDemoTestSupport.notifiedKeys(RenewalDemo.LANE_AFTER),
        'Same result, the filter only moved into the query'
      );
    }
  }
}
