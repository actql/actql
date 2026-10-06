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

`Events.lean` instantiates the composition law with distinct Rows and Events
carriers. Events has separate key/time/property records; it does not simply wrap
an unchanged Rows value. A structural encode/decode theorem preserves the ordered
records. The middle observation reconstructs Rows from those Events records, and
both stages discharge the same shared observation-composition premises.
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
| Concrete semantic instance | Ten Events model theorems, including encode/decode, the established intermediate admission and sequential postcondition; shared composition theorems are applied, not reimplemented |
| Intermediate Events observation | Actual stored identity/time role names and clock encoding, identity index, public material schema, record count and typed record fields compared independently before projection |
| Real Bridge connection | Existing `local_bridge` entrypoints, exact prepared occurrence/input binding, Carrier projection and completed-output port matching |
| Independent checked contract | Authored field names, Number/Timestamp/Text shapes and nullability compared with the schema of that same checked/lowered projection |
| Execution values | Real public column names/order and cells compared with independent expected rows; empty/all-NULL type checks are explicitly checked-contract evidence |
| Shared execution | Both real Bridge kernels use the existing bounded Session. Its counter/token/terminal/cleanup model and finite Session correspondence remain separate evidence and retain their callback premises |
| Provider / Host ownership | Existing Events retained-input, foreign-owner, two-consumer, cancellation, limits and provider material/view lifetime tests remain in place |
| Resources / physical lifetime | No physical heap upper bound, GC completion, unconditional capacity or new cancellation guarantee is derived from the semantic composition law |

The new fixture directly runs Rows → Events → Rows, without a watermark in
between. It checks empty, all-NULL payload, repeated payload with distinct IDs
and non-sorted clocks, plus timestamp and decomposed text with CRLF. The
intermediate Events carrier is observed before running the projection, so a pair
of inverse mistakes cannot be concealed by a successful final round trip. Its
record values use the same independently authored expectations as the final Rows;
expected values are never read back from the intermediate output. The existing
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
4. Register the exact proof command and each target-specific fixture in the
   existing action catalog/recipes. Bind proof inputs, fixture/package closure,
   prerequisites and residual obligations. Run the focused proof admission and
   affected real Bridge fixture; state target and revision. Three-target
   integration remains a CI obligation.
5. Keep physical/provider acceptance where its scope differs. Do not copy the
   common Session protocol suite for each new semantic operation.

Focused commands (from the repository root, using the installed pinned tools):

```sh
node scripts/local-checks.mjs test node --timeout-seconds 60 -- proofs/bounded-session/proof-check.test.mjs
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_integration/events_bridge_evidence_wbtest.mbt --deny-warn
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_integration/local_carrier_events_wbtest.mbt --filter 'rows to Events rejects duplicate semantic identities' --deny-warn
```

## Executed evidence admission

`evidence.mjs` defines one conditional Bridge claim per target. The existing
Session runner executes `events-model` once and `events-connection-{target}`
alongside every previous obligation. The original 26 action descriptors remain
unchanged; four additive actions make the current inventory 30. Their required
commands, counts, scope and prerequisites are checked against the same recipes
at collection and final admission. All four new actions execute fresh.

The producer binds the Bridge proof source separately from the common Session
snapshot and derives the claim only after the exact 16-theorem/type/axiom check,
target-specific real fixture, source/artifact identity and Session evidence
pass. Git source membership includes new files and excludes ignored generated
outputs; missing required proofs and symlinks reject. Immutable action receipts
also bind file modes and recursive directory membership through the existing
input extractor. An ignored local cache is not a proof input.

The dependency is the direct bounded Session, not the managed adapter. The
existing adapter actions still execute, but their cumulative-to-delta or cleanup
completion guarantees are not attached to this Bridge. The claim keeps both
semantic preservation premises, intermediate admission and every residual
obligation above; it cannot upgrade finite tests into verified refinement.

Existing producer collection and the final archive consumer require all 30
receipts. A focused controlled-receipt regression sends this actual inventory
through the executed Lean plan checker and bound final certificate; removing
any of the four new obligations or substituting Native for JS is refused.
That regression tests admission, not physical execution of those fixtures.
Actual three-target execution and authenticated hosted acceptance remain CI
evidence. No additional reusable action or dispatcher is introduced.

The existing Session proof-admission suite imports the concrete instance's
positive and weakened-proposition rejection tests. A deliberately incorrect
clock mapping is also refused by the real model proof; this is model admission,
not a claimed mutation detection in MoonBit product code. The normal Core target loop
discovers the new real fixture. This is an additive fresh admission boundary.
A model proof or a
selected local JS pass is not a three-target integration result.
