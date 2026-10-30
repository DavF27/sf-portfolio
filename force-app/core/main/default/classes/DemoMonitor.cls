/**
 * Implemented by strategies of asynchronous demos: tells whether the work of a run is still going,
 * finished, or stuck. A stuck run has recordsFailed > 0 and the stuck rows in failedRows.
 */
public interface DemoMonitor {
  DemoResult inspect(DemoContext context);
}
