@IsTest
public class AsyncDemoTestSupport {
  public static User runner() {
    return DemoTestFactory.demoUser(
      new List<String>{ 'Demo_Admin', 'Demo_Async' }
    );
  }

  public static DemoRunService.Request request(
    String mode,
    Integer volume,
    Boolean chaos
  ) {
    DemoRunService.Request request = new DemoRunService.Request(
      AsyncOrderDemo.DEMO_NAME,
      mode,
      volume
    );
    request.chaos = chaos;
    request.source = DemoRunService.SOURCE_TEST;
    return request;
  }

  public static AsyncOrderDemo.Prepared prepare(Integer volume, Boolean chaos) {
    return AsyncOrderDemo.prepare(
      volume,
      chaos,
      new SyntheticDataGenerator(DemoDataService.DEFAULT_SEED)
    );
  }

  /**
   * Runs the chain links deferred by AsyncChain, as the platform would. A link that throws is a failed
   * job: like the platform, the chain simply stops there. Returns the number of failed links.
   */
  public static Integer runDeferredChain() {
    Integer failures = 0;
    while (!AsyncChain.deferred.isEmpty()) {
      Queueable next = AsyncChain.deferred.remove(0);
      try {
        next.execute(null);
      } catch (DmlException e) {
        failures++;
      }
    }
    return failures;
  }

  /** Test.stopTest() rethrows the failure of a queueable; the finalizer still ran. */
  public static void stopTestTolerating() {
    try {
      Test.stopTest();
    } catch (DmlException e) {
      System.debug(
        LoggingLevel.INFO,
        'Expected job failure: ' + e.getMessage()
      );
    }
  }

  public static Integer countLines(String status) {
    return [SELECT COUNT() FROM Order_Line_Demo__c WHERE Status__c = :status];
  }

  public static Integer countBundles(String status) {
    return [SELECT COUNT() FROM Order_Bundle_Demo__c WHERE Status__c = :status];
  }

  public static List<Id> lineIds(
    AsyncOrderDemo.Prepared prepared,
    Integer position
  ) {
    List<Id> ids = new List<Id>();
    for (
      Order_Line_Demo__c line : prepared.linesByBundle.get(
        prepared.bundles[position - 1].Id
      )
    ) {
      ids.add(line.Id);
    }
    return ids;
  }

  public static List<Integer> rows(
    AsyncOrderDemo.Prepared prepared,
    Integer position
  ) {
    List<Integer> rows = new List<Integer>();
    for (
      Order_Line_Demo__c line : prepared.linesByBundle.get(
        prepared.bundles[position - 1].Id
      )
    ) {
      rows.add(line.Row__c.intValue());
    }
    return rows;
  }
}
