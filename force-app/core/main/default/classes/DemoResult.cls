/**
 * Outcome reported by a DemoStrategy.
 */
public with sharing class DemoResult {
  @AuraEnabled
  public Integer recordsProcessed = 0;
  @AuraEnabled
  public Integer recordsFailed = 0;
  @AuraEnabled
  public String asyncJobId;
  @AuraEnabled
  public String message;
  /** 1-based positions of the rows that failed, for the panel row grid. */
  @AuraEnabled
  public List<Integer> failedRows = new List<Integer>();
  /** True when the strategy enqueued asynchronous work that will publish the outcome of the run itself. */
  @AuraEnabled
  public Boolean pending = false;

  public DemoResult() {
    this(0, 0);
  }

  public DemoResult(Integer recordsProcessed, Integer recordsFailed) {
    this.recordsProcessed = recordsProcessed;
    this.recordsFailed = recordsFailed;
  }

  public Boolean hasFailures() {
    return recordsFailed != null && recordsFailed > 0;
  }
}
