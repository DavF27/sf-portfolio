@IsTest
private class AssetInstallationSeederTest {
  @IsTest
  static void seedsAndPurgesThroughTheDemoService() {
    System.runAs(OrderDemoTestSupport.runner()) {
      Test.startTest();
      Integer seeded = DemoDataService.seed(AssetDemo.DEMO_NAME, 200);
      Integer purged = DemoDataService.purge(AssetDemo.DEMO_NAME);
      Test.stopTest();

      Assert.areEqual(200, seeded);
      Assert.areEqual(200, purged);
      Assert.areEqual(0, [SELECT COUNT() FROM Asset_Demo__c]);
    }
  }
}
