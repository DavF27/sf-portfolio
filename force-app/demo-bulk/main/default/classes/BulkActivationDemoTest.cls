@IsTest
private class BulkActivationDemoTest {
  @IsTest
  static void prepareIsIdempotentAndResetsEveryRun() {
    System.runAs(BulkDemoTestSupport.runner()) {
      List<Contract_Demo__c> first = BulkDemoTestSupport.prepare(200, true);
      for (Contract_Demo__c contract : first) {
        contract.Status__c = ContractActivationHandler.STATUS_ACTIVE;
      }
      Database.update(first, false);

      Test.startTest();
      List<Contract_Demo__c> second = BulkDemoTestSupport.prepare(200, false);
      Test.stopTest();

      Assert.areEqual(first[0].Id, second[0].Id, 'Same rows, upserted');
      Assert.areEqual(200, [SELECT COUNT() FROM Contract_Demo__c]);
      Assert.areEqual(400, [SELECT COUNT() FROM Deal_Demo__c]);
      Assert.areEqual(200, BulkDemoTestSupport.countContracts('Draft'));
      Assert.areEqual(400, BulkDemoTestSupport.countDeals('Draft'));
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Deal_Demo__c WHERE Amount__c = NULL],
        'Chaos must be undone by the next prepare'
      );
      Assert.areEqual(0, [SELECT COUNT() FROM Activation_Log_Demo__c]);
      Assert.areEqual('CTR-00001', second[0].External_Id__c);
    }
  }

  @IsTest
  static void chaosRemovesTheAmountOfOneDealOnly() {
    System.runAs(BulkDemoTestSupport.runner()) {
      Test.startTest();
      BulkDemoTestSupport.prepare(50, true);
      Test.stopTest();

      List<Deal_Demo__c> invalid = [
        SELECT External_Id__c
        FROM Deal_Demo__c
        WHERE Amount__c = NULL
      ];
      Assert.areEqual(1, invalid.size());
      Assert.areEqual(
        BulkActivationDemo.contractKey(BulkActivationDemo.chaosRow(50)) + '-2',
        invalid[0].External_Id__c
      );
    }
  }

  @IsTest
  static void purgeDeletesContractsDealsAndLogs() {
    System.runAs(BulkDemoTestSupport.runner()) {
      BulkDemoTestSupport.prepare(5, false);

      Test.startTest();
      Integer purged = BulkActivationDemo.purge();
      Test.stopTest();

      Assert.areEqual(5, purged);
      Assert.areEqual(0, [SELECT COUNT() FROM Deal_Demo__c]);
    }
  }

  @IsTest
  static void chaosRowIsTheMiddleOfTheBatch() {
    Test.startTest();
    Integer single = BulkActivationDemo.chaosRow(1);
    Integer fifty = BulkActivationDemo.chaosRow(50);
    Test.stopTest();

    Assert.areEqual(1, single);
    Assert.areEqual(25, fifty);
  }
}
