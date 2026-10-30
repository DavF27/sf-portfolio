/**
 * AFTER mode of the silent asynchronous chain demo: one job per bundle activates all its lines with
 * one all-or-nothing update, so a bundle is never half active. BundleActivationFinalizer runs whatever
 * happens and logs a failure explicitly.
 */
public with sharing class BundleActivationJob implements Queueable {
  private final Id orderId;
  private final Order_Bundle_Demo__c bundle;
  private final List<Id> lineIds;
  private final List<Integer> rows;
  private final String runKey;
  private final String mode;
  private final Integer volume;

  public BundleActivationJob(
    Id orderId,
    Order_Bundle_Demo__c bundle,
    List<Id> lineIds,
    List<Integer> rows,
    String runKey,
    String mode,
    Integer volume
  ) {
    this.orderId = orderId;
    this.bundle = bundle;
    this.lineIds = lineIds;
    this.rows = rows;
    this.runKey = runKey;
    this.mode = mode;
    this.volume = volume;
  }

  public void execute(QueueableContext context) {
    System.attachFinalizer(
      new BundleActivationFinalizer(orderId, bundle, rows, runKey, mode, volume)
    );
    Datetime activatedAt = Datetime.now();
    List<Order_Line_Demo__c> lines = new List<Order_Line_Demo__c>();
    for (Id lineId : lineIds) {
      lines.add(
        new Order_Line_Demo__c(
          Id = lineId,
          Status__c = AsyncOrderDemo.STATUS_ACTIVE,
          Activated_At__c = activatedAt
        )
      );
    }
    Database.update(lines, true, AccessLevel.USER_MODE);
    Database.update(
      new Order_Bundle_Demo__c(
        Id = bundle.Id,
        Status__c = AsyncOrderDemo.STATUS_ACTIVE
      ),
      true,
      AccessLevel.USER_MODE
    );
    AsyncOrderDemo.publisher(runKey, mode, volume)
      .step(
        bundle.Name + ' activated: ' + lines.size() + ' lines in one update',
        lines.size(),
        0,
        null,
        rows,
        null
      );
  }
}
