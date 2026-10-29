@IsTest
public class BulkDemoTestSupport {
  public static User runner() {
    return DemoTestFactory.demoUser(
      new List<String>{ 'Demo_Admin', 'Demo_Bulk' }
    );
  }

  public static DemoRunService.Request request(
    String mode,
    Integer volume,
    Boolean chaos
  ) {
    DemoRunService.Request request = new DemoRunService.Request(
      ContractActivationHandler.DEMO_NAME,
      mode,
      volume
    );
    request.chaos = chaos;
    request.source = DemoRunService.SOURCE_TEST;
    return request;
  }

  public static List<Contract_Demo__c> prepare(Integer volume, Boolean chaos) {
    return BulkActivationDemo.prepare(
      volume,
      chaos,
      new SyntheticDataGenerator(DemoDataService.DEFAULT_SEED)
    );
  }

  public static Integer countContracts(String status) {
    return [SELECT COUNT() FROM Contract_Demo__c WHERE Status__c = :status];
  }

  public static Integer countDeals(String status) {
    return [SELECT COUNT() FROM Deal_Demo__c WHERE Status__c = :status];
  }

  public static Integer countLogs(String event) {
    return [SELECT COUNT() FROM Activation_Log_Demo__c WHERE Event__c = :event];
  }
}
