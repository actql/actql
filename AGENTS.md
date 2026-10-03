# Repository conventions

- Keep `docs/design` focused on architecture, semantic decisions and contract
  boundaries. Do not put branch handoffs, cherry-pick instructions, delivery
  status or test-run reports there. Report those in the working conversation
  and commit history instead.

- The specification and pinned machine contracts are authoritative. Reference
  implementations are implementation material, not an immutable version authority.
- Before proposing acceptance changes or resolving an unspecified edge case,
  follow [Semantic decision criteria](docs/design/semantic-decisions.md).
  Separate existing requirements, conflicting evidence and new decisions. Do
  not turn a reference implementation limitation or a lint preference into a
  language restriction. When the user delegates specification decisions, resolve
  ambiguities using these criteria, document the rationale and compatibility
  impact, and proceed with the recommended contract. Otherwise obtain agreement
  before changing the contract. Delegation does not expand implementation scope
  or authorize destructive/external actions.
- Owned specifications, machine contracts and identity domains use the current
  initial 0.1 baseline, including AoA contracts (`/0.1`) and versioned AoA law
  identifiers (`.v0.1`). Follow each contract's declared identifier syntax;
  do not import a different version merely because reference code uses it.
- Where an identifier is part of a canonical preimage, update dependent bodies,
  CIDs, schema pins, metadata and independent fixtures together, then run
  `npm run check:spec` and the three-target MoonBit checks. Never retain an old
  CID for a renamed body or compute expected fixtures from product output.
- Package release versions are independent of contract versions. External
  standards, dependencies and toolchains retain their selected versions and
  pins. See [Versioning policy](docs/design/versioning.md).
- Future version changes require an explicit decision and coordinated updates
  to the applicable checks. Do not rewrite published history without explicit approval.

## Local verification

Linux CI on the pushed SHA is the complete check. Locally, verify in tiers
and run only what the change can affect; do not rerun whole suites by
default.

1. While editing: the narrowest check that can fail. `node --check` or
   `node --test <file> [--test-name-pattern]`, `moon check --target js
   <package dir>`, `moon test --target js -p <package>` or one test file.
2. Before a commit: the tests of the touched files and packages, `git diff
   --check`, and `moon fmt --check` when MoonBit changed.
   `node scripts/local-checks.mjs changed` lists these for the current diff.
3. Before a push or handoff: the CI jobs for the touched areas, with
   `node scripts/local-checks.mjs run <job>`. Known full-suite/build jobs
   require a deliberate `--allow-heavy`; prefer the focused checks or hosted CI.
   It runs the same commands as
   that job in `.github/workflows/ci.yml`. Run `core` for wasm and native
   (`--target`) only when shared MoonBit core changed; canonical identifier
   changes keep the rule above (`check:spec` and all three targets).
   Run `node scripts/check-moonbit-api.mjs` when a public MoonBit interface
   changed.
4. Push, then read the CI result for that SHA (a pull request, or
   `gh workflow run CI --ref <branch>` for a working branch). A local run
   does not replace it.

`npm run check:spec` checks specifications and machine contracts: the
version gate, schemas and pins, generated artifacts, Connector boundaries,
coverage inventories, documented examples and links (about a minute locally
with a warm build). Run it when those change, not for a code-only change
covered by another job.

Build hygiene:

- Keep `_build`; MoonBit builds are incremental. Remove it only to verify a
  final SHA from a clean state or when a stale artifact is suspected.
- Never run two gates at once in the same worktree, and do not merge,
  switch branches or edit a worktree while a gate runs there; the results
  would mix states. Run one heavy gate at a time per machine and note load
  when judging timing-sensitive failures.
- Route local test/build work through `scripts/local-checks.mjs` for worktree
  exclusion and a time budget. Full Moon test/build calls need both
  `--allow-heavy` and `--timeout-seconds`; job budgets default to the workflow.
  Never treat `--allow-heavy` as human approval. Raw commands are not protected.
- Optional personal Claude Code and local Codex hooks only classify commands;
  they never run tests. See [local hooks](docs/local-checks-hooks.md) and
  [execution limits](docs/development.md#bounded-local-execution). No hook is
  installed or mandatory for contributors.
- Report the commands that ran and the gates that did not.

## Runtime package artifacts

Compiled JavaScript under `packages/local-node/_build` and the `dist`
directories of `run-host-core`, `coordinator-core`, and `transfer-core` is
ignored, not committed. After changing MoonBit sources or merging another
branch, run `npm run build:runtime-packages` before importing those packages
directly. An optional package name limits the build, for example
`npm run build:runtime-packages -- local-node`. The related npm checks prepare
their runtime dependencies automatically.

`npm pack` in each runtime package builds its payload through `prepack`;
use the pinned MoonBit toolchain and root npm dependencies. Do not use
`--ignore-scripts` when producing tarballs. Consumers may install the resulting
tarballs with `--ignore-scripts` and need no MoonBit toolchain. Generated API
interfaces, schema/pins, fixtures, and the tracked Run Host service wrappers
remain reviewed source artifacts. Regenerate wrapper changes explicitly;
runtime preparation checks them but does not silently update them.
