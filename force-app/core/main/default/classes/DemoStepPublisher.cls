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

  private final DemoRunService.Request request;
  private final DemoMetrics metrics;
  private Integer sequence = 0;
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
    if (progressSteps >= MAX_PROGRESS_STEPS) {
      return;
    }
    progressSteps++;
    emit(PHASE_STEP, label, null, recordsProcessed, recordsFailed, null);
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
    publisher.sequence = null;
    publisher.emit(
      PHASE_FAILED,
      'Failed (uncaught)',
      message,
      null,
      null,
      null
    );
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
      Sequence__c = sequence == null ? null : ++sequence,
      Label__c = label?.abbreviate(MAX_LABEL_LENGTH),
      Message__c = message?.abbreviate(MAX_MESSAGE_LENGTH),
      Records_Processed__c = recordsProcessed,
      Records_Failed__c = recordsFailed,
      Async_Job_Id__c = asyncJobId
    );
    if (metrics != null) {
      DemoMetrics.Snapshot snapshot = metrics.snapshot();
      event.SOQL_Queries__c = snapshot.soqlQueries;
      event.DML_Statements__c = snapshot.dmlStatements;
      event.DML_Rows__c = snapshot.dmlRows;
      event.CPU_Time_Ms__c = snapshot.cpuTimeMs;
      event.Heap_Bytes__c = snapshot.heapBytes;
      event.Duration_Ms__c = snapshot.durationMs;
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
