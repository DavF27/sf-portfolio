import { LightningElement, api } from "lwc";

const ICONS = {
  START: "utility:play",
  STEP: "utility:record",
  SUCCEEDED: "utility:success",
  FAILED: "utility:error"
};

/**
 * Vertical timeline of Demo_Step__e events, ordered by sequence (uncaught failures last).
 */
export default class StepTimeline extends LightningElement {
  @api label = "Run steps";
  @api emptyText = "No step yet.";
  @api steps = [];

  get hasSteps() {
    return Array.isArray(this.steps) && this.steps.length > 0;
  }

  get items() {
    const steps = Array.isArray(this.steps) ? [...this.steps] : [];
    steps.sort(
      (left, right) =>
        (left.sequence ?? Number.MAX_SAFE_INTEGER) -
        (right.sequence ?? Number.MAX_SAFE_INTEGER)
    );
    return steps.map((step, index) => ({
      key: `${step.sequence ?? "x"}-${index}`,
      label: step.label,
      phase: step.phase,
      message: step.message,
      icon: ICONS[step.phase] || ICONS.STEP,
      cssClass: `timeline__item timeline__item_${(step.phase || "STEP").toLowerCase()}`,
      detail: this.formatDetail(step)
    }));
  }

  formatDetail(step) {
    const parts = [];
    if (step.soqlQueries != null) {
      parts.push(`SOQL ${step.soqlQueries}`);
    }
    if (step.dmlStatements != null) {
      parts.push(`DML ${step.dmlStatements}`);
    }
    if (step.cpuTimeMs != null) {
      parts.push(`CPU ${step.cpuTimeMs} ms`);
    }
    if (step.recordsProcessed != null) {
      parts.push(`${step.recordsProcessed} records`);
    }
    return parts.join(" · ");
  }
}
