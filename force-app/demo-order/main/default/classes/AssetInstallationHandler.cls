/**
 * Asset_Demo__c triggers of the order of execution demo.
 *
 * The after trigger snapshots the service terms of every asset that becomes Installed. Whether the
 * terms are already there depends on where the flow that computes them runs:
 * - before-save flow (AFTER mode): before the before trigger, so the snapshot is complete;
 * - after-save flow (BEFORE mode): after the after trigger, so the snapshot is empty. The flow then
 *   saves the asset again; on that re-save the asset is no longer a new installation and no snapshot
 *   is taken.
 *
 * When the rows carry a Run_Key__c, each trigger publishes what it sees on the demo timeline.
 */
public with sharing class AssetInstallationHandler {
  public static void beforeUpdate(
    List<Asset_Demo__c> assets,
    Map<Id, Asset_Demo__c> oldAssets
  ) {
    List<Asset_Demo__c> installations = new List<Asset_Demo__c>();
    List<Asset_Demo__c> resaves = new List<Asset_Demo__c>();
    for (Asset_Demo__c asset : assets) {
      Asset_Demo__c old = oldAssets.get(asset.Id);
      if (isInstallation(asset, old)) {
        installations.add(asset);
      } else if (isResaveWithNewTerms(asset, old)) {
        resaves.add(asset);
      }
    }
    for (List<Asset_Demo__c> batch : byRunKey(installations).values()) {
      publish(batch, 'Before trigger', describeTerms(batch));
    }
    for (List<Asset_Demo__c> batch : byRunKey(resaves).values()) {
      publish(
        batch,
        'Before trigger (re-save by the flow)',
        describeTerms(batch)
      );
    }
  }

  public static void afterUpdate(
    List<Asset_Demo__c> assets,
    Map<Id, Asset_Demo__c> oldAssets
  ) {
    List<Asset_Demo__c> installations = new List<Asset_Demo__c>();
    List<Asset_Demo__c> resaves = new List<Asset_Demo__c>();
    List<Asset_Snapshot_Demo__c> snapshots = new List<Asset_Snapshot_Demo__c>();
    for (Asset_Demo__c asset : assets) {
      Asset_Demo__c old = oldAssets.get(asset.Id);
      if (isInstallation(asset, old)) {
        installations.add(asset);
        snapshots.add(snapshotOf(asset));
      } else if (isResaveWithNewTerms(asset, old)) {
        resaves.add(asset);
      }
    }
    Database.insert(snapshots, true, AccessLevel.USER_MODE);

    for (List<Asset_Demo__c> batch : byRunKey(installations).values()) {
      publish(batch, 'After trigger: snapshot taken', describeTerms(batch));
    }
    for (List<Asset_Demo__c> batch : byRunKey(resaves).values()) {
      publish(
        batch,
        'After trigger (re-save): not a new installation, snapshot left as taken',
        describeTerms(batch)
      );
    }
  }

  private static Boolean isInstallation(
    Asset_Demo__c asset,
    Asset_Demo__c old
  ) {
    return asset.Status__c == AssetDemo.STATUS_INSTALLED &&
      old.Status__c != AssetDemo.STATUS_INSTALLED;
  }

  private static Boolean isResaveWithNewTerms(
    Asset_Demo__c asset,
    Asset_Demo__c old
  ) {
    return asset.Status__c == AssetDemo.STATUS_INSTALLED &&
      old.Status__c == AssetDemo.STATUS_INSTALLED &&
      asset.Warranty_End__c != old.Warranty_End__c;
  }

  private static Asset_Snapshot_Demo__c snapshotOf(Asset_Demo__c asset) {
    return new Asset_Snapshot_Demo__c(
      Asset__c = asset.Id,
      Status__c = asset.Status__c,
      Taken_By__c = 'Asset_Demo__c after update trigger',
      Warranty_End__c = asset.Warranty_End__c,
      Service_Tier__c = asset.Service_Tier__c,
      Next_Maintenance__c = asset.Next_Maintenance__c
    );
  }

  private static String describeTerms(List<Asset_Demo__c> batch) {
    Integer withTerms = 0;
    for (Asset_Demo__c asset : batch) {
      if (AssetDemo.hasTerms(asset)) {
        withTerms++;
      }
    }
    Asset_Demo__c first = batch[0];
    return 'Service terms present on ' +
      withTerms +
      ' of ' +
      batch.size() +
      ' assets. ' +
      first.Name +
      ': warranty end ' +
      (first.Warranty_End__c == null
        ? '(empty)'
        : String.valueOf(first.Warranty_End__c)) +
      ', tier ' +
      (first.Service_Tier__c ?? '(empty)');
  }

  private static Map<String, List<Asset_Demo__c>> byRunKey(
    List<Asset_Demo__c> assets
  ) {
    Map<String, List<Asset_Demo__c>> batches = new Map<String, List<Asset_Demo__c>>();
    for (Asset_Demo__c asset : assets) {
      if (String.isBlank(asset.Run_Key__c)) {
        continue;
      }
      if (!batches.containsKey(asset.Run_Key__c)) {
        batches.put(asset.Run_Key__c, new List<Asset_Demo__c>());
      }
      batches.get(asset.Run_Key__c).add(asset);
    }
    return batches;
  }

  private static void publish(
    List<Asset_Demo__c> batch,
    String label,
    String message
  ) {
    DemoRunService.Request request = new DemoRunService.Request(
      AssetDemo.DEMO_NAME,
      batch[0].Processing_Mode__c,
      null
    );
    request.runKey = batch[0].Run_Key__c;
    new DemoStepPublisher(request, null).step(label, batch.size(), 0, message);
  }
}
