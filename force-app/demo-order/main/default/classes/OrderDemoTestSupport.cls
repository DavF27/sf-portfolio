@IsTest
public class OrderDemoTestSupport {
  public static User runner() {
    return DemoTestFactory.demoUser(
      new List<String>{ 'Demo_Admin', 'Demo_Order' }
    );
  }

  public static DemoRunService.Request request(
    String mode,
    Integer volume,
    Boolean chaos
  ) {
    DemoRunService.Request request = new DemoRunService.Request(
      AssetDemo.DEMO_NAME,
      mode,
      volume
    );
    request.chaos = chaos;
    request.source = DemoRunService.SOURCE_TEST;
    return request;
  }

  public static List<Asset_Demo__c> prepare(Integer volume) {
    return AssetDemo.prepare(
      volume,
      new SyntheticDataGenerator(DemoDataService.DEFAULT_SEED)
    );
  }

  /** Labels published by the triggers and the flow, in timeline order. */
  public static List<String> triggerAndFlowSteps() {
    List<String> labels = new List<String>();
    for (Demo_Step__e event : DemoStepPublisher.publishedEvents) {
      String label = event.Label__c ?? '';
      if (
        label.containsIgnoreCase('trigger') || label.containsIgnoreCase('flow')
      ) {
        labels.add(label);
      }
    }
    return labels;
  }

  public static List<Asset_Snapshot_Demo__c> snapshots() {
    return [
      SELECT
        Asset__c,
        Taken_By__c,
        Warranty_End__c,
        Service_Tier__c,
        Next_Maintenance__c
      FROM Asset_Snapshot_Demo__c
    ];
  }

  public static Map<Id, Asset_Demo__c> assets() {
    return new Map<Id, Asset_Demo__c>(
      [
        SELECT
          Id,
          Installed_On__c,
          Product_Family__c,
          Warranty_End__c,
          Service_Tier__c,
          Next_Maintenance__c
        FROM Asset_Demo__c
      ]
    );
  }
}
