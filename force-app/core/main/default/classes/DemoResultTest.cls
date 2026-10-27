@IsTest
private class DemoResultTest {
  @IsTest
  static void defaultsToZeroWithoutFailures() {
    Test.startTest();
    DemoResult result = new DemoResult();
    Test.stopTest();

    Assert.areEqual(0, result.recordsProcessed);
    Assert.areEqual(0, result.recordsFailed);
    Assert.isFalse(result.hasFailures());
  }

  @IsTest
  static void reportsFailures() {
    Test.startTest();
    DemoResult result = new DemoResult(200, 3);
    Test.stopTest();

    Assert.areEqual(200, result.recordsProcessed);
    Assert.isTrue(result.hasFailures());
  }
}
