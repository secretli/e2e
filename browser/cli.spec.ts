import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { expect, type Page, test } from "@playwright/test";

const run = promisify(execFile);

/**
 * The command-line client (secretli/cli) against the web app, both talking to
 * the same server: links made by one must open in the other, pasted or handed
 * over with a short code. SECRETLI_CLI points at a secretli binary; without
 * one these tests are skipped.
 */
const CLI = process.env.SECRETLI_CLI ?? "";

const CODE = /^\d{1,3}-[a-z]+-[a-z]+$/;

/** `secretli send` in the background: the code it prints, and how it ends. */
function startSend(link: string) {
  const child = spawn(CLI, ["send", link]);
  let stdout = "";
  let stderr = "";
  child.stderr.on("data", (chunk) => {
    stderr += chunk;
  });
  const exited = new Promise<number | null>((resolve) => child.on("exit", resolve));
  const code = new Promise<string>((resolve, reject) => {
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
      const end = stdout.indexOf("\n");
      if (end >= 0) resolve(stdout.slice(0, end));
    });
    exited.then((status) => reject(new Error(`send exited ${status} without a code: ${stderr}`)));
  });
  return { code, exited, stderr: () => stderr, stop: () => child.kill() };
}

async function reveal(page: Page, text: string) {
  await expect(page.locator("h1")).toHaveText("Someone sent you a secret", { timeout: 15000 });
  await page.getByRole("button", { name: /^Reveal/ }).click();
  await expect(page.locator("h1")).toHaveText("Here's your secret", { timeout: 10000 });
  await expect(page.locator("pre")).toHaveText(text);
}

test.describe("Command-line client", () => {
  test.skip(!CLI, "SECRETLI_CLI is not set");

  test("a link made by the CLI opens in the browser, pasted and handed over with a code", async ({
    page,
    baseURL,
  }) => {
    const text = `from the cli ${Date.now()}`;
    // Reusable, so that it opens twice: once pasted, once handed over.
    const { stdout } = await run(CLI, [
      "share",
      "-t",
      text,
      "-e",
      "5m",
      "--reusable",
      "-q",
      "--server",
      baseURL ?? "",
    ]);
    const link = stdout.trim();
    expect(link).toContain("/s#");

    await test.step("pasted", async () => {
      await page.goto(link);
      await reveal(page, text);
    });

    await test.step("handed over with secretli send", async () => {
      const sender = startSend(link);
      try {
        const code = await sender.code;
        expect(code).toMatch(CODE);

        await page.goto("/c");
        await page.getByLabel("Number").fill(code);
        await page.getByRole("button", { name: "Receive", exact: true }).click();
        await reveal(page, text);
        expect(await sender.exited).toBe(0);
        expect(sender.stderr()).toContain("/c and type the code");
        expect(sender.stderr()).toContain("Sent.");
      } finally {
        sender.stop();
      }
    });
  });

  test("a link made in the browser reaches the CLI with a code, and the owner link knows", async ({
    page,
    baseURL,
  }) => {
    const text = `from the browser ${Date.now()}`;
    await page.goto("/share");
    await page.fill("#secret-text", text);
    await page.click('button[type="submit"]');
    await expect(page.getByRole("heading", { name: "Your link is ready" })).toBeVisible({
      timeout: 10000,
    });
    await page.getByRole("button", { name: "Owner link" }).click();
    const ownerLink = (await page.getByTestId("owner-link").textContent()) ?? "";

    await page.getByRole("button", { name: "Send with a code" }).click();
    const shown = page.getByText(CODE);
    await expect(shown).toBeVisible({ timeout: 10000 });
    const code = (await shown.textContent()) ?? "";

    // Typed loosely, in parts. --yes, since a one-time secret is otherwise
    // asked about first. Piped: stdout is the text alone, exactly as shared.
    const received = await run(CLI, [
      "receive",
      ...code.split("-"),
      "--yes",
      "--server",
      baseURL ?? "",
    ]);
    expect(received.stdout).toBe(text);
    expect(received.stderr).toContain("A one-time text secret");
    await expect(page.getByText("Sent. The other device is opening the secret.")).toBeVisible();

    // The owner's status says it is gone, and exits 4. Servers that kept
    // what became of a secret said it was opened; now nothing is kept.
    const status = await run(CLI, ["status", ownerLink]).catch((err) => err);
    expect(status.code).toBe(4);
    expect(status.stdout).toMatch(/Your secret was opened|This secret is gone/);
  });
});
