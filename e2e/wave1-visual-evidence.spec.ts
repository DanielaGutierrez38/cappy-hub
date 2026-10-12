import { expect, test, type Page, type TestInfo } from "@playwright/test";

const widths = [1024, 1280, 1440, 1920];
const themes = ["dark", "light"] as const;

async function signIn(page: Page, account: string) {
  await page.goto("/login");
  await page.getByRole("button", { name: account, exact: true }).click();
  await expect(page).toHaveURL((url) => url.pathname === "/");
}

async function setTheme(page: Page, theme: (typeof themes)[number]) {
  const current = await page.locator("html").getAttribute("data-theme");
  if (current !== theme) {
    const label =
      theme === "light" ? "Switch to light theme" : "Switch to dark theme";
    await page.getByRole("button", { name: label }).click();
  }
  await expect(page.locator("html")).toHaveAttribute("data-theme", theme);
}

async function captureWidths(
  page: Page,
  testInfo: TestInfo,
  name: string,
  fullPage = false,
) {
  for (const theme of themes) {
    await setTheme(page, theme);
    for (const width of widths) {
      await page.setViewportSize({ width, height: 1100 });
      await expect
        .poll(() =>
          page.evaluate(
            () => document.documentElement.scrollWidth <= window.innerWidth,
          ),
        )
        .toBe(true);
      await page.screenshot({
        path: testInfo.outputPath(
          `visual-captures/${name}-${width}-${theme}.png`,
        ),
        fullPage,
      });
    }
  }
}

test("Wave 1 header: Admin navigation at all supported widths and themes", async ({
  page,
}, testInfo) => {
  await signIn(page, "Admin");
  await page.goto("/events");
  const navigation = page.getByRole("navigation", { name: "Main navigation" });
  await expect(
    navigation.getByRole("link", { name: "Admin", exact: true }),
  ).toBeVisible();
  await captureWidths(page, testInfo, "header-admin");
});

test("Wave 1 header: Officer navigation preserves role visibility", async ({
  page,
}, testInfo) => {
  await signIn(page, "Officer");
  await page.goto("/events");
  const navigation = page.getByRole("navigation", { name: "Main navigation" });
  await expect(
    navigation.getByRole("link", { name: "Events", exact: true }),
  ).toBeVisible();
  await expect(
    navigation.getByRole("link", { name: "Admin", exact: true }),
  ).toHaveCount(0);
  await captureWidths(page, testInfo, "header-officer");
});

test("Wave 1 Task assignment: capture manager detail and on-demand dialog", async ({
  page,
}, testInfo) => {
  await signIn(page, "Admin");
  await page.goto("/tasks/-8002");
  const trigger = page.getByRole("button", {
    name: "Add officers",
    exact: true,
  });
  if (!(await trigger.isVisible().catch(() => false))) {
    test.skip(
      true,
      "This branch does not contain the Wave 1 Task assignment UI.",
    );
  }

  const dialog = page.getByRole("dialog", {
    name: "Add officers to this task",
  });
  for (const theme of themes) {
    await setTheme(page, theme);
    for (const width of widths) {
      await page.setViewportSize({ width, height: 1100 });
      await expect(
        page.getByRole("region", { name: "Officers" }),
      ).toBeVisible();
      await page.screenshot({
        path: testInfo.outputPath(
          `visual-captures/task-manager-${width}-${theme}.png`,
        ),
        fullPage: true,
      });

      await trigger.click();
      await expect(dialog).toBeVisible();
      const firstCheckbox = dialog.getByRole("checkbox").first();
      await expect(firstCheckbox).toBeFocused();
      await page.screenshot({
        path: testInfo.outputPath(
          `visual-captures/task-assignment-dialog-${width}-${theme}.png`,
        ),
      });
      await page.keyboard.press("Escape");
      await expect(dialog).toBeHidden();
      await expect(trigger).toBeFocused();
    }
  }
});

test("Wave 1 Task detail: capture the unassigned Officer view", async ({
  page,
}, testInfo) => {
  await signIn(page, "Officer");
  await page.goto("/tasks/-8002");
  await expect(
    page.getByRole("heading", { name: "Write LinkedIn recap" }),
  ).toBeVisible();
  await expect(page.getByRole("region", { name: "Officers" })).toContainText(
    "Your assignment: Not assigned",
  );
  await expect(
    page.getByRole("button", { name: "Assign this task to me" }),
  ).toBeVisible();
  await expect(page.getByRole("button", { name: "Add officers" })).toHaveCount(
    0,
  );
  await captureWidths(page, testInfo, "task-officer-unassigned", true);
});

test("Wave 1 Event forms: capture create, edit, and recurring schedule states", async ({
  page,
}, testInfo) => {
  await signIn(page, "Admin");

  for (const [route, name] of [
    ["/events/new", "event-create"],
    ["/events/-2011/edit", "event-edit"],
  ] as const) {
    await page.goto(route);
    await expect(
      page.getByRole("heading", { name: /event/i }).first(),
    ).toBeVisible();
    await page
      .getByLabel("Description")
      .fill("Synthetic long-content browser evidence. ".repeat(24));
    await captureWidths(page, testInfo, name, true);

    const nameField = page.getByLabel("Name");
    const descriptionField = page.getByLabel("Description");
    await setTheme(page, "dark");
    await page.setViewportSize({ width: 1440, height: 1100 });
    await nameField.focus();
    await page.keyboard.press("Tab");
    await expect(descriptionField).toBeFocused();
    await page.screenshot({
      path: testInfo.outputPath(
        `visual-captures/${name}-keyboard-focus-1440-dark.png`,
      ),
    });

    if (name === "event-create") {
      await page.getByRole("button", { name: "Create event" }).click();
      await expect(nameField).toBeFocused();
      await expect(nameField).toHaveJSProperty("validity.valid", false);
      await page.screenshot({
        path: testInfo.outputPath(
          "visual-captures/event-create-required-validation-1440-dark.png",
        ),
      });
    }

    await page
      .locator('select[name="recurrence_frequency"]')
      .selectOption("weekly");
    await page.locator('input[name="recurrence_weekdays"][value="MO"]').check();
    await expect(
      page.getByRole("region", { name: "Schedule preview" }),
    ).toBeVisible();
    await captureWidths(page, testInfo, `${name}-weekly`, true);
  }
});

test("Wave 1 Event form: capture branch manager access", async ({
  page,
}, testInfo) => {
  await signIn(page, "VP Operations");
  await page.goto("/events/new");
  await expect(page.getByRole("heading", { name: "New event" })).toBeVisible();
  await captureWidths(page, testInfo, "event-create-vp-operations", true);
});
