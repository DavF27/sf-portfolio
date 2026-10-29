/**
 * AFTER mode of the Bulk all-or-nothing demo: one query and one partial-success update for the
 * whole batch, so the deal flows run once in bulk and an invalid deal only fails its own contract.
 */
public with sharing class ContractActivationAfter implements ContractActivationService {
  public Map<Id, String> activate(
    List<Contract_Demo__c> contracts,
    ContractActivationHandler.Progress progress
  ) {
    Set<Id> contractIds = new Map<Id, Contract_Demo__c>(contracts).keySet();
    List<Deal_Demo__c> deals = [
      SELECT Id, Name, Contract__c
      FROM Deal_Demo__c
      WHERE Contract__c IN :contractIds
      WITH USER_MODE
      ORDER BY External_Id__c
    ];
    progress.step('Queried ' + deals.size() + ' deals', 0, 0);

    Datetime activatedAt = Datetime.now();
    // Update copies holding only the changed fields: the master-detail field read above is not
    // updateable (not reparentable) and USER_MODE rejects it.
    List<Deal_Demo__c> updates = new List<Deal_Demo__c>();
    for (Deal_Demo__c deal : deals) {
      updates.add(
        new Deal_Demo__c(
          Id = deal.Id,
          Status__c = ContractActivationHandler.STATUS_ACTIVE,
          Activated_At__c = activatedAt
        )
      );
    }
    List<Database.SaveResult> results = Database.update(
      updates,
      false,
      AccessLevel.USER_MODE
    );

    Map<Id, String> errorsByContract = new Map<Id, String>();
    for (Integer i = 0; i < results.size(); i++) {
      Id contractId = deals[i].Contract__c;
      if (
        !results[i].isSuccess() && !errorsByContract.containsKey(contractId)
      ) {
        errorsByContract.put(
          contractId,
          'Deal ' +
            deals[i].Name +
            ': ' +
            results[i].getErrors()[0].getMessage()
        );
      }
    }
    progress.step(
      'Activated deals',
      contracts.size() - errorsByContract.size(),
      errorsByContract.size()
    );
    return errorsByContract;
  }
}
