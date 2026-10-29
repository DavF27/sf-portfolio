/**
 * Activates the deals of contracts that were just activated.
 */
public interface ContractActivationService {
  /**
   * @return contract Id to error message, for the contracts whose deals could not be activated
   */
  Map<Id, String> activate(
    List<Contract_Demo__c> contracts,
    ContractActivationHandler.Progress progress
  );
}
