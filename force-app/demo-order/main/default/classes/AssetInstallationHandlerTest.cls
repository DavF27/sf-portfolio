@IsTest
private class AssetInstallationHandlerTest {
  private static void install(List<Asset_Demo__c> assets, String mode) {
    for (Asset_Demo__c asset : assets) {
      asset.Status__c = AssetDemo.STATUS_INSTALLED;
      asset.Processing_Mode__c = mode;
    }
  }

  @IsTest
  static void installationWithoutRunKeyIsNotInstrumented() {
    System.runAs(OrderDemoTestSupport.runner()) {
      List<Asset_Demo__c> assets = OrderDemoTestSupport.prepare(3);
      install(assets, DemoRunService.MODE_AFTER);

      Test.startTest();
      update assets;
      Test.stopTest();

      Assert.areEqual(3, OrderDemoTestSupport.snapshots().size());
      Assert.isTrue(DemoStepPublisher.publishedEvents.isEmpty());
      Assert.areEqual(0, [SELECT COUNT() FROM Demo_Run__c]);
    }
  }

  @IsTest
  static void savingAnInstalledAssetAgainTakesNoNewSnapshot() {
    System.runAs(OrderDemoTestSupport.runner()) {
      List<Asset_Demo__c> assets = OrderDemoTestSupport.prepare(3);
      install(assets, DemoRunService.MODE_AFTER);
      update assets;

      Test.startTest();
      update assets;
      Test.stopTest();

      List<Asset_Snapshot_Demo__c> snapshots = OrderDemoTestSupport.snapshots();
      Assert.areEqual(3, snapshots.size());
      Assert.areEqual(
        'Asset_Demo__c after update trigger',
        snapshots[0].Taken_By__c
      );
    }
  }

  @IsTest
  static void withoutModeNoFlowComputesTheTerms() {
    System.runAs(OrderDemoTestSupport.runner()) {
      List<Asset_Demo__c> assets = OrderDemoTestSupport.prepare(2);
      install(assets, null);

      Test.startTest();
      update assets;
      Test.stopTest();

      for (Asset_Demo__c asset : OrderDemoTestSupport.assets().values()) {
        Assert.isFalse(AssetDemo.hasTerms(asset));
      }
    }
  }
}
