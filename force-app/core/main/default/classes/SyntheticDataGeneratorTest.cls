@IsTest
private class SyntheticDataGeneratorTest {
  @IsTest
  static void sameSeedProducesSameSequence() {
    SyntheticDataGenerator first = new SyntheticDataGenerator(42L);
    SyntheticDataGenerator second = new SyntheticDataGenerator(42L);
    SyntheticDataGenerator other = new SyntheticDataGenerator(43L);
    List<Integer> a = new List<Integer>();
    List<Integer> b = new List<Integer>();
    List<Integer> c = new List<Integer>();

    Test.startTest();
    for (Integer i = 0; i < 200; i++) {
      a.add(first.nextInt(1000));
      b.add(second.nextInt(1000));
      c.add(other.nextInt(1000));
    }
    Test.stopTest();

    Assert.areEqual(a, b);
    Assert.areNotEqual(a, c);
  }

  @IsTest
  static void valuesStayWithinBounds() {
    SyntheticDataGenerator generator = new SyntheticDataGenerator(null);
    Date startDate = Date.newInstance(2026, 1, 1);
    List<String> colors = new List<String>{ 'red', 'green' };

    Test.startTest();
    for (Integer i = 0; i < 200; i++) {
      Integer value = generator.nextIntBetween(5, 9);
      Assert.isTrue(value >= 5 && value <= 9, String.valueOf(value));
      Decimal amount = generator.nextAmount(10, 20);
      Assert.isTrue(amount >= 10 && amount <= 20, String.valueOf(amount));
      Assert.areEqual(2, amount.scale());
      Date d = generator.nextDate(startDate, 30);
      Assert.isTrue(d >= startDate && d < startDate.addDays(30));
      Assert.isTrue(colors.contains(generator.pick(colors)));
      generator.chance(50);
    }
    Test.stopTest();

    Assert.isFalse(generator.chance(0));
    Assert.isTrue(generator.chance(100));
  }

  @IsTest
  static void rejectsNonPositiveBound() {
    SyntheticDataGenerator generator = new SyntheticDataGenerator(1L);

    Test.startTest();
    try {
      generator.nextInt(0);
      Assert.fail('Expected DemoException');
    } catch (DemoException e) {
      Assert.areEqual('bound must be positive', e.getMessage());
    }
    Test.stopTest();
  }

  @IsTest
  static void buildsSortableLabels() {
    Test.startTest();
    String label = SyntheticDataGenerator.label('DEMO', 42);
    Test.stopTest();

    Assert.areEqual('DEMO-00042', label);
  }
}
