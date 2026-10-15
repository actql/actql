# Original temporal JOIN normal release completion

This genuine child of TimeSeries #1953 connects the existing F05 `asof_join`
and `interval_join` fixtures to the normal four-release-package source-free
worker. The original `scripts/fixtures/temporal-join-source-input.mjs` retains its original JSON bodies, arguments, values, contracts and limits: four semantic variants, each JSON/SQL/AQL-text, twelve normal
cases and nine static refusals. No Source supplier, evaluator, engine, language
rule or additional authored acceptance case is introduced.

The original controls use VALUES and source-free WITH SELECT producers. Backward
as-of tolerance 12, point-in-interval output ceiling 3, left/inner behavior,
nullable right output, exact field roles and ordered `id,value` schema are
unchanged. Independent results contain 27 rows per transport. Original Source
row reads are zero; the optional session observation is absent from these
fixtures and is not inserted into the submitted request. The empty installation
and existing process/fetch/secret guard observe zero Source sessions and I/O.

## Release and reread boundaries

The closed `--temporal-join-only` flag reuses the normal `@actql/node` Local and
installed HTTPS Host/SDK factories. All thirteen test-only relative-import
modules are delivered outside node_modules. The four product archives are
installed through the existing registry with source/manifest/digest fences.
No checkout runtime, adapter overlay, NODE_PATH or Provider is supplied.
Default IN/UNNEST 4+6, Sequence 18+9 and TimeSeries 9+7 remain distinct cohorts.

The existing same-process reader checks rows/full schema, same Submission/Run,
attach, lookup, resend, no added admission/acquisition and cleanup. After that
worker exits, the existing reread worker takes the closed temporal suite and
reopens the same durable transport state in another OS process. It retains the
original Submission reference, compares the independent fixture again, resends
without a new nonce and observes unchanged durable admission and Source I/O.
Only synthetic test authorization is saved mode 0600 in the private consumer
for restart; no key body is included in Git or receipt output. Failure and
partial completion observations remain retained.

## Finite verification and pending public execution

```sh
node reviews/2026-10-14-temporal-join-release-matrix/prepared-checks.mjs <clean-source-sha>
```

Node-only 60 seconds/TERM grace 5, non-Heavy, focused child 30 seconds. These
selection, audit mutation, custody and delivery checks do not execute TEA,
Common checker, installed Host, transport or actual fresh-process Run replay.
The audit's synthetic test reports are not product receipt evidence.

After actual resource/Owner admission through the existing guard:

```sh
node reviews/2026-10-14-temporal-join-release-matrix/prepared-release-public.mjs --producer <clean-source-sha> <new-absolute-RC>
node reviews/2026-10-14-temporal-join-release-matrix/prepared-release-public.mjs --consumer <same-source-sha> <same-RC> <new-absolute-receipt.json>
node reviews/2026-10-14-temporal-join-release-matrix/public-audit.mjs <receipt.json>
```

Original producer 300 seconds/TERM grace 5 and complete consumer 300 seconds/
TERM grace 5 are unchanged, including both transports and rereads. The read-only
independent audit requires Local/HTTPS each 12 normal + 9 refusal, full ordered
schema and NULL values, 27 rows, exact refusal codes, saved references, zero
Source I/O and all six actual consumer commands complete. It cannot promote an
incomplete transport or reread to PASS.

## Preserved failures and the local execution repair

The original fixture used unquoted reserved aliases `at` and `current`.
`preimages/original-temporal-source-input.mjs` preserves those exact bytes.
Only their quoting changed; a Node control compares every other fixture field
and every independent expected value to the original. Three parser controls
retain both exact old refusal positions and the quoted positive input.

The corrected normal release at `efb566b7e4d5d84255856436b20364eab1b18868`
passed seven Local normal cases (18 rows), including JSON interval-left, then
accepted SQL interval-left but failed before publication. HTTPS and remaining
inventory were not completed. Its manifest, archives, consumer, Run/DB and raw
failure are retained; the earlier reserved-alias refusal remains separate.

The SQL/JSON interval arguments, complete input/output contracts and original
six-pair search/three-row output ceilings agree. The SQL Values/derive/select/
append prefix exposes a distinct Common row-layout defect: SELECT keeps
`id, at` physical order, whereas checked schemas use `at, id`. Append treated
schema alignment ordinals as physical positions and rejected the valid input
with `Rows(4, InputMismatch)` in an independent five-step counterexample.

`append_rows.mbt` now resolves the same checked field against physical names
through the existing charged resolver when its checked ordinal has a different
name. Already aligned inputs retain their exact previous logical work.
Ownership, checked field identity, row/value/work/workspace limits and output
order remain unchanged. No interval kernel, task Owner, fallback or limit is
added. The original complete SQL/JSON prefixes and selected interval controls
retain independent expected rows and NULLs. Existing append exact-work and
one-short budget tests are unchanged.

At `7ed81b7ec6adf2da0e874ab7cf684a07299bd107`, the focused eight JS tests
passed, including the new append counterexample, both original prefixes, and
all existing append tests. `run-BQ4mVj` retains the initial counterexample
failure; `run-NKZqtD` retains the intermediate 6/8 result before preserving
aligned-input work. `run-5jj04i` is the actual 8/8 result. These are component
results, not a new installed public campaign. The final normal release
Local/HTTPS inventory after this repair is pending.

Pure installed compiler plan projections use the unchanged original archives;
they create no Host, Run, Source or DB. They are diagnostic evidence only.
The failed whole-prefix diagnostic setup remains under `preimages`; it is not
used to generate independent expectations. Optional Calendar and other P2
matrices remain separate. No all-Core, Native/Wasm execution, hosted CI,
Provider service or publication is claimed.


## Mixed-chain scratch lifetime

The normal package campaign at `eee74e1f` completed Local seven normal cases
(eighteen rows), then accepted the SQL interval-left request but failed before
publication. HTTPS, remaining cases, refusals and fresh-process rereads were
not executed. The original failure, Run and private diagnostic custody are kept.
A private safe-tag observation established `LocalManagedStart -> Execution ->
Physical`; the publication `StrategyNotComplete` was only a later symptom.
The same original JSON and normalized SQL through the ordinary Common Host
reproduced `Physical(ExecutionLimit)` at `1fea1dd59` (`run-lsjrfF`). A direct
bounded provider control had succeeded because it did not reserve the Run ledger.

A family step made the previous whole-chain eligibility test retain the scratch
of every earlier built-in. The repair reclaims only the already-audited built-in
prefix, confirming the same child's cleanup before advancing. The first family
or unaudited step ends this prefix; its complete suffix keeps the previous
conservative execution lifetime. All accepted intermediate outputs, exact input
ports and metadata handles remain retained. Capacity is independently composed
as retained children plus max(prefix scratch peak, conservative suffix scratch
sum), with unchanged coefficients and 512 MiB ledger ceiling. No memory samples,
forced cleanup, missing ACK, cap increase or operand change establishes admission.

At `091debb60`, the original JSON/SQL Host control and eight existing lifetime,
cleanup and cancellation controls passed 9/9 (`run-9pfkgS`). Earlier setup
failures remain failures: adjacent control strings (`run-MG1yRV`) and a mismatch
with the ordinary Host output mode (`run-cK9JTV`, `run-IX3e3p`, `run-Zr2Q9W`).
This is component evidence, not a completed installed public matrix.
