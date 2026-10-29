@IsTest
private class ContractActivationBeforeTest {
  @IsTest
  static void activatesDealsWithOneQueryAndOneDmlPerContract() {
    System.runAs(BulkDemoTestSupport.runner()) {
      List<Contract_Demo__c> contracts = BulkDemoTestSupport.prepare(10, false);
      DemoMetrics metrics = new DemoMetrics();

      Test.startTest();
      Map<Id, String> errors = new ContractActivationBefore()
        .activate(contracts, new ContractActivationHandler.Progress());
      DemoMetrics.Snapshot snapshot = metrics.snapshot();
      Test.stopTest();

      Assert.isTrue(errors.isEmpty());
      Assert.areEqual(20, BulkDemoTestSupport.countDeals('Active'));
      Assert.isTrue(
        snapshot.soqlQueries >= 2 * contracts.size(),
        'Expected the per-contract cascade, got ' + snapshot.soqlQueries
      );
      Assert.isTrue(snapshot.dmlStatements >= contracts.size());
    }
  }

  @IsTest
  static void invalidDealThrowsForTheWholeBatch() {
    System.runAs(BulkDemoTestSupport.runner()) {
      List<Contract_Demo__c> contracts = BulkDemoTestSupport.prepare(4, true);

      Test.startTest();
      try {
        new ContractActivationBefore()
          .activate(contracts, new ContractActivationHandler.Progress());
        Assert.fail('The all-or-none update must throw');
      } catch (DmlException e) {
        Assert.isTrue(
          e.getMessage().contains('Amount must be greater than zero')
        );
      }
      Test.stopTest();
    }
  }
}
