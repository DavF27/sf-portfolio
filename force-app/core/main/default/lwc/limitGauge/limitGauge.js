import { LightningElement, api } from "lwc";

const WARNING_RATIO = 0.7;

/**
 * Semicircle gauge for one governor limit. Turns amber at 70 % and red when the limit is reached.
 */
export default class LimitGauge extends LightningElement {
  @api label;
  @api value = 0;
  @api max = 100;

  get safeValue() {
    const value = Number(this.value);
    return Number.isFinite(value) && value > 0 ? value : 0;
  }

  get safeMax() {
    const max = Number(this.max);
    return Number.isFinite(max) && max > 0 ? max : 1;
  }

  get ratio() {
    return Math.min(this.safeValue / this.safeMax, 1);
  }

  get level() {
    if (this.safeValue >= this.safeMax) {
      return "error";
    }
    return this.ratio >= WARNING_RATIO ? "warning" : "success";
  }

  get arcClass() {
    return `gauge__arc gauge__arc_${this.level}`;
  }

  get dashArray() {
    const filled = Math.round(this.ratio * 100);
    return `${filled} 100`;
  }

  get valueText() {
    return `${this.label}: ${this.safeValue} of ${this.safeMax}`;
  }
}
