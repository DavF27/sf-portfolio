/**
 * Transaction Finalizer of BundleActivationJob (AFTER mode). Runs after the job whether it succeeded
 * or not: a failure is logged on the bundle (Failed + cause) and on the demo timeline, then the run
 * is closed when it was the last bundle.
 */
public with sharing class BundleActivationFinalizer implements Finalizer {
  private final Id orderId;
  private final Order_Bundle_Demo__c bundle;
  private final List<Integer> rows;
  private final String runKey;
  private final String mode;
  private final Integer volume;

  public BundleActivationFinalizer(
    Id orderId,
    Order_Bundle_Demo__c bundle,
    List<Integer> rows,
    String runKey,
    String mode,
    Integer volume
  ) {
    this.orderId = orderId;
    this.bundle = bundle;
    this.rows = rows;
    this.runKey = runKey;
    this.mode = mode;
    this.volume = volume;
  }

  public void execute(FinalizerContext context) {
    if (context.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
      String cause = context.getException()?.getMessage() ?? 'Unknown error';
      Database.update(
        new Order_Bundle_Demo__c(
          Id = bundle.Id,
          Status__c = AsyncOrderDemo.STATUS_FAILED,
          Failure__c = cause.abbreviate(255)
        ),
        true,
        AccessLevel.USER_MODE
      );
      AsyncOrderDemo.publisher(runKey, mode, volume)
        .step(
          bundle.Name + ' failed and was rolled back as a whole',
          0,
          rows.size(),
          cause,
          null,
          rows
        );
    }
    AsyncOrderDemo.closeRunIfDone(
      orderId,
      runKey,
      mode,
      volume,
      context.getAsyncApexJobId()
    );
  }
}
