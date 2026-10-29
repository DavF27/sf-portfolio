/**
 * DemoDataSeeder of the Bulk all-or-nothing demo.
 */
public with sharing class BulkActivationSeeder implements DemoDataSeeder {
  public Integer seed(Integer volume, SyntheticDataGenerator generator) {
    return BulkActivationDemo.prepare(volume, false, generator).size();
  }

  public Integer purge() {
    return BulkActivationDemo.purge();
  }
}
