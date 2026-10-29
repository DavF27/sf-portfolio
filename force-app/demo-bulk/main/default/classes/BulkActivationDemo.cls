/**
 * Synthetic data of the Bulk all-or-nothing demo. prepare() is idempotent: it upserts the same
 * N Draft contracts (2 deals each) by external Id, so every run starts from the same state.
 */
public with sharing class BulkActivationDemo {
  public static final Integer DEALS_PER_CONTRACT = 2;
  public static final String CONTRACT_PREFIX = 'CTR';
  private static final Decimal MIN_AMOUNT = 1000;
  private static final Decimal MAX_AMOUNT = 50000;

  /** Contract (1-based) whose last deal has no amount when chaos is on. */
  public static Integer chaosRow(Integer volume) {
    return Math.max(1, volume / 2);
  }

  public static String contractKey(Integer row) {
    return SyntheticDataGenerator.label(CONTRACT_PREFIX, row);
  }

  /**
   * @return the contracts in batch order (row 1 first), all Draft, with their deals Draft and
   *         their activation logs removed
   */
  public static List<Contract_Demo__c> prepare(
    Integer volume,
    Boolean chaos,
    SyntheticDataGenerator generator
  ) {
    List<Contract_Demo__c> contracts = new List<Contract_Demo__c>();
    for (Integer row = 1; row <= volume; row++) {
      String key = contractKey(row);
      contracts.add(
        new Contract_Demo__c(
          Name = key,
          External_Id__c = key,
          Status__c = ContractActivationHandler.STATUS_DRAFT,
          Processing_Mode__c = null,
          Run_Key__c = null
        )
      );
    }
    Database.upsert(
      contracts,
      Contract_Demo__c.External_Id__c,
      true,
      AccessLevel.USER_MODE
    );

    List<Deal_Demo__c> deals = buildDeals(contracts, chaos, generator);
    Database.upsert(
      deals,
      Deal_Demo__c.External_Id__c,
      true,
      AccessLevel.USER_MODE
    );

    List<Activation_Log_Demo__c> logs = [
      SELECT Id
      FROM Activation_Log_Demo__c
      WHERE Deal__r.Contract__c IN :contracts
      WITH USER_MODE
    ];
    Database.delete(logs, true, AccessLevel.USER_MODE);
    return contracts;
  }

  /** Deletes every demo contract; deals and logs follow through master-detail. */
  public static Integer purge() {
    List<Contract_Demo__c> contracts = [
      SELECT Id
      FROM Contract_Demo__c
      WITH USER_MODE
    ];
    Database.delete(contracts, true, AccessLevel.USER_MODE);
    return contracts.size();
  }

  private static List<Deal_Demo__c> buildDeals(
    List<Contract_Demo__c> contracts,
    Boolean chaos,
    SyntheticDataGenerator generator
  ) {
    Set<String> keys = new Set<String>();
    for (Contract_Demo__c contract : contracts) {
      for (Integer index = 1; index <= DEALS_PER_CONTRACT; index++) {
        keys.add(contract.External_Id__c + '-' + index);
      }
    }
    // The master-detail field is not reparentable: only set it on new deals.
    Set<String> existingKeys = new Set<String>();
    for (Deal_Demo__c existing : [
      SELECT External_Id__c
      FROM Deal_Demo__c
      WHERE External_Id__c IN :keys
      WITH USER_MODE
    ]) {
      existingKeys.add(existing.External_Id__c);
    }

    Integer invalidRow = chaos == true ? chaosRow(contracts.size()) : null;
    List<Deal_Demo__c> deals = new List<Deal_Demo__c>();
    for (Integer row = 1; row <= contracts.size(); row++) {
      Contract_Demo__c contract = contracts[row - 1];
      for (Integer index = 1; index <= DEALS_PER_CONTRACT; index++) {
        String key = contract.External_Id__c + '-' + index;
        Boolean invalid = row == invalidRow && index == DEALS_PER_CONTRACT;
        Deal_Demo__c deal = new Deal_Demo__c(
          Name = key,
          External_Id__c = key,
          Status__c = ContractActivationHandler.STATUS_DRAFT,
          Amount__c = invalid
            ? null
            : generator.nextAmount(MIN_AMOUNT, MAX_AMOUNT),
          Activated_At__c = null
        );
        if (!existingKeys.contains(key)) {
          deal.Contract__c = contract.Id;
        }
        deals.add(deal);
      }
    }
    return deals;
  }
}
