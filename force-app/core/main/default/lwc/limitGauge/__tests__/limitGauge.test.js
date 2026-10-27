import { createElement } from "lwc";
import LimitGauge from "c/limitGauge";

function render(props) {
  const element = createElement("c-limit-gauge", { is: LimitGauge });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

describe("c-limit-gauge", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders value, max and accessible meter attributes", () => {
    const element = render({ label: "SOQL", value: 20, max: 100 });
    const meter = element.shadowRoot.querySelector('[role="meter"]');
    expect(meter.getAttribute("aria-label")).toBe("SOQL");
    expect(meter.getAttribute("aria-valuenow")).toBe("20");
    expect(meter.getAttribute("aria-valuemax")).toBe("100");
    expect(meter.getAttribute("aria-valuetext")).toBe("SOQL: 20 of 100");
    expect(
      element.shadowRoot.querySelector('[data-id="value"]').textContent
    ).toBe("20");
    expect(
      element.shadowRoot
        .querySelector(".gauge__arc")
        .getAttribute("stroke-dasharray")
    ).toBe("20 100");
  });

  it.each([
    [10, "gauge__arc_success"],
    [70, "gauge__arc_warning"],
    [101, "gauge__arc_error"]
  ])("value %i out of 100 uses %s", (value, expectedClass) => {
    const element = render({ label: "SOQL", value, max: 100 });
    expect(element.shadowRoot.querySelector(".gauge__arc").classList).toContain(
      expectedClass
    );
  });

  it("caps the arc at 100 % and guards invalid inputs", () => {
    const over = render({ label: "CPU", value: 250, max: 100 });
    expect(
      over.shadowRoot
        .querySelector(".gauge__arc")
        .getAttribute("stroke-dasharray")
    ).toBe("100 100");

    const invalid = render({ label: "DML", value: "abc", max: 0 });
    const meter = invalid.shadowRoot.querySelector('[role="meter"]');
    expect(meter.getAttribute("aria-valuenow")).toBe("0");
    expect(meter.getAttribute("aria-valuemax")).toBe("1");
  });
});
