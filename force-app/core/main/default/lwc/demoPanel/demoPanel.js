import { LightningElement, wire } from "lwc";
import { subscribe, unsubscribe, onError } from "lightning/empApi";
import getDemos from "@salesforce/apex/DemoController.getDemos";
import getLimits from "@salesforce/apex/DemoController.getLimits";
import runDemo from "@salesforce/apex/DemoController.runDemo";
import recordUncaughtFailure from "@salesforce/apex/DemoController.recordUncaughtFailure";
import getRecentRuns from "@salesforce/apex/DemoController.getRecentRuns";
import monitorRun from "@salesforce/apex/DemoController.monitorRun";

export const CHANNEL = "/event/Demo_Step__e";
const RECENT_RUNS = 10;
const TERMINAL_PHASES = new Set(["SUCCEEDED", "FAILED"]);
const TERMINAL_STATUSES = new Set(["Succeeded", "Failed"]);
/** An asynchronous run silent for this long is checked by its demo monitor. */
export const IDLE_MS = 20000;
const WATCH_INTERVAL_MS = 5000;
const RACE_TICK_MS = 500;
const RACE_MODES = ["BEFORE", "AFTER"];
const RACE_SUBTITLES = {
  BEFORE: "Current implementation",
  AFTER: "Fixed implementation"
};
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
  { label: "Error", fieldName: "errorSummary", wrapText: true }
];

const ERROR_SUMMARY_LENGTH = 160;

/** First line of a platform error, shortened for the runs table (the full text stays in the record). */
export function summarizeError(message) {
  if (!message) {
    return "";
  }
  const firstLine = String(message).split(/\r?\n/)[0].trim();
  return firstLine.length > ERROR_SUMMARY_LENGTH
    ? `${firstLine.slice(0, ERROR_SUMMARY_LENGTH - 1)}…`
    : firstLine;
}

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

/** "3,4,5" -> [3, 4, 5] */
export function parseRows(text) {
  return String(text || "")
    .split(",")
    .map((row) => Number(row.trim()))
    .filter((row) => Number.isInteger(row) && row > 0);
}

function unionRows(current, incoming) {
  return [...new Set([...(current || []), ...(incoming || [])])].sort(
    (a, b) => a - b
  );
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
    recordsFailed: payload.Records_Failed__c,
    rowsDone: parseRows(payload.Rows_Done__c),
    rowsFailed: parseRows(payload.Rows_Failed__c)
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
  watchdog;
  monitoring = false;
  lastEventAt = 0;
  race;
  raceTicker;
  now = Date.now();

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

  connectedCallback() {
    onError((error) => {
      this.streamingError = `Live progress unavailable: ${reduceError(error)}`;
    });
    this.subscribeToSteps();
    this.loadLimits();
    this.loadRuns();
  }

  disconnectedCallback() {
    this.stopWatchdog();
    this.stopRaceTicker();
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

  // Imperative on purpose: getLimits must not be cacheable (see DemoController.getLimits).
  async loadLimits() {
    try {
      this.limits = await getLimits();
    } catch {
      // Gauges then use the limits returned with the first run.
      this.limits = undefined;
    }
  }

  async loadRuns() {
    try {
      const runs = await getRecentRuns({ limitSize: RECENT_RUNS });
      this.runs = runs.map((run) => ({
        ...run,
        errorSummary: summarizeError(run.Error_Message__c)
      }));
      this.runsError = undefined;
    } catch (error) {
      this.runsError = reduceError(error);
    }
  }

  handleStepMessage(message) {
    const payload = message?.data?.payload;
    if (payload && this.race) {
      this.applyRaceStep(payload);
      return;
    }
    if (
      !payload ||
      !this.activeRun ||
      payload.Run_Key__c !== this.activeRun.runKey
    ) {
      return;
    }
    const step = toStep(payload);
    this.lastEventAt = Date.now();
    const updated = {
      ...this.activeRun,
      steps: [...this.activeRun.steps, step],
      metrics: mergeMetrics(this.activeRun.metrics, step),
      doneRows: unionRows(this.activeRun.doneRows, step.rowsDone),
      failedRows: unionRows(this.activeRun.failedRows, step.rowsFailed)
    };
    if (TERMINAL_PHASES.has(step.phase)) {
      this.stopWatchdog();
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

  /** Runs BEFORE and AFTER at the same time (each mode on its own data) and shows them side by side. */
  async handleRace(event) {
    const { demo } = event.currentTarget.dataset;
    const definition = this.demos.find((item) => item.name === demo);
    const volume = this.volumes[demo] ?? definition?.defaultVolume;
    const chaos = this.chaosByDemo[demo] === true;
    this.stopWatchdog();
    this.activeRun = undefined;
    this.isRunning = true;
    this.now = Date.now();
    const lanes = {};
    RACE_MODES.forEach((mode) => {
      lanes[mode] = {
        key: mode,
        label: mode,
        subtitle: RACE_SUBTITLES[mode],
        runKey: newRunKey(),
        status: "Running",
        processed: 0,
        total: volume,
        executions: null,
        finishedAt: null,
        message: null
      };
    });
    this.race = {
      label: definition?.label || demo,
      volume,
      startedAt: this.now,
      lanes
    };
    this.startRaceTicker();
    try {
      await Promise.all(
        RACE_MODES.map(async (mode) => {
          const request = {
            demoName: demo,
            mode,
            volume,
            chaos,
            runKey: lanes[mode].runKey
          };
          try {
            const response = await runDemo(request);
            if (response.status !== "Running") {
              this.updateRaceLane(mode, {
                status: response.status,
                message: response.errorMessage || response.result?.message
              });
            }
          } catch (error) {
            this.updateRaceLane(mode, {
              status: "Failed",
              message: reduceError(error)
            });
          }
        })
      );
    } finally {
      this.isRunning = false;
      this.loadRuns();
    }
  }

  applyRaceStep(payload) {
    const mode = RACE_MODES.find(
      (item) => this.race.lanes[item].runKey === payload.Run_Key__c
    );
    if (!mode) {
      return;
    }
    const lane = this.race.lanes[mode];
    const changes = {
      processed: Math.max(lane.processed, payload.Records_Processed__c ?? 0),
      executions: payload.Async_Executions__c ?? lane.executions
    };
    if (TERMINAL_PHASES.has(payload.Phase__c)) {
      changes.status =
        payload.Phase__c === "SUCCEEDED" ? "Succeeded" : "Failed";
      changes.message = payload.Message__c;
      this.loadRuns();
    }
    this.updateRaceLane(mode, changes);
  }

  updateRaceLane(mode, changes) {
    if (!this.race) {
      return;
    }
    const lane = this.race.lanes[mode];
    if (TERMINAL_STATUSES.has(lane.status)) {
      return;
    }
    const updated = { ...lane, ...changes };
    if (TERMINAL_STATUSES.has(updated.status)) {
      updated.finishedAt = Date.now();
    }
    this.race = {
      ...this.race,
      lanes: { ...this.race.lanes, [mode]: updated }
    };
    if (
      RACE_MODES.every((item) =>
        TERMINAL_STATUSES.has(this.race.lanes[item].status)
      )
    ) {
      this.stopRaceTicker();
    }
  }

  startRaceTicker() {
    this.stopRaceTicker();
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- live chronometer of the race lanes
    this.raceTicker = setInterval(() => {
      this.now = Date.now();
    }, RACE_TICK_MS);
  }

  stopRaceTicker() {
    if (this.raceTicker) {
      clearInterval(this.raceTicker);
      this.raceTicker = undefined;
    }
    this.now = Date.now();
  }

  get raceLanes() {
    if (!this.race) {
      return [];
    }
    return RACE_MODES.map((mode) => {
      const lane = this.race.lanes[mode];
      return {
        ...lane,
        elapsedMs: (lane.finishedAt ?? this.now) - this.race.startedAt
      };
    });
  }

  async handleRun(event) {
    const { demo, mode } = event.currentTarget.dataset;
    const definition = this.demos.find((item) => item.name === demo);
    this.race = undefined;
    this.stopRaceTicker();
    const request = {
      demoName: demo,
      mode,
      volume: this.volumes[demo] ?? definition?.defaultVolume,
      chaos: this.chaosByDemo[demo] === true,
      runKey: newRunKey()
    };
    this.stopWatchdog();
    this.isRunning = true;
    this.lastEventAt = Date.now();
    this.activeRun = {
      ...request,
      label: definition?.label || demo,
      status: "Running",
      steps: [],
      metrics: {},
      doneRows: [],
      failedRows: []
    };
    try {
      const response = await runDemo(request);
      this.applyResponse(request.runKey, response);
      if (this.activeRun?.status === "Running" && definition?.hasMonitor) {
        this.startWatchdog(request);
      }
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
    if (response.metrics?.soqlLimit) {
      // Limits of the transaction that actually ran the demo.
      this.limits = response.metrics;
    }
    // Asynchronous jobs may have closed the run before the synchronous response arrived.
    const closedByJobs =
      TERMINAL_STATUSES.has(this.activeRun.status) &&
      response.status === "Running";
    this.activeRun = {
      ...this.activeRun,
      status: closedByJobs ? this.activeRun.status : response.status,
      error: response.errorMessage,
      failedRows: unionRows(
        this.activeRun.failedRows,
        response.result?.failedRows
      ),
      metrics: mergeMetrics(
        mergeMetrics(this.activeRun.metrics, response.metrics),
        response.result
      )
    };
  }

  startWatchdog(request) {
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- periodic check of a silent asynchronous run
    this.watchdog = setInterval(
      () => this.checkIdleRun(request),
      WATCH_INTERVAL_MS
    );
  }

  stopWatchdog() {
    if (this.watchdog) {
      clearInterval(this.watchdog);
      this.watchdog = undefined;
    }
  }

  /** Nothing published for IDLE_MS: ask the demo monitor whether the run is stuck. */
  async checkIdleRun(request) {
    if (
      this.activeRun?.runKey !== request.runKey ||
      this.activeRun.status !== "Running"
    ) {
      this.stopWatchdog();
      return;
    }
    if (this.monitoring || Date.now() - this.lastEventAt < IDLE_MS) {
      return;
    }
    this.monitoring = true;
    try {
      const response = await monitorRun(request);
      this.lastEventAt = Date.now();
      if (response.status !== "Running") {
        this.stopWatchdog();
        this.applyMonitoring(request.runKey, response);
      }
    } catch (error) {
      this.stopWatchdog();
      if (this.activeRun?.runKey === request.runKey) {
        this.activeRun = {
          ...this.activeRun,
          error: `Monitoring failed: ${reduceError(error)}`
        };
      }
    } finally {
      this.monitoring = false;
    }
  }

  applyMonitoring(runKey, response) {
    if (this.activeRun?.runKey !== runKey) {
      return;
    }
    this.activeRun = {
      ...this.activeRun,
      status: response.status,
      error: response.errorMessage || this.activeRun.error,
      failedRows: unionRows(
        this.activeRun.failedRows,
        response.result?.failedRows
      )
    };
    this.loadRuns();
  }

  async reportUncaughtFailure(request, message) {
    let error = message;
    const breach = extractLimitBreach(message);
    try {
      await recordUncaughtFailure({ ...request, message });
    } catch (recordError) {
      error = `${message} (not recorded: ${reduceError(recordError)})`;
    }
    if (this.activeRun?.runKey === request.runKey) {
      // Merge after the await: live steps may have arrived in the meantime.
      const metrics = breach
        ? mergeMetrics(this.activeRun.metrics, {
            [breach.field]: breach.value
          })
        : this.activeRun.metrics;
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
      raceLabel: `Run ${demo.label} in BEFORE and AFTER mode at the same time`,
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
