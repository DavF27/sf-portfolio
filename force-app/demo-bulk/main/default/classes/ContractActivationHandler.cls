/**
 * Contract_Demo__c after update: activates the deals of contracts moving from Draft to Active,
 * with the BEFORE or AFTER code selected per row by Processing_Mode__c (a Bulk API job cannot
 * pass parameters, so the mode travels in the data).
 *
 * The transition check is also the recursion guard. It is deliberately not a static Set:
 * on partial-success saves the platform re-runs this trigger for the successful rows, and
 * static variables survive between attempts, so a static guard would skip them.
 */
public with sharing class ContractActivationHandler {
  public static final String DEMO_NAME = 'Bulk_All_Or_Nothing';
  public static final String STATUS_ACTIVE = 'Active';
  public static final String STATUS_DRAFT = 'Draft';

  /** Set by BulkActivationStrategy while the panel runs the demo; steps then flow through it. */
  @TestVisible
  private static DemoContext panelContext;

  public static void handle(
    List<Contract_Demo__c> newContracts,
    Map<Id, Contract_Demo__c> oldContracts
  ) {
    Map<String, List<Contract_Demo__c>> contractsByMode = new Map<String, List<Contract_Demo__c>>();
    for (Contract_Demo__c contract : newContracts) {
      Boolean activated =
        contract.Status__c == STATUS_ACTIVE &&
        oldContracts.get(contract.Id).Status__c != STATUS_ACTIVE;
      if (!activated) {
        continue;
      }
      String mode = contract.Processing_Mode__c ?? DemoRunService.MODE_AFTER;
      if (!contractsByMode.containsKey(mode)) {
        contractsByMode.put(mode, new List<Contract_Demo__c>());
      }
      contractsByMode.get(mode).add(contract);
    }
    for (String mode : contractsByMode.keySet()) {
      process(mode, contractsByMode.get(mode));
    }
  }

  public static void setPanelContext(DemoContext context) {
    panelContext = context;
  }

  private static void process(String mode, List<Contract_Demo__c> contracts) {
    Progress progress = progressFor(mode, contracts);
    progress.start();
    Map<Id, String> errorsByContract = serviceFor(mode)
      .activate(contracts, progress);
    for (Contract_Demo__c contract : contracts) {
      if (errorsByContract.containsKey(contract.Id)) {
        contract.addError(errorsByContract.get(contract.Id));
      }
    }
    progress.finish(contracts.size(), errorsByContract.values());
  }

  @TestVisible
  private static ContractActivationService serviceFor(String mode) {
    return mode == DemoRunService.MODE_BEFORE
      ? (ContractActivationService) new ContractActivationBefore()
      : new ContractActivationAfter();
  }

  private static Progress progressFor(
    String mode,
    List<Contract_Demo__c> contracts
  ) {
    if (panelContext != null) {
      return new PanelProgress(panelContext);
    }
    String runKey = contracts[0].Run_Key__c;
    if (String.isBlank(runKey)) {
      return new Progress();
    }
    DemoRunService.Request request = new DemoRunService.Request(
      DEMO_NAME,
      mode,
      contracts.size()
    );
    request.runKey = runKey;
    request.source = DemoRunService.SOURCE_SCRIPT;
    return new BulkJobProgress(request);
  }

  /** Progress of an activation nobody measures (e.g. a user activating a contract). */
  public virtual class Progress {
    public virtual void start() {
    }
    public virtual void step(String label, Integer processed, Integer failed) {
    }
    public virtual void finish(Integer total, List<String> errors) {
    }
  }

  /** Panel run: DemoRunService owns the run, steps go through its context. */
  private class PanelProgress extends Progress {
    private final DemoContext context;

    PanelProgress(DemoContext context) {
      this.context = context;
    }

    public override void step(String label, Integer processed, Integer failed) {
      context.step(label, processed, failed);
    }
  }

  /**
   * Bulk API job: the trigger owns the run. Steps are published immediately, so they survive a
   * LimitException; the caller then records the failure with the same run key.
   */
  private class BulkJobProgress extends Progress {
    private final DemoStepPublisher publisher;

    BulkJobProgress(DemoRunService.Request request) {
      publisher = new DemoStepPublisher(request, new DemoMetrics());
    }

    public override void start() {
      publisher.start();
    }

    public override void step(String label, Integer processed, Integer failed) {
      publisher.step(label, processed, failed);
    }

    public override void finish(Integer total, List<String> errors) {
      DemoResult result = new DemoResult(total, errors.size());
      result.message = errors.isEmpty()
        ? 'Activated ' + total + ' contracts'
        : String.join(errors, '\n');
      publisher.succeed(result);
    }
  }
}
