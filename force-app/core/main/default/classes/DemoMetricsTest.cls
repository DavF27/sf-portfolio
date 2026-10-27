@IsTest
private class DemoMetricsTest {
  @IsTest
  static void measuresQueriesAndDmlSinceBaseline() {
    Test.startTest();
    Integer ignored = [SELECT COUNT() FROM Demo_Run__c];
    DemoMetrics metrics = new DemoMetrics();
    ignored = [SELECT COUNT() FROM Demo_Run__c];
    ignored = [SELECT COUNT() FROM Demo_Run__c];
    List<Demo_Run__c> runs = new List<Demo_Run__c>();
    for (Integer i = 0; i < 200; i++) {
      runs.add(new Demo_Run__c(Demo__c = 'Metrics'));
    }
    insert runs;
    DemoMetrics.Snapshot snapshot = metrics.snapshot();
    Test.stopTest();

    Assert.areEqual(
      2,
      snapshot.soqlQueries,
      'Only queries after the baseline count'
    );
    Assert.areEqual(1, snapshot.dmlStatements);
    Assert.areEqual(200, snapshot.dmlRows);
    Assert.areEqual(Limits.getLimitQueries(), snapshot.soqlLimit);
    Assert.isTrue(snapshot.durationMs >= 0);
    Assert.isTrue(snapshot.heapBytes > 0);
  }

  @IsTest
  static void excludesInstrumentationOverhead() {
    Test.startTest();
    DemoMetrics metrics = new DemoMetrics();
    metrics.beginOverhead();
    Integer ignored = [SELECT COUNT() FROM Demo_Run__c];
    insert new Demo_Run__c(Demo__c = 'Overhead');
    metrics.endOverhead();
    metrics.endOverhead();
    DemoMetrics.Snapshot snapshot = metrics.snapshot();
    Test.stopTest();

    Assert.areEqual(0, snapshot.soqlQueries);
    Assert.areEqual(0, snapshot.dmlStatements);
    Assert.areEqual(0, snapshot.dmlRows);
  }

  @IsTest
  static void resetMovesTheBaseline() {
    Test.startTest();
    DemoMetrics metrics = new DemoMetrics();
    Integer ignored = [SELECT COUNT() FROM Demo_Run__c];
    metrics.reset();
    DemoMetrics.Snapshot snapshot = metrics.snapshot();
    Test.stopTest();

    Assert.areEqual(0, snapshot.soqlQueries);
  }
}
