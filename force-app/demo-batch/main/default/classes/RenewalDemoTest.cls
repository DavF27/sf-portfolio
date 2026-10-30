@IsTest
private class RenewalDemoTest {
  @IsTest
  static void prepareIsIdempotentAndTrimsThePreviousRun() {
    System.runAs(BatchDemoTestSupport.runner()) {
      BatchDemoTestSupport.prepare(RenewalDemo.LANE_BEFORE, 300);
      update new Renewal_Demo__c(
        Id = [SELECT Id FROM Renewal_Demo__c LIMIT 1]
        .Id,
        Notice_Sent__c = true
      );

      Test.startTest();
      Integer prepared = BatchDemoTestSupport.prepare(
        RenewalDemo.LANE_BEFORE,
        200
      );
      Test.stopTest();

      Assert.areEqual(200, prepared);
      Assert.areEqual(200, [SELECT COUNT() FROM Renewal_Demo__c]);
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Renewal_Demo__c WHERE Notice_Sent__c = TRUE]
      );
    }
  }

  @IsTest
  static void oneRenewalInTwentyIsDueAndTheFormulaMatchesApex() {
    System.runAs(BatchDemoTestSupport.runner()) {
      BatchDemoTestSupport.prepare(RenewalDemo.LANE_AFTER, 200);

      Test.startTest();
      List<Renewal_Demo__c> renewals = [
        SELECT
          External_Id__c,
          Status__c,
          Notice_Sent__c,
          Start_Date__c,
          Term_Months__c,
          Notice_Days__c,
          Notice_Deadline__c
        FROM Renewal_Demo__c
      ];
      Test.stopTest();

      Date today = Date.today();
      Integer due = 0;
      for (Renewal_Demo__c renewal : renewals) {
        Assert.areEqual(
          renewal.Start_Date__c
            .addMonths(renewal.Term_Months__c.intValue())
            .addDays(-renewal.Notice_Days__c.intValue()),
          renewal.Notice_Deadline__c,
          renewal.External_Id__c
        );
        Integer row = Integer.valueOf(renewal.External_Id__c.right(5));
        Assert.areEqual(
          RenewalDemo.isEligibleRow(row),
          RenewalDemo.isDue(renewal, today),
          renewal.External_Id__c
        );
        due += RenewalDemo.isDue(renewal, today) ? 1 : 0;
      }
      Assert.areEqual(RenewalDemo.eligibleCount(200), due);
    }
  }

  /** Formula fields cannot be set in Apex: build the record from JSON. */
  private static Renewal_Demo__c withDeadline(Date deadline, Boolean sent) {
    return (Renewal_Demo__c) JSON.deserialize(
      JSON.serialize(
        new Map<String, Object>{
          'attributes' => new Map<String, Object>{
            'type' => 'Renewal_Demo__c'
          },
          'Status__c' => RenewalDemo.STATUS_ACTIVE,
          'Notice_Sent__c' => sent,
          'Notice_Deadline__c' => deadline
        }
      ),
      Renewal_Demo__c.class
    );
  }

  @IsTest
  static void dueOnlyWithinTheHorizonAndBeforeNotice() {
    Date today = Date.newInstance(2026, 6, 10);

    Test.startTest();
    Map<Integer, Boolean> dueByOffset = new Map<Integer, Boolean>();
    for (Integer offset : new List<Integer>{ -1, 0, 30, 31 }) {
      dueByOffset.put(
        offset,
        RenewalDemo.isDue(withDeadline(today.addDays(offset), false), today)
      );
    }
    Boolean alreadySent = RenewalDemo.isDue(
      withDeadline(today.addDays(5), true),
      today
    );
    Test.stopTest();

    Assert.isFalse(dueByOffset.get(-1));
    Assert.isTrue(dueByOffset.get(0));
    Assert.isTrue(dueByOffset.get(30));
    Assert.isFalse(dueByOffset.get(31));
    Assert.isFalse(alreadySent);
  }

  @IsTest
  static void purgeDeletesEveryLane() {
    System.runAs(BatchDemoTestSupport.runner()) {
      BatchDemoTestSupport.prepare(RenewalDemo.LANE_BEFORE, 10);
      BatchDemoTestSupport.prepare(RenewalDemo.LANE_AFTER, 10);

      Test.startTest();
      Integer purged = RenewalDemo.purge();
      Test.stopTest();

      Assert.areEqual(20, purged);
    }
  }
}
