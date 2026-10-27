import { LightningElement, wire } from "lwc";
import { subscribe, unsubscribe, onError } from "lightning/empApi";
import getDemos from "@salesforce/apex/DemoController.getDemos";
import getLimits from "@salesforce/apex/DemoController.getLimits";
import runDemo from "@salesforce/apex/DemoController.runDemo";
import recordUncaughtFailure from "@salesforce/apex/DemoController.recordUncaughtFailure";
import getRecentRuns from "@salesforce/apex/DemoController.getRecentRuns";

export const CHANNEL = "/event/Demo_Step__e";
const RECENT_RUNS = 10;
const TERMINAL_PHASES = new Set(["SUCCEEDED", "FAILED"]);
const LIMIT_PATTERN = /Too many (SOQL queries|DML statements|DML rows): (\d+)/;
const LIMIT_FIELDS = {
  "SOQL queries": "soqlQueries",
  "DML statements": "dmlStatements",
  "DML rows": "dmlRows"
};
const METRIC_FIELDS = [
  "soqlQueries",
  "dmlStatements",
  "dmlRows",
  "cpuTimeMs",
  "recordsProcessed",
  "recordsFailed"
];

const RUN_COLUMNS = [
  { label: "Run", fieldName: "Name", initialWidth: 110 },
  { label: "Demo", fieldName: "Demo__c" },
  { label: "Mode", fieldName: "Mode__c", initialWidth: 90 },
  { label: "Status", fieldName: "Status__c", initialWidth: 100 },
  {
    label: "SOQL",
    fieldName: "SOQL_Queries__c",
    type: "number",
    initialWidth: 80
  },
  {
    label: "DML",
    fieldName: "DML_Statements__c",
    type: "number",
    initialWidth: 80
  },
  {
    label: "CPU (ms)",
    fieldName: "CPU_Time_Ms__c",
    type: "number",
    initialWidth: 100
  },
  {
    label: "Duration (ms)",
    fieldName: "Duration_Ms__c",
    type: "number",
    initialWidth: 120
  },
  {
    label: "Processed",
    fieldName: "Records_Processed__c",
    type: "number",
    initialWidth: 100
  },
  {
    label: "Failed",
    fieldName: "Records_Failed__c",
    type: "number",
    initialWidth: 80
  },
  { label: "Error", fieldName: "Error_Message__c", wrapText: true }
];

export function reduceError(error) {
  if (!error) {
    return "Unknown error";
  }
  if (Array.isArray(error.body)) {
    return error.body.map((item) => item.message).join(", ");
  }
  return error.body?.message || error.message || String(error);
}

/** Reads the value the platform reported when a limit broke, e.g. "Too many SOQL queries: 101". */
export function extractLimitBreach(message) {
  const match = LIMIT_PATTERN.exec(message || "");
  return match
    ? { field: LIMIT_FIELDS[match[1]], value: Number(match[2]) }
    : null;
}

function newRunKey() {
  if (globalThis.crypto?.randomUUID) {
    return globalThis.crypto.randomUUID();
  }
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`;
}

function toStep(payload) {
  return {
    phase: payload.Phase__c,
    label: payload.Label__c,
    sequence: payload.Sequence__c,
    message: payload.Message__c,
    soqlQueries: payload.SOQL_Queries__c,
    dmlStatements: payload.DML_Statements__c,
    dmlRows: payload.DML_Rows__c,
    cpuTimeMs: payload.CPU_Time_Ms__c,
    recordsProcessed: payload.Records_Processed__c,
    recordsFailed: payload.Records_Failed__c
  };
}

function mergeMetrics(current, incoming) {
  const merged = { ...current };
  METRIC_FIELDS.forEach((field) => {
    const value = incoming?.[field];
    if (value != null) {
      merged[field] = Math.max(merged[field] ?? 0, value);
    }
  });
  return merged;
}

export default class DemoPanel extends LightningElement {
  demos = [];
  demosError;
  limits;
  volumes = {};
  chaosByDemo = {};
  activeRun;
  runs = [];
  runsError;
  streamingError;
  isRunning = false;
  columns = RUN_COLUMNS;
  subscription;

  @wire(getDemos)
  wiredDemos({ data, error }) {
    if (data) {
      this.demos = data;
      this.demosError = undefined;
    } else if (error) {
      this.demos = [];
      this.demosError = reduceError(error);
    }
  }

  @wire(getLimits)
  wiredLimits({ data, error }) {
    if (data) {
      this.limits = data;
    } else if (error) {
      this.limits = undefined;
    }
  }

  connectedCallback() {
    onError((error) => {
      this.streamingError = `Live progress unavailable: ${reduceError(error)}`;
    });
    this.subscribeToSteps();
    this.loadRuns();
  }

  disconnectedCallback() {
    if (this.subscription) {
      unsubscribe(this.subscription, () => {});
      this.subscription = undefined;
    }
  }

  async subscribeToSteps() {
    try {
      this.subscription = await subscribe(CHANNEL, -1, (message) =>
        this.handleStepMessage(message)
      );
    } catch (error) {
      this.streamingError = `Live progress unavailable: ${reduceError(error)}`;
    }
  }

  async loadRuns() {
    try {
      this.runs = await getRecentRuns({ limitSize: RECENT_RUNS });
      this.runsError = undefined;
    } catch (error) {
      this.runsError = reduceError(error);
    }
  }

  handleStepMessage(message) {
    const payload = message?.data?.payload;
    if (
      !payload ||
      !this.activeRun ||
      payload.Run_Key__c !== this.activeRun.runKey
    ) {
      return;
    }
    const step = toStep(payload);
    const updated = {
      ...this.activeRun,
      steps: [...this.activeRun.steps, step],
      metrics: mergeMetrics(this.activeRun.metrics, step)
    };
    if (TERMINAL_PHASES.has(step.phase)) {
      updated.status = step.phase === "SUCCEEDED" ? "Succeeded" : "Failed";
      updated.error =
        updated.error || (step.phase === "FAILED" ? step.message : undefined);
      this.loadRuns();
    }
    this.activeRun = updated;
  }

  handleVolumeChange(event) {
    this.volumes = {
      ...this.volumes,
      [event.target.dataset.demo]: Number(event.detail.value)
    };
  }

  handleChaosChange(event) {
    this.chaosByDemo = {
      ...this.chaosByDemo,
      [event.target.dataset.demo]: event.detail.checked
    };
  }

  async handleRun(event) {
    const { demo, mode } = event.currentTarget.dataset;
    const definition = this.demos.find((item) => item.name === demo);
    const request = {
      demoName: demo,
      mode,
      volume: this.volumes[demo] ?? definition?.defaultVolume,
      chaos: this.chaosByDemo[demo] === true,
      runKey: newRunKey()
    };
    this.isRunning = true;
    this.activeRun = {
      ...request,
      label: definition?.label || demo,
      status: "Running",
      steps: [],
      metrics: {}
    };
    try {
      const response = await runDemo(request);
      this.applyResponse(request.runKey, response);
    } catch (error) {
      await this.reportUncaughtFailure(request, reduceError(error));
    } finally {
      this.isRunning = false;
      this.loadRuns();
    }
  }

  applyResponse(runKey, response) {
    if (!this.activeRun || this.activeRun.runKey !== runKey) {
      return;
    }
    this.activeRun = {
      ...this.activeRun,
      status: response.status,
      error: response.errorMessage,
      metrics: mergeMetrics(
        mergeMetrics(this.activeRun.metrics, response.metrics),
        response.result
      )
    };
  }

  async reportUncaughtFailure(request, message) {
    let error = message;
    const breach = extractLimitBreach(message);
    const metrics = breach
      ? mergeMetrics(this.activeRun.metrics, { [breach.field]: breach.value })
      : this.activeRun.metrics;
    try {
      await recordUncaughtFailure({ ...request, message });
    } catch (recordError) {
      error = `${message} (not recorded: ${reduceError(recordError)})`;
    }
    if (this.activeRun?.runKey === request.runKey) {
      this.activeRun = { ...this.activeRun, status: "Failed", error, metrics };
    }
  }

  get hasDemos() {
    return this.demos.length > 0;
  }

  get demoCards() {
    return this.demos.map((demo) => ({
      ...demo,
      volume: this.volumes[demo.name] ?? demo.defaultVolume,
      chaos: this.chaosByDemo[demo.name] === true,
      volumeLabel: `Volume (max ${demo.maxVolume})`,
      beforeLabel: `Run ${demo.label} in BEFORE mode`,
      afterLabel: `Run ${demo.label} in AFTER mode`
    }));
  }

  get hasActiveRun() {
    return this.activeRun !== undefined;
  }

  get activeMetrics() {
    return this.activeRun?.metrics || {};
  }

  get statusClass() {
    const status = this.activeRun?.status;
    if (status === "Succeeded") {
      return "slds-badge slds-theme_success";
    }
    return status === "Failed" ? "slds-badge slds-theme_error" : "slds-badge";
  }

  get isFailed() {
    return this.activeRun?.status === "Failed";
  }

  get soqlLimit() {
    return this.limits?.soqlLimit;
  }

  get dmlLimit() {
    return this.limits?.dmlStatementsLimit;
  }

  get cpuLimit() {
    return this.limits?.cpuTimeLimit;
  }

  get hasRuns() {
    return this.runs.length > 0;
  }
}
