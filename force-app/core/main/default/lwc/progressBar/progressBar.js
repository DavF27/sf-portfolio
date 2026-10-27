import { LightningElement, api } from "lwc";

/**
 * Horizontal progress bar; turns red when failed and green when complete.
 */
export default class ProgressBar extends LightningElement {
  @api label;
  @api value = 0;
  @api max = 100;
  @api failed = false;

  get safeValue() {
    const value = Number(this.value);
    return Number.isFinite(value) && value > 0
      ? Math.min(value, this.safeMax)
      : 0;
  }

  get safeMax() {
    const max = Number(this.max);
    return Number.isFinite(max) && max > 0 ? max : 1;
  }

  get percent() {
    return Math.round((this.safeValue / this.safeMax) * 100);
  }

  get barClass() {
    if (this.failed) {
      return "progress__bar progress__bar_error";
    }
    return this.percent >= 100
      ? "progress__bar progress__bar_success"
      : "progress__bar";
  }

  get barStyle() {
    return `width: ${this.percent}%`;
  }
}
