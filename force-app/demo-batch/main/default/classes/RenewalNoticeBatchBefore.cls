/**
 * BEFORE mode of the batch filter demo. Deliberately inefficient, never reuse: start() returns the whole
 * stock, the batch runs with a batch size of 1 and execute() filters in Apex. About 95% of the
 * executions do nothing but still cost a transaction each.
 */
public with sharing class RenewalNoticeBatchBefore implements Database.Batchable<SObject>, Database.Stateful {
  public static final Integer BATCH_SIZE = 1;
  /** Progress steps per run, kept low: Developer Edition delivers 10,000 events a day. */
  private static final Integer PROGRESS_STEPS = 20;

  private final String runKey;
  private final String mode;
  private final Integer volume;
  private final Integer progressEvery;
  private Integer scanned = 0;
  private Integer sent = 0;
  private Integer executions = 0;

  public RenewalNoticeBatchBefore(String runKey, String mode, Integer volume) {
    this.runKey = runKey;
    this.mode = mode;
    this.volume = volume;
    this.progressEvery = Math.max(1, volume / PROGRESS_STEPS);
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    // Intentional anti-pattern for the BEFORE demo: no filter, the whole stock goes through execute().
    return Database.getQueryLocatorWithBinds(
      'SELECT Id, Status__c, Notice_Sent__c, Notice_Deadline__c FROM Renewal_Demo__c WHERE Lane__c = :lane',
      new Map<String, Object>{ 'lane' => RenewalDemo.LANE_BEFORE },
      AccessLevel.USER_MODE
    );
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    executions++;
    Date today = Date.today();
    List<Renewal_Demo__c> due = new List<Renewal_Demo__c>();
    for (SObject record : scope) {
      scanned++;
      // Intentional anti-pattern for the BEFORE demo: the filter belongs in the query of start().
      if (RenewalDemo.isDue((Renewal_Demo__c) record, today)) {
        due.add(RenewalDemo.notified(record.Id, today));
      }
    }
    if (!due.isEmpty()) {
      Database.update(due, true, AccessLevel.USER_MODE);
      sent += due.size();
    }
    if (Math.mod(scanned, progressEvery) == 0) {
      RenewalDemo.publisher(runKey, mode, volume)
        .step('Scanned ' + scanned + ' of ' + volume, scanned, 0);
    }
  }

  public void finish(Database.BatchableContext context) {
    RenewalDemo.closeRun(
      context?.getJobId(),
      runKey,
      mode,
      volume,
      executions,
      sent,
      'Scanned ' + scanned + ' renewals, batch size ' + BATCH_SIZE
    );
  }
}
