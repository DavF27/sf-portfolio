import { createElement } from "lwc";
import DemoPanel, {
  CHANNEL,
  extractLimitBreach,
  reduceError
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
    expect(
      element.shadowRoot.querySelector('[data-id="runs-table"]').data
    ).toEqual(RUNS);
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
      result: { recordsProcessed: 50, recordsFailed: 0 }
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
    expect(element.shadowRoot.querySelector("c-progress-bar").failed).toBe(
      true
    );
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

describe("demoPanel helpers", () => {
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
