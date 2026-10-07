# Resumable retained compound input metadata

## Completion unit

Verified implementation SHA: `0ee2f1b32dde441d46d99d87cf6eec3f1122dc0e`.
Dependency: compound completion-port preparation #774, with unary #769 beneath it.
Adopted main: `8f4889ef52510063600490211fb46718a006fc97`.
Both parents received ordinary integration commits; their algorithms and historical
verification receipts are retained. No child implementation is included in either
parent. The final child integration has the same source tree as its first main
merge, before the separate implementation commit.

| Provider | Previous synchronous preparation | Connected bounded owner |
| --- | --- | --- |
| Nest | Complete input-name arrays, whole column scans and output-name charges | Borrowed schemas, existing schema lookup and name-charge cursors |
| Interval Join | All keys, temporal operands and selected columns inside start | `ResolveMetadata`, before clock loading |
| As-of Join, Relation or Events input | Clocks, keys, identity, tie and selected columns inside start | `ResolveMetadata`, before identity validation |

The existing `RowMetadataLookup` compares virtual qualification in fragments of at
most 64 UTF-16 code units. A small charge continuation preserves the old candidate
entry and UTF-8 charges one scalar at a time. Nest also charges the candidate's
original spelling; temporal lookup retains its original requested-name-only cost.
No normalization, whole-name flattening or second evaluator is introduced.

Each lookup reserves one continuation entry, closes it once and borrows the existing
schema. Original metadata reservations remain in force. Intermediate field arrays
are populated only after resolution and cleared by the same cleanup owner. Temporal
positions use Int64 arithmetic before indexing the already checked finite lists.
Nest's generated-role comparison and output-name charge are also resumable. Exact
ordered input binding, kernel algorithms, NULL demand and accepted-output custody
remain unchanged. Public APIs, wire formats, identities and pins do not change.

## Independent and public acceptance

- Two qualified Unicode names have 139 and 140 UTF-8 bytes. Two inspected
  candidates cost `2 * (1 + 140) = 282` for temporal lookup, and another
  `139 + 140`, or **561**, for Nest. Exact work succeeds; one less gives `RowLimit`.
  One workspace entry succeeds; zero rejects before cursor allocation.
- Interval metadata costs **118**: key lookups 16, clocks 20 + 18 + 4, and output
  sources 30 + 30. As-of metadata costs **114**: clocks 12, keys 24, identity 6,
  tie 36, and sources 6 + 30. Exact quantities and one-short failure retain the
  existing typed `InvalidExecution` metadata refusal. These are literal formulas,
  not values recovered from a successful execution's counters.
- Existing whole-operation limits, including Nest **115** and Interval **132**,
  remain passing. Existing compound fixtures compare full literal ordered output,
  cumulative physical/logical work and workspace across quanta 1, 7 and 256.
- Stops occur during entry/name/candidate/comparison preparation, including midway
  through a 256-character Unicode Nest key. No output is accepted, borrowed inputs
  remain live, cursor reservations are reclaimed once and a second cleanup is inert.
- Three ordinary Programs use a long actual input key, not only a generated output
  label. Nest, Interval and As-of publish through the standard public Host and real
  retained Store. Producer and two consumers are read by exact result names and
  compared with independently written rows and schema. Resubmission does not add
  dispatch; post-progress cancellation distinguishes physical stop and preserves
  custody until cleanup. The public cancellation barrier is not claimed to identify
  the private metadata phase; the core phase tests establish that boundary.
- Fifteen role-removal and twelve source-connection mutations reject missing
  per-operation registration or lookup/charge/cleanup calls. The unchanged baseline
  is checked first. This gate evidence is not a substitute for executed semantics.

## Executed checks

At the clean implementation SHA above:

- Six selected JS fixture files: **42/42 passed**.
  `run-tY7Jdn`, `focused-test-tuBi1y`.
- Three public Host cases, two resource-gate cases and two inventory cases:
  **7/7 passed**. `run-ixRQUr`, `focused-test-oWuJ74`.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 2 \
  src/execution_relation/compound_metadata_cursor_wbtest.mbt \
  src/execution_relation/bounded_nest_wbtest.mbt \
  src/execution_relation/bounded_interval_join_wbtest.mbt \
  src/execution_relation/bounded_asof_join_wbtest.mbt \
  src/execution_relation/bounded_compound_port_preparation_wbtest.mbt \
  src/execution_relation/row_metadata_cursor_wbtest.mbt

node scripts/local-checks.mjs test node --timeout-seconds 150 -- \
  --test-name-pattern 'public retained .* source metadata|compound metadata|acceptance evidence index|evidence paths exist' \
  adapters/host-node/public-property-name-retention.test.mjs \
  scripts/check-local-resource-accounting.test.mjs \
  scripts/pure-operation-inventory.test.mjs
```

Receipts remain under `_build/local-checks/attempts/` and `_build/focused-evidence/`.
Only the seven JS roots needed by the consuming Host were built, using the pinned
toolchain, `--release --jobs 2` and a 180-second envelope (`run-F9llK4`). Local Node
assets and Run Host runtime were regenerated and their read-only checks passed.
Generation preceded committing identical production sources. Ignored runtime
bundles are not committed. Existing pinned dependencies and toolchain were borrowed
without installation or modification. This is checkout-runtime evidence, not a
packed package campaign.

Earlier failed attempts are preserved: `run-T9nUfE`, `run-vg5wnE`, `run-2uOIah`,
`run-0PdqGP` and `run-v8XAF6`. They exposed cumulative-poll-work assertions, old
caller phase assumptions, a first-occurrence-only fixture rename, an active-session
cleanup attempt, a diagnostic using the opaque Issue instead of its kind, and an
Int64 boundary literal mismatch. All were corrected without inflating logical
limits or deriving expected charges from observed output. The earlier 42/42 run
`run-hK835J` precedes the final Int64 representation and is not substituted for
the clean implementation receipts above.

## Remaining work

This closes these providers' input-metadata preparation, not all Local retention.
Installed input-availability callbacks, other provider/kernel start metadata and
Native allocation/callback correspondence remain distinct. The extra continuation
is accounted structurally; its Native physical capacity model is not certified
by JS checks. Whole Store-failure/retry suites, Wasm, Native, full Core, packed,
proof and performance campaigns were not rerun. Public post-progress cancellation
and private phase cancellation are separate evidence. Draft CI is preparation only;
no required CI success is asserted for this unit or refreshed parent HEADs.
