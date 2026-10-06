# Bounded Events input-name matching

## Completion unit

This component depends on #610 at
`cf2d938f96ebfa02a697e449fe78115dd1f06a61`. The parent remains
unmerged; the eventual destination is main. Watermark, fixed/sliding
window, dedupe and Events/Relation session now resolve input names using
the existing common reference-fragment comparator instead of flattening
and comparing whole Strings in a single poll.

The names are borrowed typed FieldNames. Qualification spelling is
preserved without assembling a second String; unequal lengths need no
scan. Each poll compares at most 64 UTF-16 units. Spelling equality is
not schema, role or input-identity admission: those existing checks
remain in place. Clock, grouping, ordering and session identity semantics
are unchanged, including exact Unicode spelling.

## Work, reservation and custody

Each incomplete fragment consumes the existing control step. The cursor
position persists across advances and its one slot is reserved before
allocation. Watermark/window retain a pending borrowed field in their
existing array, without rereading it on each fragment. Dedupe/session use
their existing pending field and term. A term advances only after a
terminal comparison. The extra slot remains in caller scratch during
record append and its deeper reservations.

Short-name control work is unchanged. A 513-unit clock takes nine polls,
adding eight input comparison polls. The common record append additionally
scans the field hash, schema match, required hash/match and wire name:
five passes add forty polls. Independent one-record primitive boundaries
at depth ten are:

| Kernel | Control exact / one-short | Workspace exact / one-short |
| --- | --- | --- |
| Watermark | 101 / 100 | 81 / 80 |
| Fixed window | 101 / 100 | 80 / 79 |
| Dedupe | 107 / 106 | 71 / 70 |
| Events session | 138 / 137 | 91 / 90 |

The fixtures run quanta 1, 7 and 256 and compare independent values,
typed limit failures and cumulative work. Existing short-name workspace
boundaries add exactly one position slot, including Relation session and
empty session. Work limits are not increased to hide a scheduling change.

Cancellation is requested at offset 64 in each kernel's input-name
phase, before append begins. Request and confirmed stop retain the
offset, input and pending custody; cleanup clears them once. Neither
stop nor cleanup evaluates the record again.

## Ordinary retained Host path

The representative JSON Program uses 31 Values rows, to_events,
session by event_id, events, and two separate select consumers. Its
65-unit clock name crosses a fragment boundary. All 31 published rows
and both consumers are compared in order to literal session rules, not
sorted product output. The Result names must match published,
consumed_a and consumed_b exactly. Request reuse causes no additional
dispatch or positive Compute observation.

The core fixture independently derives the Host cancellation barrier.
Initialization costs `3*31+1+31+1=126` polls; input loading costs eighteen
per record. Clock comparison starts at `130+18*record`; poll 256 is the
first fragment of record seven. The core asserts offset 64, the still
unbound clock cell and zero emission progress. The ordinary Host holds
an awaited barrier at that same operator poll after the bridge's 124
polls/progress 31. Cancellation cannot release snapshot custody before
confirmed stop. All three Results remain unavailable; final cleanup
reclaims snapshots without another dispatch or positive Compute poll.

The four existing public emission cases are preserved. The resource gate
requires per-operation name limits and stop/cleanup fixtures, plus the
representative public session case. Missing roles or a missing production
cursor connection fail the gate; suite import and fixture checks remain.

## Candidate evidence and remaining work

Focused JS passed 59/59 at the candidate tree (`run-uUrgyl`,
`focused-test-Bzd7IV`). The existing four Host cases passed in
`run-i8jDsU`; the final name case passed separately in `run-cmSRbt`,
`focused-test-N37YWh`. These are dirty candidate receipts based on the
parent, not claims of clean final-SHA or CI verification. Only local-node
and run-host-core ignored runtimes were regenerated from these sources.

The initial 61-row/513-unit public candidate failed with
CapturedRunPublicationFailed; temporary local diagnostics identified
the underlying typed `Execution(InputSet)` before strategy completion.
A trailing filter did not resolve it. Those failing receipts remain
`run-i8jDsU`, `run-Uyvj1j`, `run-AJAIq3` and `run-1f7jcH`. No product
limit or expected success was weakened. The larger shape remains an
unresolved diagnostic, not proven equivalent to an installed capacity
refusal or a name-cursor defect. It is not covered by the successful
31-row public fixture. Temporary diagnostics were removed.

The first one-record fixture incorrectly expected session time twelve
despite input time zero; the independent expectation was corrected to
`session:0:v:1:1:v:1:1`. Its failed receipt remains `run-snTT03`.

Key/Text comparisons and session identity construction are separate
algorithmic scans. Constructor/Bridge record append, preparation/schema
lookup, identifier normalization, runtime buffer assembly, aggregate
intermediate bytes and whole-Run physical accounting remain outside this
component. No full Core, packed Local/HTTP, proof, performance or
Wasm/native execution campaign is claimed. This does not close the full
Local retained completion goal.

Selected commands:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/local_tea src/query_integration/local_carrier_events_wbtest.mbt
npm run build:runtime-packages -- local-node run-host-core
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-name-pattern 'public retained (watermark|window|dedupe|session)|Events input-name matching' \
  adapters/host-node/public-events-record-retention.test.mjs \
  scripts/check-local-resource-accounting.test.mjs
node scripts/check-local-resource-accounting.mjs
```

At clean source `333c514d2d544c99e7badb14045f723f24e85451`, focused
JS passed 59/59 (`run-1vOI7D`, `focused-test-fcngWT`) and the public
Store/gate selection passed 7/7 (`run-WcgPvs`, `focused-test-uojneO`).
The accounting scan, per-file formatting, Node syntax checks, diff check,
and read-only Node Host/Workers freshness checks passed. Generated fixture
sources and public interfaces needed no changes. This subsequent evidence
addition changes documentation only, not tested sources or fixtures.

The ignored runtime built from the same implementation inputs has SHA-256
`a493482e8a36a7e7ceb90ddc66399404f82cc6582014ca7408ed2a6fdb856130`
for local-node connectors_builtin_node, and
`afd59ea3984645a1e8112c0470133b80846bd10cb7d6a417e5abf88aabd2ad22`
for run-host-core client_values_host_abi. These are checkout runtime
artifacts, not a packed-distribution or all-target acceptance claim.
