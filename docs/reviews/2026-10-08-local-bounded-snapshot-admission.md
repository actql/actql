# Resumed retained Result snapshot preparation

## Scope and source

The clean implementation source is
`4df42cbe1d6ae72e21e0a364503d8a0bfa96aeaf`. Its two implementation commits
separate shared Text admission from the retained publication connection.
The parent is #913 at `8b9539c3e7e1b633a91878c516df6be62da443d2`, which
depends on #911 and #907. The eventual integration destination is main;
dependencies are not integration branches.

Previously, the JS publication adapter synchronously re-encoded every row
and then parsed, copied, canonicalized, checked and hashed the whole payload.
Polling only the first traversal would leave the second traversal blocking.
This record concerns that connection, not a newly reproduced erroneous Run
result or a measured universal stop-latency bound.

## Existing owners and the production connection

`CompletedRelationSnapshotPreparation` emits one structural transition or
existing ordered-key/runtime-wire cursor step. It checks the exact export
identity before allocation, keeps the receipt live, reserves private workspace
before appending, and transfers the wire and authored field inventory once.

`CapturedResultSnapshotPreparation` polls the existing source JSON parser,
decode admission, canonical admission, canonical emitter and tuple sorter.
Canonical wire equality, duplicate field detection and row-field checks use
the existing UTF-16 fragment comparator. Indexed immutable canonical rows are
not copied into another whole-array view. Logical Relation hashing uses the
same preimage and writer as before. Explicit synchronous callers drain this
same owner, rather than a second implementation.

The shared JSON grammar now retains a string cursor and yields after at most
64 decoded scalars or whitespace scalars. The existing decode/canonical
admission owners use a shared raw UTF-8 measuring cursor for long Text. They
preserve data spelling, Unicode errors, source coordinates and byte budgets;
identifier normalization is not applied to data values.

The actual JS path is:

`storeCompletedResultPublicationPayload` -> awaited publication control ->
`strategyHostOutputSnapshotBegin/Advance/Finish` ->
`PublicationOutputSnapshotPreparation` -> exact export emission -> canonical
snapshot admission.

The adapter yields between polls and checks its AbortSignal before transfer.
The Store path awaits the snapshot before schema storage and payload sealing,
and checks cancellation again before sealing. A cancelled snapshot child
releases its private state, not the parent's retained Result pin or receipt.
The existing export/Store cleanup owner retires those resources afterward.
Compute is not redispatched by this preparation or its cleanup.

## Independent boundaries and actual Host evidence

Common tests compare identical wire/fields across quanta 1, 7 and 64. The
two-row Unicode fixture independently requires 37 UTF-8 payload bytes, seven
nodes and depth two; one-short in each dimension fails. Empty-row emission
requires four fixed custody entries plus two field references: six workspace
slots succeed and five fail. Empty-row snapshot admission needs eight owner
entries, three references per field and two sorter indices per field:
18 slots succeed for two fields and 17 fail. These are structural workspace
counts, not a total heap/RSS measurement or Relation logical-work charge.

Additional checks cover cancellation across phases, receipt revocation,
foreign receipts, canonical/row/field substitutions and raw Unicode/NULL.
UTF-8 expectations are independently derived from scalar widths, including
the exact/one-short cases for supplementary and decomposed data Text.

The actual standard Host uses a normal Values -> Filter -> Select Program
and two consumer Stages, with real retained and publication Stores. All three
committed names are required explicitly, then read and compared with fixed
rows in declared descending order. The payload contains long non-ASCII Text,
decomposed Unicode, CR/LF, a supplementary scalar and an explicit NULL.

A second case observes positive progress inside the common canonical Text
cursor before delivering cancellation. The child cancellation check observes
that the parent still owns its receipt/pin. The exact abort cause is retained,
no committed Result index exists, and all three completed Compute dispatches
remain the only dispatches. Existing cleanup verifies zero held/reserved
execution bytes and zero retained/publication Store reservations. A recursive
schema success case exercises the previous publication connection unchanged.

## Executed checks

The following checks ran at clean implementation source `4df42cbe1...`:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 1 \
  src/run_publication/captured_run_issuance_test.mbt \
  src/run_publication/captured_snapshot_preparation_wbtest.mbt \
  src/query_integration/captured_publication_preparation_wbtest.mbt
node scripts/local-checks.mjs build moon --timeout-seconds 180 -- \
  --target js --release --jobs 1 \
  src/connectors_builtin_node src/connectors/duckdb/conformance
node scripts/local-checks.mjs test node --timeout-seconds 90 -- \
  --test-concurrency=1 \
  adapters/host-node/result-snapshot-control.test.mjs \
  adapters/host-node/result-transformation-control.test.mjs \
  adapters/host-common/durable-result-payload.test.mjs
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-concurrency=1 \
  --test-name-pattern '^(retained Result snapshot admission yields inside long Text: (success|cancel-during-result-snapshot)|retained Named Result schema yields within recursive contracts: success)$' \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
```

Results: common JS 14/14 (`run-mzzM0H`, `focused-test-aHyn13`);
consumed runtime roots 142 build tasks (`run-Oyy6fM`); Node controls/Store
19/19 (`run-1kP9lP`, `focused-test-6xT4yE`); actual Host 3/3
(`run-YhJA1J`, `focused-test-U57X1P`). The runtime roots were built from the
same clean implementation source. This is checkout acceptance, not pristine
packed distribution evidence.

Before the implementation commits, the broader affected-package selection
passed 624/624 in `run-o25D22` / `focused-test-lyLYEF`. That run preceded the
final consolidation of the explicit synchronous wrapper and is not relabeled
as a full 624-case run at `4df42cbe1...`; the final wrapper's callers were
checked by the clean-source 14-case selection above.

Earlier failed attempts are not successful evidence: two compile-time test
helper exception declarations and a constructor pattern were corrected;
one test selection named a nonexistent file; generator invocations without
the pinned tool environment failed before generation. A 604/607 run exposed
whitespace handling after container starts, an independently misnamed usage
counter expectation, and an insufficient old fixture export batch. The
grammar was corrected without changing its expectations; the counter was
identified as raw UTF-8 bytes, and the long-cell fixture explicitly supplies
its own larger batch budget. No product policy limit was raised.

Node/RelA/Workers bridge projections and public interfaces were regenerated
with their existing generators and `moon info`. Node Host and Workers fixture
freshness, the composition generators, formatting and diff checks passed.
Runtime bundles remain ignored. `moon info` reported the existing unused
`parameter_contract` import warning in the RelA-only Node package.

## Remaining boundaries

This is not whole retained Local completion. Field-name NFC validation and
duplicate-map key hashing remain synchronous metadata leaves. Long untrusted
numeric lexemes and identifier normalization in the generic JSON reader,
runtime allocation/contiguous-string finalization, physical chunk admission,
aggregate Captured Run serialization and explicit blocking Native/direct
callers remain separate boundaries. None is hidden behind a claim that every
possible snapshot poll has a universal time bound.

Full Core, Wasm/Native execution, packed/HTTPS, proof and performance campaigns
were not run. Exact submitted-HEAD hosted verification must be reported
separately. No manual CI rerun or history rewrite is part of this unit.
Existing parent history is preserved; the new commit messages satisfy the
72-column Conventional Commits requirement.

## Main integration

After confirming that #913, #911 and #907 had merged to main, this branch
normally merged the published parent
`a76ca3d0b251078c38d6264026b31054cdb7d24b` and then current main
`4256490e50dec0eb261c35c156210a62539aabc6`. Both merges were conflict-free;
no history, parent declaration, independent expectation or limit was changed
to accommodate the integration. PR #921 can target main without unmerged
parent dependencies.

The clean integrated implementation is
`c91c4425737430ad0c43a4c62aa827bd4f6efc56`. On this source:

- The same focused common JS selection above passed 14/14 in `run-iREjyV`
  / `focused-test-2Gdy9d`.
- Both consumed release runtime roots were rebuilt from the integrated
  sources, with 74 build tasks in `run-rBpcU7`.
- The two long-Text snapshot Host cases passed 2/2 in `run-CSKGdt`
  / `focused-test-klsBpP`. The selected command was the Host command above
  with `--test-name-pattern '^retained Result snapshot admission yields
  inside long Text: (success|cancel-during-result-snapshot)$'` on one line.
  It exercised real retained/publication Stores, the exact three committed
  names, independently expected Unicode/NULL rows and order, cancellation
  inside admission, parent custody and final reservation release without
  additional Compute.
- Node Host and Workers fixtures, both composition generators and
  `git diff --check` passed again. Runtime bundles remain ignored.

Before adopting latest main, common JS passed 14/14 and the Node controls/Store
selection passed 19/19 at `da0acded73b7ac90676095a9c59a266a513a31d4`
(`run-tWGKOk` / `focused-test-3TwmHP` and `run-38MLSK` /
`focused-test-abuzFw`). The three Node test files and their two shared adapter
implementation files have identical Git content at the final integrated
source; that earlier 19-case run is retained as scoped evidence, not relabeled
as a new 19-case execution. The earlier recursive-schema Host case and
624-case affected-package run likewise retain their original provenance.

The remaining aggregate boundary is concrete: `seal_effect_context` emits
every snapshot's canonical rows, and `issue_captured_computation_run` then
seals and validates the complete capture through synchronous hashing and
row checks. Splitting only the JS await or dropping those checks would not
close this boundary. The next unit must resume the existing common issuer
and its validation while preserving exact snapshot/Artifact bindings, private
capture identity and publication custody. This integration does not claim
that remaining work or hosted/all-target/packed verification has completed.
