@IsTest
private class AsyncOrderDemoTest {
  @IsTest
  static void prepareIsIdempotentAndTrimsLargerPreviousRuns() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      AsyncDemoTestSupport.prepare(100, true);

      Test.startTest();
      AsyncOrderDemo.Prepared prepared = AsyncDemoTestSupport.prepare(
        12,
        false
      );
      Test.stopTest();

      Assert.areEqual(1, [SELECT COUNT() FROM Order_Demo__c]);
      Assert.areEqual(3, prepared.bundles.size());
      Assert.areEqual(3, [SELECT COUNT() FROM Order_Bundle_Demo__c]);
      Assert.areEqual(12, [SELECT COUNT() FROM Order_Line_Demo__c]);
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Order_Line_Demo__c WHERE Unit_Price__c = NULL],
        'Chaos is undone by the next prepare'
      );
      Assert.areEqual(
        2,
        prepared.linesByBundle.get(prepared.bundles[2].Id).size(),
        'Last bundle holds the remainder'
      );
    }
  }

  @IsTest
  static void chaosTrapsTheThirdLineOfTheMiddleBundle() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      Test.startTest();
      AsyncDemoTestSupport.prepare(50, true);
      Test.stopTest();

      Order_Line_Demo__c trapped = [
        SELECT Row__c, Bundle__r.Position__c
        FROM Order_Line_Demo__c
        WHERE Unit_Price__c = NULL
      ];
      Assert.areEqual(23, trapped.Row__c);
      Assert.areEqual(5, trapped.Bundle__r.Position__c);
    }
  }

  @IsTest
  static void trapRowStaysInsideSmallRuns() {
    Test.startTest();
    Integer single = AsyncOrderDemo.trapRow(1);
    Integer ten = AsyncOrderDemo.trapRow(10);
    Integer bundles = AsyncOrderDemo.bundleCount(11);
    Test.stopTest();

    Assert.areEqual(1, single);
    Assert.areEqual(3, ten);
    Assert.areEqual(3, bundles);
    Assert.areEqual('ORD-00001-B07', AsyncOrderDemo.bundleKey(7));
  }

  @IsTest
  static void closesTheRunOnlyWhenNoBundleIsLeft() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      AsyncOrderDemo.Prepared prepared = AsyncDemoTestSupport.prepare(
        10,
        false
      );
      String runKey = UUID.randomUUID().toString();

      Test.startTest();
      AsyncOrderDemo.closeRunIfDone(
        prepared.order.Id,
        runKey,
        'AFTER',
        10,
        null
      );
      Integer whilePending = DemoStepPublisher.publishedEvents.size();
      List<Order_Bundle_Demo__c> bundles = new List<Order_Bundle_Demo__c>{
        new Order_Bundle_Demo__c(
          Id = prepared.bundles[0].Id,
          Status__c = 'Active'
        ),
        new Order_Bundle_Demo__c(
          Id = prepared.bundles[1].Id,
          Status__c = 'Failed',
          Failure__c = 'Unit price missing'
        )
      };
      update bundles;
      AsyncOrderDemo.closeRunIfDone(
        prepared.order.Id,
        runKey,
        'AFTER',
        10,
        null
      );
      Test.stopTest();

      Assert.areEqual(0, whilePending);
      Demo_Step__e closed = DemoStepPublisher.publishedEvents[0];
      Assert.areEqual(DemoStepPublisher.PHASE_SUCCEEDED, closed.Phase__c);
      Assert.areEqual(5, closed.Records_Failed__c);
      Assert.isTrue(
        closed.Message__c.contains('ORD-00001-B02: Unit price missing')
      );
      Assert.areEqual(
        'Active',
        [SELECT Status__c FROM Order_Demo__c].Status__c
      );
    }
  }

  @IsTest
  static void purgeDeletesOrdersBundlesAndLines() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      AsyncDemoTestSupport.prepare(10, false);

      Test.startTest();
      Integer purged = AsyncOrderDemo.purge();
      Test.stopTest();

      Assert.areEqual(1, purged);
      Assert.areEqual(0, [SELECT COUNT() FROM Order_Line_Demo__c]);
    }
  }
}
