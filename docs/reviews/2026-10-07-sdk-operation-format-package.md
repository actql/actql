# SDK operation-format module: distribution closure repair

Base: main `e3c85c7b7b7a98e94ebe919764e05225f83d8dd9`.
`packages/sdk/index.mjs` imports `operation-formats.mjs`, but the SDK package's
explicit files list omitted it. A normal tarball therefore cannot resolve the
SDK's own entry module. No diagnostic or SDK response implementation is changed.

Found while normally packing Frontend source
`51d7a5e4b860ecd11938d005621441bb796c96a0`, whose SDK sources match that main.
SDK tarball digest:
`d9c1b34df5eb6e2de012f135c79a6df14b960878b2f32b1ae6097299aa5a4d9e`.
The unchanged packed public-query runner failed before Host execution with
`Could not resolve "./operation-formats.mjs"`. Evidence:
`worktrees/.codex-scratch/public-query-evidence-WxksIZ/summary.json` retains
failed status and exact tarball evidence; the module audit's exception occurred
outside a captured child command. The executable regression below retains the
concrete missing-module diagnostic in its focused-test output.

[B's ownership handoff](https://github.com/actql/actql/pull/679#issuecomment-6025518165)
limits this repair to the package files list and distribution regression. E
retains SDK/operation-diagnostic behavior; no files are injected into installed
packages or altered tarballs counted as acceptance.

The regression normally packs only SDK and client-wire (neither has a prepack
build), installs them outside the checkout, runs the existing complete import
closure audit and imports SDK. It fails before the fix with the same missing
module (`focused-test-oNigl0`); adding the module to the files list passes 2/2
Node cases (`focused-test-0MOZKD`). Test installations/caches are removed in
finally; wrapper evidence is retained. Command:

```sh
node scripts/local-checks.mjs test node -- scripts/packed-package-boundaries.test.mjs
```

This establishes SDK archive/load closure, not Local/HTTPS query acceptance.
Named-WINDOW source acceptance must resume with new normal five-package
distributions after adopting the fix. No full Core, all-packed, CI retry or
merge was performed for this repair.
