/**
 * Publishes Demo_Step__e events for one run. The event is configured with PublishImmediately,
 * so steps survive a transaction rolled back by an uncatchable LimitException (the BEFORE demos).
 */
public with sharing class DemoStepPublisher {
  public static final String PHASE_START = 'START';
  public static final String PHASE_STEP = 'STEP';
  public static final String PHASE_SUCCEEDED = 'SUCCEEDED';
  public static final String PHASE_FAILED = 'FAILED';

  /** Keeps well below the 150 publish-immediately calls per transaction. */
  @TestVisible
  private static final Integer MAX_PROGRESS_STEPS = 40;
  private static final Integer MAX_LABEL_LENGTH = 255;
  private static final Integer MAX_MESSAGE_LENGTH = 32768;

  @TestVisible
  private static List<Demo_Step__e> publishedEvents = new List<Demo_Step__e>();

  /**
   * One sequence per run for the whole transaction: triggers, flows (through DemoStepAction) and the
   * run service publish with their own publisher, and the panel timeline orders their steps by it.
   */
  private static Map<String, Integer> sequenceByRun = new Map<String, Integer>();

  private final DemoRunService.Request request;
  private final DemoMetrics metrics;
  private Boolean sequenced = true;
  private List<Integer> pendingRowsDone;
  private List<Integer> pendingRowsFailed;
  private Integer progressSteps = 0;

  public DemoStepPublisher(
    DemoRunService.Request request,
    DemoMetrics metrics
  ) {
    this.request = request;
    this.metrics = metrics;
  }

  public void start() {
    emit(PHASE_START, 'Started', null, null, null, null);
  }

  public void step(
    String label,
    Integer recordsProcessed,
    Integer recordsFailed
  ) {
    step(label, recordsProcessed, recordsFailed, null);
  }

  public void step(
    String label,
    Integer recordsProcessed,
    Integer recordsFailed,
    String message
  ) {
    step(label, recordsProcessed, recordsFailed, message, null, null);
  }

  /** Step that also tells the panel which rows (1-based) it completed or failed. */
  public void step(
    String label,
    Integer recordsProcessed,
    Integer recordsFailed,
    String message,
    List<Integer> rowsDone,
    List<Integer> rowsFailed
  ) {
    if (progressSteps >= MAX_PROGRESS_STEPS) {
      return;
    }
    progressSteps++;
    pendingRowsDone = rowsDone;
    pendingRowsFailed = rowsFailed;
    emit(PHASE_STEP, label, message, recordsProcessed, recordsFailed, null);
  }

  /**
   * Asynchronous jobs run in their own transactions, where a per-transaction sequence restarts at 1:
   * they publish without sequence and the panel keeps them in arrival order, after the synchronous steps.
   */
  public DemoStepPublisher withoutSequence() {
    sequenced = false;
    return this;
  }

  /** Synchronous part done, asynchronous work enqueued: the run stays open, its first job is recorded. */
  public void enqueued(DemoResult result) {
    emit(
      PHASE_STEP,
      'Asynchronous work enqueued',
      result?.message,
      result?.recordsProcessed,
      0,
      result?.asyncJobId
    );
  }

  public void succeed(DemoResult result) {
    emit(
      PHASE_SUCCEEDED,
      'Succeeded',
      result?.message,
      result?.recordsProcessed,
      result?.recordsFailed,
      result?.asyncJobId
    );
  }

  public void fail(String message, DemoResult partial) {
    pendingRowsFailed = partial?.failedRows;
    emit(
      PHASE_FAILED,
      'Failed',
      message,
      partial?.recordsProcessed,
      partial?.recordsFailed,
      null
    );
  }

  /**
   * Records a failure the server could not catch (e.g. System.LimitException) on behalf of the caller.
   * No metrics are attached: the last progress steps already carry them.
   */
  public static void publishUncaughtFailure(
    DemoRunService.Request request,
    String message
  ) {
    DemoStepPublisher publisher = new DemoStepPublisher(request, null);
    publisher.sequenced = false;
    publisher.emit(
      PHASE_FAILED,
      'Failed (uncaught)',
      message,
      null,
      null,
      null
    );
  }

  private static String joinRows(List<Integer> rows) {
    return rows == null || rows.isEmpty()
      ? null
      : String.join(rows, ',').abbreviate(MAX_LABEL_LENGTH);
  }

  private static Integer nextSequence(String runKey) {
    Integer next = (sequenceByRun.get(runKey) ?? 0) + 1;
    sequenceByRun.put(runKey, next);
    return next;
  }

  private void emit(
    String phase,
    String label,
    String message,
    Integer recordsProcessed,
    Integer recordsFailed,
    String asyncJobId
  ) {
    Demo_Step__e event = new Demo_Step__e(
      Run_Key__c = request.runKey,
      Demo__c = request.demoName,
      Mode__c = request.mode,
      Source__c = request.source,
      Volume__c = request.volume,
      Chaos__c = request.chaos == true,
      Phase__c = phase,
      Sequence__c = sequenced ? nextSequence(request.runKey) : null,
      Label__c = label?.abbreviate(MAX_LABEL_LENGTH),
      Message__c = message?.abbreviate(MAX_MESSAGE_LENGTH),
      Records_Processed__c = recordsProcessed,
      Records_Failed__c = recordsFailed,
      Async_Job_Id__c = asyncJobId,
      Rows_Done__c = joinRows(pendingRowsDone),
      Rows_Failed__c = joinRows(pendingRowsFailed)
    );
    pendingRowsDone = null;
    pendingRowsFailed = null;
    if (metrics != null) {
      DemoMetrics.Snapshot snapshot = metrics.snapshot();
      event.SOQL_Queries__c = snapshot.soqlQueries;
      event.DML_Statements__c = snapshot.dmlStatements;
      event.DML_Rows__c = snapshot.dmlRows;
      event.CPU_Time_Ms__c = snapshot.cpuTimeMs;
      event.Heap_Bytes__c = snapshot.heapBytes;
      event.Duration_Ms__c = snapshot.durationMs;
      event.SOQL_Limit__c = snapshot.soqlLimit;
      event.DML_Limit__c = snapshot.dmlStatementsLimit;
      metrics.beginOverhead();
    }
    Database.SaveResult result = EventBus.publish(event);
    metrics?.endOverhead();
    if (!result.isSuccess()) {
      throw new DemoException(
        'Demo_Step__e publish failed: ' + result.getErrors()[0].getMessage()
      );
    }
    if (Test.isRunningTest()) {
      publishedEvents.add(event);
    }
  }
}
