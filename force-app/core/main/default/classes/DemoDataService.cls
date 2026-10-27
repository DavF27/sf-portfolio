/**
 * Seeds and purges the synthetic data of a demo through its configured DemoDataSeeder.
 */
public with sharing class DemoDataService {
  public static final Long DEFAULT_SEED = 20261027L;

  public static Integer seed(String demoName, Integer volume) {
    Demo_Setting__mdt setting = DemoCatalog.get(demoName);
    Integer maxVolume = setting.Max_Volume__c == null
      ? 1
      : setting.Max_Volume__c.intValue();
    if (volume == null || volume < 1 || volume > maxVolume) {
      throw new DemoException('Volume must be between 1 and ' + maxVolume);
    }
    return DemoStrategyFactory.createSeeder(setting)
      .seed(volume, new SyntheticDataGenerator(DEFAULT_SEED));
  }

  public static Integer purge(String demoName) {
    return DemoStrategyFactory.createSeeder(DemoCatalog.get(demoName)).purge();
  }
}
