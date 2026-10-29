/**
 * Panel strategy of the Bulk all-or-nothing demo, used for both modes: the mode only changes the
 * Processing_Mode__c sent with each row, exactly like the Bulk API job of scripts/bulk-demo.js.
 * The faulty BEFORE code lives in ContractActivationBefore.
 *
 * The batch is saved with one partial-success update, which is how the Bulk API saves a chunk:
 * rows succeed or fail independently, unless the trigger breaks the whole transaction.
 */
public with sharing class BulkActivationStrategy implements DemoStrategy {
  public DemoResult execute(DemoContext context) {
    List<Contract_Demo__c> contracts = BulkActivationDemo.prepare(
      context.volume,
      context.chaos,
      new SyntheticDataGenerator(DemoDataService.DEFAULT_SEED)
    );
    // Measure the batch only, not the data preparation.
    context.metrics.reset();
    context.step('Batch of ' + contracts.size() + ' contracts ready', 0, 0);

    for (Contract_Demo__c contract : contracts) {
      contract.Status__c = ContractActivationHandler.STATUS_ACTIVE;
      contract.Processing_Mode__c = context.mode;
      contract.Run_Key__c = context.runKey;
    }
    List<Database.SaveResult> results;
    ContractActivationHandler.setPanelContext(context);
    try {
      results = Database.update(contracts, false, AccessLevel.USER_MODE);
    } finally {
      ContractActivationHandler.setPanelContext(null);
    }
    return toResult(results, context);
  }

  private DemoResult toResult(
    List<Database.SaveResult> results,
    DemoContext context
  ) {
    DemoResult result = new DemoResult(results.size(), 0);
    String firstError;
    for (Integer i = 0; i < results.size(); i++) {
      if (!results[i].isSuccess()) {
        result.recordsFailed++;
        result.failedRows.add(i + 1);
        firstError = firstError ?? results[i].getErrors()[0].getMessage();
      }
    }
    context.step(
      'Batch saved',
      results.size() - result.recordsFailed,
      result.recordsFailed
    );
    if (result.recordsFailed == results.size()) {
      throw new DemoException(
        'All ' + results.size() + ' rows of the batch failed: ' + firstError
      );
    }
    result.message = result.hasFailures()
      ? result.recordsFailed +
        ' of ' +
        results.size() +
        ' rows failed, the others were saved. ' +
        firstError
      : 'Activated ' + results.size() + ' contracts';
    return result;
  }
}
