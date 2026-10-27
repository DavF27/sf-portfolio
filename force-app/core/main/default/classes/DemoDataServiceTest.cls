@IsTest
private class DemoDataServiceTest {
  @IsTest
  static void seeds200RecordsDeterministically() {
    DemoTestFactory.registerDefault();

    Test.startTest();
    Integer seeded = DemoDataService.seed(DemoTestFactory.DEMO, 200);
    Test.stopTest();

    Assert.areEqual(200, seeded);
    List<Demo_Run__c> records = [
      SELECT Volume__c
      FROM Demo_Run__c
      WHERE Demo__c = :DemoTestFactory.SEEDED_DEMO_MARKER
      ORDER BY Name
    ];
    SyntheticDataGenerator expected = new SyntheticDataGenerator(
      DemoDataService.DEFAULT_SEED
    );
    Assert.areEqual(
      expected.nextIntBetween(1, 100),
      records[0].Volume__c,
      'Same seed, same data'
    );
  }

  @IsTest
  static void purgesSeededRecords() {
    DemoTestFactory.registerDefault();
    DemoDataService.seed(DemoTestFactory.DEMO, 20);

    Test.startTest();
    Integer purged = DemoDataService.purge(DemoTestFactory.DEMO);
    Test.stopTest();

    Assert.areEqual(20, purged);
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM Demo_Run__c
        WHERE Demo__c = :DemoTestFactory.SEEDED_DEMO_MARKER
      ]
    );
  }

  @IsTest
  static void rejectsVolumeOutsideBounds() {
    DemoTestFactory.registerDefault();

    Test.startTest();
    for (Integer volume : new List<Integer>{ null, 0, 501 }) {
      try {
        DemoDataService.seed(DemoTestFactory.DEMO, volume);
        Assert.fail('Expected DemoException for ' + volume);
      } catch (DemoException e) {
        Assert.isTrue(e.getMessage().startsWith('Volume must be between'));
      }
    }
    Test.stopTest();
  }
}
