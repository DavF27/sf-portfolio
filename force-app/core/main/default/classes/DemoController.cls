/**
 * Server API of the demoPanel LWC.
 */
public with sharing class DemoController {
  private static final Integer MAX_RECENT_RUNS = 50;

  @AuraEnabled(cacheable=true)
  public static List<DemoDefinition> getDemos() {
    List<DemoDefinition> demos = new List<DemoDefinition>();
    for (Demo_Setting__mdt setting : DemoCatalog.getActive()) {
      demos.add(new DemoDefinition(setting));
    }
    return demos;
  }

  /** Governor limits of a synchronous Apex transaction, as reported by the platform. */
  // Not cacheable: in a cacheable (read-only) context the platform reports a DML statement limit of 1.
  @AuraEnabled
  public static DemoMetrics.Snapshot getLimits() {
    return new DemoMetrics().snapshot();
  }

  @AuraEnabled
  public static DemoRunService.Response runDemo(
    String demoName,
    String mode,
    Integer volume,
    Boolean chaos,
    String runKey
  ) {
    try {
      DemoRunService.Request request = new DemoRunService.Request(
        demoName,
        mode,
        volume
      );
      request.chaos = chaos == true;
      request.runKey = runKey;
      request.source = DemoRunService.SOURCE_PANEL;
      return DemoRunService.run(request);
    } catch (DemoException e) {
      throw toAuraException(e);
    }
  }

  /** Called by the panel when runDemo died on an uncatchable exception (e.g. Too many SOQL queries). */
  @AuraEnabled
  public static void recordUncaughtFailure(
    String demoName,
    String mode,
    Integer volume,
    Boolean chaos,
    String runKey,
    String message
  ) {
    try {
      DemoRunService.Request request = new DemoRunService.Request(
        demoName,
        mode,
        volume
      );
      request.chaos = chaos == true;
      request.runKey = runKey;
      request.source = DemoRunService.SOURCE_PANEL;
      DemoRunService.recordUncaughtFailure(request, message);
    } catch (DemoException e) {
      throw toAuraException(e);
    }
  }

  @AuraEnabled
  public static List<Demo_Run__c> getRecentRuns(Integer limitSize) {
    Integer size = (limitSize == null ||
      limitSize < 1)
      ? 10
      : Math.min(limitSize, MAX_RECENT_RUNS);
    return [
      SELECT
        Id,
        Name,
        Run_Key__c,
        Demo__c,
        Mode__c,
        Status__c,
        Source__c,
        Volume__c,
        Chaos__c,
        SOQL_Queries__c,
        DML_Statements__c,
        DML_Rows__c,
        CPU_Time_Ms__c,
        Duration_Ms__c,
        Records_Processed__c,
        Records_Failed__c,
        Step_Count__c,
        Error_Message__c,
        Started_At__c,
        Finished_At__c
      FROM Demo_Run__c
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT :size
    ];
  }

  @AuraEnabled
  public static Integer seedData(String demoName, Integer volume) {
    try {
      return DemoDataService.seed(demoName, volume);
    } catch (DemoException e) {
      throw toAuraException(e);
    }
  }

  @AuraEnabled
  public static Integer purgeData(String demoName) {
    try {
      return DemoDataService.purge(demoName);
    } catch (DemoException e) {
      throw toAuraException(e);
    }
  }

  private static AuraHandledException toAuraException(Exception e) {
    AuraHandledException auraException = new AuraHandledException(
      e.getMessage()
    );
    auraException.setMessage(e.getMessage());
    return auraException;
  }

  public class DemoDefinition {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String defaultMode;
    @AuraEnabled
    public Integer defaultVolume;
    @AuraEnabled
    public Integer maxVolume;
    @AuraEnabled
    public Boolean hasSeeder;

    public DemoDefinition(Demo_Setting__mdt setting) {
      name = setting.DeveloperName;
      label = setting.MasterLabel;
      description = setting.Description__c;
      defaultMode = setting.Mode__c;
      defaultVolume = setting.Default_Volume__c?.intValue();
      maxVolume = setting.Max_Volume__c?.intValue();
      hasSeeder = String.isNotBlank(setting.Seeder_Class__c);
    }
  }
}
