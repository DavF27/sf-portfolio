@IsTest
private class AsyncOrderSeederTest {
  @IsTest
  static void seedsAndPurgesThroughTheDemoService() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      Test.startTest();
      Integer seeded = DemoDataService.seed(AsyncOrderDemo.DEMO_NAME, 100);
      Integer purged = DemoDataService.purge(AsyncOrderDemo.DEMO_NAME);
      Test.stopTest();

      Assert.areEqual(100, seeded);
      Assert.areEqual(1, purged);
      Assert.areEqual(0, [SELECT COUNT() FROM Order_Line_Demo__c]);
    }
  }
}
