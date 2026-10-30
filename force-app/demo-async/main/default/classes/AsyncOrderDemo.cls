/**
 * Synthetic data and run bookkeeping of the silent asynchronous chain demo.
 * One order, bundles of BUNDLE_SIZE lines (the maximum queueable chain depth in Developer Edition),
 * lines numbered 1..N across the run for the panel row grid.
 */
public with sharing class AsyncOrderDemo {
  public static final String DEMO_NAME = 'Async_Chain_Break';
  public static final Integer BUNDLE_SIZE = 5;
  public static final String ORDER_KEY = 'ORD-00001';
  public static final String STATUS_DRAFT = 'Draft';
  public static final String STATUS_PENDING = 'Pending';
  public static final String STATUS_ACTIVATING = 'Activating';
  public static final String STATUS_ACTIVE = 'Active';
  public static final String STATUS_FAILED = 'Failed';
  private static final Decimal MIN_PRICE = 10;
  private static final Decimal MAX_PRICE = 500;

  public static Integer bundleCount(Integer volume) {
    return (volume + BUNDLE_SIZE - 1) / BUNDLE_SIZE;
  }

  /** Row of the trapped line (no unit price): third line of the middle bundle. */
  public static Integer trapRow(Integer volume) {
    Integer middleBundle = Math.max(1, bundleCount(volume) / 2);
    return Math.min(volume, (middleBundle - 1) * BUNDLE_SIZE + 3);
  }

  public static String bundleKey(Integer position) {
    return ORDER_KEY + '-B' + String.valueOf(position).leftPad(2, '0');
  }

  public static String lineKey(Integer row) {
    return SyntheticDataGenerator.label(ORDER_KEY + '-L', row);
  }

  public class Prepared {
    public Order_Demo__c order;
    public List<Order_Bundle_Demo__c> bundles = new List<Order_Bundle_Demo__c>();
    public Map<Id, List<Order_Line_Demo__c>> linesByBundle = new Map<Id, List<Order_Line_Demo__c>>();
  }

  /**
   * Idempotent: upserts the order, ceil(N / 5) Pending bundles and N Pending lines, and deletes what a
   * previous, larger run left. With chaos, the line at trapRow() has no unit price.
   */
  public static Prepared prepare(
    Integer volume,
    Boolean chaos,
    SyntheticDataGenerator generator
  ) {
    Prepared prepared = new Prepared();
    prepared.order = new Order_Demo__c(
      Name = ORDER_KEY,
      External_Id__c = ORDER_KEY,
      Status__c = STATUS_DRAFT,
      Processing_Mode__c = null,
      Run_Key__c = null
    );
    Database.upsert(
      prepared.order,
      Order_Demo__c.External_Id__c,
      true,
      AccessLevel.USER_MODE
    );

    Integer bundles = bundleCount(volume);
    Set<String> existingBundles = existingKeys(
      [
        SELECT External_Id__c
        FROM Order_Bundle_Demo__c
        WHERE Order__c = :prepared.order.Id
        WITH USER_MODE
      ]
    );
    for (Integer position = 1; position <= bundles; position++) {
      String key = bundleKey(position);
      Order_Bundle_Demo__c bundle = new Order_Bundle_Demo__c(
        Name = key,
        External_Id__c = key,
        Position__c = position,
        Status__c = STATUS_PENDING,
        Failure__c = null
      );
      // Master-detail fields are not reparentable: only set them on new records.
      if (!existingBundles.contains(key)) {
        bundle.Order__c = prepared.order.Id;
      }
      prepared.bundles.add(bundle);
    }
    Database.upsert(
      prepared.bundles,
      Order_Bundle_Demo__c.External_Id__c,
      true,
      AccessLevel.USER_MODE
    );
    Database.delete(
      [
        SELECT Id
        FROM Order_Bundle_Demo__c
        WHERE Order__c = :prepared.order.Id AND Position__c > :bundles
        WITH USER_MODE
      ],
      true,
      AccessLevel.USER_MODE
    );

    Set<String> existingLines = existingKeys(
      [
        SELECT External_Id__c
        FROM Order_Line_Demo__c
        WHERE Bundle__r.Order__c = :prepared.order.Id
        WITH USER_MODE
      ]
    );
    Integer trapped = chaos == true ? trapRow(volume) : null;
    List<Order_Line_Demo__c> lines = new List<Order_Line_Demo__c>();
    for (Integer row = 1; row <= volume; row++) {
      String key = lineKey(row);
      Order_Bundle_Demo__c bundle = prepared.bundles[(row - 1) / BUNDLE_SIZE];
      Order_Line_Demo__c line = new Order_Line_Demo__c(
        Name = key,
        External_Id__c = key,
        Row__c = row,
        Status__c = STATUS_PENDING,
        Unit_Price__c = row == trapped
          ? null
          : generator.nextAmount(MIN_PRICE, MAX_PRICE),
        Activated_At__c = null
      );
      if (!existingLines.contains(key)) {
        line.Bundle__c = bundle.Id;
      }
      lines.add(line);
      if (!prepared.linesByBundle.containsKey(bundle.Id)) {
        prepared.linesByBundle.put(bundle.Id, new List<Order_Line_Demo__c>());
      }
      prepared.linesByBundle.get(bundle.Id).add(line);
    }
    Database.upsert(
      lines,
      Order_Line_Demo__c.External_Id__c,
      true,
      AccessLevel.USER_MODE
    );
    Database.delete(
      [
        SELECT Id
        FROM Order_Line_Demo__c
        WHERE Bundle__r.Order__c = :prepared.order.Id AND Row__c > :volume
        WITH USER_MODE
      ],
      true,
      AccessLevel.USER_MODE
    );
    return prepared;
  }

  /** Deletes every demo order; bundles and lines follow through master-detail. */
  public static Integer purge() {
    List<Order_Demo__c> orders = [SELECT Id FROM Order_Demo__c WITH USER_MODE];
    Database.delete(orders, true, AccessLevel.USER_MODE);
    return orders.size();
  }

  /**
   * Called when a bundle is done (last link of a chain, or finalizer). Publishes the outcome of the run
   * once no bundle is Pending or Activating any more. The order row is locked so that two bundles
   * finishing at the same time cannot both believe the other one is still running.
   */
  public static void closeRunIfDone(
    Id orderId,
    String runKey,
    String mode,
    Integer volume,
    Id asyncJobId
  ) {
    Order_Demo__c order = [
      SELECT Id
      FROM Order_Demo__c
      WHERE Id = :orderId
      WITH USER_MODE
      FOR UPDATE
    ];
    Integer unfinished = [
      SELECT COUNT()
      FROM Order_Bundle_Demo__c
      WHERE
        Order__c = :orderId
        AND Status__c IN (:STATUS_PENDING, :STATUS_ACTIVATING)
      WITH USER_MODE
    ];
    if (unfinished > 0) {
      return;
    }
    DemoResult result = new DemoResult(volume, 0);
    List<String> causes = new List<String>();
    for (Order_Bundle_Demo__c bundle : [
      SELECT Name, Failure__c, (SELECT Row__c FROM Lines__r ORDER BY Row__c)
      FROM Order_Bundle_Demo__c
      WHERE Order__c = :orderId AND Status__c = :STATUS_FAILED
      WITH USER_MODE
    ]) {
      causes.add(bundle.Name + ': ' + bundle.Failure__c);
      for (Order_Line_Demo__c line : bundle.Lines__r) {
        result.failedRows.add(line.Row__c.intValue());
      }
    }
    result.recordsFailed = result.failedRows.size();
    result.asyncJobId = asyncJobId;
    result.message = causes.isEmpty()
      ? 'All ' + volume + ' lines activated'
      : causes.size() +
        ' bundle(s) failed as a whole and were logged: ' +
        String.join(causes, '; ');
    order.Status__c = STATUS_ACTIVE;
    Database.update(order, true, AccessLevel.USER_MODE);
    publisher(runKey, mode, volume).succeed(result);
  }

  /** Publisher for asynchronous jobs: their steps have no sequence (see DemoStepPublisher). */
  public static DemoStepPublisher publisher(
    String runKey,
    String mode,
    Integer volume
  ) {
    DemoRunService.Request request = new DemoRunService.Request(
      DEMO_NAME,
      mode,
      volume
    );
    request.runKey = runKey;
    request.source = null;
    return new DemoStepPublisher(request, null).withoutSequence();
  }

  private static Set<String> existingKeys(List<SObject> records) {
    Set<String> keys = new Set<String>();
    for (SObject record : records) {
      keys.add((String) record.get('External_Id__c'));
    }
    return keys;
  }
}
