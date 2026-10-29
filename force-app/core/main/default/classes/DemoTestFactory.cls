/**
 * Shared fixtures for the core framework tests: in-memory Demo_Setting__mdt records and
 * test strategies/seeders resolved through Type.forName.
 */
@IsTest
public class DemoTestFactory {
  public static final String DEMO = 'Test_Demo';
  public static final String SEEDED_DEMO_MARKER = 'Seeded';

  public static Demo_Setting__mdt setting(
    String name,
    String beforeClass,
    String afterClass
  ) {
    return new Demo_Setting__mdt(
      DeveloperName = name,
      MasterLabel = name.replace('_', ' '),
      Mode__c = DemoRunService.MODE_BEFORE,
      Before_Class__c = beforeClass,
      After_Class__c = afterClass,
      Seeder_Class__c = 'DemoTestFactory.RunSeeder',
      Description__c = 'Test demo',
      Default_Volume__c = 10,
      Max_Volume__c = 500,
      Sort_Order__c = 1,
      Is_Active__c = true
    );
  }

  /** Registers a single active demo whose BEFORE strategy fails and AFTER strategy succeeds. */
  public static Demo_Setting__mdt registerDefault() {
    Demo_Setting__mdt demo = setting(
      DEMO,
      'DemoTestFactory.FailingStrategy',
      'DemoTestFactory.SucceedingStrategy'
    );
    register(new List<Demo_Setting__mdt>{ demo });
    return demo;
  }

  public static void register(List<Demo_Setting__mdt> settings) {
    Map<String, Demo_Setting__mdt> byName = new Map<String, Demo_Setting__mdt>();
    for (Demo_Setting__mdt setting : settings) {
      byName.put(setting.DeveloperName, setting);
    }
    DemoCatalog.settingsOverride = byName;
  }

  public static DemoRunService.Request request(String mode, Integer volume) {
    DemoRunService.Request request = new DemoRunService.Request(
      DEMO,
      mode,
      volume
    );
    request.source = DemoRunService.SOURCE_TEST;
    return request;
  }

  /** User holding Demo_Admin: required by the WITH USER_MODE queries (FLS comes from the permission set only). */
  public static User demoUser() {
    return demoUser(new List<String>{ 'Demo_Admin' });
  }

  /** Demo runner holding the given permission sets (each demo package ships its own). */
  public static User demoUser(List<String> permissionSetNames) {
    String unique = UUID.randomUUID().toString().left(8);
    User demoUser = new User(
      ProfileId = UserInfo.getProfileId(),
      LastName = 'Demo Runner',
      Alias = 'demorun',
      Email = 'demo.runner@example.com',
      Username = 'demo.runner.' + unique + '@example.com',
      TimeZoneSidKey = 'Europe/Paris',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert demoUser;
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permissionSet : [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN :permissionSetNames
    ]) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = demoUser.Id,
          PermissionSetId = permissionSet.Id
        )
      );
    }
    Assert.areEqual(
      permissionSetNames.size(),
      assignments.size(),
      'Missing permission set among ' + permissionSetNames
    );
    insert assignments;
    return demoUser;
  }

  public static Demo_Run__c findRun(String runKey) {
    List<Demo_Run__c> runs = [
      SELECT
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
        SOQL_Limit__c,
        DML_Limit__c,
        Error_Message__c,
        Started_At__c,
        Finished_At__c
      FROM Demo_Run__c
      WHERE Run_Key__c = :runKey
    ];
    return runs.isEmpty() ? null : runs[0];
  }

  /** One query and one DML per call, then a step per record. */
  public class SucceedingStrategy implements DemoStrategy {
    public DemoResult execute(DemoContext context) {
      Integer existing = [SELECT COUNT() FROM Demo_Run__c];
      List<Demo_Run__c> created = new List<Demo_Run__c>();
      for (Integer i = 0; i < context.volume; i++) {
        created.add(new Demo_Run__c(Demo__c = 'Strategy output'));
      }
      insert created;
      context.injectChaos('after insert');
      context.step('Inserted', context.volume, 0);
      DemoResult result = new DemoResult(context.volume, 0);
      result.message = 'existing=' + existing;
      return result;
    }
  }

  /** Writes then throws: the run must be rolled back and recorded as failed. */
  public class FailingStrategy implements DemoStrategy {
    public DemoResult execute(DemoContext context) {
      insert new Demo_Run__c(Demo__c = 'Must be rolled back');
      throw new DemoException('Expected failure');
    }
  }

  public class NotAStrategy {
  }

  public class RunSeeder implements DemoDataSeeder {
    public Integer seed(Integer volume, SyntheticDataGenerator generator) {
      List<Demo_Run__c> records = new List<Demo_Run__c>();
      for (Integer i = 0; i < volume; i++) {
        records.add(
          new Demo_Run__c(
            Demo__c = SEEDED_DEMO_MARKER,
            Volume__c = generator.nextIntBetween(1, 100)
          )
        );
      }
      insert records;
      return records.size();
    }

    public Integer purge() {
      List<Demo_Run__c> records = [
        SELECT Id
        FROM Demo_Run__c
        WHERE Demo__c = :SEEDED_DEMO_MARKER
      ];
      delete records;
      return records.size();
    }
  }
}
