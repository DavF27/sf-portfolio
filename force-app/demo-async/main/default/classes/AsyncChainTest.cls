@IsTest
private class AsyncChainTest {
  private class NoopJob implements Queueable {
    public void execute(QueueableContext context) {
    }
  }

  @IsTest
  static void defersTheNextLinkInTests() {
    Test.startTest();
    Id jobId = AsyncChain.enqueueNext(new NoopJob());
    Test.stopTest();

    Assert.isNull(jobId);
    Assert.areEqual(1, AsyncChain.deferred.size());
    Assert.areEqual(0, [SELECT COUNT() FROM AsyncApexJob]);
  }
}
