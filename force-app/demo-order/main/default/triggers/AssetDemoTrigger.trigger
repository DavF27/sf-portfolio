trigger AssetDemoTrigger on Asset_Demo__c(before update, after update) {
  if (Trigger.isBefore) {
    AssetInstallationHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
  } else {
    AssetInstallationHandler.afterUpdate(Trigger.new, Trigger.oldMap);
  }
}
