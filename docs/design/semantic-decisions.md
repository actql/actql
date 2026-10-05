# Semantic decision criteria

This guide governs design proposals and reviews. It is not a second language
specification: accepted behavior belongs in the normative owners, grammar and
applicable machine contracts. A preference below does not authorize an
implementation to accept syntax that the specification has not admitted.

## Evidence and authority

Start with explicit normative requirements and recorded agreements. Compare
prose, grammar, machine schemas, acceptance cases and relevant decision records.
If they disagree, report the disagreement instead of silently choosing the
most permissive, strictest or easiest source. Distinguish a clarification from
a change to an existing rule, including an exception to a general rule.

Inspect relevant reference implementations at fixed revisions. Their code,
tests and adapters are evidence and reusable implementation material, not
automatic authority over ActQL. Record meaningful differences rather than
assuming all reference implementations agree. Backend limitations belong in
the implementation compatibility plan, not in an invented language prohibition.
An unresolved backend gap also prevents claiming execution support.

## Unspecified boundaries

For an empty collection, repetition or other edge case, first apply the ordinary
meaning of the operation. Describe the resulting values, multiplicity, schema,
order and evidence. Prefer acceptance when that meaning is unambiguous and
preserves existing invariants; this is a design preference, not a claim that
the current specification already accepts the case.

Additional rejection needs a concrete reason: for example duplicate output
names, an unrepresentable result, unresolved ambiguity or an explicit contract
violation. Low expected usage, possible authoring mistakes, ease of implementation
or rejection by reference code alone are insufficient. Advisory lint may flag
suspicious but valid input. An intentional product restriction is still possible,
but needs an explicit rationale and agreement rather than being disguised as
semantic necessity.

Shared syntax should reuse shared meaning where applicable. Similar spelling
does not erase operation-specific behavior: an empty partition key can denote
one global partition, while aggregation and representative-row selection still
differ on empty input. Likewise, repeated partition keys do not create output
columns, whereas repeated projection fields can create forbidden duplicate names.

## Vocabulary across representations

Use the adopted specification's vocabulary for concepts with the same meaning.
Frontend syntax, checked Program, AoA IR, diagnostics and documentation must
not accumulate unexplained synonyms or semantic drift. GoogleSQL is the
reference for the adopted SQL/Pipe profile; GQL, VecA and TEA surfaces must name
their own adopted specifications. This is not a blanket compatibility claim.

Different abstraction levels need not use identical names: SELECT can lower to
projection. Record the mapping and the preserved meaning. Distinguish aggregate
groups, analytic partitions and window frames, event-time windows, final query
order and partition-local order. Do not approximate a missing IR meaning in the
frontend; identify the exact missing contract and coordinate with Compute or
Host owners.

Use the [standard-profile ledger](frontend-standard-profiles.md) to distinguish
GoogleSQL, SQL/PGQ-derived mapping, GQL syntax evidence and ActQL extensions.
Meaning preservation is relative to the applicable admitted contract pins; it
does not freeze historical Program or kernel behavior against an adopted
standard-alignment decision. A conflicting common meaning must change in its
normative owner and dependent laws, schemas, pins and independent expectations.
Do not hide that change in source spelling, a Frontend evaluator or a vendor
procedure with a merely similar name. A supported subset and an implementation
gap are different from an intentional semantic deviation.

Limit terminology cleanup to the affected implementation. Internal renames are
separate from wire or canonical-preimage changes. The latter require their
schema, pins and independent fixtures to move together on the agreed version.

## Keep the boundaries separate

- Syntax acceptance is not proof of type correctness or execution support.
- Type checking is not proof of stable order, uniqueness, bounded execution,
  identity evidence or permission to publish.
- Unfinished obligations must remain explicit and be discharged at the required
  boundary. They are not permission to postpone static errors until runtime.
- A no-op preserves its input evidence; it does not fabricate new evidence or
  prevent a later consumer from establishing evidence by its own permitted rules.
- Acceptance of a no-op or repeated condition does not authorize operation
  deletion, preimage deduplication or CID equivalence with a different source.
- Bounded implementation support is not a restriction on the entire language.

## Decision record and completion

For each disputed case, state: the current requirements; reference behavior;
the proposed semantics and reason; whether this clarifies or changes a rule;
effects on identities, proofs and consumers; and remaining implementation gaps.
Get agreement before changing acceptance unless the user has explicitly delegated
specification decisions. Under that delegation, investigate the competing
evidence, select the recommended semantics, record the rationale and impact,
and proceed without another approval round. Report the decision; do not hide
it as an already-existing requirement. Escalate choices outside the delegated
scope or requiring additional authority. A later proposal should identify new
evidence or an explicit decision change, not merely a different reviewer preference.

After agreement, update normative prose, structural grammar, applicable schemas
and their dependent pins/requirement records together. Add fixed positive,
negative and boundary expectations when implementing the affected operation.
Verify the implementation on all supported targets and report execution evidence
separately from documentation and regeneration checks.

## Ordering and deduplication decisions

The normative owners are [sort](../spec/language.md#sort) and
[distinct and dedupe](../spec/language.md#distinct-and-dedupe).

| Case | Decision and rationale |
| --- | --- |
| Empty sort | Identity operation, retaining existing order and evidence. This is an explicit exception to sort's candidate-key completion, not an instruction to synthesize a sort. |
| Empty keyed distinct | Rejected, consistent with its select projection and the existing prohibition on empty select. Never reinterpreted as whole-row distinct. |
| Repeated distinct fields | Rejected because projection cannot create duplicate output names. |
| Repeated dedupe keys | Accepted and retained; they do not duplicate output fields or strengthen uniqueness/tie evidence. |
| Empty dedupe keys | Accepted as one global partition; a nonempty order selects its first existing row, with top ties failing and empty input yielding no row. |

Empty dedupe keys are not a no-op. Their acceptance follows partition semantics,
not an assertion that every empty operation is an identity. Global aggregation
can emit an aggregate row for empty input; dedupe cannot invent a representative
row. It also differs from sort followed by take-one because dedupe retains its
mandatory top-tie failure rule.

Implementation follow-through remains necessary: the existing AoA adapters reject
empty order terms and empty dedupe keys, and the limit adapter does not forward
offset. Lowering must implement the admitted behavior without removing the
authored semantic operation or claiming unsupported execution conformance.
The type-checking increment does not implement those adapters or proof propagation.

## Graph snapshot identity for Delta

The normative owner is
[Graph equality and Delta](../spec/language.md#graph-equality-and-delta).
The original Delta contract required exact base and target graph CIDs but did
not define their preimage. That omission made independently implemented
`graph_diff` and `apply_graph_delta` unable to establish the same identity.

The previous four-element `actql-graph-snapshot/0.1` preimage conflicts with
the sole current Property Graph snapshot owner, which also saves admitted
definitions. The approved replacement is the canonical JSON array
`["actql-property-graph-snapshot/0.1", graph_contract_cid,
admitted_definition_body, nodes, edges]`. Delta base and target identities use
that formal snapshot CID, not another implementation-specific graph digest.
This changes the previously prescribed Delta identity domain; the old preimage
is retired, with no guessed conversion or compatibility fallback.

Complete records are the current snapshot's node `{id, key, props}` and edge
`{dst, id, key, props, src}`. The existing snapshot and Graph storage owners
validate the definition/domain/type bindings, original key components,
per-definition properties and endpoint identities. Both node and edge order
use their independent typed identities; parallel edges cannot collapse into
endpoint tuples. Labels and key-column metadata remain in the saved admitted
definitions, rather than being reconstructed from current data or a catalog.

This decision adds neither an authority nor another Graph runtime or snapshot
owner. Exact-before matching, atomic application and target-CID verification
are unchanged. The CID is computed only where Delta semantics or another
selected contract requires it. Input enumeration, storage indexes, provider
identity and physical allocation do not participate. Existing canonical values
and the formal snapshot body remain unchanged; Delta's dependent contracts,
requirement records and independently authored vectors must use the formal
snapshot identity. Kernel acceptance alone does not establish Program or
public Host support for diff/apply.

## Result publication limit binding in an Executable Plan

The language already requires every Result publication limit to bind to the
actual Unit Result port and its `rows` or `bytes` measurement. The previous
Executable Plan schema only offered barrier, AoA step/output, and input
preflight targets. None identifies a Result publication port, and an AoA output
byte limit has a different measurement subject. This was a machine-schema gap,
not a new publication rule.

The `result_publication` target carries the Unit Definition CID, authored
Result name, and measurement. The checker must compare those fields with the
resolved limit's escaped `subject_ref` and the checked Unit port before issuing
or accepting a Plan. This clarification changes the Executable Plan and Plan
Document schema CIDs. It does not change Unit Definition identity or permit a
schema-valid Plan to run without that semantic validation. Issuance and
validation remain implementation work.

## Plan fact manifest body

The language requires a content-addressed `actql-plan-fact-manifest/0.1`
containing resolved limits, fixed laws and Contract facts, while the existing
Executable Plan schema already defines their closed `plan_facts` union and a
`plan_fact_manifest_cid`. The standalone manifest body was not registered.
The adopted body carries the same `plan_facts` array, its version and its own
CID. The Executable Plan must reproduce the referenced array exactly; array
order is identity-bearing and no fact is silently inserted or dropped during
admission. This fills a missing structural preimage without adding fact kinds,
changing Program Definition identity, or authorizing an incomplete Plan.
The new manifest schema and artifact-registry CIDs change. A compiler must
still derive the complete facts from checked owners and validate their laws,
dependencies, resolved minima, executable consumers and current Host policy.

## Canonical group null placement

The normative owner is [group](../spec/language.md#group). Its final output uses
lexicographic ascending key tuples in authored `by` order, NULLS FIRST at each
component. This fills a previously unspecified null-placement boundary; it is
not a claim that all earlier implementations agreed. The prior ascending AoA
wording and the adopted `REL.groupBy` law (null keys are first-class keys) did
not independently specify placement. The non-null canonical order and grouping
equality are unchanged. Authored sort's default NULLS LAST does not apply.

At AoA revision `dbab4fe8c1d624d81ed967f90e2abe742163f84f`,
`packages/rela/src/exec-js.ts` uses `canonicalGroupTypeRank(null) = 0` and a
lexicographic comparator for aggregation groups. Its empty-aggregate path instead
preserves first occurrence, so ActQL still requires its final canonical sort.
At Sketch revision `87dc7144138edfcba108cdc59dc485ac976ba976`,
`src/actql-compiler.ts` adds `REL.orderByStable` with explicit `nulls: 'last'`
after grouping. That final order differs from the decision here, even though
`src/actql-expression-fragment-v2.ts` delegates grouping to AoA.

NULLS FIRST preserves the selected AoA aggregation convention and the current
lowering convention without importing authored-sort defaults. Compatibility with
the cited Sketch final output requires changing its generated sort terms; this
is an observable ordering difference, not an identity-neutral implementation
optimization. No source spelling or identity preimage is rewritten. The adopted
primitive law body is unchanged: ActQL specifies the final group order rather
than changing every use of primitive `REL.groupBy`. Independent numeric/null
vectors are in `portability/corpus/group-canonical-order.json`; they specify the
ordering boundary, not backend execution certification.

## Common membership and empty sets

The normative owner is [common membership](../spec/language.md#membership-semantics).
The previous general strict-null rule made nullable collection membership
propagate null. The adopted GoogleSQL alignment changes that rule explicitly:
`in` and `not_in` treat both a null array and an empty array as an empty set,
with false/true respectively for every admitted left value, including null.
A null element in a nonempty collection remains an unknown comparison; an
actual match wins over such an unknown. `not_in` is three-valued negation.

The reference is Google's published [IN operator](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators#in_operator)
and [UNNEST null handling](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#unnest_and_null_values).
These distinguish a null array (zero rows) from an array containing null (a row
with a null value). ActQL adopts that distinction in the common expression
contract rather than keeping a separate nullable-list exception or rewriting
only Frontend expressions. This is a semantic change, not a clarification of
the former strict-null behavior.

The common type rule excludes container nullability and proves a non-nullable
Boolean result for a zero-item contract. Scalar domain checking, eager operand
evaluation, failure precedence and optimization identity remain in force.
Constant evaluation uses the same rule, including for typed null operands and
empty collections; failure suppression is not an allowed empty-set rewrite.
The current canonical lowerer retains authored expressions without constant
folding. This alignment does not introduce a physical optimizer.
The expression law body and dependent contract, registry, grammar and consumer
pins change together without a version bump. Independent truth-table and type
fixtures record the new expectations rather than copying evaluator output.
Existing pinned contract bodies retain their previous meaning.

Set meaning does not expand source syntax. SQL `IN ()` remains rejected, and
this decision does not add `UNNEST` or subquery support. Execution conformance
still requires the affected shared evaluator and consuming boundaries to be
verified on their supported targets.
