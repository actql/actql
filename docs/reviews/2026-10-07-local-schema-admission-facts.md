# Immutable Relation schema admission facts

## Source and connection

Base: main `b98a50ff763d1367e344fdfa8aea380ec8749132`.
Branch: `perf/local-schema-admission-facts`; target: main, with no unmerged
parent dependency. The JSON-name cursor in #663 is independent of this unit.

`bounded_binding_input_charge_cell` and retained row/wire readers repeatedly
call `all_fields_required`. Previously, a scoped schema inspected its entire
field array per call. `has_qualified_fields` likewise searched the array.
These scans are synchronous inside otherwise stepped consumers; an admissible
wide schema therefore adds hidden width-dependent work to a cell poll.

The existing schema constructor already determines whether any field is
conditional or qualified while validating/copying the declarations. Schema now
retains those two immutable Boolean facts, and both readers return the facts
directly. Object admission initializes Required/unqualified without traversal.
No new array, duplicate validation, callback, cursor, ledger or admission owner
is introduced. The private schema record retains two additional scalar flags;
this is not a claim of a measured physical heap bound.

Field presence remains independent of nullability. Facts belong to the opaque
schema, not a caller-owned entry array or serialized authority claim. Restored
schemas derive them through the same constructors. Field/schema wire, canonical
ordering, identity, liveness checks, logical work and runtime workspace remain
unchanged. Other metadata/name lookup and prepare-time scans remain separate.

## Evidence

The 257-column corpus independently covers all four combinations of
qualification and conditional presence. Nullable columns stay Required unless
explicitly declared Conditional. Clearing construction arrays or returned
field views leaves the admitted schema and facts unchanged. Existing tests
cover dense/object admission, bounds and typed refusals.

Focused JS checks passed 29/29 (`run-573XnF`, `focused-test-zQONLm`), including
schema, input/snapshot presence, bounded filter/derive/selection, cancellation,
cleanup and fixed independent schema CID vectors. This is semantic/resource
regression evidence; no wall-clock performance benchmark was run.

The existing public binding Program exercises the current Graph constructor,
sparse node rows, filter, derive, mandatory-column projection, real retained
Store, three Named Results, reopen/read and same-request reuse. Two companion
cases cancel after positive filter/derive progress and keep private custody
until confirmed stop and cleanup.

The first public invocation passed cancellation 2/2 but failed the success
oracle: Graph identity JSON cells were expected without their typed envelope.
The current normative `common-expression-contract.typed-json-wire` and
`result-delivery.typed-json-wire-profile` require `{"$json":payload}` in both
retention and delivery. The independent Graph definition domain/key/descriptor
and row order are preserved; only this envelope was added to the fixture.
No observed product values were copied into the oracle. The current Graph
source fixtures already use the same envelope. The corrected public selection
passed 3/3 (`run-QxHt1B`, `focused-test-IgNWmq`). A JSON column contract assertion
is included in the final public test. Final source SHA/receipts are in the PR.

Local Node and Run Host Core were rebuilt from the changed production sources.
Runtime bundles remain ignored. `moon info --target js src/relation_schema`
preserves the opaque public interface. Unexecuted target or distribution
coverage is not implied by API generation.

## Remaining verification and work

No wrong-result counterexample or timing measurement is claimed for the old
fact readers; their width-dependent loops are established directly by source.
This closes only those repeated immutable scans. General field-name lookup,
binding preparation, per-poll input lists, legacy drains, physical aggregate
bytes and runtime buffer assembly remain distinct residuals.

Full Core, proof, performance, Wasm/native execution, packed/HTTPS acceptance
and whole-Run accounting were not run. The public test uses checkout runtime
packages, not a pristine packed distribution. Automatic submitted-SHA CI is
reported separately, without manual retry or inferred success.
