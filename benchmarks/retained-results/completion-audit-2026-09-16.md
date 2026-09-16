# Retained execution completion audit

This is an incremental audit, not a completion certificate. The original base
was `b87584fed46217659589315c1f819994dc0cfe77`. The implementation checkpoint is
`de86a96fdd74f1f6cc2463924428d2e4de19a4d0`; use that checkpoint, not the original
base, for the retained execution implementation described here.

## Required behavior and evidence

| Requirement | Current evidence | Remaining verification |
| --- | --- | --- |
| Completion does not require a Host row table | Common retained-output/material/evidence types and rejection tests; standard Host file-backed outputs | Final fixed-revision regression |
| One local execution process per Run performs acquisition, validation, Compute, canonical identity and file writing | `managed-example.mjs` invokes the shipped controller/worker and actual standard Host; process exits while independent files survive | Full final regression; process memory/traffic acceptance measurements |
| Local and DuckDB use the same retained-input contract | Managed all-Local, all-DuckDB, DuckDB-to-Local and Local-to-DuckDB cases check selected realizations and result identities | Final fixed-revision regression |
| Ordinary candidate comparison includes independent file work and resident reuse | Managed fresh cost 1 selects fresh; cost 20 selects resident with one import; all outputs remain independently held | Large-profile resident estimates remain conservative; no general optimal-placement claim |
| Ownership, obligations and failure rules remain enforced | Foreign-input and obligation regressions; real corruption after resident import refuses completion; native stop alone does not settle failed Store reads | Final all-target/real-connector verification |
| Explicit release reclaims held files, while uncertain stop remains pending | Managed exit/close tests, Store/custody tests, actual native rollback/holding tests | Combined abnormal process-exit coverage must be audited before final sign-off |
| No unnecessary control-side whole-row transfer or materialization | Installed worker writes delegated files directly; controller receives metadata/custody reports | Measure control memory growth, transferred bytes, hash passes and copies under registered workloads |
| Reuse in a fresh process | Readmission and exact producer binding plus actual bounded Store read are exercised | A subsequent genuine Compute is not yet demonstrated; read-only success must not be called execution continuation |
| Performance acceptance | Registered 27-case readiness passed earlier; bounded imports substantially reduced diagnostic time | Four-comparator runner/samples, alternating pairs and confidence gates are not complete |

Formal Run/Result publication, control-Host restart recovery, remote authentication,
cross-Run process pools, cross-task fusion and new semantics are excluded. They
must not be introduced merely to satisfy one integration test.

## Regression results and outstanding runs

Logs: `/tmp/actql-retained-verification.q56Wue/` (local diagnostic artifacts).

- Whole-repository JS: 4,327 passed.
- Whole-repository Wasm: 4,326 passed. The application assembly is JS-only.
- Whole-repository native: 4,326 passed.
- Documentation checks: passed.
- Workers verification: passed 24/24 after regenerating the stale projected
  fixture from its authoritative shared helpers. Initialization-I/O rejection
  output is an expected negative test, not an ignored runtime error.
- Process capacity/accounting: passed 14/14.
- Metadata: passed; no document metadata changes required.
- Complete real-DuckDB suite: passed 68/68, including the 27-case smoke matrix
  (100/1,000/10,000 rows), managed fresh/resident retention and read-failure
  settlement. This is not the registered large matrix or performance sampling.
- No-DuckDB installation: actual dependency-free standard-entry fixture and
  27 Node tests passed. Its stale generated fixture was regenerated from the
  authoritative shared helpers before the passing rerun.
- Core-only closure: seven explicit roots, 90 packages, isolated check passed
  without concrete connectors.
- Three-target interface regeneration, `moon fmt --check`, both projected
  fixture freshness checks and `git diff --check` passed. The commit-relative
  generated-API gate remains a distinct pending check.
- AoA semantic boundary, portable Core and pinned benchmark fixture checks:
  19 passed; concrete dispatch boundary checks: 3 passed.

The generated-API gate passed on the clean implementation checkpoint
`de86a96fdd74f1f6cc2463924428d2e4de19a4d0`. The isolated third-connector-addition
gate also passed on that SHA: baseline and extended checks, independent connector
execution on JS/Wasm/native, and the real standard Node Host integration. Its
inventory confirmed 2,311 common files unchanged, with 162 permitted addition/
composition/conformance changes. Evidence resides in
`/var/folders/sk/89cnymvx0t3fy94vwmqwrg4c0000gn/T/actql-connector-addition-0Aeoiv`.

The broad regressions above preceded the checkpoint; the last generated fixture
refresh was separately covered by Workers and no-DuckDB checks. Further product
changes require rerunning the relevant gates before final sign-off.
Linux/GitHub Actions has not been verified here. Remaining functional and
performance items in the requirement table are not closed by this checkpoint.
