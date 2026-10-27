@IsTest
private class DemoCatalogTest {
  @IsTest
  static void returnsActiveDemosSortedByOrderThenName() {
    Demo_Setting__mdt second = DemoTestFactory.setting('B_Demo', 'X', 'Y');
    Demo_Setting__mdt first = DemoTestFactory.setting('A_Demo', 'X', 'Y');
    Demo_Setting__mdt unordered = DemoTestFactory.setting('C_Demo', 'X', 'Y');
    unordered.Sort_Order__c = null;
    Demo_Setting__mdt zero = DemoTestFactory.setting('Z_Demo', 'X', 'Y');
    zero.Sort_Order__c = 0;
    Demo_Setting__mdt inactive = DemoTestFactory.setting(
      'Inactive_Demo',
      'X',
      'Y'
    );
    inactive.Is_Active__c = false;
    DemoTestFactory.register(
      new List<Demo_Setting__mdt>{ unordered, second, inactive, first, zero }
    );

    Test.startTest();
    List<Demo_Setting__mdt> active = DemoCatalog.getActive();
    Test.stopTest();

    Assert.areEqual(4, active.size());
    Assert.areEqual('Z_Demo', active[0].DeveloperName);
    Assert.areEqual('A_Demo', active[1].DeveloperName);
    Assert.areEqual('B_Demo', active[2].DeveloperName);
    Assert.areEqual('C_Demo', active[3].DeveloperName);
  }

  @IsTest
  static void rejectsUnknownBlankAndInactiveDemos() {
    Demo_Setting__mdt inactive = DemoTestFactory.setting(
      'Inactive_Demo',
      'X',
      'Y'
    );
    inactive.Is_Active__c = false;
    DemoTestFactory.register(new List<Demo_Setting__mdt>{ inactive });

    Test.startTest();
    for (String name : new List<String>{ 'Missing', '', 'Inactive_Demo' }) {
      try {
        DemoCatalog.get(name);
        Assert.fail('Expected DemoException for ' + name);
      } catch (DemoException e) {
        Assert.isTrue(e.getMessage().startsWith('Unknown or inactive demo'));
      }
    }
    Test.stopTest();
  }

  @IsTest
  static void readsDeployedCustomMetadata() {
    Test.startTest();
    Demo_Setting__mdt probe = DemoCatalog.get('Limits_Probe');
    Test.stopTest();

    Assert.areEqual('LimitsProbeBeforeStrategy', probe.Before_Class__c);
  }
}
