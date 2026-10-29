@IsTest
private class BulkActivationStrategyTest {
  private static final String ACTIVE = ContractActivationHandler.STATUS_ACTIVE;
  /** Record-triggered flows on Deal_Demo__c, each with one query and one insert. */
  private static final Integer FLOWS = 2;
  private static final Integer PLATFORM_CHUNK = 200;

  private static Integer flowChunks(Integer records) {
    return (records + PLATFORM_CHUNK - 1) / PLATFORM_CHUNK;
  }

  /**
   * A System.LimitException cannot be caught, so the BEFORE failure is proven by measurement:
   * the cascade costs a fixed number of queries per contract, which puts the first failing
   * batch size below the 50 rows of the demo.
   */
  @IsTest
  static void beforeCascadeBreaksTheQueryLimitBelow50Rows() {
    System.runAs(BulkDemoTestSupport.runner()) {
      Test.startTest();
      DemoRunService.Response five = DemoRunService.run(
        BulkDemoTestSupport.request(DemoRunService.MODE_BEFORE, 5, false)
      );
      DemoRunService.Response ten = DemoRunService.run(
        BulkDemoTestSupport.request(DemoRunService.MODE_BEFORE, 10, false)
      );
      Test.stopTest();

      Assert.isTrue(five.isSuccess(), five.errorMessage ?? '');
      Assert.isTrue(ten.isSuccess(), ten.errorMessage ?? '');
      Decimal perContract =
        (ten.metrics.soqlQueries - five.metrics.soqlQueries) / 5.0;
      Decimal fixedCost = five.metrics.soqlQueries - 5 * perContract;
      Assert.isTrue(
        perContract >= 2,
        'The deal query and the flows run again for every contract, got ' +
        perContract
      );
      Integer firstFailingVolume =
        ((five.metrics.soqlLimit - fixedCost) / perContract)
          .round(System.RoundingMode.FLOOR)
          .intValue() + 1;
      Assert.isTrue(
        firstFailingVolume < 50,
        'A batch of 50 must break the limit, first failing volume ' +
        firstFailingVolume
      );
    }
  }

  @IsTest
  static void beforeChaosFailsEveryRowOfTheBatch() {
    System.runAs(BulkDemoTestSupport.runner()) {
      Test.startTest();
      DemoRunService.Response response = DemoRunService.run(
        BulkDemoTestSupport.request(DemoRunService.MODE_BEFORE, 5, true)
      );
      Test.stopTest();

      Assert.isFalse(response.isSuccess());
      Assert.isTrue(
        response.errorMessage.contains('All 5 rows of the batch failed'),
        response.errorMessage
      );
      Assert.isTrue(
        response.errorMessage.contains('Amount must be greater than zero'),
        response.errorMessage
      );
      Assert.areEqual(0, BulkDemoTestSupport.countContracts(ACTIVE));
      Assert.areEqual(0, BulkDemoTestSupport.countDeals(ACTIVE));
    }
  }

  @IsTest
  static void afterActivates200ContractsWithConstantQueries() {
    System.runAs(BulkDemoTestSupport.runner()) {
      Test.startTest();
      DemoRunService.Response small = DemoRunService.run(
        BulkDemoTestSupport.request(DemoRunService.MODE_AFTER, 10, false)
      );
      DemoRunService.Response large = DemoRunService.run(
        BulkDemoTestSupport.request(DemoRunService.MODE_AFTER, 200, false)
      );
      Test.stopTest();

      Assert.isTrue(large.isSuccess(), large.errorMessage ?? '');
      Assert.areEqual(200, large.result.recordsProcessed);
      Assert.areEqual(0, large.result.recordsFailed);
      // The platform runs the deal flows per chunk of 200 records: each extra chunk adds one query
      // and one insert per flow. The cost depends on chunks, never on the number of contracts.
      Integer extraChunks =
        flowChunks(200 * BulkActivationDemo.DEALS_PER_CONTRACT) -
        flowChunks(10 * BulkActivationDemo.DEALS_PER_CONTRACT);
      Assert.areEqual(
        small.metrics.soqlQueries + FLOWS * extraChunks,
        large.metrics.soqlQueries,
        'Queries grow with platform chunks only'
      );
      Assert.areEqual(
        small.metrics.dmlStatements + FLOWS * extraChunks,
        large.metrics.dmlStatements,
        'DML statements grow with platform chunks only'
      );
      Assert.areEqual(200, BulkDemoTestSupport.countContracts(ACTIVE));
      Assert.areEqual(400, BulkDemoTestSupport.countDeals(ACTIVE));
      Assert.areEqual(400, BulkDemoTestSupport.countLogs('Deal activated'));
      // Both deals of a contract are activated by the same DML, so each interview of the
      // completion flow sees its sibling already active: one completion log per deal.
      Assert.areEqual(
        400,
        BulkDemoTestSupport.countLogs('Contract fully activated')
      );
    }
  }

  @IsTest
  static void afterChaosIsolatesTheInvalidRow() {
    System.runAs(BulkDemoTestSupport.runner()) {
      DemoRunService.Request request = BulkDemoTestSupport.request(
        DemoRunService.MODE_AFTER,
        200,
        true
      );

      Test.startTest();
      DemoRunService.Response response = DemoRunService.run(request);
      Test.stopTest();

      Assert.isTrue(response.isSuccess(), response.errorMessage ?? '');
      Assert.areEqual(1, response.result.recordsFailed);
      Assert.areEqual(
        new List<Integer>{ BulkActivationDemo.chaosRow(200) },
        response.result.failedRows
      );
      Assert.isTrue(
        response.result.message.contains('Amount must be greater than zero'),
        response.result.message
      );
      Assert.areEqual(199, BulkDemoTestSupport.countContracts(ACTIVE));
      Contract_Demo__c invalid = [
        SELECT Status__c
        FROM Contract_Demo__c
        WHERE
          External_Id__c = :BulkActivationDemo.contractKey(
            BulkActivationDemo.chaosRow(200)
          )
      ];
      Assert.areEqual(
        ContractActivationHandler.STATUS_DRAFT,
        invalid.Status__c
      );
      Assert.areEqual(
        1,
        DemoTestFactory.findRun(request.runKey).Records_Failed__c
      );
    }
  }
}
