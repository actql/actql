# Original temporal JOIN normal release completion

This genuine child of TimeSeries #1953 connects the existing F05 `asof_join`
and `interval_join` fixtures to the normal four-release-package source-free
worker. The original `scripts/fixtures/temporal-join-source-input.mjs` remains
byte-identical: four semantic variants, each JSON/SQL/AQL-text, twelve normal
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

Only after each explicit shared-window allocation:

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

Installed public E2E is zero; producer/consumer are unexecuted. TimeSeries root
classification/selected task repair and Vector captured suffix execution belong
to Root, outside this harness diff. Optional Calendar runtime and other P2
public matrices remain separate unfinished work. No extra compiler, Native,
all-Core, hosted CI, Provider execution or publication is requested here.
