@IsTest
private class DemoStrategyFactoryTest {
  @IsTest
  static void createsStrategyPerMode() {
    Demo_Setting__mdt setting = DemoTestFactory.registerDefault();

    Test.startTest();
    DemoStrategy before = DemoStrategyFactory.create(
      setting,
      DemoRunService.MODE_BEFORE
    );
    DemoStrategy after = DemoStrategyFactory.create(
      setting,
      DemoRunService.MODE_AFTER
    );
    DemoDataSeeder seeder = DemoStrategyFactory.createSeeder(setting);
    Test.stopTest();

    Assert.isInstanceOfType(before, DemoTestFactory.FailingStrategy.class);
    Assert.isInstanceOfType(after, DemoTestFactory.SucceedingStrategy.class);
    Assert.isInstanceOfType(seeder, DemoTestFactory.RunSeeder.class);
  }

  @IsTest
  static void rejectsMissingAndWrongClasses() {
    Demo_Setting__mdt setting = DemoTestFactory.setting(
      'Broken',
      'DoesNotExist',
      'DemoTestFactory.NotAStrategy'
    );
    setting.Seeder_Class__c = 'DemoTestFactory.NotAStrategy';
    Demo_Setting__mdt noSeeder = DemoTestFactory.setting('No_Seeder', 'X', 'Y');
    noSeeder.Seeder_Class__c = null;

    Test.startTest();
    assertThrows(setting, DemoRunService.MODE_BEFORE, 'Apex class not found');
    assertThrows(
      setting,
      DemoRunService.MODE_AFTER,
      'does not implement DemoStrategy'
    );
    try {
      DemoStrategyFactory.createSeeder(setting);
      Assert.fail('Expected DemoException');
    } catch (DemoException e) {
      Assert.isTrue(
        e.getMessage().contains('does not implement DemoDataSeeder')
      );
    }
    try {
      DemoStrategyFactory.createSeeder(noSeeder);
      Assert.fail('Expected DemoException');
    } catch (DemoException e) {
      Assert.isTrue(e.getMessage().startsWith('No seeder configured'));
    }
    Test.stopTest();
  }

  private static void assertThrows(
    Demo_Setting__mdt setting,
    String mode,
    String expected
  ) {
    try {
      DemoStrategyFactory.create(setting, mode);
      Assert.fail('Expected DemoException');
    } catch (DemoException e) {
      Assert.isTrue(e.getMessage().contains(expected), e.getMessage());
    }
  }
}
