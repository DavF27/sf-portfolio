@IsTest
private class DemoContextTest {
  private static DemoContext buildContext(Boolean chaos) {
    DemoTestFactory.registerDefault();
    DemoRunService.Request request = DemoTestFactory.request(
      DemoRunService.MODE_BEFORE,
      5
    );
    request.chaos = chaos;
    DemoMetrics metrics = new DemoMetrics();
    return new DemoContext(
      request,
      metrics,
      new DemoStepPublisher(request, metrics)
    );
  }

  @IsTest
  static void exposesRequestValues() {
    Test.startTest();
    DemoContext context = buildContext(false);
    context.step('First');
    context.injectChaos('nowhere');
    Test.stopTest();

    Assert.areEqual(DemoTestFactory.DEMO, context.demoName);
    Assert.isTrue(context.isBefore());
    Assert.areEqual(5, context.volume);
    Assert.areEqual(
      1,
      DemoStepPublisher.publishedEvents.size(),
      'step() must publish one event'
    );
  }

  @IsTest
  static void chaosThrows() {
    DemoContext context = buildContext(true);
    Test.startTest();
    try {
      context.injectChaos('the middle');
      Assert.fail('Chaos must throw');
    } catch (DemoException e) {
      Assert.isTrue(e.getMessage().contains('the middle'));
    }
    Test.stopTest();
  }
}
