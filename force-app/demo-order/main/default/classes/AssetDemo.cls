/**
 * Synthetic data of the trigger and flow order of execution demo. prepare() is idempotent: it
 * upserts the same N ordered assets, clears their service terms and deletes their snapshots.
 */
public with sharing class AssetDemo {
  public static final String DEMO_NAME = 'Order_Of_Execution';
  public static final String STATUS_ORDERED = 'Ordered';
  public static final String STATUS_INSTALLED = 'Installed';
  public static final String FAMILY_PREMIUM = 'Premium';
  public static final String FAMILY_STANDARD = 'Standard';
  private static final String PREFIX = 'AST';
  private static final Integer PREMIUM_PERCENT = 30;

  public static String assetKey(Integer row) {
    return SyntheticDataGenerator.label(PREFIX, row);
  }

  /**
   * Installation dates stay between the 1st and the 27th: on a last day of month, the flow ADDMONTHS
   * function and Apex Date.addMonths do not agree.
   */
  public static Date installationDate(Integer row) {
    return Date.newInstance(
      2026,
      1 + Math.mod(row - 1, 12),
      1 + Math.mod(row - 1, 27)
    );
  }

  public static List<Asset_Demo__c> prepare(
    Integer volume,
    SyntheticDataGenerator generator
  ) {
    List<Asset_Demo__c> assets = new List<Asset_Demo__c>();
    for (Integer row = 1; row <= volume; row++) {
      String key = assetKey(row);
      assets.add(
        new Asset_Demo__c(
          Name = key,
          External_Id__c = key,
          Status__c = STATUS_ORDERED,
          Installed_On__c = installationDate(row),
          Product_Family__c = generator.chance(PREMIUM_PERCENT)
            ? FAMILY_PREMIUM
            : FAMILY_STANDARD,
          Processing_Mode__c = null,
          Run_Key__c = null,
          Warranty_End__c = null,
          Service_Tier__c = null,
          Next_Maintenance__c = null
        )
      );
    }
    Database.upsert(
      assets,
      Asset_Demo__c.External_Id__c,
      true,
      AccessLevel.USER_MODE
    );
    List<Asset_Snapshot_Demo__c> snapshots = [
      SELECT Id
      FROM Asset_Snapshot_Demo__c
      WHERE Asset__c IN :assets
      WITH USER_MODE
    ];
    Database.delete(snapshots, true, AccessLevel.USER_MODE);
    return assets;
  }

  /** Deletes every demo asset; snapshots follow through master-detail. */
  public static Integer purge() {
    List<Asset_Demo__c> assets = [SELECT Id FROM Asset_Demo__c WITH USER_MODE];
    Database.delete(assets, true, AccessLevel.USER_MODE);
    return assets.size();
  }

  public static Boolean isPremium(Asset_Demo__c asset) {
    return asset.Product_Family__c == FAMILY_PREMIUM;
  }

  /** Same rules as the formulas of the two Asset_Demo__c flows. */
  public static Date expectedWarrantyEnd(Asset_Demo__c asset) {
    return asset.Installed_On__c.addMonths(isPremium(asset) ? 36 : 24);
  }

  public static String expectedServiceTier(Asset_Demo__c asset) {
    return isPremium(asset) ? 'Gold' : 'Silver';
  }

  public static Date expectedNextMaintenance(Asset_Demo__c asset) {
    return asset.Installed_On__c.addMonths(isPremium(asset) ? 3 : 6);
  }

  /** True when the record (asset or snapshot) carries the three service terms. */
  public static Boolean hasTerms(SObject record) {
    return record.get('Warranty_End__c') != null &&
      String.isNotBlank((String) record.get('Service_Tier__c')) &&
      record.get('Next_Maintenance__c') != null;
  }
}
