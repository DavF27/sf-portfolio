/**
 * Limits Probe, AFTER mode: a single aggregate query, whatever the volume.
 */
public with sharing class LimitsProbeAfterStrategy implements DemoStrategy {
  private static final Integer STEP_EVERY = 10;

  public DemoResult execute(DemoContext context) {
    Integer runCount = [
      SELECT COUNT()
      FROM Demo_Run__c
      WHERE Demo__c = :context.demoName
      WITH USER_MODE
    ];
    Integer matches = 0;
    for (Integer i = 1; i <= context.volume; i++) {
      matches += runCount;
      if (i == Math.max(1, context.volume / 2)) {
        context.injectChaos('iteration ' + i);
      }
      if (Math.mod(i, STEP_EVERY) == 0) {
        context.step('Iteration ' + i, i, 0);
      }
    }
    DemoResult result = new DemoResult(context.volume, 0);
    result.message = 'Counted ' + matches + ' runs with 1 query';
    return result;
  }
}
