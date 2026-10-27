/**
 * Deterministic pseudo-random values for synthetic data: the same seed always produces the
 * same data set, so CI runs are comparable. Not suitable for anything security related.
 */
public with sharing class SyntheticDataGenerator {
  private static final Long MODULUS = 2147483648L; // 2^31
  private static final Long MULTIPLIER = 1103515245L;
  private static final Long INCREMENT = 12345L;

  private Long state;

  public SyntheticDataGenerator(Long seed) {
    state = Math.mod(Math.abs(seed ?? 0L), MODULUS);
  }

  /** Integer in [0, bound). */
  public Integer nextInt(Integer bound) {
    if (bound == null || bound <= 0) {
      throw new DemoException('bound must be positive');
    }
    state = Math.mod(state * MULTIPLIER + INCREMENT, MODULUS);
    return Math.mod(state, (Long) bound).intValue();
  }

  /** Integer in [minValue, maxValue]. */
  public Integer nextIntBetween(Integer minValue, Integer maxValue) {
    return minValue + nextInt(maxValue - minValue + 1);
  }

  public Decimal nextAmount(Decimal minValue, Decimal maxValue) {
    Integer cents = nextInt(
      Math.max(1, ((maxValue - minValue) * 100).intValue() + 1)
    );
    return (minValue + cents / 100.0).setScale(2);
  }

  public Boolean chance(Integer percent) {
    return nextInt(100) < percent;
  }

  public String pick(List<String> values) {
    return values[nextInt(values.size())];
  }

  public Date nextDate(Date startDate, Integer spanDays) {
    return startDate.addDays(nextInt(Math.max(1, spanDays)));
  }

  /** Stable, sortable label such as "DEMO-00042". */
  public static String label(String prefix, Integer index) {
    return prefix + '-' + String.valueOf(index).leftPad(5, '0');
  }
}
