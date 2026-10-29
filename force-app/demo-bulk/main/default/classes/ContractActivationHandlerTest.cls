@IsTest
private class ContractActivationHandlerTest {
  private static final String ACTIVE = ContractActivationHandler.STATUS_ACTIVE;

  private static void activate(
    List<Contract_Demo__c> contracts,
    String mode,
    String runKey
  ) {
    for (Contract_Demo__c contract : contracts) {
      contract.Status__c = ACTIVE;
      contract.Processing_Mode__c = mode;
      contract.Run_Key__c = runKey;
    }
  }

  @IsTest
  static void bulkJobRowsWithRunKeyAreMeasuredAsScriptRun() {
    System.runAs(BulkDemoTestSupport.runner()) {
      List<Contract_Demo__c> contracts = BulkDemoTestSupport.prepare(20, false);
      String runKey = UUID.randomUUID().toString();
      activate(contracts, DemoRunService.MODE_AFTER, runKey);

      Test.startTest();
      update contracts;
      Test.stopTest();

      Demo_Run__c run = DemoTestFactory.findRun(runKey);
      Assert.areEqual(DemoStepHandler.STATUS_SUCCEEDED, run.Status__c);
      Assert.areEqual(DemoRunService.SOURCE_SCRIPT, run.Source__c);
      Assert.areEqual(ContractActivationHandler.DEMO_NAME, run.Demo__c);
      Assert.areEqual(DemoRunService.MODE_AFTER, run.Mode__c);
      Assert.areEqual(20, run.Records_Processed__c);
      Assert.isTrue(run.SOQL_Queries__c > 0);
      Assert.areEqual(40, BulkDemoTestSupport.countDeals(ACTIVE));
    }
  }

  @IsTest
  static void bulkJobInvalidRowIsReportedOnItsOwnRow() {
    System.runAs(BulkDemoTestSupport.runner()) {
      List<Contract_Demo__c> contracts = BulkDemoTestSupport.prepare(20, true);
      String runKey = UUID.randomUUID().toString();
      activate(contracts, DemoRunService.MODE_AFTER, runKey);

      Test.startTest();
      List<Database.SaveResult> results = Database.update(contracts, false);
      Test.stopTest();

      Integer invalidRow = BulkActivationDemo.chaosRow(20);
      for (Integer i = 0; i < results.size(); i++) {
        Assert.areEqual(i + 1 != invalidRow, results[i].isSuccess());
      }
      Assert.isTrue(
        results[invalidRow - 1].getErrors()[0]
          .getMessage()
          .contains('Amount must be greater than zero')
      );
      Assert.areEqual(19, BulkDemoTestSupport.countContracts(ACTIVE));
      Assert.areEqual(1, DemoTestFactory.findRun(runKey).Records_Failed__c);
    }
  }

  @IsTest
  static void unmeasuredActivationStillActivatesDeals() {
    System.runAs(BulkDemoTestSupport.runner()) {
      List<Contract_Demo__c> contracts = BulkDemoTestSupport.prepare(3, false);
      activate(contracts, null, null);

      Test.startTest();
      update contracts;
      Test.stopTest();

      Assert.areEqual(6, BulkDemoTestSupport.countDeals(ACTIVE));
      Assert.areEqual(0, [SELECT COUNT() FROM Demo_Run__c]);
    }
  }

  @IsTest
  static void onlyDraftToActiveTransitionsTriggerActivation() {
    System.runAs(BulkDemoTestSupport.runner()) {
      List<Contract_Demo__c> contracts = BulkDemoTestSupport.prepare(3, false);
      activate(contracts, DemoRunService.MODE_AFTER, null);
      update contracts;
      List<Deal_Demo__c> deals = [SELECT Id FROM Deal_Demo__c];
      for (Deal_Demo__c deal : deals) {
        deal.Status__c = ContractActivationHandler.STATUS_DRAFT;
      }
      update deals;

      Test.startTest();
      update contracts; // Active -> Active: no transition, deals stay Draft
      Test.stopTest();

      Assert.areEqual(0, BulkDemoTestSupport.countDeals(ACTIVE));
    }
  }

  @IsTest
  static void selectsServicePerMode() {
    Test.startTest();
    ContractActivationService before = ContractActivationHandler.serviceFor(
      DemoRunService.MODE_BEFORE
    );
    ContractActivationService after = ContractActivationHandler.serviceFor(
      DemoRunService.MODE_AFTER
    );
    Test.stopTest();

    Assert.isInstanceOfType(before, ContractActivationBefore.class);
    Assert.isInstanceOfType(after, ContractActivationAfter.class);
  }
}
