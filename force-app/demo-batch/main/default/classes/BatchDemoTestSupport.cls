@IsTest
public class BatchDemoTestSupport {
  public static User runner() {
    return DemoTestFactory.demoUser(
      new List<String>{ 'Demo_Admin', 'Demo_Batch' }
    );
  }

  public static DemoRunService.Request request(String mode, Integer volume) {
    DemoRunService.Request request = new DemoRunService.Request(
      RenewalDemo.DEMO_NAME,
      mode,
      volume
    );
    request.source = DemoRunService.SOURCE_TEST;
    return request;
  }

  public static Integer prepare(String lane, Integer volume) {
    return RenewalDemo.prepare(
      lane,
      volume,
      new SyntheticDataGenerator(DemoDataService.DEFAULT_SEED)
    );
  }

  /**
   * Plays a batch exactly as the platform does with a batch size of 1: start(), one execute() per record,
   * finish(). An Apex test can only run one execute() through Database.executeBatch.
   */
  public static Integer runOneByOne(RenewalNoticeBatchBefore batch) {
    Integer executions = 0;
    Database.QueryLocatorIterator records = batch.start(null).iterator();
    while (records.hasNext()) {
      batch.execute(null, new List<SObject>{ records.next() });
      executions++;
    }
    batch.finish(null);
    return executions;
  }

  public static Set<String> notifiedKeys(String lane) {
    Set<String> keys = new Set<String>();
    for (Renewal_Demo__c renewal : [
      SELECT External_Id__c
      FROM Renewal_Demo__c
      WHERE Lane__c = :lane AND Notice_Sent__c = TRUE
    ]) {
      keys.add(renewal.External_Id__c.right(5));
    }
    return keys;
  }

  public static Demo_Step__e lastEvent() {
    List<Demo_Step__e> events = DemoStepPublisher.publishedEvents;
    return events[events.size() - 1];
  }
}
