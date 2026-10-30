@IsTest
private class RenewalNoticeSeederTest {
  @IsTest
  static void seedsBothLanesAndPurges() {
    System.runAs(BatchDemoTestSupport.runner()) {
      Test.startTest();
      Integer seeded = DemoDataService.seed(RenewalDemo.DEMO_NAME, 100);
      Integer purged = DemoDataService.purge(RenewalDemo.DEMO_NAME);
      Test.stopTest();

      Assert.areEqual(200, seeded);
      Assert.areEqual(200, purged);
    }
  }
}
