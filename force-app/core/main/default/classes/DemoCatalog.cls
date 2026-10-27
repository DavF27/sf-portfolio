/**
 * Read access to Demo_Setting__mdt. getAll() does not consume SOQL queries.
 */
public with sharing class DemoCatalog {
  @TestVisible
  private static Map<String, Demo_Setting__mdt> settingsOverride;

  public static List<Demo_Setting__mdt> getActive() {
    List<Demo_Setting__mdt> active = new List<Demo_Setting__mdt>();
    for (Demo_Setting__mdt setting : all().values()) {
      if (setting.Is_Active__c) {
        active.add(setting);
      }
    }
    active.sort(new SortOrderComparator());
    return active;
  }

  public static Demo_Setting__mdt get(String demoName) {
    Demo_Setting__mdt setting = String.isBlank(demoName)
      ? null
      : all().get(demoName);
    if (setting == null || !setting.Is_Active__c) {
      throw new DemoException('Unknown or inactive demo: ' + demoName);
    }
    return setting;
  }

  private static Map<String, Demo_Setting__mdt> all() {
    return settingsOverride ?? Demo_Setting__mdt.getAll();
  }

  private class SortOrderComparator implements Comparator<Demo_Setting__mdt> {
    public Integer compare(Demo_Setting__mdt left, Demo_Setting__mdt right) {
      Decimal leftOrder = left.Sort_Order__c ?? 999;
      Decimal rightOrder = right.Sort_Order__c ?? 999;
      if (leftOrder == rightOrder) {
        return left.DeveloperName.compareTo(right.DeveloperName);
      }
      return leftOrder < rightOrder ? -1 : 1;
    }
  }
}
