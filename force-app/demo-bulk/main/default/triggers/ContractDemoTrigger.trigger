trigger ContractDemoTrigger on Contract_Demo__c(after update) {
  ContractActivationHandler.handle(Trigger.new, Trigger.oldMap);
}
