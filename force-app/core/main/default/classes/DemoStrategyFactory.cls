/**
 * Instantiates the DemoStrategy configured for a demo and mode in Demo_Setting__mdt.
 */
public with sharing class DemoStrategyFactory {
  public static DemoStrategy create(Demo_Setting__mdt setting, String mode) {
    String className = mode == DemoRunService.MODE_BEFORE
      ? setting.Before_Class__c
      : setting.After_Class__c;
    Object instance = instantiate(className);
    if (!(instance instanceof DemoStrategy)) {
      throw new DemoException(className + ' does not implement DemoStrategy');
    }
    return (DemoStrategy) instance;
  }

  public static DemoDataSeeder createSeeder(Demo_Setting__mdt setting) {
    if (String.isBlank(setting.Seeder_Class__c)) {
      throw new DemoException(
        'No seeder configured for demo ' + setting.DeveloperName
      );
    }
    Object instance = instantiate(setting.Seeder_Class__c);
    if (!(instance instanceof DemoDataSeeder)) {
      throw new DemoException(
        setting.Seeder_Class__c + ' does not implement DemoDataSeeder'
      );
    }
    return (DemoDataSeeder) instance;
  }

  private static Object instantiate(String className) {
    Type strategyType = String.isBlank(className)
      ? null
      : Type.forName(className);
    if (strategyType == null) {
      throw new DemoException('Apex class not found: ' + className);
    }
    return strategyType.newInstance();
  }
}
