/**
 * AFTER mode of the batch filter demo: the query of start() only returns the renewals due for a notice
 * (filter on the Notice_Deadline__c formula), processed 200 at a time.
 */
public with sharing class RenewalNoticeBatchAfter implements Database.Batchable<SObject>, Database.Stateful {
  public static final Integer BATCH_SIZE = 200;

  private final String runKey;
  private final String mode;
  private final Integer volume;
  private Integer sent = 0;
  private Integer executions = 0;

  public RenewalNoticeBatchAfter(String runKey, String mode, Integer volume) {
    this.runKey = runKey;
    this.mode = mode;
    this.volume = volume;
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    Date today = Date.today();
    return Database.getQueryLocatorWithBinds(
      'SELECT Id FROM Renewal_Demo__c WHERE Lane__c = :lane AND Status__c = :status' +
      ' AND Notice_Sent__c = false AND Notice_Deadline__c >= :today AND Notice_Deadline__c <= :horizon',
      new Map<String, Object>{
        'lane' => RenewalDemo.LANE_AFTER,
        'status' => RenewalDemo.STATUS_ACTIVE,
        'today' => today,
        'horizon' => today.addDays(RenewalDemo.HORIZON_DAYS)
      },
      AccessLevel.USER_MODE
    );
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    executions++;
    Date today = Date.today();
    List<Renewal_Demo__c> due = new List<Renewal_Demo__c>();
    for (SObject record : scope) {
      due.add(RenewalDemo.notified(record.Id, today));
    }
    Database.update(due, true, AccessLevel.USER_MODE);
    sent += due.size();
    RenewalDemo.publisher(runKey, mode, volume)
      .step('Sent ' + sent + ' notices', sent, 0);
  }

  public void finish(Database.BatchableContext context) {
    RenewalDemo.closeRun(
      context?.getJobId(),
      runKey,
      mode,
      volume,
      executions,
      sent,
      'Queried only the due renewals, batch size ' + BATCH_SIZE
    );
  }
}
