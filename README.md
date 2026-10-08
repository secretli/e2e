# Secretli end-to-end

Tests of the whole of [Secretli](https://secretli.app): the [server](https://github.com/secretli/server) and the [web app](https://github.com/secretli/web) behind a gateway that routes like production, used by both clients, the browser and the [command-line client](https://github.com/secretli/cli). Each of those repositories tests itself; this one tests how they work together.

## What it checks

- **Routing** (`stack/routing-checks.sh`): one origin, where `/api/` reaches the server and everything else the web app.
- **Command-line journeys** (`cli/journeys.sh`): share, look, open and delete secrets, with and without a password, a 40 MiB upload in several parts, and handing a link over with a code, checking every answer and exit code. It also runs with older client releases, to check that the server still works with what people have installed: flags a release does not know are left out, and journeys it cannot make are skipped.
- **The client and the browser together** (`browser/`): links made by one open in the other, pasted or handed over with a code.
- **Production** (`smoke/smoke.sh`): health, the version and the routing of a deployed Secretli, and that each address its name resolves to answers; optionally also a secret that expires after five minutes and a handover with a code.

The web app's own flows, the server's API and the client's commands are tested in their repositories.

## Running it locally

Docker, Node 24 with pnpm 10, and a `secretli` binary:

```bash
stack/stack.sh up                               # the latest published images, on http://localhost:8080
stack/routing-checks.sh
SECRETLI_CLI="$(command -v secretli)" cli/journeys.sh
(cd browser && pnpm install && SECRETLI_CLI="$(command -v secretli)" pnpm test)
stack/stack.sh down
```

`WEB_IMAGE` and `SERVER_IMAGE` replace a published image with another, such as one built from a checkout:

```bash
docker build -t secretli-server:local ../server
SERVER_IMAGE=secretli-server:local stack/stack.sh up
```

Every test comes from one address, so the stack's server runs with raised rate limits (`RATE_LIMIT_MULTIPLIER`, 100 by default); production leaves that unset.

## In CI

- **Whole setup** (`.github/workflows/whole-setup.yml`) runs on every change here and nightly, against everything at main. The component repositories call it with their own change in place of one published part:

  ```yaml
  whole-setup:
    uses: secretli/e2e/.github/workflows/whole-setup.yml@main
    with:
      server_ref: ${{ github.event.pull_request.head.sha || github.sha }}
  ```

  `server_ref` and `web_ref` build that component at the ref instead of pulling its image, and `cli_ref` builds the client instead of installing its latest release. Only the latest client is supported, so the journeys run with that one alone.
- **Smoke** (`.github/workflows/smoke.yml`) checks secretli.app after every deploy, every hour and on demand. Flux announces each Secretli deploy once it is rolled out and healthy (or, for a deploy that only deletes something, once it has deleted it), as a `repository_dispatch` event (set up in pscheid92/k8s, `apps/secretli/deploy-notifications.yaml`); a deploy Flux reports as failed fails a run here, so it gets noticed. The smoke test checks health, the version and the routing, that every address of secretli.app answers, and shares and opens a secret that expires after five minutes and hands a link over with a code. `create_secrets: false` checks without writing to the server.
- **CI** runs shellcheck on the scripts.

Every repository's checks depend on this one's main branch, so changes here go through a pull request whose own run of the whole setup must pass first.

## License

[MIT](LICENSE)
