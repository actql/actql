---
name: actql-local-verification
description: Select and run focused local checks for ActQL OSS changes, including MoonBit core tests and Node SDK, adapter, or script tests. Use before local test/build work or verification handoff; excludes ActQL Cloud operations, deployment, and release publishing.
---

# ActQL local verification

Work from the repository root. Use the checked-in toolchain, dependency and CI
pins; do not maintain another version table here.

## Select the smallest meaningful check

1. Inspect the diff and relevant package/test imports.
   `node scripts/local-checks.mjs changed` offers candidates, not complete
   reverse-dependent coverage or a requirement to run its listed CI jobs.
2. For shared MoonBit core, select the affected package or test file on JS.
   Prefer an explicit package path over a fuzzy `-p` name. Add affected caller
   tests when shared behavior or interfaces change; do not treat compiled
   dependencies as executed tests.
3. For SDK, adapters and scripts, select their Node tests. A changed MoonBit
   runtime may also need a focused consuming boundary test.
4. For native-only packages, C FFI or target-specific failures, choose that
   backend explicitly and read
   [Target-specific diagnostics](../../../docs/development.md#target-specific-diagnostics).
   Do not report JS tests as coverage of a native-only implementation.

Examples; replace the package/file with the actual selection:

```sh
node scripts/local-checks.mjs test moon -- --target js src/execution_relation
node scripts/local-checks.mjs test node -- scripts/packed-client-packages.test.mjs
```

A name filter narrows test execution, not necessarily compilation. Keep the
existing nonzero-test guard: zero discovery, unmatched or skip-only selections
are not a pass. For supported filters and evidence, read
[Focused test execution](../../../docs/development.md#focused-test-execution).

For specification, canonical identity or generated-contract changes, select the
relevant validators as well as affected tests. Preserve the specification and
cross-target CI obligations in [AGENTS.md](../../../AGENTS.md).

## Prepare only the boundary being tested

- Before directly importing changed runtime packages, read
  [Runtime package artifacts](../../../docs/development.md#runtime-package-artifacts).
  Select only needed packages; related npm checks already prepare dependencies.
- Only when packed acceptance is needed, read
  [Client package reuse](../../../docs/ci-client.md#local-and-hosted-verification).
  Reuse verified tarballs across multiple consumers of the same clean HEAD;
  preserve private installations. Do not commit/stash changes just to obtain
  reuse, edit the manifest to hide a mismatch, or skip producer prepack.
- Full Core, all-target, proof, packed and performance suites are not defaults.
  For an explicit broader diagnostic, inspect the actual job and
  [execution limits](../../../docs/development.md#bounded-local-execution).
  `--allow-heavy` does not grant approval, and CI-only wrappers stay CI-only.

## Finish

Run `git diff --check` and check formatting for changed MoonBit files. Keep
incremental builds and avoid concurrent gates or edits in a running gate's
worktree. Report commands, actual test counts and unverified coverage separately.
A local or selected PR check does not replace full main CI.
