/**
 * BEFORE mode of the Bulk all-or-nothing demo. Deliberately broken, never reuse:
 * - one query and one DML per contract, and every DML re-runs the two deal flows, so the
 *   cascade costs about 3 queries per contract and breaks the 100-query limit inside a
 *   single batch of 50: the whole batch fails;
 * - an all-or-none update: one invalid deal throws, which also fails every row of the batch.
 */
public with sharing class ContractActivationBefore implements ContractActivationService {
  // One step per contract: the gauges climb up to the breaking point (it breaks around 33).
  private static final Integer STEP_EVERY = 1;

  public Map<Id, String> activate(
    List<Contract_Demo__c> contracts,
    ContractActivationHandler.Progress progress
  ) {
    Integer processed = 0;
    for (Contract_Demo__c contract : contracts) {
      // Intentional anti-pattern for the BEFORE demo: SOQL and DML inside the loop.
      List<Deal_Demo__c> deals = [
        SELECT Id
        FROM Deal_Demo__c
        WHERE Contract__c = :contract.Id
        WITH USER_MODE
      ];
      for (Deal_Demo__c deal : deals) {
        deal.Status__c = ContractActivationHandler.STATUS_ACTIVE;
        deal.Activated_At__c = Datetime.now();
      }
      // Intentional anti-pattern for the BEFORE demo: all-or-none DML, one invalid deal fails the batch.
      update as user deals;
      processed++;
      if (Math.mod(processed, STEP_EVERY) == 0) {
        progress.step('Contract ' + processed, processed, 0);
      }
    }
    return new Map<Id, String>();
  }
}
