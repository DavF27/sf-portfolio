@IsTest
private class ContractActivationAfterTest {
  @IsTest
  static void activates200ContractsInOneQueryAndOneUpdate() {
    System.runAs(BulkDemoTestSupport.runner()) {
      List<Contract_Demo__c> contracts = BulkDemoTestSupport.prepare(
        200,
        false
      );
      DemoMetrics metrics = new DemoMetrics();

      Test.startTest();
      Map<Id, String> errors = new ContractActivationAfter()
        .activate(contracts, new ContractActivationHandler.Progress());
      DemoMetrics.Snapshot snapshot = metrics.snapshot();
      Test.stopTest();

      Assert.isTrue(errors.isEmpty());
      Assert.areEqual(400, BulkDemoTestSupport.countDeals('Active'));
      Assert.isTrue(
        snapshot.soqlQueries <= 5,
        'Bulk path must not query per contract, got ' + snapshot.soqlQueries
      );
    }
  }

  @IsTest
  static void reportsTheInvalidDealOnItsContractOnly() {
    System.runAs(BulkDemoTestSupport.runner()) {
      List<Contract_Demo__c> contracts = BulkDemoTestSupport.prepare(10, true);
      Contract_Demo__c invalid = contracts[BulkActivationDemo.chaosRow(10) - 1];

      Test.startTest();
      Map<Id, String> errors = new ContractActivationAfter()
        .activate(contracts, new ContractActivationHandler.Progress());
      Test.stopTest();

      Assert.areEqual(new Set<Id>{ invalid.Id }, errors.keySet());
      Assert.isTrue(
        errors.get(invalid.Id).startsWith('Deal ' + invalid.External_Id__c)
      );
      Assert.areEqual(19, BulkDemoTestSupport.countDeals('Active'));
    }
  }
}
