/**
 * BEFORE mode of the silent asynchronous chain demo. Deliberately broken, never reuse: one job per
 * line, each job enqueues the next one after its own update, with no finalizer and no error handling.
 * When a line cannot be activated, the job fails, the next link is never enqueued and the bundle
 * stays Activating forever. The only trace is a failed job in Setup > Apex Jobs.
 */
public with sharing class LineActivationChainJob implements Queueable {
  @TestVisible
  private static Integer executions = 0;

  private final Id orderId;
  private final Id bundleId;
  private final List<Id> lineIds;
  private final List<Integer> rows;
  private final Integer index;
  private final String runKey;
  private final String mode;
  private final Integer volume;

  public LineActivationChainJob(
    Id orderId,
    Id bundleId,
    List<Id> lineIds,
    List<Integer> rows,
    Integer index,
    String runKey,
    String mode,
    Integer volume
  ) {
    this.orderId = orderId;
    this.bundleId = bundleId;
    this.lineIds = lineIds;
    this.rows = rows;
    this.index = index;
    this.runKey = runKey;
    this.mode = mode;
    this.volume = volume;
  }

  public void execute(QueueableContext context) {
    executions++;
    // Intentional anti-pattern for the BEFORE demo: an unhandled failure here silently ends the chain.
    Database.update(
      new Order_Line_Demo__c(
        Id = lineIds[index],
        Status__c = AsyncOrderDemo.STATUS_ACTIVE,
        Activated_At__c = Datetime.now()
      ),
      true,
      AccessLevel.USER_MODE
    );
    AsyncOrderDemo.publisher(runKey, mode, volume)
      .step(
        'Line ' + rows[index] + ' activated',
        1,
        0,
        null,
        new List<Integer>{ rows[index] },
        null
      );

    if (index + 1 < lineIds.size()) {
      AsyncChain.enqueueNext(
        new LineActivationChainJob(
          orderId,
          bundleId,
          lineIds,
          rows,
          index + 1,
          runKey,
          mode,
          volume
        )
      );
      return;
    }
    Database.update(
      new Order_Bundle_Demo__c(
        Id = bundleId,
        Status__c = AsyncOrderDemo.STATUS_ACTIVE
      ),
      true,
      AccessLevel.USER_MODE
    );
    AsyncOrderDemo.closeRunIfDone(
      orderId,
      runKey,
      mode,
      volume,
      context?.getJobId()
    );
  }
}
