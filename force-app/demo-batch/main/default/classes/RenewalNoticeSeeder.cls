/**
 * DemoDataSeeder of the batch filter demo: seeds both lanes.
 */
public with sharing class RenewalNoticeSeeder implements DemoDataSeeder {
  public Integer seed(Integer volume, SyntheticDataGenerator generator) {
    return RenewalDemo.prepare(RenewalDemo.LANE_BEFORE, volume, generator) +
      RenewalDemo.prepare(RenewalDemo.LANE_AFTER, volume, generator);
  }

  public Integer purge() {
    return RenewalDemo.purge();
  }
}
