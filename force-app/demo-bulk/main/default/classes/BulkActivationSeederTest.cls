@IsTest
private class BulkActivationSeederTest {
  @IsTest
  static void seedsAndPurgesThroughTheDemoService() {
    System.runAs(BulkDemoTestSupport.runner()) {
      Test.startTest();
      Integer seeded = DemoDataService.seed(
        ContractActivationHandler.DEMO_NAME,
        200
      );
      Integer purged = DemoDataService.purge(
        ContractActivationHandler.DEMO_NAME
      );
      Test.stopTest();

      Assert.areEqual(200, seeded);
      Assert.areEqual(200, purged);
      Assert.areEqual(0, [SELECT COUNT() FROM Contract_Demo__c]);
    }
  }
}
