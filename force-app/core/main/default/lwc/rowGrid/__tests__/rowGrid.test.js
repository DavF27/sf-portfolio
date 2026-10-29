import { createElement } from "lwc";
import RowGrid from "c/rowGrid";

function render(props) {
  const element = createElement("c-row-grid", { is: RowGrid });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

function states(element) {
  return Array.from(element.shadowRoot.querySelectorAll(".grid__tile")).map(
    (tile) => tile.className.replace("grid__tile grid__tile_", "")
  );
}

function summary(element) {
  return element.shadowRoot
    .querySelector('[data-id="summary"]')
    .textContent.trim();
}

describe("c-row-grid", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("lights up processed rows while running", () => {
    const element = render({
      label: "Rows",
      total: 5,
      processed: 2,
      status: "Running"
    });
    expect(states(element)).toEqual([
      "processing",
      "processing",
      "pending",
      "pending",
      "pending"
    ]);
    expect(summary(element)).toBe("Rows: 2 of 5 processed");
  });

  it("turns rows green except the failed ones", () => {
    const element = render({
      label: "Rows",
      total: 4,
      status: "Succeeded",
      failedRows: [3]
    });
    expect(states(element)).toEqual([
      "succeeded",
      "succeeded",
      "failed",
      "succeeded"
    ]);
    expect(summary(element)).toBe("Rows: 3 succeeded, 1 failed");
    expect(
      element.shadowRoot
        .querySelector('[role="img"]')
        .getAttribute("aria-label")
    ).toBe("Rows: 3 succeeded, 1 failed");
  });

  it("turns every row red when the whole batch was rolled back", () => {
    const element = render({
      label: "Rows",
      total: 3,
      processed: 2,
      status: "Failed"
    });
    expect(states(element)).toEqual(["failed", "failed", "failed"]);
    expect(summary(element)).toBe(
      "Rows: all 3 failed, the whole batch was rolled back"
    );
  });

  it("guards invalid inputs and caps the number of tiles", () => {
    const empty = render({ total: "abc", failedRows: null, processed: null });
    expect(states(empty)).toEqual([]);
    expect(summary(empty)).toBe("Rows: 0 of 0 processed");

    const huge = render({ total: 10000, status: "Succeeded" });
    expect(states(huge)).toHaveLength(500);
  });
});
