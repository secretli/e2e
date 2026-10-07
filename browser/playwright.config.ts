import { defineConfig } from "@playwright/test";

// The command-line client and the web app against the same Secretli: links
// and codes in both directions. The web app's own flows are tested in
// secretli/web. Every test makes its own secrets, and the stack's server has
// raised rate limits, so the tests run in parallel.
export default defineConfig({
  testDir: ".",
  timeout: 30000,
  retries: 0,
  fullyParallel: true,
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL ?? "http://localhost:8080",
    headless: true,
  },
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
});
