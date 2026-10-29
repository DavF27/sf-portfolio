/**
 * DemoDataSeeder of the order of execution demo.
 */
public with sharing class AssetInstallationSeeder implements DemoDataSeeder {
  public Integer seed(Integer volume, SyntheticDataGenerator generator) {
    return AssetDemo.prepare(volume, generator).size();
  }

  public Integer purge() {
    return AssetDemo.purge();
  }
}
