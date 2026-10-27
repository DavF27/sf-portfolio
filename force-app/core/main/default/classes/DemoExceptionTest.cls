@IsTest
private class DemoExceptionTest {
  @IsTest
  static void carriesMessage() {
    Test.startTest();
    DemoException error = new DemoException('boom');
    Test.stopTest();

    Assert.areEqual('boom', error.getMessage());
  }
}
