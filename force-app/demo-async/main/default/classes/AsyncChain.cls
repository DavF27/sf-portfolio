/**
 * Enqueues the next link of a queueable chain. Apex tests cannot run chained queueables: there, the
 * next link is kept in deferred and the test runs it itself.
 */
public with sharing class AsyncChain {
  @TestVisible
  private static List<Queueable> deferred = new List<Queueable>();

  public static Id enqueueNext(Queueable job) {
    if (Test.isRunningTest()) {
      deferred.add(job);
      return null;
    }
    return System.enqueueJob(job);
  }
}
