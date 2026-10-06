# Stepped Relation-to-record Bridge

## Scope and ownership

The previous rows-to-Events/Vectors owner checked a whole cell with
`producer_read_checked_cell` and emitted a whole record with `append_record`
inside one charged step. An unused nested column could therefore monopolize
that step even though the outer driver yielded between rows.

The same `start_rows_to_records` owner now retains a common value recheck
and RecordAppend across advances. Raw Text enters the existing Text cursor
without an initial synchronous `text_value` call. Array/Object/Vector cells
use the existing typed value cursor, not a second validator. Each cursor
advance consumes one physical work unit. Record progress follows commit.

The input's exact operation binding and availability checks remain intact.
Recheck continuation room is admitted before allocation. Append reservation
includes pending fields, handles and retained output, using the shared
RecordAppend reservation. Stop leaves the pending cursor, builder and input
under their existing owners; cleanup cancels cursors before the builder,
and is once-only. No completion, identity, wire or public API rule changes.

`start_rows_to_vectors` delegates to this owner and uses the same advance
and cleanup functions. Its vector-specific caller tests remain separate.
Shared large-value evidence proves this common input/append discipline,
not a separate public large-value Vectors campaign.

## Independent boundaries

The large record has id 1, time 12, 8193 ASCII payload characters and an
unused Array of 129 numbers. All four fields must survive conversion.

- Cell loading: numbers 3+3 polls, Text 132, Array 262 = 400.
- Append start: 1; shared append: 423, including 130 Text and 260 Array
  wire polls. Total physical work is 824 across quanta 1, 7 and 256.
- Logical construction: identity 2 + outer record 1 + field arrays/names
  8 + values 133 + copy 5 = 149. One-short 148 is typed WorkLimit.
- Retained wire bytes: names 35 + field punctuation 20 + numbers 3 +
  quoted payload 8195 + Array 259 + record separators 5 + key 3 = 8520.
- Workspace: cursor `16+3*4+1+3*10=59`, caller fields/handles 6 and
  committed row 6 overlap: exact 71, one-short 70 is WorkspaceLimit.

Existing small Events and Vectors fixtures retain logical construction
32 and 28 respectively. Explicit continuation custody changes workspace
to 71 and 65; physical work is 78 and 70. These are independently derived
costs, not budgets copied from a successful execution measurement.

The normal Values preparation scan, literal scan and literal reservation
each charge the payload: 24579 text bytes before finite schema/name costs.
The large fixture therefore has a separate 30000-byte preparation allowance.
Bridge output/value byte limits remain 10000; no installed limit increases.
The earlier Values(BudgetExceeded) receipts are rejected fixture setup,
not Bridge failures.

Cancellation coordinates 9, 256 and 430 lie inside Text recheck, unused
Array recheck and Text emission respectively. The paired exact-poll test
fixes those coordinates. A temporary synchronous recheck drain passes the
cancellation-only selection (`run-4vzaax`), so that selection alone is not
evidence of its phase. The paired fixture rejects the drain with 1/2 passing
(`run-kcLFHl`, `focused-test-cDMy55`). The mutation was removed. No product
failure, timing guarantee or public API phase observation is inferred from
that negative control alone.

## Ordinary retained Host

The existing normal JSON Program goes through Values, to_events, an Events
operator, events projection and two select consumers. It uses the installed
Local provider and actual retained Store. All three explicit Named Results
are read and compared in order to independent rows. Request reuse does not
dispatch or compute again.

The new representative cancellation case awaits the Bridge's first
256-work observation: zero record progress, inside the unused Array recheck.
Cancel delivery does not release snapshot custody before confirmed stop.
After stop, all Results are unavailable, snapshots are reclaimed and no
additional dispatch/positive advance occurs. Existing operator-emission
and session input-name cancellation barriers remain after the Bridge.

The short-name prefix costs 824 polls. The 31-row/65-unit clock prefix costs
`31*44=1364`; the 61-row/513-unit clock prefix costs `61*79=4819`. The
Host hook reports deltas, so prefix work and progress accumulate across
advances. The larger session still refuses aggregate projection text at
the installed allowance; it is not relabeled successful execution.

## Candidate evidence and remaining work

Based on `82a0f185bb086f88ac387ed4fc14eda2821c9990`:

- Existing affected Events/Vectors caller selection: 94/94 passed;
  new fixture setup failed in `run-T10yJq` before its allowance correction.
- Corrected large-value JS fixture: 2/2 passed (`run-5OJ8Wz`,
  `focused-test-uXYDnb`).
- Public retained Host cases: 7/7 passed (`run-slfVcI`,
  `focused-test-H3G9oB`) after regenerating only local-node.
- Resource accounting scan passes with unchanged inventory totals:
  69 operations, 62 mapped, seven typed pre-execution refusals,
  62 full work/workspace records and 114 path-scoped records.

These are candidate-tree receipts, not clean final-SHA CI or packed evidence.
The gate requires shared large-value limits/stop fixtures for both Bridge
entrypoints and ordinary Store evidence for Events. It checks the actual
rows-to-record step and cleanup functions, rather than borrowing markers
from the inverse Graph/Events projection in the same file.

Remaining boundaries include Events/Vectors-to-Relation name lookup and
atomic Relation output append, constructor/schema preparation, JSON key
normalization/reference leaves in common value recheck, Events comparisons
and session identity construction, intermediate aggregate byte admission,
and whole-Run physical accounting. This component does not close the full
Local retained goal or all possible nested-value scans. Full Core, packed
Local/HTTP, proofs, performance and Wasm/native execution are not claimed.

Commands selected for this component:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_integration/rows_events_bridge_steps_wbtest.mbt \
  src/query_integration/local_carrier_events_wbtest.mbt \
  src/query_integration/local_carrier_vectors_wbtest.mbt
node scripts/build-runtime-packages.mjs local-node
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  adapters/host-node/public-events-record-retention.test.mjs
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  --test-name-pattern 'record Bridges' \
  scripts/check-local-resource-accounting.test.mjs
node scripts/check-local-resource-accounting.mjs
```

At clean implementation SHA `2304fb1f2dba1439436d495a0797a96c58dd7a00`,
the focused JS/caller selection passed 96/96 (`run-KRbfta`,
`focused-test-YCjVc0`). The public Store and guard selection passed 9/9
(`run-wP8dkL`, `focused-test-rC0BbJ`) with pattern
`public retained|record Bridges`. Accounting, Node syntax, per-file
formatting, diff checks and read-only Node Host/Workers freshness passed.
The new guard checks are scoped to the rows-to-record step and cleanup;
the inverse projection's recheck cannot substitute for that connection.

The ignored local-node connectors_builtin_node runtime has SHA-256
`eab18a3cc08a906002cfe1646c92951b73e33a008d7b30c163df27e68f9790b6`.
It was regenerated from these production inputs before the public checks.
The temporary negative changed only test-build inputs, was removed before
committing, and did not rebuild that runtime. Unchanged run-host-core
client_values_host_abi remains
`afd59ea3984645a1e8112c0470133b80846bd10cb7d6a417e5abf88aabd2ad22`.
This subsequent record changes documentation only. It does not establish
packed-distribution freshness or final-SHA CI success.
