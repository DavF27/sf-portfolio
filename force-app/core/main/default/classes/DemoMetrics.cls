/**
 * Measures governor limit consumption of a demo run from a baseline.
 * Work done by the instrumentation itself (event publishing) is excluded through
 * beginOverhead()/endOverhead() so the figures reflect the demo code only.
 */
public with sharing class DemoMetrics {
  private Integer baseQueries;
  private Integer baseDmlStatements;
  private Integer baseDmlRows;
  private Integer baseCpuTime;
  private Long startedAtMs;

  private Integer overheadQueries = 0;
  private Integer overheadDmlStatements = 0;
  private Integer overheadDmlRows = 0;
  private Integer overheadCpuTime = 0;

  private Integer pauseQueries;
  private Integer pauseDmlStatements;
  private Integer pauseDmlRows;
  private Integer pauseCpuTime;

  public DemoMetrics() {
    reset();
  }

  public void reset() {
    baseQueries = Limits.getQueries();
    baseDmlStatements = Limits.getDmlStatements();
    baseDmlRows = Limits.getDmlRows();
    baseCpuTime = Limits.getCpuTime();
    startedAtMs = System.currentTimeMillis();
    overheadQueries = 0;
    overheadDmlStatements = 0;
    overheadDmlRows = 0;
    overheadCpuTime = 0;
    pauseQueries = null;
  }

  public void beginOverhead() {
    pauseQueries = Limits.getQueries();
    pauseDmlStatements = Limits.getDmlStatements();
    pauseDmlRows = Limits.getDmlRows();
    pauseCpuTime = Limits.getCpuTime();
  }

  public void endOverhead() {
    if (pauseQueries == null) {
      return;
    }
    overheadQueries += Limits.getQueries() - pauseQueries;
    overheadDmlStatements += Limits.getDmlStatements() - pauseDmlStatements;
    overheadDmlRows += Limits.getDmlRows() - pauseDmlRows;
    overheadCpuTime += Limits.getCpuTime() - pauseCpuTime;
    pauseQueries = null;
  }

  public Snapshot snapshot() {
    Snapshot result = new Snapshot();
    result.soqlQueries = Limits.getQueries() - baseQueries - overheadQueries;
    result.dmlStatements =
      Limits.getDmlStatements() -
      baseDmlStatements -
      overheadDmlStatements;
    result.dmlRows = Limits.getDmlRows() - baseDmlRows - overheadDmlRows;
    result.cpuTimeMs = Math.max(
      0,
      Limits.getCpuTime() - baseCpuTime - overheadCpuTime
    );
    result.heapBytes = Limits.getHeapSize();
    result.durationMs = System.currentTimeMillis() - startedAtMs;
    result.soqlLimit = Limits.getLimitQueries();
    result.dmlStatementsLimit = Limits.getLimitDmlStatements();
    result.dmlRowsLimit = Limits.getLimitDmlRows();
    result.cpuTimeLimit = Limits.getLimitCpuTime();
    result.heapLimit = Limits.getLimitHeapSize();
    return result;
  }

  /**
   * Consumption since the baseline, with the limits of the current context (sync or async).
   */
  public class Snapshot {
    @AuraEnabled
    public Integer soqlQueries;
    @AuraEnabled
    public Integer dmlStatements;
    @AuraEnabled
    public Integer dmlRows;
    @AuraEnabled
    public Integer cpuTimeMs;
    @AuraEnabled
    public Integer heapBytes;
    @AuraEnabled
    public Long durationMs;
    @AuraEnabled
    public Integer soqlLimit;
    @AuraEnabled
    public Integer dmlStatementsLimit;
    @AuraEnabled
    public Integer dmlRowsLimit;
    @AuraEnabled
    public Integer cpuTimeLimit;
    @AuraEnabled
    public Integer heapLimit;
  }
}
