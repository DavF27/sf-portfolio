import { createElement } from "lwc";
import RaceLanes, { formatElapsed } from "c/raceLanes";

function render(lanes) {
  const element = createElement("c-race-lanes", { is: RaceLanes });
  element.lanes = lanes;
  document.body.appendChild(element);
  return element;
}

function lane(element, mode) {
  return element.shadowRoot.querySelector(
    `[data-id="lane"][data-mode="${mode}"]`
  );
}

describe("c-race-lanes", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows each lane's progress, elapsed time, executions and the winner", () => {
    const element = render([
      {
        key: "BEFORE",
        label: "BEFORE",
        subtitle: "Filter in Apex",
        status: "Running",
        processed: 120,
        total: 500,
        elapsedMs: 42000
      },
      {
        key: "AFTER",
        label: "AFTER",
        subtitle: "Filter in SOQL",
        status: "Succeeded",
        processed: 500,
        total: 500,
        elapsedMs: 3400,
        executions: 1,
        message: "1 execution(s), 25 notice(s) sent"
      }
    ]);

    const before = lane(element, "BEFORE");
    expect(before.getAttribute("aria-label")).toBe("BEFORE");
    expect(before.querySelector('[data-id="lane-elapsed"]').textContent).toBe(
      "42.0 s"
    );
    expect(
      before.querySelector('[data-id="lane-executions"]').textContent.trim()
    ).toBe("–");
    expect(before.querySelector('[data-id="lane-winner"]')).toBeNull();
    expect(before.querySelector("c-progress-bar").value).toBe(120);

    const after = lane(element, "AFTER");
    expect(after.querySelector('[data-id="lane-status"]').className).toContain(
      "slds-theme_success"
    );
    expect(
      after.querySelector('[data-id="lane-executions"]').textContent.trim()
    ).toBe("1");
    expect(after.querySelector('[data-id="lane-winner"]')).not.toBeNull();
    expect(
      after.querySelector('[data-id="lane-message"]').textContent
    ).toContain("25 notice(s)");
  });

  it("marks failed lanes and picks the fastest of several finishers", () => {
    const element = render([
      { key: "A", label: "A", status: "Succeeded", elapsedMs: 9000, total: 1 },
      { key: "B", label: "B", status: "Succeeded", elapsedMs: 2000, total: 1 },
      { key: "C", label: "C", status: "Failed", elapsedMs: 100, total: 1 }
    ]);

    expect(
      lane(element, "A").querySelector('[data-id="lane-winner"]')
    ).toBeNull();
    expect(
      lane(element, "B").querySelector('[data-id="lane-winner"]')
    ).not.toBeNull();
    expect(
      lane(element, "C").querySelector('[data-id="lane-status"]').className
    ).toContain("slds-theme_error");
    expect(lane(element, "C").querySelector("c-progress-bar").failed).toBe(
      true
    );
  });

  it("guards missing lanes and invalid durations", () => {
    const element = render(null);
    expect(
      element.shadowRoot.querySelectorAll('[data-id="lane"]')
    ).toHaveLength(0);
    expect(formatElapsed(undefined)).toBe("–");
    expect(formatElapsed(-5)).toBe("–");
    expect(formatElapsed(1250)).toBe("1.3 s");
  });
});
