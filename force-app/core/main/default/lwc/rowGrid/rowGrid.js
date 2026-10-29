import { LightningElement, api } from "lwc";

const MAX_TILES = 500;

/**
 * One tile per row of a batch. While running, processed rows light up; at the end rows turn green,
 * except failed rows. A failed run without failed rows means the whole transaction was rolled back:
 * every row turns red at once.
 */
export default class RowGrid extends LightningElement {
  @api label = "Rows";
  @api total = 0;
  @api processed = 0;
  @api failedRows = [];
  @api status;

  get safeTotal() {
    const total = Number(this.total);
    return Number.isFinite(total) && total > 0
      ? Math.min(Math.floor(total), MAX_TILES)
      : 0;
  }

  get failedSet() {
    return new Set(Array.isArray(this.failedRows) ? this.failedRows : []);
  }

  get wholeBatchFailed() {
    return this.status === "Failed" && this.failedSet.size === 0;
  }

  get tiles() {
    const failed = this.failedSet;
    const processed = Number(this.processed) || 0;
    const tiles = [];
    for (let row = 1; row <= this.safeTotal; row++) {
      const state = this.stateOf(row, failed, processed);
      tiles.push({
        key: row,
        cssClass: `grid__tile grid__tile_${state}`,
        title: `Row ${row}: ${state}`
      });
    }
    return tiles;
  }

  stateOf(row, failed, processed) {
    if (this.wholeBatchFailed || failed.has(row)) {
      return "failed";
    }
    if (this.status === "Succeeded") {
      return "succeeded";
    }
    return row <= processed ? "processing" : "pending";
  }

  get summary() {
    const total = this.safeTotal;
    if (this.wholeBatchFailed) {
      return `${this.label}: all ${total} failed, the whole batch was rolled back`;
    }
    const failed = this.failedSet.size;
    if (this.status === "Succeeded") {
      return `${this.label}: ${total - failed} succeeded, ${failed} failed`;
    }
    const processed = Math.min(Number(this.processed) || 0, total);
    return `${this.label}: ${processed} of ${total} processed`;
  }
}
