/**
 * A demo implementation selected by DemoStrategyFactory for one mode (BEFORE or AFTER).
 * Implementations must report progress through context.step() and never swallow exceptions:
 * DemoRunService records failures.
 */
public interface DemoStrategy {
  DemoResult execute(DemoContext context);
}
