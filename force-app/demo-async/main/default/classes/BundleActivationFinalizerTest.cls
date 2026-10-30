@IsTest
private class BundleActivationFinalizerTest {
  private class Context implements FinalizerContext {
    private final ParentJobResult result;
    private final Exception error;

    Context(ParentJobResult result, Exception error) {
      this.result = result;
      this.error = error;
    }

    public Id getAsyncApexJobId() {
      return null;
    }
    public Exception getException() {
      return error;
    }
    public ParentJobResult getResult() {
      return result;
    }
    public String getRequestId() {
      return null;
    }
  }

  private static BundleActivationFinalizer finalizer(
    AsyncOrderDemo.Prepared prepared
  ) {
    return new BundleActivationFinalizer(
      prepared.order.Id,
      prepared.bundles[0],
      AsyncDemoTestSupport.rows(prepared, 1),
      UUID.randomUUID().toString(),
      DemoRunService.MODE_AFTER,
      5
    );
  }

  @IsTest
  static void logsTheFailureOnTheBundleAndTheTimeline() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      AsyncOrderDemo.Prepared prepared = AsyncDemoTestSupport.prepare(5, false);

      Test.startTest();
      finalizer(prepared)
        .execute(
          new Context(
            ParentJobResult.UNHANDLED_EXCEPTION,
            new DemoException('Unit price must be greater than zero')
          )
        );
      Test.stopTest();

      Order_Bundle_Demo__c bundle = [
        SELECT Status__c, Failure__c
        FROM Order_Bundle_Demo__c
      ];
      Assert.areEqual(AsyncOrderDemo.STATUS_FAILED, bundle.Status__c);
      Assert.areEqual(
        'Unit price must be greater than zero',
        bundle.Failure__c
      );
      List<Demo_Step__e> events = DemoStepPublisher.publishedEvents;
      Assert.areEqual('1,2,3,4,5', events[0].Rows_Failed__c);
      Assert.areEqual(
        DemoStepPublisher.PHASE_SUCCEEDED,
        events[1].Phase__c,
        'Last bundle: the run is closed with its failure counted'
      );
      Assert.areEqual(5, events[1].Records_Failed__c);
    }
  }

  @IsTest
  static void successOnlyClosesTheRunWhenDone() {
    System.runAs(AsyncDemoTestSupport.runner()) {
      AsyncOrderDemo.Prepared prepared = AsyncDemoTestSupport.prepare(5, false);
      update new Order_Bundle_Demo__c(
        Id = prepared.bundles[0].Id,
        Status__c = AsyncOrderDemo.STATUS_ACTIVE
      );

      Test.startTest();
      finalizer(prepared).execute(new Context(ParentJobResult.SUCCESS, null));
      Test.stopTest();

      List<Demo_Step__e> events = DemoStepPublisher.publishedEvents;
      Assert.areEqual(1, events.size());
      Assert.areEqual(DemoStepPublisher.PHASE_SUCCEEDED, events[0].Phase__c);
      Assert.areEqual(0, events[0].Records_Failed__c);
    }
  }
}
