/**
 * Panel strategy of the batch filter demo, used for both modes: each mode prepares its own lane and
 * starts its batch, so the panel can race BEFORE and AFTER side by side. The batch closes the run.
 */
public with sharing class RenewalNoticeStrategy implements DemoStrategy, DemoRaceable {
  private static final List<String> ACTIVE_JOB_STATUSES = new List<String>{
    'Holding',
    'Queued',
    'Preparing',
    'Processing'
  };

  public DemoResult execute(DemoContext context) {
    String batchClass = context.isBefore()
      ? 'RenewalNoticeBatchBefore'
      : 'RenewalNoticeBatchAfter';
    // A new run resets the lane: it must not run under the previous batch of the same lane.
    Integer running = [
      SELECT COUNT()
      FROM AsyncApexJob
      WHERE ApexClass.Name = :batchClass AND Status IN :ACTIVE_JOB_STATUSES
    ];
    if (running > 0) {
      throw new DemoException(
        'The previous ' +
          context.mode +
          ' batch is still running: wait for it to finish'
      );
    }
    Integer prepared = RenewalDemo.prepare(
      context.mode,
      context.volume,
      new SyntheticDataGenerator(DemoDataService.DEFAULT_SEED)
    );
    context.injectChaos('before starting the batch');
    context.metrics.reset();

    Id jobId = context.isBefore()
      ? Database.executeBatch(
          new RenewalNoticeBatchBefore(
            context.runKey,
            context.mode,
            context.volume
          ),
          RenewalNoticeBatchBefore.BATCH_SIZE
        )
      : Database.executeBatch(
          new RenewalNoticeBatchAfter(
            context.runKey,
            context.mode,
            context.volume
          ),
          RenewalNoticeBatchAfter.BATCH_SIZE
        );

    // Nothing is covered yet: the batch publishes its own progress.
    DemoResult result = new DemoResult(0, 0);
    result.pending = true;
    result.asyncJobId = jobId;
    result.message = context.isBefore()
      ? 'Batch size 1 over the whole stock of ' + prepared + ' renewals'
      : 'Batch size 200 over the ' +
        RenewalDemo.eligibleCount(prepared) +
        ' renewals selected by the query';
    return result;
  }
}
