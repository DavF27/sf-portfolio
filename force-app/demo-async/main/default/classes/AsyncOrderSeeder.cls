/**
 * DemoDataSeeder of the silent asynchronous chain demo.
 */
public with sharing class AsyncOrderSeeder implements DemoDataSeeder {
  public Integer seed(Integer volume, SyntheticDataGenerator generator) {
    AsyncOrderDemo.Prepared prepared = AsyncOrderDemo.prepare(
      volume,
      false,
      generator
    );
    Integer lines = 0;
    for (
      List<Order_Line_Demo__c> bundleLines : prepared.linesByBundle.values()
    ) {
      lines += bundleLines.size();
    }
    return lines;
  }

  public Integer purge() {
    return AsyncOrderDemo.purge();
  }
}
