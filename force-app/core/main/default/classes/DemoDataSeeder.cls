/**
 * Creates and removes the synthetic data a demo needs. Registered in Demo_Setting__mdt.Seeder_Class__c.
 */
public interface DemoDataSeeder {
  /** Inserts volume records built from the deterministic generator; returns the number inserted. */
  Integer seed(Integer volume, SyntheticDataGenerator generator);

  /** Deletes every record created by seed(); returns the number deleted. */
  Integer purge();
}
