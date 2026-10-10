# Sheets public connector completion unit

## Scope and dependency

This unit adds finite typed read and collection-only approved append to the
standard Node installation. It depends on the shared Mapping contract from
[#1089](https://github.com/actql/actql/pull/1089), merged as
`e59e4ddbfea0a1a606d11cc4c7e51e5fbddc16e3`. It does not add a separate Effect
scheduler, approval system, credential owner or Ledger.

## Owner and acceptance map

| Responsibility | Existing owner / connector contribution | Evidence |
| --- | --- | --- |
| Connector, Resource, Mapping, Capability admission | Generated Host manifest; `client_row_source_host` declaration/Mapping; `check_environment` | Shared #1089 vectors and refusal tests; generated installation inventory tests |
| Source schema, typed cells, finite budgets | `connectors/sheets/catalog`, pure `host_node` bridge | Independent API-shaped cells, NULL vs absent, empty formula, errors, raw Unicode, exact/one-short bounds |
| Read authorization and credential custody | `installed-row-source`, scoped credential journal and physical HTTPS resource | Public Local/HTTPS retained Result; same submission/repeated read makes no additional acquisition |
| Read emptiness and errors | Same public Source/capture/publication owners | All-blank Local/HTTPS reads publish `[]`; evaluated formula errors fail without a NULL row or public Result |
| Preview and Set approval | `installed-row-effect` and common checkpoint owners | Before approval zero appends; one approval for multiple rows; restart before/after approval |
| Pure row refusal | Common Effect projection uses its existing typed preparation result | NULL and unrepresentable Text refuse before send; shared preparation/transport-classification regressions remain |
| Physical send and response projection | Sheets I/O adapter; common durable Effect claim, Ledger and capture | Literal Text, zero/false; exact ack without row ID; success prefix / unknown / unsent distinction |
| Recovery and uncertainty | Existing installed Effect continuation and saved response owners | Lost reply, 503 and pending-response cancellation do not resend; separate-process reconstruction |
| Current authorization and target binding | Account gate, common commit admission, Sheets numeric metadata check | Revoked account and modified numeric tab refuse approved sends |
| Cleanup | Existing initialization/shutdown/Ledger retry handles | Failed publication removes its own temporary file; Ledger close retry retains same owner and append count |
| Distribution | Manifest-driven inventory and the official four-package release recipe | External `@actql/node`, `@actql/sdk`, `@actql/local-node` exports; independent fixture Programs; release SHA and tarball digests |

Provider transport is deliberately weaker than settlement authority. Append has
no idempotency key or authoritative row lookup. Repeated equality checks cannot
turn unknown into success. The independent response fixture contains no invented
row ID. Common driver registration/recovery-hook tests are reused through
`installed-effect-site.test.mjs`, not cloned under a new provider name.

## Executed local diagnostics

These receipts predate the final committed source identity and establish only
the recorded dirty-source selections, not a pristine final-SHA campaign:

- `run-bNes3K` / `focused-test-IYgbxK`: 63 Node cases passed, including ten
  initial Sheets public cases and 53 shared Effect caller regressions.
- `run-bTruiF` / `focused-test-Y3HSpY`: 23 Node cases passed, including ten
  Sheets public cases with deterministic in-flight reply cancellation and
  separate-process replay, plus 13 HTTPS fixture cases.
- `run-v33FBu` / `focused-test-OoZMv0`: ten selected Sheets codec/bridge JS
  cases passed, zero failed.
- Selected `moon info --target js,wasm,native` generated both new interfaces
  without a divergence report. This is API compilation, not Wasm/native tests.
- `run-cLAejO` verified unpublished temporary-file cleanup but the new partial
  success case failed because it assumed the physical send position from row
  text. `run-A1Rp4Z` also disproved that assumption. The common Effect orders
  its canonical row keys; no production expectation or ordering was changed.
  `run-NCfUsI` / `focused-test-A2OfKj` verified the corrected independent fault
  at the second actual send: saved success, unknown and remaining unsent row,
  with no additional send on same-process or fresh-process reconciliation.
- After merging main, `run-aSQY1y` / `focused-test-R4abvr` passed the ten
  codec/bridge JS cases on clean SHA
  `62cef1aceaf22b130688915f0fba14e62d93ef0a`.
- `run-dlLdIS` / `focused-test-1VxMes` passed a focused dirty-source regression
  rejecting grid/sheet indexes above the bridge's int32 domain before any
  provider request. This does not relax the rectangle or response limits.
- On clean SHA `985fd9eb27068c1cf62010565b7d84ab8a5c8aef`,
  `run-o9E3TR` / `focused-test-TgxyJP` passed 53 common installed Effect
  contract cases, including required recovery-hook admission, exact saved
  values, pending custody and cleanup without Compute. This is a targeted
  driver suite, not real-provider acceptance.
- `run-bTQeQV` / `focused-test-NK60AZ` passed two dirty-source public read
  selections against the unchanged compiled runtime: populated and all-blank
  Local/HTTPS reads, plus evaluated formula-error refusal without publication.
  These selections supplement, not relabel, the prior 13-case packed receipt.
- `run-pa29UG` / `focused-test-1mH9GM` passed the strengthened formula-error
  selection in a nullable Number column. Substitution with NULL would be a
  legal row, so the failure assertion cannot pass merely because a required
  Text column rejects NULL. This remains dirty-source focused evidence.

Receipts live under this worktree's `_build/local-checks/attempts` and
`_build/focused-evidence`. They contain commands, actual source SHA and dirty
state. Runtime bundles remain ignored. Final fixed-SHA packed receipts and
artifact correspondence belong in the PR validation record.

## Known limits and unverified coverage

- Source read uses the common scan/filter/select capture stage plus a separate
  publishing Relation stage. Direct capture-task publication remains rejected
  by the common managed identity policy after acquisition; this unit does not
  claim pre-I/O admission for that shape.
- Hosted Cloud / Native Sheets execution, arbitrary queries, row-addressed
  writes and automatic OAuth refresh are outside this unit.
- The original external environment dependency was resolved on 2026-10-10.
  Real read, approved two-row append and separate-process saved Result replay
  passed; see the [fixed-artifact report](2026-10-10-sheets-real-service-acceptance.md).
  Real write was exercised over HTTPS; Local write and uncertainty/cleanup
  fault injection were exercised against the controlled service, not Google.
- Hosted CI remains stopped. Local evidence is not CI success, Preview success
  or npm release readiness. Full Core, proof and performance campaigns are not
  local requirements for this adapter change.

The detailed supported values, installation and public examples are in
[Sheets](../connectors/sheets.md). The real campaign's two-row permission is
exhausted. Its completion is not permission to expand the service scope.
