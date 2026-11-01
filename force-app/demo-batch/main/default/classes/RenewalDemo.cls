/**
 * Synthetic data and shared rules of the batch filter demo. Each mode has its own lane of renewals so
 * that both batches can race at the same time. One renewal in ELIGIBLE_EVERY is due for a notice.
 */
public with sharing class RenewalDemo {
  public static final String DEMO_NAME = 'Batch_Filter';
  public static final String LANE_BEFORE = 'BEFORE';
  public static final String LANE_AFTER = 'AFTER';
  public static final String STATUS_ACTIVE = 'Active';
  public static final Integer ELIGIBLE_EVERY = 20;
  public static final Integer HORIZON_DAYS = 30;
  private static final List<Integer> TERMS = new List<Integer>{ 12, 24, 36 };
  private static final List<Integer> NOTICES = new List<Integer>{ 30, 60, 90 };

  public static String renewalKey(String lane, Integer row) {
    return SyntheticDataGenerator.label('RNW-' + lane.left(1), row);
  }

  public static Boolean isEligibleRow(Integer row) {
    return Math.mod(row, ELIGIBLE_EVERY) == 0;
  }

  public static Integer eligibleCount(Integer volume) {
    return volume / ELIGIBLE_EVERY;
  }

  /** Due for a notice: active, not notified yet, notice deadline within the next HORIZON_DAYS days. */
  public static Boolean isDue(Renewal_Demo__c renewal, Date today) {
    return renewal.Status__c == STATUS_ACTIVE &&
      renewal.Notice_Sent__c != true &&
      renewal.Notice_Deadline__c != null &&
      renewal.Notice_Deadline__c >= today &&
      renewal.Notice_Deadline__c <= today.addDays(HORIZON_DAYS);
  }

  /**
   * Idempotent: upserts N active, not notified renewals of the lane and deletes the lane's extra rows.
   * Start dates are derived from a target notice deadline: inside the horizon for eligible rows,
   * far in the future or in the past for the others.
   */
  public static Integer prepare(
    String lane,
    Integer volume,
    SyntheticDataGenerator generator
  ) {
    Date today = Date.today();
    List<Renewal_Demo__c> renewals = new List<Renewal_Demo__c>();
    Set<String> keys = new Set<String>();
    for (Integer row = 1; row <= volume; row++) {
      Integer term = TERMS[generator.nextInt(TERMS.size())];
      Integer notice = NOTICES[generator.nextInt(NOTICES.size())];
      Date deadline;
      if (isEligibleRow(row)) {
        deadline = today.addDays(5 + generator.nextInt(20));
      } else if (generator.chance(50)) {
        deadline = today.addDays(60 + generator.nextInt(600));
      } else {
        deadline = today.addDays(-30 - generator.nextInt(400));
      }
      Date startDate = deadline.addDays(notice).addMonths(-term);
      // Keep start dates off month ends: ADDMONTHS maps a last day of month to the last day of the target month,
      // Date.addMonths does not (e.g. 28 Feb 2025 + 36 months: 29 Feb 2028 vs 28 Feb 2028).
      Integer lastSafeDay = Math.min(
        28,
        Date.daysInMonth(startDate.year(), startDate.month()) - 1
      );
      if (startDate.day() > lastSafeDay) {
        startDate = startDate.addDays(lastSafeDay - startDate.day());
      }
      String key = renewalKey(lane, row);
      keys.add(key);
      renewals.add(
        new Renewal_Demo__c(
          Name = key,
          External_Id__c = key,
          Lane__c = lane,
          Status__c = STATUS_ACTIVE,
          Start_Date__c = startDate,
          Term_Months__c = term,
          Notice_Days__c = notice,
          Notice_Sent__c = false,
          Notice_Sent_On__c = null
        )
      );
    }
    Database.upsert(
      renewals,
      Renewal_Demo__c.External_Id__c,
      true,
      AccessLevel.USER_MODE
    );
    Database.delete(
      [
        SELECT Id
        FROM Renewal_Demo__c
        WHERE Lane__c = :lane AND External_Id__c NOT IN :keys
        WITH USER_MODE
      ],
      true,
      AccessLevel.USER_MODE
    );
    return renewals.size();
  }

  public static Integer purge() {
    List<Renewal_Demo__c> renewals = [
      SELECT Id
      FROM Renewal_Demo__c
      WITH USER_MODE
    ];
    Database.delete(renewals, true, AccessLevel.USER_MODE);
    return renewals.size();
  }

  public static Renewal_Demo__c notified(Id renewalId, Date today) {
    return new Renewal_Demo__c(
      Id = renewalId,
      Notice_Sent__c = true,
      Notice_Sent_On__c = today
    );
  }

  /** Publisher for batch transactions: their steps have no sequence (see DemoStepPublisher). */
  public static DemoStepPublisher publisher(
    String runKey,
    String mode,
    Integer volume
  ) {
    DemoRunService.Request request = new DemoRunService.Request(
      DEMO_NAME,
      mode,
      volume
    );
    request.runKey = runKey;
    request.source = null;
    return new DemoStepPublisher(request, null).withoutSequence();
  }

  /** Closes the run from finish(): executions, notices sent and failed chunks measured by the job. */
  public static void closeRun(
    Id jobId,
    String runKey,
    String mode,
    Integer volume,
    Integer executions,
    Integer sent,
    String summary
  ) {
    DemoResult result = new DemoResult(volume, 0);
    result.asyncJobId = jobId;
    result.asyncExecutions = executions;
    if (jobId != null) {
      AsyncApexJob job = [
        SELECT JobItemsProcessed, NumberOfErrors
        FROM AsyncApexJob
        WHERE Id = :jobId
      ];
      result.asyncExecutions = Math.max(executions, job.JobItemsProcessed);
      result.recordsFailed = job.NumberOfErrors;
    }
    result.message =
      summary +
      ': ' +
      result.asyncExecutions +
      ' execution(s), ' +
      sent +
      ' notice(s) sent';
    publisher(runKey, mode, volume).succeed(result);
  }
}
