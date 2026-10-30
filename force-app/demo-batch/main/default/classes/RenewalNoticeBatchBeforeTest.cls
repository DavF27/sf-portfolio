@IsTest
private class RenewalNoticeBatchBeforeTest {
  @IsTest
  static void scansTheWholeStockWithOneExecutionPerRenewal() {
    System.runAs(BatchDemoTestSupport.runner()) {
      BatchDemoTestSupport.prepare(RenewalDemo.LANE_BEFORE, 200);
      RenewalNoticeBatchBefore batch = new RenewalNoticeBatchBefore(
        UUID.randomUUID().toString(),
        DemoRunService.MODE_BEFORE,
        200
      );

      Test.startTest();
      Integer executions = BatchDemoTestSupport.runOneByOne(batch);
      Test.stopTest();

      Assert.areEqual(
        200,
        executions,
        'Batch size 1: one execution per record'
      );
      Assert.areEqual(
        10,
        BatchDemoTestSupport.notifiedKeys(RenewalDemo.LANE_BEFORE).size(),
        'Only 1 renewal in 20 is due'
      );
      Demo_Step__e closed = BatchDemoTestSupport.lastEvent();
      Assert.areEqual(DemoStepPublisher.PHASE_SUCCEEDED, closed.Phase__c);
      Assert.areEqual(200, closed.Async_Executions__c);
      Assert.isTrue(
        closed.Message__c.contains('10 notice(s) sent'),
        closed.Message__c
      );
      Assert.areEqual(
        21,
        DemoStepPublisher.publishedEvents.size(),
        '20 progress steps and the closing step'
      );
    }
  }
}
