/**
 * Runs one demo in a given mode, measures it and publishes its progress.
 * Catchable failures are rolled back and recorded as FAILED. Uncatchable ones
 * (System.LimitException) abort the transaction: the caller then reports them via
 * DemoStepPublisher.publishUncaughtFailure using the same run key.
 */
public with sharing class DemoRunService {
  public static final String MODE_BEFORE = 'BEFORE';
  public static final String MODE_AFTER = 'AFTER';
  public static final String SOURCE_PANEL = 'Panel';
  public static final String SOURCE_SCRIPT = 'Script';
  public static final String SOURCE_TEST = 'Test';

  private static final Pattern RUN_KEY_PATTERN = Pattern.compile(
    '^[A-Za-z0-9-]{8,36}$'
  );

  public static Response run(Request request) {
    Demo_Setting__mdt setting = validate(request);
    DemoStrategy strategy = DemoStrategyFactory.create(setting, request.mode);

    Savepoint savepoint = Database.setSavepoint();
    DemoMetrics metrics = new DemoMetrics();
    DemoStepPublisher publisher = new DemoStepPublisher(request, metrics);
    publisher.start();

    Response response = new Response(request.runKey);
    try {
      DemoResult result = strategy.execute(
        new DemoContext(request, metrics, publisher)
      ) ?? new DemoResult();
      response.result = result;
      response.metrics = metrics.snapshot();
      if (result.pending == true) {
        // The asynchronous work publishes the outcome; the run stays Running until then.
        response.status = DemoStepHandler.STATUS_RUNNING;
        publisher.enqueued(result);
      } else {
        response.status = DemoStepHandler.STATUS_SUCCEEDED;
        publisher.succeed(result);
      }
    } catch (Exception e) {
      response.metrics = metrics.snapshot();
      Database.rollback(savepoint);
      response.status = DemoStepHandler.STATUS_FAILED;
      response.errorMessage = e.getTypeName() + ': ' + e.getMessage();
      publisher.fail(response.errorMessage, null);
    }
    return response;
  }

  /**
   * Asks the demo whether its asynchronous work is stuck. A stuck run is closed as FAILED with the
   * stuck rows: in the BEFORE mode of an asynchronous demo, nobody else would ever close it.
   */
  public static Response monitor(Request request) {
    Demo_Setting__mdt setting = validate(request);
    DemoStrategy strategy = DemoStrategyFactory.create(setting, request.mode);
    if (!(strategy instanceof DemoMonitor)) {
      throw new DemoException(setting.DeveloperName + ' has no monitor');
    }
    DemoMetrics metrics = new DemoMetrics();
    DemoStepPublisher publisher = new DemoStepPublisher(request, metrics)
      .withoutSequence();
    DemoResult result = ((DemoMonitor) strategy)
      .inspect(new DemoContext(request, metrics, publisher));

    Response response = new Response(request.runKey);
    response.result = result;
    response.metrics = metrics.snapshot();
    if (result.pending == true) {
      response.status = DemoStepHandler.STATUS_RUNNING;
    } else if (result.hasFailures()) {
      response.status = DemoStepHandler.STATUS_FAILED;
      response.errorMessage = 'Detected by monitoring: ' + result.message;
      publisher.fail(response.errorMessage, result);
    } else {
      // Finished: close the run in case no job could (first terminal event wins).
      response.status = DemoStepHandler.STATUS_SUCCEEDED;
      publisher.succeed(result);
    }
    return response;
  }

  public static void recordUncaughtFailure(Request request, String message) {
    validate(request);
    DemoStepPublisher.publishUncaughtFailure(
      request,
      String.isBlank(message) ? 'Unknown error' : message
    );
  }

  /** Normalises the request in place and returns the matching setting. */
  @TestVisible
  private static Demo_Setting__mdt validate(Request request) {
    if (request == null) {
      throw new DemoException('Request is required');
    }
    Demo_Setting__mdt setting = DemoCatalog.get(request.demoName);
    request.demoName = setting.DeveloperName;
    request.mode = String.isBlank(request.mode)
      ? setting.Mode__c
      : request.mode.toUpperCase();
    if (request.mode != MODE_BEFORE && request.mode != MODE_AFTER) {
      throw new DemoException(
        'Mode must be BEFORE or AFTER, got ' + request.mode
      );
    }
    Integer maxVolume = setting.Max_Volume__c == null
      ? 1
      : setting.Max_Volume__c.intValue();
    request.volume = request.volume ??
      (setting.Default_Volume__c == null
        ? 1
        : setting.Default_Volume__c.intValue());
    if (request.volume < 1 || request.volume > maxVolume) {
      throw new DemoException('Volume must be between 1 and ' + maxVolume);
    }
    if (
      request.runKey == null ||
      !RUN_KEY_PATTERN.matcher(request.runKey).matches()
    ) {
      throw new DemoException(
        'Run key must match ' + RUN_KEY_PATTERN.pattern()
      );
    }
    request.source = request.source ?? SOURCE_PANEL;
    request.chaos = request.chaos == true;
    return setting;
  }

  public class Request {
    public String demoName;
    public String mode;
    public Integer volume;
    public Boolean chaos = false;
    public String runKey;
    public String source;

    public Request(String demoName, String mode, Integer volume) {
      this.demoName = demoName;
      this.mode = mode;
      this.volume = volume;
      this.runKey = UUID.randomUUID().toString();
    }
  }

  public class Response {
    @AuraEnabled
    public String runKey;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String errorMessage;
    @AuraEnabled
    public DemoResult result;
    @AuraEnabled
    public DemoMetrics.Snapshot metrics;

    public Response(String runKey) {
      this.runKey = runKey;
    }

    public Boolean isSuccess() {
      return status == DemoStepHandler.STATUS_SUCCEEDED;
    }
  }
}
