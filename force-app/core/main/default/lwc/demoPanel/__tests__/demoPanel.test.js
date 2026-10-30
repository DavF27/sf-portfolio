import { createElement } from "lwc";
import DemoPanel, {
  CHANNEL,
  extractLimitBreach,
  reduceError,
  summarizeError,
  parseRows,
  IDLE_MS
} from "c/demoPanel";
import {
  subscribe,
  unsubscribe,
  onError,
  jestMockPublish
} from "lightning/empApi";
import getDemos from "@salesforce/apex/DemoController.getDemos";
import getLimits from "@salesforce/apex/DemoController.getLimits";
import runDemo from "@salesforce/apex/DemoController.runDemo";
import recordUncaughtFailure from "@salesforce/apex/DemoController.recordUncaughtFailure";
import getRecentRuns from "@salesforce/apex/DemoController.getRecentRuns";
import monitorRun from "@salesforce/apex/DemoController.monitorRun";

jest.mock(
  "@salesforce/apex/DemoController.getDemos",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DemoController.getLimits",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DemoController.runDemo",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DemoController.recordUncaughtFailure",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DemoController.monitorRun",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DemoController.getRecentRuns",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const DEMOS = [
  {
    name: "Limits_Probe",
    label: "Limits Probe",
    description: "Calibration demo",
    defaultMode: "BEFORE",
    defaultVolume: 50,
    maxVolume: 150,
    hasSeeder: false
  }
];
const LIMITS = { soqlLimit: 100, dmlStatementsLimit: 150, cpuTimeLimit: 10000 };
const RUNS = [
  {
    Id: "a00000000000001AAA",
    Name: "RUN-000001",
    Demo__c: "Limits_Probe",
    Mode__c: "AFTER",
    Status__c: "Succeeded"
  },
  {
    Id: "a00000000000002AAA",
    Name: "RUN-000002",
    Demo__c: "Bulk_All_Or_Nothing",
    Mode__c: "BEFORE",
    Status__c: "Failed",
    Error_Message__c:
      "DemoException: All 50 rows of the batch failed\n\ncaused by: System.DmlException\nClass.X: line 1"
  }
];

// eslint-disable-next-line @lwc/lwc/no-async-operation -- a macrotask flushes chained Apex promises in tests
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

async function renderPanel() {
  const element = createElement("c-demo-panel", { is: DemoPanel });
  document.body.appendChild(element);
  getDemos.emit(DEMOS);
  await flushPromises();
  return element;
}

function button(element, mode) {
  return element.shadowRoot.querySelector(
    `lightning-button[data-mode="${mode}"]`
  );
}

function gauge(element, id) {
  return element.shadowRoot.querySelector(`c-limit-gauge[data-id="${id}"]`);
}

function stepMessage(runKey, phase, fields = {}) {
  return {
    data: {
      payload: {
        Run_Key__c: runKey,
        Phase__c: phase,
        Label__c: phase,
        ...fields
      }
    }
  };
}

describe("c-demo-panel", () => {
  beforeEach(() => {
    getRecentRuns.mockResolvedValue(RUNS);
    getLimits.mockResolvedValue(LIMITS);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists demos, subscribes to steps and shows recent runs", async () => {
    const element = await renderPanel();

    const cards = element.shadowRoot.querySelectorAll('[data-id="demo-card"]');
    expect(cards).toHaveLength(1);
    expect(cards[0].textContent).toContain("Limits Probe");
    expect(button(element, "BEFORE").title).toBe(
      "Run Limits Probe in BEFORE mode"
    );
    expect(subscribe).toHaveBeenCalledWith(CHANNEL, -1, expect.any(Function));
    expect(onError).toHaveBeenCalled();
    expect(getRecentRuns).toHaveBeenCalledWith({ limitSize: 10 });
    const tableData = element.shadowRoot.querySelector(
      '[data-id="runs-table"]'
    ).data;
    expect(tableData).toHaveLength(2);
    expect(tableData[0].errorSummary).toBe("");
    expect(tableData[1].errorSummary).toBe(
      "DemoException: All 50 rows of the batch failed"
    );
    expect(tableData[1].Error_Message__c).toContain("caused by");
    expect(
      element.shadowRoot.querySelector('[data-id="no-run"]')
    ).not.toBeNull();
  });

  it("runs AFTER mode and shows measured metrics and live steps", async () => {
    let resolveRun;
    runDemo.mockImplementation(
      () => new Promise((resolve) => (resolveRun = resolve))
    );
    getLimits.mockResolvedValueOnce({ ...LIMITS, dmlStatementsLimit: 1 });
    const element = await renderPanel();

    button(element, "AFTER").click();
    await flushPromises();
    const request = runDemo.mock.calls[0][0];
    expect(request).toMatchObject({
      demoName: "Limits_Probe",
      mode: "AFTER",
      volume: 50,
      chaos: false
    });
    expect(request.runKey).toMatch(/^[A-Za-z0-9-]{8,36}$/);
    expect(
      element.shadowRoot.querySelector('[data-id="run-status"]').textContent
    ).toBe("Running");
    expect(button(element, "BEFORE").disabled).toBe(true);
    expect(gauge(element, "gauge-dml").max).toBe(1);

    jestMockPublish(
      CHANNEL,
      stepMessage("another-run", "STEP", { SOQL_Queries__c: 99 })
    );
    jestMockPublish(
      CHANNEL,
      stepMessage(request.runKey, "START", { Sequence__c: 1 })
    );
    jestMockPublish(
      CHANNEL,
      stepMessage(request.runKey, "STEP", {
        Sequence__c: 2,
        SOQL_Queries__c: 1,
        Records_Processed__c: 10
      })
    );
    await flushPromises();
    expect(gauge(element, "gauge-soql").value).toBe(1);
    expect(
      element.shadowRoot.querySelector("c-step-timeline").steps
    ).toHaveLength(2);

    resolveRun({
      runKey: request.runKey,
      status: "Succeeded",
      metrics: {
        soqlQueries: 1,
        dmlStatements: 0,
        cpuTimeMs: 15,
        ...LIMITS
      },
      result: { recordsProcessed: 50, recordsFailed: 1, failedRows: [25] }
    });
    await flushPromises();
    jestMockPublish(
      CHANNEL,
      stepMessage(request.runKey, "SUCCEEDED", { Sequence__c: 3 })
    );
    await flushPromises();

    expect(
      element.shadowRoot.querySelector('[data-id="run-status"]').textContent
    ).toBe("Succeeded");
    expect(gauge(element, "gauge-soql").max).toBe(100);
    expect(gauge(element, "gauge-dml").max).toBe(150);
    expect(gauge(element, "gauge-cpu").value).toBe(15);
    expect(element.shadowRoot.querySelector("c-progress-bar").value).toBe(50);
    const rowGrid = element.shadowRoot.querySelector('[data-id="row-grid"]');
    expect(rowGrid.total).toBe(50);
    expect(rowGrid.failedRows).toEqual([25]);
    expect(rowGrid.status).toBe("Succeeded");
    expect(
      element.shadowRoot.querySelector('[data-id="run-error"]')
    ).toBeNull();
    expect(button(element, "AFTER").disabled).toBe(false);
    expect(getRecentRuns.mock.calls.length).toBeGreaterThanOrEqual(3);
  });

  it("records an uncaught BEFORE failure and shows the breached limit", async () => {
    runDemo.mockRejectedValue({
      body: { message: "System.LimitException: Too many SOQL queries: 101" }
    });
    recordUncaughtFailure.mockResolvedValue(undefined);
    const element = await renderPanel();

    const volumeInput = element.shadowRoot.querySelector(
      'lightning-input[data-id="volume-input"]'
    );
    volumeInput.dispatchEvent(
      new CustomEvent("change", { detail: { value: "150" } })
    );
    const chaosToggle = element.shadowRoot.querySelector(
      'lightning-input[data-id="chaos-toggle"]'
    );
    chaosToggle.dispatchEvent(
      new CustomEvent("change", { detail: { checked: true } })
    );
    await flushPromises();
    button(element, "BEFORE").click();
    await flushPromises();
    await flushPromises();

    const request = runDemo.mock.calls[0][0];
    expect(request).toMatchObject({ mode: "BEFORE", volume: 150, chaos: true });
    expect(recordUncaughtFailure).toHaveBeenCalledWith({
      ...request,
      message: "System.LimitException: Too many SOQL queries: 101"
    });
    expect(
      element.shadowRoot.querySelector('[data-id="run-status"]').textContent
    ).toBe("Failed");
    expect(
      element.shadowRoot.querySelector('[data-id="run-error"]').textContent
    ).toContain("Too many SOQL queries: 101");
    expect(gauge(element, "gauge-soql").value).toBe(101);
    const failedGrid = element.shadowRoot.querySelector('[data-id="row-grid"]');
    expect(failedGrid.status).toBe("Failed");
    expect(failedGrid.total).toBe(150);
    expect(element.shadowRoot.querySelector("c-progress-bar").failed).toBe(
      true
    );
  });

  it("keeps live steps that arrive while the uncaught failure is recorded", async () => {
    runDemo.mockRejectedValue({
      body: { message: "System.LimitException: Too many SOQL queries: 101" }
    });
    let resolveRecord;
    recordUncaughtFailure.mockImplementation(
      () => new Promise((resolve) => (resolveRecord = resolve))
    );
    const element = await renderPanel();

    button(element, "BEFORE").click();
    await flushPromises();
    const { runKey } = runDemo.mock.calls[0][0];
    jestMockPublish(
      CHANNEL,
      stepMessage(runKey, "STEP", {
        Sequence__c: 11,
        SOQL_Queries__c: 100,
        CPU_Time_Ms__c: 119,
        Records_Processed__c: 100
      })
    );
    resolveRecord();
    await flushPromises();

    expect(gauge(element, "gauge-soql").value).toBe(101);
    expect(gauge(element, "gauge-cpu").value).toBe(119);
    expect(element.shadowRoot.querySelector("c-progress-bar").value).toBe(100);
  });

  it("keeps the error visible when the failure cannot be recorded", async () => {
    runDemo.mockRejectedValue({
      body: { message: "Unknown or inactive demo: X" }
    });
    recordUncaughtFailure.mockRejectedValue({
      body: { message: "Run key must match" }
    });
    const element = await renderPanel();

    button(element, "AFTER").click();
    await flushPromises();
    await flushPromises();

    const error = element.shadowRoot.querySelector(
      '[data-id="run-error"]'
    ).textContent;
    expect(error).toContain("Unknown or inactive demo: X");
    expect(error).toContain("not recorded: Run key must match");
  });

  it("shows a caught failure returned by the server and its FAILED step", async () => {
    runDemo.mockImplementation((request) =>
      Promise.resolve({
        runKey: request.runKey,
        status: "Failed",
        errorMessage: "DemoException: Chaos injected at iteration 25",
        metrics: {}
      })
    );
    const element = await renderPanel();

    button(element, "AFTER").click();
    await flushPromises();
    const { runKey } = runDemo.mock.calls[0][0];
    jestMockPublish(
      CHANNEL,
      stepMessage(runKey, "FAILED", {
        Message__c: "DemoException: Chaos injected at iteration 25"
      })
    );
    await flushPromises();

    expect(
      element.shadowRoot.querySelector('[data-id="run-status"]').className
    ).toContain("slds-theme_error");
    expect(
      element.shadowRoot.querySelector('[data-id="run-error"]').textContent
    ).toContain("Chaos injected");
    expect(recordUncaughtFailure).not.toHaveBeenCalled();
  });

  it("reports wire, streaming and recent runs errors", async () => {
    getRecentRuns.mockRejectedValue({ body: { message: "No access" } });
    subscribe.mockRejectedValueOnce(new Error("Streaming disabled"));
    getLimits.mockRejectedValueOnce({ body: { message: "Limits failed" } });
    const element = createElement("c-demo-panel", { is: DemoPanel });
    document.body.appendChild(element);
    getDemos.error({ message: "Wire failed" });
    await flushPromises();

    expect(gauge(element, "gauge-soql")).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="demos-error"]')
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="no-demos"]')
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="streaming-error"]')
        .textContent
    ).toContain("Streaming disabled");
    expect(
      element.shadowRoot.querySelector('[data-id="runs-error"]').textContent
    ).toBe("No access");

    onError.mock.calls[0][0]({ error: "handshake" });
    await flushPromises();
    expect(
      element.shadowRoot.querySelector('[data-id="streaming-error"]')
        .textContent
    ).toContain("Live progress unavailable");
  });

  it("unsubscribes when removed", async () => {
    const element = await renderPanel();
    document.body.removeChild(element);
    expect(unsubscribe).toHaveBeenCalled();
  });
});

describe("c-demo-panel asynchronous runs", () => {
  const ASYNC_DEMO = {
    name: "Async_Chain_Break",
    label: "Silent Async Chain",
    description: "Queueables",
    defaultMode: "BEFORE",
    defaultVolume: 10,
    maxVolume: 100,
    hasSeeder: true,
    hasMonitor: true
  };

  beforeEach(() => {
    // Fake the watchdog interval and Date only; flushPromises keeps a real setTimeout.
    jest.useFakeTimers({
      doNotFake: ["setTimeout", "queueMicrotask", "nextTick"]
    });
    getRecentRuns.mockResolvedValue([]);
    getLimits.mockResolvedValue(LIMITS);
    runDemo.mockImplementation((request) =>
      Promise.resolve({
        runKey: request.runKey,
        status: "Running",
        result: { pending: true, recordsProcessed: 10, failedRows: [] },
        metrics: {}
      })
    );
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  async function startAsyncRun(demo = ASYNC_DEMO) {
    const element = createElement("c-demo-panel", { is: DemoPanel });
    document.body.appendChild(element);
    getDemos.emit([demo]);
    await flushPromises();
    button(element, "BEFORE").click();
    await flushPromises();
    return { element, request: runDemo.mock.calls[0][0] };
  }

  function grid(element) {
    return element.shadowRoot.querySelector('[data-id="row-grid"]');
  }

  it("lights rows as jobs report them and closes a silent run as stuck", async () => {
    monitorRun.mockResolvedValue({
      status: "Failed",
      errorMessage: "Detected by monitoring: 3 lines stuck",
      result: { failedRows: [3, 4, 5] }
    });
    const { element, request } = await startAsyncRun();

    jestMockPublish(
      CHANNEL,
      stepMessage(request.runKey, "STEP", { Rows_Done__c: "2,1" })
    );
    await flushPromises();
    expect(grid(element).doneRows).toEqual([1, 2]);
    expect(monitorRun).not.toHaveBeenCalled();

    jest.advanceTimersByTime(IDLE_MS + 5000);
    await flushPromises();

    expect(monitorRun).toHaveBeenCalledWith(request);
    expect(grid(element).status).toBe("Failed");
    expect(grid(element).failedRows).toEqual([3, 4, 5]);
    expect(
      element.shadowRoot.querySelector('[data-id="run-error"]').textContent
    ).toContain("Detected by monitoring");

    jest.advanceTimersByTime(IDLE_MS * 3);
    await flushPromises();
    expect(monitorRun).toHaveBeenCalledTimes(1);
  });

  it("keeps watching while jobs run and stops once a job closes the run", async () => {
    monitorRun.mockResolvedValue({
      status: "Running",
      result: { pending: true }
    });
    const { element, request } = await startAsyncRun();

    jest.advanceTimersByTime(IDLE_MS + 5000);
    await flushPromises();
    jest.advanceTimersByTime(IDLE_MS + 5000);
    await flushPromises();
    expect(monitorRun).toHaveBeenCalledTimes(2);

    jestMockPublish(
      CHANNEL,
      stepMessage(request.runKey, "SUCCEEDED", { Rows_Failed__c: "6,7" })
    );
    await flushPromises();
    jest.advanceTimersByTime(IDLE_MS * 3);
    await flushPromises();

    expect(monitorRun).toHaveBeenCalledTimes(2);
    expect(grid(element).status).toBe("Succeeded");
    expect(grid(element).failedRows).toEqual([6, 7]);
  });

  it("keeps the outcome published by jobs that finished before the response", async () => {
    let resolveRun;
    runDemo.mockImplementation(
      () => new Promise((resolve) => (resolveRun = resolve))
    );
    const element = createElement("c-demo-panel", { is: DemoPanel });
    document.body.appendChild(element);
    getDemos.emit([ASYNC_DEMO]);
    await flushPromises();
    button(element, "AFTER").click();
    await flushPromises();
    const { runKey } = runDemo.mock.calls[0][0];

    jestMockPublish(CHANNEL, stepMessage(runKey, "SUCCEEDED"));
    resolveRun({
      runKey,
      status: "Running",
      result: { pending: true },
      metrics: {}
    });
    await flushPromises();
    jest.advanceTimersByTime(IDLE_MS * 3);
    await flushPromises();

    expect(
      element.shadowRoot.querySelector('[data-id="run-status"]').textContent
    ).toBe("Succeeded");
    expect(monitorRun).not.toHaveBeenCalled();
  });

  it("reports a monitoring error and stops watching", async () => {
    monitorRun.mockRejectedValue({ body: { message: "No order found" } });
    const { element } = await startAsyncRun();

    jest.advanceTimersByTime(IDLE_MS + 5000);
    await flushPromises();
    jest.advanceTimersByTime(IDLE_MS * 3);
    await flushPromises();

    expect(monitorRun).toHaveBeenCalledTimes(1);
    expect(
      element.shadowRoot.querySelector('[data-id="run-error"]').textContent
    ).toBe("Monitoring failed: No order found");
  });

  it("does not watch demos without monitor", async () => {
    await startAsyncRun({ ...ASYNC_DEMO, hasMonitor: false });

    jest.advanceTimersByTime(IDLE_MS * 3);
    await flushPromises();

    expect(monitorRun).not.toHaveBeenCalled();
  });
});

describe("c-demo-panel race", () => {
  const RACE_DEMO = {
    name: "Batch_Filter",
    label: "Batch Filter",
    description: "Batch",
    defaultMode: "BEFORE",
    defaultVolume: 500,
    maxVolume: 1000,
    hasSeeder: true,
    hasMonitor: false,
    supportsRace: true
  };

  beforeEach(() => {
    jest.useFakeTimers({
      doNotFake: ["setTimeout", "queueMicrotask", "nextTick"]
    });
    getRecentRuns.mockResolvedValue([]);
    getLimits.mockResolvedValue(LIMITS);
    runDemo.mockImplementation((request) =>
      Promise.resolve({
        runKey: request.runKey,
        status: "Running",
        result: { pending: true },
        metrics: {}
      })
    );
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  async function startRace() {
    const element = createElement("c-demo-panel", { is: DemoPanel });
    document.body.appendChild(element);
    getDemos.emit([RACE_DEMO, DEMOS[0]]);
    await flushPromises();
    element.shadowRoot.querySelector('[data-id="race-button"]').click();
    await flushPromises();
    const keys = Object.fromEntries(
      runDemo.mock.calls.map(([request]) => [request.mode, request.runKey])
    );
    return { element, keys };
  }

  function lanes(element) {
    return element.shadowRoot.querySelector('[data-id="race-lanes"]').lanes;
  }

  it("offers the race only on demos that support it", async () => {
    const element = createElement("c-demo-panel", { is: DemoPanel });
    document.body.appendChild(element);
    getDemos.emit([RACE_DEMO, DEMOS[0]]);
    await flushPromises();

    expect(
      element.shadowRoot.querySelectorAll('[data-id="race-button"]')
    ).toHaveLength(1);
  });

  it("runs both modes at once and races them live", async () => {
    const { element, keys } = await startRace();

    expect(runDemo).toHaveBeenCalledTimes(2);
    expect(runDemo.mock.calls.map(([request]) => request.mode)).toEqual([
      "BEFORE",
      "AFTER"
    ]);
    expect(keys.BEFORE).not.toBe(keys.AFTER);
    expect(lanes(element).map((lane) => lane.status)).toEqual([
      "Running",
      "Running"
    ]);

    jest.advanceTimersByTime(2000);
    jestMockPublish(
      CHANNEL,
      stepMessage(keys.BEFORE, "STEP", { Records_Processed__c: 25 })
    );
    jestMockPublish(
      CHANNEL,
      stepMessage(keys.AFTER, "SUCCEEDED", {
        Records_Processed__c: 500,
        Async_Executions__c: 1,
        Message__c: "1 execution(s), 25 notice(s) sent"
      })
    );
    jestMockPublish(CHANNEL, stepMessage("unknown-run-key", "STEP"));
    await flushPromises();

    let [before, after] = lanes(element);
    expect(before.processed).toBe(25);
    expect(before.status).toBe("Running");
    expect(after.status).toBe("Succeeded");
    expect(after.executions).toBe(1);
    expect(after.elapsedMs).toBe(2000);

    jest.advanceTimersByTime(8000);
    await flushPromises();
    [before, after] = lanes(element);
    expect(before.elapsedMs).toBe(10000);
    // A finished lane keeps its time.
    expect(after.elapsedMs).toBe(2000);

    jestMockPublish(
      CHANNEL,
      stepMessage(keys.BEFORE, "SUCCEEDED", {
        Records_Processed__c: 500,
        Async_Executions__c: 500
      })
    );
    jestMockPublish(CHANNEL, stepMessage(keys.BEFORE, "FAILED"));
    await flushPromises();
    [before] = lanes(element);
    // The first terminal event wins.
    expect(before.status).toBe("Succeeded");
    expect(before.executions).toBe(500);
  });

  it("shows a lane that could not start as failed", async () => {
    runDemo.mockImplementation((request) => {
      if (request.mode === "BEFORE") {
        return Promise.reject({
          body: { message: "The previous BEFORE batch is still running" }
        });
      }
      return Promise.resolve({
        runKey: request.runKey,
        status: "Failed",
        errorMessage: "Chaos injected"
      });
    });
    const { element } = await startRace();

    const [before, after] = lanes(element);
    expect(before.status).toBe("Failed");
    expect(before.message).toContain("still running");
    expect(after.status).toBe("Failed");
    expect(after.message).toBe("Chaos injected");
  });

  it("leaves the race view when a single run starts", async () => {
    const { element } = await startRace();

    element.shadowRoot
      .querySelectorAll('lightning-button[data-mode="AFTER"]')[1]
      .click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector('[data-id="race-lanes"]')
    ).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="run-status"]')
    ).not.toBeNull();
  });
});

describe("demoPanel helpers", () => {
  it("parses the rows carried by a step", () => {
    expect(parseRows("3, 4,5")).toEqual([3, 4, 5]);
    expect(parseRows(undefined)).toEqual([]);
    expect(parseRows("x,0,-1,2")).toEqual([2]);
  });

  it("summarizes errors to their first line, shortened", () => {
    expect(summarizeError(undefined)).toBe("");
    expect(summarizeError("first\r\nsecond")).toBe("first");
    const long = summarizeError("x".repeat(400));
    expect(long).toHaveLength(160);
    expect(long.endsWith("…")).toBe(true);
  });

  it("extracts the breached limit reported by the platform", () => {
    expect(extractLimitBreach("Too many DML statements: 151")).toEqual({
      field: "dmlStatements",
      value: 151
    });
    expect(extractLimitBreach("Too many DML rows: 10001")).toEqual({
      field: "dmlRows",
      value: 10001
    });
    expect(extractLimitBreach("Apex CPU time limit exceeded")).toBeNull();
    expect(extractLimitBreach(undefined)).toBeNull();
  });

  it("reduces every error shape to a message", () => {
    expect(reduceError(undefined)).toBe("Unknown error");
    expect(reduceError({ body: [{ message: "a" }, { message: "b" }] })).toBe(
      "a, b"
    );
    expect(reduceError({ body: { message: "body" } })).toBe("body");
    expect(reduceError(new Error("plain"))).toBe("plain");
    expect(reduceError("text")).toBe("text");
  });
});
