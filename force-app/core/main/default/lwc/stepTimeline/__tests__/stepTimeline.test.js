import { createElement } from "lwc";
import StepTimeline from "c/stepTimeline";

function render(props) {
  const element = createElement("c-step-timeline", { is: StepTimeline });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

describe("c-step-timeline", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows the empty text without steps", () => {
    const element = render({ steps: null, emptyText: "Nothing yet" });
    expect(
      element.shadowRoot.querySelector('[data-id="empty"]').textContent
    ).toBe("Nothing yet");
  });

  it("orders steps by sequence and keeps uncaught failures last", () => {
    const element = render({
      label: "Run",
      steps: [
        {
          phase: "FAILED",
          label: "Failed (uncaught)",
          sequence: null,
          message: "Too many SOQL queries: 101"
        },
        {
          phase: "STEP",
          label: "Iteration 10",
          sequence: 2,
          soqlQueries: 10,
          dmlStatements: 0,
          cpuTimeMs: 12,
          recordsProcessed: 10
        },
        { phase: "START", label: "Started", sequence: 1 }
      ]
    });
    const items = element.shadowRoot.querySelectorAll('[data-id="step"]');
    expect(items).toHaveLength(3);
    expect(items[0].textContent).toContain("Started");
    expect(items[1].textContent).toContain(
      "SOQL 10 · DML 0 · CPU 12 ms · 10 records"
    );
    expect(items[2].classList).toContain("timeline__item_failed");
    expect(items[2].textContent).toContain("Too many SOQL queries: 101");
    expect(items[2].querySelector("lightning-icon").iconName).toBe(
      "utility:error"
    );
    expect(
      element.shadowRoot.querySelector("ol").getAttribute("aria-label")
    ).toBe("Run");
  });

  it("falls back to a step icon for unknown phases", () => {
    const element = render({ steps: [{ label: "Odd", sequence: 1 }] });
    expect(element.shadowRoot.querySelector("lightning-icon").iconName).toBe(
      "utility:record"
    );
  });
});
