import { LightningElement, api } from "lwc";

const MAX_TILES = 500;

/**
 * One tile per row of a batch. Rows reported done (asynchronous demos) turn green as they complete;
 * otherwise processed rows light up while running. At the end rows turn green, except failed rows.
 * A failed run without failed rows means the whole transaction was rolled back: every row turns red.
 */
export default class RowGrid extends LightningElement {
  @api label = "Rows";
  @api total = 0;
  @api processed = 0;
  @api failedRows = [];
  @api doneRows = [];
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

  get doneSet() {
    return new Set(Array.isArray(this.doneRows) ? this.doneRows : []);
  }

  get wholeBatchFailed() {
    return this.status === "Failed" && this.failedSet.size === 0;
  }

  get tiles() {
    const failed = this.failedSet;
    const done = this.doneSet;
    // Rows reported one by one replace the "first N processed" approximation.
    const processed = done.size > 0 ? 0 : Number(this.processed) || 0;
    const tiles = [];
    for (let row = 1; row <= this.safeTotal; row++) {
      const state = this.stateOf(row, failed, done, processed);
      tiles.push({
        key: row,
        cssClass: `grid__tile grid__tile_${state}`,
        title: `Row ${row}: ${state}`
      });
    }
    return tiles;
  }

  stateOf(row, failed, done, processed) {
    if (this.wholeBatchFailed || failed.has(row)) {
      return "failed";
    }
    if (done.has(row) || this.status === "Succeeded") {
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
    const done = this.doneSet.size;
    if (this.status === "Failed") {
      return `${this.label}: ${done} succeeded, ${failed} failed`;
    }
    if (done > 0) {
      return `${this.label}: ${done} of ${total} done`;
    }
    const processed = Math.min(Number(this.processed) || 0, total);
    return `${this.label}: ${processed} of ${total} processed`;
  }
}
