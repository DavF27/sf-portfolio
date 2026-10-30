/**
 * Panel strategy and monitor of the silent asynchronous chain demo, used for both modes.
 * BEFORE enqueues one LineActivationChainJob chain per bundle; AFTER one BundleActivationJob per
 * bundle. The jobs publish the outcome of the run; inspect() detects lines stuck by a broken chain.
 */
public with sharing class AsyncOrderStrategy implements DemoStrategy, DemoMonitor {
  private static final List<String> JOB_CLASSES = new List<String>{
    'LineActivationChainJob',
    'BundleActivationJob'
  };
  private static final List<String> ACTIVE_JOB_STATUSES = new List<String>{
    'Holding',
    'Queued',
    'Preparing',
    'Processing'
  };

  public DemoResult execute(DemoContext context) {
    // A new run resets the same lines: it must not run under the jobs of the previous one.
    Integer activeJobs = countActiveJobs();
    if (activeJobs > 0) {
      throw new DemoException(
        'The previous run still has ' +
          activeJobs +
          ' activation job(s) queued or running: wait for it to finish'
      );
    }
    AsyncOrderDemo.Prepared prepared = AsyncOrderDemo.prepare(
      context.volume,
      context.chaos,
      new SyntheticDataGenerator(DemoDataService.DEFAULT_SEED)
    );
    context.metrics.reset();

    prepared.order.Status__c = AsyncOrderDemo.STATUS_ACTIVATING;
    prepared.order.Processing_Mode__c = context.mode;
    prepared.order.Run_Key__c = context.runKey;
    Database.update(prepared.order, true, AccessLevel.USER_MODE);
    List<Order_Bundle_Demo__c> activating = new List<Order_Bundle_Demo__c>();
    for (Order_Bundle_Demo__c bundle : prepared.bundles) {
      activating.add(
        new Order_Bundle_Demo__c(
          Id = bundle.Id,
          Status__c = AsyncOrderDemo.STATUS_ACTIVATING
        )
      );
    }
    Database.update(activating, true, AccessLevel.USER_MODE);

    Id firstJobId;
    for (Order_Bundle_Demo__c bundle : prepared.bundles) {
      List<Id> lineIds = new List<Id>();
      List<Integer> rows = new List<Integer>();
      for (Order_Line_Demo__c line : prepared.linesByBundle.get(bundle.Id)) {
        lineIds.add(line.Id);
        rows.add(line.Row__c.intValue());
      }
      Queueable job = context.isBefore()
        ? (Queueable) new LineActivationChainJob(
            prepared.order.Id,
            bundle.Id,
            lineIds,
            rows,
            0,
            context.runKey,
            context.mode,
            context.volume
          )
        : new BundleActivationJob(
            prepared.order.Id,
            bundle,
            lineIds,
            rows,
            context.runKey,
            context.mode,
            context.volume
          );
      Id jobId = System.enqueueJob(job);
      firstJobId = firstJobId ?? jobId;
    }

    DemoResult result = new DemoResult(context.volume, 0);
    result.pending = true;
    result.asyncJobId = firstJobId;
    result.message = context.isBefore()
      ? prepared.bundles.size() +
        ' chains of up to ' +
        AsyncOrderDemo.BUNDLE_SIZE +
        ' jobs, one job per line (' +
        context.volume +
        ' jobs)'
      : prepared.bundles.size() +
        ' jobs, one per bundle, each with a Transaction Finalizer';
    return result;
  }

  /**
   * Still running while activation jobs are queued or processing. Afterwards, a line still Pending in a
   * bundle still Activating can only come from a chain that stopped without telling anyone.
   */
  public DemoResult inspect(DemoContext context) {
    List<Order_Demo__c> orders = [
      SELECT Id
      FROM Order_Demo__c
      WHERE Run_Key__c = :context.runKey
      WITH USER_MODE
      LIMIT 1
    ];
    if (orders.isEmpty()) {
      throw new DemoException('No order found for run ' + context.runKey);
    }
    DemoResult result = new DemoResult(context.volume, 0);
    Integer activeJobs = countActiveJobs();
    if (activeJobs > 0) {
      result.pending = true;
      result.message =
        activeJobs + ' activation job(s) still queued or running';
      return result;
    }

    for (Order_Line_Demo__c line : [
      SELECT Row__c
      FROM Order_Line_Demo__c
      WHERE
        Bundle__r.Order__c = :orders[0].Id
        AND Bundle__r.Status__c = :AsyncOrderDemo.STATUS_ACTIVATING
        AND Status__c = :AsyncOrderDemo.STATUS_PENDING
      WITH USER_MODE
      ORDER BY Row__c
    ]) {
      result.failedRows.add(line.Row__c.intValue());
    }
    result.recordsFailed = result.failedRows.size();
    Datetime runStart = runStartedAt(context.runKey);
    Integer failedJobs = [
      SELECT COUNT()
      FROM AsyncApexJob
      WHERE
        ApexClass.Name IN :JOB_CLASSES
        AND Status = 'Failed'
        AND CreatedDate >= :runStart
    ];
    result.message = result.hasFailures()
      ? result.recordsFailed +
        ' lines stuck in bundles still Activating; the application logged no error (' +
        failedJobs +
        ' failed job(s) visible only in Setup > Apex Jobs)'
      : 'No stuck line';
    return result;
  }

  private static Integer countActiveJobs() {
    return [
      SELECT COUNT()
      FROM AsyncApexJob
      WHERE ApexClass.Name IN :JOB_CLASSES AND Status IN :ACTIVE_JOB_STATUSES
    ];
  }

  /** Start of the run (Demo_Run__c), so that failed jobs of earlier runs are not counted. */
  private static Datetime runStartedAt(String runKey) {
    List<Demo_Run__c> runs = [
      SELECT Started_At__c
      FROM Demo_Run__c
      WHERE Run_Key__c = :runKey
      WITH USER_MODE
      LIMIT 1
    ];
    Datetime startedAt = runs.isEmpty() ? null : runs[0].Started_At__c;
    // Event timestamps have second precision: include jobs created in the same second.
    return (startedAt ?? Datetime.now().addHours(-1)).addSeconds(-1);
  }
}
