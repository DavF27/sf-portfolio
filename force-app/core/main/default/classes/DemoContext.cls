/**
 * Inputs and services available to a DemoStrategy during one run.
 */
public with sharing class DemoContext {
  public final String demoName;
  public final String mode;
  public final Integer volume;
  public final Boolean chaos;
  public final String runKey;
  public final DemoMetrics metrics;
  private final DemoStepPublisher publisher;

  public DemoContext(
    DemoRunService.Request request,
    DemoMetrics metrics,
    DemoStepPublisher publisher
  ) {
    this.demoName = request.demoName;
    this.mode = request.mode;
    this.volume = request.volume;
    this.chaos = request.chaos == true;
    this.runKey = request.runKey;
    this.metrics = metrics;
    this.publisher = publisher;
  }

  public Boolean isBefore() {
    return mode == DemoRunService.MODE_BEFORE;
  }

  /** Publishes a progress step carrying the current metrics. */
  public void step(String label) {
    step(label, null, null);
  }

  public void step(
    String label,
    Integer recordsProcessed,
    Integer recordsFailed
  ) {
    publisher.step(label, recordsProcessed, recordsFailed);
  }

  /** Throws when chaos is requested; strategies call it where the failure should be injected. */
  public void injectChaos(String location) {
    if (chaos) {
      throw new DemoException('Chaos injected at ' + location);
    }
  }
}
