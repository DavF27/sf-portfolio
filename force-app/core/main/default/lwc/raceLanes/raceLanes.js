import { LightningElement, api } from "lwc";

/** Formats milliseconds as seconds with one decimal: 12345 -> "12.3 s". */
export function formatElapsed(ms) {
  const value = Number(ms);
  return ms != null && Number.isFinite(value) && value >= 0
    ? `${(value / 1000).toFixed(1)} s`
    : "–";
}

/**
 * Side-by-side race of runs: one lane per run with its progress, elapsed time and executions.
 * The first lane to succeed is marked as the winner.
 */
export default class RaceLanes extends LightningElement {
  @api lanes = [];

  get items() {
    const lanes = Array.isArray(this.lanes) ? this.lanes : [];
    const finished = lanes.filter(
      (lane) => lane.status === "Succeeded" && lane.elapsedMs != null
    );
    let winner = null;
    for (const lane of finished) {
      if (winner === null || lane.elapsedMs < winner.elapsedMs) {
        winner = lane;
      }
    }
    return lanes.map((lane) => ({
      key: lane.key,
      label: lane.label,
      subtitle: lane.subtitle,
      status: lane.status,
      processed: lane.processed,
      total: lane.total,
      failed: lane.status === "Failed",
      message: lane.message,
      elapsed: formatElapsed(lane.elapsedMs),
      executions: lane.executions ?? "–",
      winner: winner !== null && winner.key === lane.key,
      badgeClass: badgeClass(lane.status)
    }));
  }
}

function badgeClass(status) {
  if (status === "Succeeded") {
    return "slds-badge slds-theme_success";
  }
  return status === "Failed" ? "slds-badge slds-theme_error" : "slds-badge";
}
