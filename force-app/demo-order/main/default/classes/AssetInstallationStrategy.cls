/**
 * Panel strategy of the order of execution demo, used for both modes: the mode only selects which
 * flow computes the service terms (Processing_Mode__c), the trigger is the same.
 *
 * The BEFORE failure is silent on purpose: the save succeeds, only the data is wrong. The run is
 * reported as succeeded with every incomplete snapshot counted as a failed row.
 */
public with sharing class AssetInstallationStrategy implements DemoStrategy {
  public DemoResult execute(DemoContext context) {
    List<Asset_Demo__c> assets = AssetDemo.prepare(
      context.volume,
      new SyntheticDataGenerator(DemoDataService.DEFAULT_SEED)
    );
    context.metrics.reset();
    context.step('Installing ' + assets.size() + ' assets in one save', 0, 0);

    for (Asset_Demo__c asset : assets) {
      asset.Status__c = AssetDemo.STATUS_INSTALLED;
      asset.Processing_Mode__c = context.mode;
      asset.Run_Key__c = context.runKey;
    }
    Database.update(assets, true, AccessLevel.USER_MODE);
    context.injectChaos('after the installation');
    return checkSnapshots(assets, context);
  }

  private DemoResult checkSnapshots(
    List<Asset_Demo__c> assets,
    DemoContext context
  ) {
    Map<Id, Asset_Demo__c> saved = new Map<Id, Asset_Demo__c>(
      [
        SELECT Id, Warranty_End__c, Service_Tier__c, Next_Maintenance__c
        FROM Asset_Demo__c
        WHERE Id IN :assets
        WITH USER_MODE
      ]
    );
    Map<Id, Asset_Snapshot_Demo__c> snapshotByAsset = new Map<Id, Asset_Snapshot_Demo__c>();
    for (Asset_Snapshot_Demo__c snapshot : [
      SELECT Asset__c, Warranty_End__c, Service_Tier__c, Next_Maintenance__c
      FROM Asset_Snapshot_Demo__c
      WHERE Asset__c IN :assets
      WITH USER_MODE
    ]) {
      snapshotByAsset.put(snapshot.Asset__c, snapshot);
    }

    DemoResult result = new DemoResult(assets.size(), 0);
    for (Integer i = 0; i < assets.size(); i++) {
      Asset_Demo__c asset = saved.get(assets[i].Id);
      if (!matches(snapshotByAsset.get(asset.Id), asset)) {
        result.recordsFailed++;
        result.failedRows.add(i + 1);
      }
    }
    context.step(
      'Snapshots checked against the saved assets',
      assets.size() - result.recordsFailed,
      result.recordsFailed
    );
    result.message = result.hasFailures()
      ? 'Saved without error, but ' +
        result.recordsFailed +
        ' of ' +
        assets.size() +
        ' snapshots miss the service terms the assets now have.'
      : 'All ' + assets.size() + ' snapshots carry the service terms.';
    return result;
  }

  private Boolean matches(
    Asset_Snapshot_Demo__c snapshot,
    Asset_Demo__c asset
  ) {
    return snapshot != null &&
      AssetDemo.hasTerms(asset) &&
      snapshot.Warranty_End__c == asset.Warranty_End__c &&
      snapshot.Service_Tier__c == asset.Service_Tier__c &&
      snapshot.Next_Maintenance__c == asset.Next_Maintenance__c;
  }
}
