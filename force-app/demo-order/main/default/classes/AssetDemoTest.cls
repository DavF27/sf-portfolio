@IsTest
private class AssetDemoTest {
  @IsTest
  static void prepareIsIdempotentAndClearsEveryRun() {
    System.runAs(OrderDemoTestSupport.runner()) {
      List<Asset_Demo__c> first = OrderDemoTestSupport.prepare(200);
      for (Asset_Demo__c asset : first) {
        asset.Status__c = AssetDemo.STATUS_INSTALLED;
        asset.Processing_Mode__c = DemoRunService.MODE_AFTER;
      }
      update first;

      Test.startTest();
      List<Asset_Demo__c> second = OrderDemoTestSupport.prepare(200);
      Test.stopTest();

      Assert.areEqual(first[0].Id, second[0].Id, 'Same rows, upserted');
      Assert.areEqual(200, [SELECT COUNT() FROM Asset_Demo__c]);
      Assert.areEqual(
        200,
        [SELECT COUNT() FROM Asset_Demo__c WHERE Status__c = 'Ordered']
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Asset_Demo__c WHERE Warranty_End__c != NULL]
      );
      Assert.areEqual(0, OrderDemoTestSupport.snapshots().size());
    }
  }

  @IsTest
  static void installationDatesAvoidMonthEnds() {
    Test.startTest();
    Set<Integer> days = new Set<Integer>();
    for (Integer row = 1; row <= 400; row++) {
      Date installedOn = AssetDemo.installationDate(row);
      days.add(installedOn.day());
      Assert.isTrue(installedOn.day() <= 27, String.valueOf(installedOn));
    }
    Test.stopTest();

    Assert.areEqual(27, days.size());
  }

  @IsTest
  static void expectedTermsFollowTheProductFamily() {
    Asset_Demo__c premium = new Asset_Demo__c(
      Installed_On__c = Date.newInstance(2026, 3, 10),
      Product_Family__c = AssetDemo.FAMILY_PREMIUM
    );
    Asset_Demo__c standard = new Asset_Demo__c(
      Installed_On__c = Date.newInstance(2026, 3, 10),
      Product_Family__c = AssetDemo.FAMILY_STANDARD
    );

    Test.startTest();
    Date premiumWarranty = AssetDemo.expectedWarrantyEnd(premium);
    Date standardMaintenance = AssetDemo.expectedNextMaintenance(standard);
    Test.stopTest();

    Assert.areEqual(Date.newInstance(2029, 3, 10), premiumWarranty);
    Assert.areEqual('Gold', AssetDemo.expectedServiceTier(premium));
    Assert.areEqual(Date.newInstance(2026, 9, 10), standardMaintenance);
    Assert.areEqual('Silver', AssetDemo.expectedServiceTier(standard));
  }

  @IsTest
  static void purgeDeletesAssetsAndSnapshots() {
    System.runAs(OrderDemoTestSupport.runner()) {
      List<Asset_Demo__c> assets = OrderDemoTestSupport.prepare(5);
      for (Asset_Demo__c asset : assets) {
        asset.Status__c = AssetDemo.STATUS_INSTALLED;
      }
      update assets;

      Test.startTest();
      Integer purged = AssetDemo.purge();
      Test.stopTest();

      Assert.areEqual(5, purged);
      Assert.areEqual(0, OrderDemoTestSupport.snapshots().size());
    }
  }
}
