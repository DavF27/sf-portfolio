@IsTest
private class AssetInstallationStrategyTest {
  /** BEFORE is expected to be broken: this test passes by proving every snapshot is empty. */
  @IsTest
  static void beforeLeaves200SnapshotsEmptyWhileTheRunSucceeds() {
    System.runAs(OrderDemoTestSupport.runner()) {
      Test.startTest();
      DemoRunService.Response response = DemoRunService.run(
        OrderDemoTestSupport.request(DemoRunService.MODE_BEFORE, 200, false)
      );
      Test.stopTest();

      Assert.isTrue(response.isSuccess(), response.errorMessage ?? '');
      Assert.areEqual(200, response.result.recordsFailed);
      Assert.areEqual(200, response.result.failedRows.size());
      Assert.isTrue(response.result.message.startsWith('Saved without error'));

      Map<Id, Asset_Demo__c> assets = OrderDemoTestSupport.assets();
      List<Asset_Snapshot_Demo__c> snapshots = OrderDemoTestSupport.snapshots();
      Assert.areEqual(200, snapshots.size(), 'One snapshot per installation');
      for (Asset_Snapshot_Demo__c snapshot : snapshots) {
        Assert.isNull(snapshot.Warranty_End__c);
        Assert.isNull(snapshot.Service_Tier__c);
        Assert.isNull(snapshot.Next_Maintenance__c);
        Asset_Demo__c asset = assets.get(snapshot.Asset__c);
        Assert.areEqual(
          AssetDemo.expectedWarrantyEnd(asset),
          asset.Warranty_End__c,
          'The flow did run, but after the trigger'
        );
      }
    }
  }

  @IsTest
  static void afterSnapshots200AssetsWithEveryServiceTerm() {
    System.runAs(OrderDemoTestSupport.runner()) {
      Test.startTest();
      DemoRunService.Response response = DemoRunService.run(
        OrderDemoTestSupport.request(DemoRunService.MODE_AFTER, 200, false)
      );
      Test.stopTest();

      Assert.isTrue(response.isSuccess(), response.errorMessage ?? '');
      Assert.areEqual(0, response.result.recordsFailed);

      Map<Id, Asset_Demo__c> assets = OrderDemoTestSupport.assets();
      List<Asset_Snapshot_Demo__c> snapshots = OrderDemoTestSupport.snapshots();
      Assert.areEqual(200, snapshots.size());
      Integer premium = 0;
      for (Asset_Snapshot_Demo__c snapshot : snapshots) {
        Asset_Demo__c asset = assets.get(snapshot.Asset__c);
        premium += AssetDemo.isPremium(asset) ? 1 : 0;
        Assert.areEqual(
          AssetDemo.expectedWarrantyEnd(asset),
          snapshot.Warranty_End__c
        );
        Assert.areEqual(
          AssetDemo.expectedServiceTier(asset),
          snapshot.Service_Tier__c
        );
        Assert.areEqual(
          AssetDemo.expectedNextMaintenance(asset),
          snapshot.Next_Maintenance__c
        );
      }
      Assert.isTrue(
        premium > 0 && premium < 200,
        'Both product families are covered'
      );
    }
  }

  @IsTest
  static void timelineRecordsTheRealOrderOfExecution() {
    System.runAs(OrderDemoTestSupport.runner()) {
      Test.startTest();
      DemoRunService.run(
        OrderDemoTestSupport.request(DemoRunService.MODE_BEFORE, 3, false)
      );
      List<String> beforeSteps = OrderDemoTestSupport.triggerAndFlowSteps();
      DemoStepPublisher.publishedEvents.clear();
      DemoRunService.run(
        OrderDemoTestSupport.request(DemoRunService.MODE_AFTER, 3, false)
      );
      List<String> afterSteps = OrderDemoTestSupport.triggerAndFlowSteps();
      Test.stopTest();

      Assert.areEqual(5, beforeSteps.size(), String.join(beforeSteps, ' | '));
      Assert.areEqual('Before trigger', beforeSteps[0]);
      Assert.areEqual('After trigger: snapshot taken', beforeSteps[1]);
      Assert.isTrue(beforeSteps[2].startsWith('After-save flow'));
      Assert.areEqual('Before trigger (re-save by the flow)', beforeSteps[3]);
      Assert.isTrue(beforeSteps[4].startsWith('After trigger (re-save)'));

      Assert.areEqual(
        new List<String>{ 'Before trigger', 'After trigger: snapshot taken' },
        afterSteps,
        'The before-save flow computes the terms before both triggers'
      );
    }
  }

  private static String beforeTriggerMessage() {
    for (Demo_Step__e event : DemoStepPublisher.publishedEvents) {
      if (event.Label__c == 'Before trigger') {
        return event.Message__c;
      }
    }
    return null;
  }

  @IsTest
  static void beforeTriggerSeesTheTermsOnlyInAfterMode() {
    System.runAs(OrderDemoTestSupport.runner()) {
      Test.startTest();
      DemoRunService.run(
        OrderDemoTestSupport.request(DemoRunService.MODE_BEFORE, 4, false)
      );
      String beforeMode = beforeTriggerMessage();
      DemoStepPublisher.publishedEvents.clear();
      DemoRunService.run(
        OrderDemoTestSupport.request(DemoRunService.MODE_AFTER, 4, false)
      );
      String afterMode = beforeTriggerMessage();
      Test.stopTest();

      Assert.isTrue(
        beforeMode.startsWith('Service terms present on 0 of 4'),
        beforeMode
      );
      Assert.isTrue(
        afterMode.startsWith('Service terms present on 4 of 4'),
        afterMode
      );
    }
  }

  @IsTest
  static void chaosRollsTheInstallationBack() {
    System.runAs(OrderDemoTestSupport.runner()) {
      Test.startTest();
      DemoRunService.Response response = DemoRunService.run(
        OrderDemoTestSupport.request(DemoRunService.MODE_AFTER, 5, true)
      );
      Test.stopTest();

      Assert.isFalse(response.isSuccess());
      Assert.isTrue(response.errorMessage.contains('Chaos injected'));
      Assert.areEqual(0, OrderDemoTestSupport.snapshots().size());
    }
  }
}
