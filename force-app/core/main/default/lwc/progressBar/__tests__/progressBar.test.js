import { createElement } from "lwc";
import ProgressBar from "c/progressBar";

function render(props) {
  const element = createElement("c-progress-bar", { is: ProgressBar });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

describe("c-progress-bar", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows partial progress with an accessible progressbar", () => {
    const element = render({ label: "Records", value: 25, max: 50 });
    const bar = element.shadowRoot.querySelector('[role="progressbar"]');
    expect(bar.getAttribute("aria-label")).toBe("Records");
    expect(bar.getAttribute("aria-valuenow")).toBe("25");
    expect(
      element.shadowRoot.querySelector('[data-id="count"]').textContent
    ).toBe("25 / 50");
    const fill = element.shadowRoot.querySelector(".progress__bar");
    expect(fill.style.width).toBe("50%");
    expect(fill.classList).not.toContain("progress__bar_success");
  });

  it("turns green when complete and red when failed", () => {
    const complete = render({ label: "Records", value: 80, max: 50 });
    expect(
      complete.shadowRoot.querySelector(".progress__bar").classList
    ).toContain("progress__bar_success");

    const failed = render({
      label: "Records",
      value: 10,
      max: 50,
      failed: true
    });
    expect(
      failed.shadowRoot.querySelector(".progress__bar").classList
    ).toContain("progress__bar_error");
  });

  it("guards invalid inputs", () => {
    const element = render({ label: "Records", value: null, max: -3 });
    expect(
      element.shadowRoot.querySelector('[data-id="count"]').textContent
    ).toBe("0 / 1");
  });
});
