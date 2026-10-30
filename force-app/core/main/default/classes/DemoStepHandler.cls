/**
 * Folds Demo_Step__e events into one Demo_Run__c per Run_Key__c.
 * Runs as the Automated Process user: queries and DML use system mode on purpose, because the
 * event payload was produced by DemoStepPublisher (trusted code) and Demo_Run__c is a
 * Public Read/Write instrumentation object.
 */
public with sharing class DemoStepHandler {
  public static final String STATUS_RUNNING = 'Running';
  public static final String STATUS_SUCCEEDED = 'Succeeded';
  public static final String STATUS_FAILED = 'Failed';

  @TestVisible
  private static final Integer MAX_RETRIES = 3;
  private static final Set<String> SOURCES = new Set<String>{
    'Panel',
    'Script',
    'Test'
  };
  private static final Pattern LIMIT_PATTERN = Pattern.compile(
    'Too many (SOQL queries|DML statements|DML rows): (\\d+)'
  );

  public static void handle(List<Demo_Step__e> events) {
    Map<String, List<Demo_Step__e>> eventsByKey = groupByRunKey(events);
    if (eventsByKey.isEmpty()) {
      return;
    }

    Map<String, Demo_Run__c> runsByKey = new Map<String, Demo_Run__c>();
    for (Demo_Run__c run : [
      SELECT
        Id,
        Run_Key__c,
        Demo__c,
        Mode__c,
        Status__c,
        Source__c,
        Volume__c,
        Chaos__c,
        SOQL_Queries__c,
        DML_Statements__c,
        DML_Rows__c,
        CPU_Time_Ms__c,
        Heap_Bytes__c,
        Duration_Ms__c,
        Records_Processed__c,
        Records_Failed__c,
        Step_Count__c,
        SOQL_Limit__c,
        DML_Limit__c,
        Error_Message__c,
        Async_Job_Id__c,
        Started_At__c,
        Finished_At__c
      FROM Demo_Run__c
      WHERE Run_Key__c IN :eventsByKey.keySet()
      WITH SYSTEM_MODE
    ]) {
      runsByKey.put(run.Run_Key__c, run);
    }

    List<Demo_Run__c> toUpsert = new List<Demo_Run__c>();
    for (String runKey : eventsByKey.keySet()) {
      Demo_Run__c run = runsByKey.containsKey(runKey)
        ? runsByKey.get(runKey)
        : new Demo_Run__c(Run_Key__c = runKey);
      for (Demo_Step__e event : eventsByKey.get(runKey)) {
        apply(run, event);
      }
      toUpsert.add(run);
    }

    List<Database.UpsertResult> results = Database.upsert(
      toUpsert,
      Demo_Run__c.Run_Key__c,
      false,
      AccessLevel.SYSTEM_MODE
    );
    List<String> errors = new List<String>();
    for (Integer i = 0; i < results.size(); i++) {
      if (!results[i].isSuccess()) {
        errors.add(
          toUpsert[i].Run_Key__c + ': ' + results[i].getErrors()[0].getMessage()
        );
      }
    }
    if (!errors.isEmpty()) {
      if (EventBus.TriggerContext.currentContext().retries < MAX_RETRIES) {
        throw new EventBus.RetryableException(String.join(errors, '; '));
      }
      System.debug(
        LoggingLevel.ERROR,
        'Demo_Run__c upsert failed after retries: ' + String.join(errors, '; ')
      );
    }
  }

  private static Map<String, List<Demo_Step__e>> groupByRunKey(
    List<Demo_Step__e> events
  ) {
    Map<String, List<Demo_Step__e>> eventsByKey = new Map<String, List<Demo_Step__e>>();
    for (Demo_Step__e event : events) {
      if (String.isBlank(event.Run_Key__c)) {
        continue;
      }
      if (!eventsByKey.containsKey(event.Run_Key__c)) {
        eventsByKey.put(event.Run_Key__c, new List<Demo_Step__e>());
      }
      eventsByKey.get(event.Run_Key__c).add(event);
    }
    return eventsByKey;
  }

  @TestVisible
  private static void apply(Demo_Run__c run, Demo_Step__e event) {
    run.Demo__c = run.Demo__c ?? event.Demo__c;
    run.Mode__c = run.Mode__c ?? event.Mode__c;
    if (run.Source__c == null && SOURCES.contains(event.Source__c)) {
      run.Source__c = event.Source__c;
    }
    run.Volume__c = run.Volume__c ?? event.Volume__c;
    run.Chaos__c = run.Chaos__c == true || event.Chaos__c == true;

    Datetime occurredAt = event.CreatedDate ?? Datetime.now();
    run.Started_At__c = run.Started_At__c ?? occurredAt;
    if (run.Status__c == null) {
      run.Status__c = STATUS_RUNNING;
    }

    run.SOQL_Queries__c = maxOf(run.SOQL_Queries__c, event.SOQL_Queries__c);
    run.DML_Statements__c = maxOf(
      run.DML_Statements__c,
      event.DML_Statements__c
    );
    run.DML_Rows__c = maxOf(run.DML_Rows__c, event.DML_Rows__c);
    run.CPU_Time_Ms__c = maxOf(run.CPU_Time_Ms__c, event.CPU_Time_Ms__c);
    run.Heap_Bytes__c = maxOf(run.Heap_Bytes__c, event.Heap_Bytes__c);
    run.Duration_Ms__c = maxOf(run.Duration_Ms__c, event.Duration_Ms__c);
    run.Records_Processed__c = maxOf(
      run.Records_Processed__c,
      event.Records_Processed__c
    );
    run.Records_Failed__c = maxOf(
      run.Records_Failed__c,
      event.Records_Failed__c
    );
    run.Step_Count__c = maxOf(run.Step_Count__c, event.Sequence__c);
    run.SOQL_Limit__c = maxOf(run.SOQL_Limit__c, event.SOQL_Limit__c);
    run.DML_Limit__c = maxOf(run.DML_Limit__c, event.DML_Limit__c);
    run.Async_Job_Id__c = run.Async_Job_Id__c ?? event.Async_Job_Id__c;

    Boolean terminal =
      event.Phase__c == DemoStepPublisher.PHASE_SUCCEEDED ||
      event.Phase__c == DemoStepPublisher.PHASE_FAILED;
    Boolean alreadyFinished =
      run.Status__c == STATUS_SUCCEEDED ||
      run.Status__c == STATUS_FAILED;
    if (!terminal || alreadyFinished) {
      return;
    }
    run.Status__c = event.Phase__c == DemoStepPublisher.PHASE_SUCCEEDED
      ? STATUS_SUCCEEDED
      : STATUS_FAILED;
    run.Finished_At__c = occurredAt;
    if (run.Status__c == STATUS_FAILED) {
      run.Error_Message__c = event.Message__c;
      applyLimitFromMessage(run, event.Message__c);
    }
    // Event timestamps only have second precision: fall back on them only when no step measured the
    // duration, or when an asynchronous job closes the run (the synchronous part only measured itself).
    Boolean closedByAsyncJob =
      String.isNotBlank(event.Async_Job_Id__c) ||
      String.isNotBlank(run.Async_Job_Id__c);
    if (
      run.Started_At__c != null &&
      (run.Duration_Ms__c == null || closedByAsyncJob)
    ) {
      run.Duration_Ms__c = maxOf(
        run.Duration_Ms__c,
        occurredAt.getTime() - run.Started_At__c.getTime()
      );
    }
  }

  /** The platform reports the value that broke the limit (e.g. "Too many SOQL queries: 101"). */
  private static void applyLimitFromMessage(Demo_Run__c run, String message) {
    if (String.isBlank(message)) {
      return;
    }
    Matcher matcher = LIMIT_PATTERN.matcher(message);
    if (!matcher.find()) {
      return;
    }
    Decimal value = Decimal.valueOf(matcher.group(2));
    switch on matcher.group(1) {
      when 'SOQL queries' {
        run.SOQL_Queries__c = maxOf(run.SOQL_Queries__c, value);
      }
      when 'DML statements' {
        run.DML_Statements__c = maxOf(run.DML_Statements__c, value);
      }
      when else {
        run.DML_Rows__c = maxOf(run.DML_Rows__c, value);
      }
    }
  }

  private static Decimal maxOf(Decimal current, Decimal candidate) {
    if (candidate == null) {
      return current;
    }
    return current == null ? candidate : Math.max(current, candidate);
  }
}
