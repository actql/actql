# Rows / Events compositional evidence

This is a concrete semantic instance plus finite implementation correspondence,
not a formal proof of the MoonBit implementation or a new execution mechanism.
No existing tests, limits, CI selection rules or reusable actions are removed.

## Theory and instance

`Composition.lean` is maintained entirely in this repository. Its six laws
compose explicitly supplied observations across different carriers, preserve
errors, associate sequential execution, and require an intermediate
postcondition. `CompositionClaims.lean` fixes their exact proposition types;
the checker audits all common and instance theorem dependencies with the pinned
Lean toolchain. The source closure uses only Lean's standard prelude and these
local proof files. No external theory repository, source snapshot or build is
referenced or required.

The observation-composition law requires both stage-specific preservation
premises. It does not infer them from matching types or construct a canonical
quotient automatically. Failure short-circuits the downstream semantic function.
None of these theorems licenses operation reordering.

`Events.lean` instantiates the composition law with distinct Rows and Events carriers.
The finite correspondence scope uses numeric integer IDs and numeric or authored
UTC timestamp clocks, with the roles named `event_id` and `occurred_at`.
Additional payload fields admit integer numbers, text and declared NULL.
Schema width, names, nullability, clock encoding and unique IDs are checked by
the semantic admission function. Ordered rows, schema and text bytes are kept
exactly. The observations intentionally retain complete ordered semantic values: no
quotient discards duplicates, row order, NULL or schema.

The admitted round trip preserves the complete input Rows value. Duplicate IDs
and malformed semantic schemas remain errors; they are not empty success.
The nonvacuous witnesses cover empty input, repeated payload under distinct IDs,
unsorted clocks, NULL and authored timestamp/text. Valid calendar parsing,
floating-point range/finite checks and the real value-admission implementation
remain implementation obligations; an arbitrary timestamp string in the model
is not evidence that the product will admit that string.

## Existing implementation and remaining obligations

| Layer | Evidence / obligation |
| --- | --- |
| General composition | Local observation and precondition composition; exact claim types and axiom audit |
| Concrete semantic instance | Six Events model theorems; the same observation-composition theorem is applied, not reimplemented |
| Real Bridge connection | Existing `local_bridge` entrypoints, exact prepared occurrence/input binding, Carrier projection and completed-output port matching |
| Independent checked contract | Authored field names, Number/Timestamp/Text shapes and nullability compared with the schema of that same checked/lowered projection |
| Execution values | Real public column names/order and cells compared with independent expected rows; empty/all-NULL type checks are explicitly checked-contract evidence |
| Shared execution | Both real Bridge kernels use the existing bounded Session. Its counter/token/terminal/cleanup model and finite Session correspondence remain separate evidence and retain their callback premises |
| Provider / Host ownership | Existing Events retained-input, foreign-owner, two-consumer, cancellation, limits and provider material/view lifetime tests remain in place |
| Resources / physical lifetime | No physical heap upper bound, GC completion, unconditional capacity or new cancellation guarantee is derived from the semantic composition law |

The new fixture directly runs Rows → Events → Rows, without a watermark in
between. It checks empty, all-NULL payload, repeated payload with distinct IDs
and non-sorted clocks, plus timestamp and decomposed text with CRLF. The existing
duplicate-identity test supplies the real semantic refusal boundary. Existing
two-consumer and limit/stop tests supply their own ownership/resource boundary;
their observations are not replaced by the pure round-trip theorem.

`cleanup_rows_to_events` and `cleanup_events_to_rows` expose the bounded Session's
change/reclamation transition result. This is different from the managed
provider callback's completion Boolean. The retained Events result remains
available after encoder cleanup and is discarded once at its own boundary.
The fixture does not claim that cleanup success means its allocation disappeared.

## Developer procedure

1. Preserve the Bridge's independent schema, values, order and refusal
   expectations. Use the existing typed preparation/input-owner fixtures.
2. Add a Carrier-specific semantic instance of the shared composition law and discharge
   its observation-preservation and intermediate-precondition premises. Preserve
   observable errors; do not normalize data to obtain equality.
3. Add the exact claim types and residual implementation/resource obligations.
   Review the local proof source; do not update a hash instead of reviewing a law.
4. Run the focused proof admission and affected real Bridge fixture. State the
   target and source revision. Three-target integration remains a CI obligation.
5. Keep physical/provider acceptance where its scope differs. Do not copy the
   common Session protocol suite for each new semantic operation.

Focused commands (from the repository root, using the installed pinned tools):

```sh
node scripts/local-checks.mjs test node --timeout-seconds 60 -- proofs/bounded-session/proof-check.test.mjs
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_integration/events_bridge_evidence_wbtest.mbt --deny-warn
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_integration/local_carrier_events_wbtest.mbt --filter 'rows to Events rejects duplicate semantic identities' --deny-warn
```

The existing Session proof-admission suite imports the concrete instance's
positive and weakened-proposition rejection tests. The normal Core target loop
discovers the new real fixture. This is an additive admission boundary, not an
extra reusable-action registration or new CI dispatcher. A model proof or a
selected local JS pass is not a three-target integration result.
