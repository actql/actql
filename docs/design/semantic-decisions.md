# Semantic decision criteria

This guide governs design proposals and reviews. It is not a second language
specification: accepted behavior belongs in the normative owners, grammar and
applicable machine contracts. A preference below does not authorize an
implementation to accept syntax that the specification has not admitted.

## Evidence and authority

### Host-verified Source Request value policy

The accepted request-provenance rule does not treat authored literals, scalar
Parameters, defaults or successful type admission as classification authority.
This left legitimate installed file-listing requests unknown at Model admission
even when a Host could verify their exact value contributors. The adopted
extension lets that Host bind evidence through the existing Checker/policy owner,
not through an authored Program flag or a default classification.

Evidence retains the Program Definition and effective Parameters CIDs, the
Stage/input occurrence, SourceView contract, exact static request identity and
its contributing admitted data-policy Envelope. The response policy remains a
separate contribution; keyed correlation retains its original producer policy.
Missing, duplicate, foreign and mismatched evidence does not discharge unknown
provenance, and an admitted unknown policy remains unknown. Request identity uses
the existing value wire emitter without configuration string normalization.

This adds a trusted Host admission path, not a Model invocation grant. Current
Source and destination authorization, egress, scope and separate approval remain
mandatory. Evidence must be rebound and checked against the original subjects on
recheck or recovery. The effective-policy closed preimage and deduplicated
admitted policy reference sets are unchanged; occurrence correspondence stays in
the owner rather than being inferred from an equal policy CID.

Public Host installation, real keyed Content-to-INFER acceptance and continuation
coverage remain implementation obligations; a portable Checker test alone is
not evidence that those boundaries execute.

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

## Delayed Model invocation authority and recovery

The Run protocol previously classified inference as `read` and its closed
Checkpoint table had no Model-invocation combination, while installed Model
dispatch evidence already identified operation `infer`. The adopted rule
classifies metadata inspection as `read` and provider invocation as `infer`.
This is an explicit contract change resolving conflicting evidence. Finite
grants and bootstrap profiles are not silently broadened; `{all: true}` keeps
its existing current-and-future meaning.

The new `actql-model-invocation-scope/0.1` and
`actql-model-provider-binding/0.1` originals bind the exact ordered call set,
Run occurrence, input, barrier, installed provider and activation context.
They preserve existing call-slot and fixed-request identities. The activation
subject is the completed scope CID, excluded from its own context preimage.
The review and compatibility approval retain the actual Run PreparedInvocation
original rather than renaming the new scope as a PreparedInvocation.

Approval applies to the fixed call set, but durable dispatch ownership is per
call. A whole-set once-only marker would unnecessarily strand proven-unsent
calls after one response is saved and another is lost. Recovery instead reuses
saved responses, never resends possibly sent calls, and permits proven-unsent
work only while current approval, infer authority and egress hold. Unknown
attempt evidence is not a fabricated provider failure or completed slot.

This updates initial 0.1 schemas, pins, signed wire fixtures and SDK kind
handling together. Historical authority/response bytes remain admissible only
for no-send replay; absent scope evidence is never upgraded into send authority.
Contract-vector coverage is not evidence that every Host and execution target
implements the new continuation boundary. Unsupported consumers refuse it.

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
the sole current Graph snapshot owner, which also saves admitted
definitions. The approved replacement is the canonical JSON array
`["actql-graph-snapshot/0.1", graph_contract_cid,
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

## Confirmed cancellation of a running Run

The public transition table omitted `running` → `cancelled`, while the common
unpublished-Run observation issuer and installed Host cancellation path already
reported a confirmed stopped execution as cancelled. Registering immediate
Model work in the existing Checkpoint journal exposed that disagreement.

The adopted clarification permits this transition only after admitted
cancellation and confirmed physical stopping, with no unresolved execution,
Effect or publication outcome and no committed publication. A committed
publication still determines success; a lost response remains unknown and is
never resent. This aligns the transition table and journal lifecycle with the
existing physical observation boundary. It adds no public state, artifact,
identity domain or permission to release retained evidence before cleanup.

## Unary Unicode TRIM

The normative owner is [Scalar expressions](../spec/language.md#scalar-expressions).
The previous scalar law and language prose selected only ASCII whitespace,
while the adopted [GoogleSQL TRIM reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#trim)
removes leading and trailing whitespace when its optional character set is
omitted. The common syntax and type rule already admitted unary `trim`, but
that alone did not establish common execution support.

ActQL now selects the 25-code-point `White_Space` property in
[Unicode 16.0 PropList.txt](https://www.unicode.org/Public/16.0.0/ucd/PropList.txt),
consistent with its pinned Unicode data version. This explicitly changes the
former ASCII-only contract; it is not a claim that the GoogleSQL page pins a
Unicode release. U+0085 is included; U+FEFF and U+200B are excluded. Host trim
routines and regular-expression whitespace classes are not substitute owners.
Retained interior strings, combining sequences and line breaks are preserved
without normalization. Nullability, unary arity, lazy demand and authored-node
retention keep the existing common expression rules.

The scalar manifest and containing expression law receive new CIDs, together
with their AoA, registry, environment, compilation and consumer dependencies.
The existing source and machine schema shapes are unchanged. Frozen predecessor
bodies keep the old ASCII-only meaning and their original identity preimages;
they are not regenerated from current bodies with selected laws removed.
This initial 0.1 alignment adds neither an optional set or BYTES overload nor
LTRIM/RTRIM. Contract registration does not establish execution conformance on
an unverified target or consumer.


## Unary Unicode side trimming

The normative owner is [Scalar expressions](../spec/language.md#scalar-expressions).
The GoogleSQL [LTRIM](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#ltrim)
and [RTRIM](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#rtrim)
references select the leading-only and trailing-only variants of trimming.
That unary increment admitted only their unary STRING form, using exactly the pinned
Unicode 16.0 `White_Space` set already selected for unary TRIM. This is an
explicit ActQL Unicode pin, not a claim that the GoogleSQL pages pin a release.
The opposite end and all retained scalar sequences are unchanged; combining
sequences and line breaks receive no normalization or special conversion.

New closed source and machine schema cases and scalar laws receive coordinated
expression, scalar-manifest, AoA, registry, environment, compilation and consumer
identities. Exact predecessor bodies and complete identity preimages are frozen
before extending the current owners; existing history remains immutable. TRIM
kept its adopted two-sided rule. Optional trim sets, BYTES and collation were
excluded at that adoption; the following decision extends STRING sets.
Registration alone does not establish execution conformance on an
unverified target or consumer.


## Explicit STRING trim character sets

The normative owner is [Scalar expressions](../spec/language.md#scalar-expressions).
The selected GoogleSQL [TRIM](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#trim),
[LTRIM](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#ltrim)
and [RTRIM](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#rtrim)
references define the optional STRING argument as a set of Unicode code points.
Their combining-mark example makes membership independent of the surrounding
base character. Accordingly, this increment admits exactly two STRING operands
for each operation; substring, grapheme and normalized matching are excluded.
Duplicates and order in the set do not affect values, and an empty explicit set
is a no-op rather than a request for the omitted whitespace default. Unary
behavior keeps the existing explicit Unicode 16.0 White_Space pin.

The existing tags retain their unary expression body and additionally admit an
exact two-element operand array in common source and machine forms. This avoids
rewriting authored unary nodes or changing their canonical bytes. Equivalent set
values do not authorize constant folding or deduplication of authored children.
The common strict-null rule evaluates both demanded children once, left to
right, before propagating NULL, preserving a failure in the second child after
a NULL first child. Runtime membership work, including large sets and repeated
nonmatches, remains subject to the existing cooperative budgets and cancellation.

Exact pre-set contract bodies, complete identity envelopes and independent
Values Program/Run preimages are retained before changing the owners; older
history is unchanged. Schema, scalar law, expression and dependent identities
move together. This initial 0.1 extension does not admit BYTES or collation and
does not claim conformance on unverified targets or live BigQuery.


## GoogleSQL STRING substring and profile ownership

The current normative owner is [Scalar expressions](../spec/language.md#scalar-expressions).
Google's [SUBSTR/SUBSTRING rule](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#substr)
uses optional length, one-based positive positions, zero-to-one clamping and
end-relative negative positions. The previous common declaration used exact
interval intersection, fixed arity and the optional text-time profile:
`substring('abcd',0,2)` meant `a`; the aligned rule means `ab`. That is a semantic
change, not a spelling alias. Before this change the text/JSON checker and
text-time bound derivation admitted substring, but executable lowering rejected
its unresolved HostEnvelope and did not implement its tag; SQL/Pipe did not
admit either public spelling.

Keep one common `substring` tag with `{value,start,length?}` and its matching
machine body. Both documented SQL spellings lower to that owner. Preserve
omission as omission and retain every supplied child once in authored order.
This adds no frontend evaluator, sentinel expression or fallback alias. The
existing finite binary64 domain accepts only safe-integer indices; full INT64
and BYTES remain explicit coverage gaps.

Substring now uses the existing scalar continuation's bounded count, boundary,
sizing and construction passes. The scalar work/live-value/workspace and
cancellation owners remain authoritative. Removing substring's text-time
membership is a coordinated current-contract change, not permission to ignore
other pending obligations. Current profile source/envelope/barrier schemas
omit substring, while the inherited base and all historical snapshots keep
exact old bodies and CIDs. Nested profile operations retain their own profile,
pattern, policy, envelope and preflight obligations, even in skipped branches.

A substring result inherits sound input byte/codepoint maxima, drops minimum
length and unions all supplied nullability. Type checking neither evaluates
length nor rejects invalid literal data. This preserves directly known upper
bounds. Profile-produced extents derived after typing do not pass through a
new invented substring envelope: an outer profile falls back to its checked
input contract or selected-policy preflight. Consequently some formerly
checkable nested profile plans may need a wider conservative bound and fail a
tight policy that admitted the old profile chain. The current contract records
that compatibility effect; it does not claim unchanged historical admission.


## Finite-number SAFE arithmetic

GoogleSQL [SAFE arithmetic](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#safe_divide)
converts the operation's own arithmetic error into NULL, and its
[floating-point rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/data-types#floating_point_semantics)
classify non-finite output from finite inputs as overflow. Thus a zero-only
safe division rule is insufficient for SAFE_DIVIDE.

The normative owner is [Scalar expressions](../spec/language.md#scalar-expressions).
The existing `safe_div` spelling already means zero-divisor null with overflow
failure. That original meaning is retained. New `safe_divide` is a distinct
closed common operation with GoogleSQL zero-divisor-or-overflow null semantics;
the SQL/Pipe function SAFE_DIVIDE lowers to it, not to the legacy spelling.
SAFE_ADD, SAFE_SUBTRACT, SAFE_MULTIPLY and SAFE_NEGATE use the same existing
arithmetic evaluator and retained-expression continuation. Only the arithmetic
result at the operation boundary is made safe. This follows the documented
[SAFE error boundary](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/functions-reference#safe_prefix).
Child errors and all resource
or cancellation failures retain their original owner and precedence.

This increment admits the existing finite binary64 Number domain. Underflow is
an ordinary finite result and operation-boundary zero is canonical positive
zero. Binary safe operations produce nullable Number; safe negation preserves
operand nullability because negation cannot overflow for finite binary64.
INT64, NUMERIC, BIGNUMERIC, Decimal and non-finite overloads are not implied.
The initial 0.1 expression, scalar-manifest, schema and dependent identity
contracts change together, retaining exact predecessor bodies and preimages.
Registration alone is not execution conformance for an unverified target.

## Finite Number powers, exponentials and logarithms

The scalar surface adds POW/POWER, EXP, LN, LOG and LOG10 for the existing finite
binary64 Number domain. GoogleSQL's mathematical-function documentation supplies
the finite-FLOAT64 domain, strict NULL, overflow and underflow rules. This does
not add distinct INT64, NUMERIC or BIGNUMERIC domains, coercions, non-finite values,
or GoogleSQL MOD: MOD has no FLOAT64 overload. The existing internal modulo
operation and `%` retain their existing meaning.

POW requires an integral exponent for a negative base. Integrality is tested in
binary64 before any bounded integer conversion, so representable integral
exponents at and beyond 2^53 remain valid. Either sign of zero to a negative power
fails; zero to zero is one. POW and EXP preserve representable subnormals, return
canonical positive zero on unrepresentable underflow, and fail if a finite input
produces a non-finite result. LN and LOG10 require positive input. Binary LOG
requires a positive value and positive base other than one; bases between zero
and one are allowed. Successfully evaluated NULL operands propagate before these
value-domain checks, while demanded child errors retain their original owner.

The canonical unary operators are exp, ln and log10, and the canonical binary
operators are pow and log. SQL POW/POWER and expression-text pow/power share pow.
SQL LOG(x) and expression-text log(x) normalize to unary ln; canonical JSON log
remains a two-element argument array. Group-function identity recognizes the
LOG/LN synonym only at arity one. No generic lowered-operator fallback changes
existing alias identities or malformed-arity behavior.

Implementation reuses the existing canonical scalar, continuation, resource and
cancellation owners with the pinned portable MoonBit core Double algorithms
in `src/scalar_numeric_kernel`, selected identically on all three targets. Binary LOG
uses ln(value)/ln(base), matching GoogleSQL `Logarithm` at selected revision
`81c15b796138185c046aefe852321011fdf96615`. The target-selected platform-library exception is rejected because pure
scalar observations retain exact capture/replay identity. Identical admitted
inputs and selected contracts use identical pinned arithmetic across JS,
WebAssembly and Native. The demonstrated exact-bit counterexamples are retained
independently. Live BigQuery last-bit equality is not claimed. No frontend-local math engine or permissive fallback is
introduced.

References:
- https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions
- https://github.com/google/googlesql/blob/81c15b796138185c046aefe852321011fdf96615/googlesql/public/functions/math.h

## Finite Number GREATEST and LEAST

GoogleSQL accepts one or more compatible orderable arguments, propagates NULL,
and evaluates ordinary function arguments before applying the function. Its
STRING ordering is by Unicode code point. ActQL's existing shared comparison,
ordering, aggregate extrema and canonical-name paths use UTF-16 code units.
U+10000 sorts before U+E000 in UTF-16 but after it by Unicode code point.
Changing that shared law would affect identities and callers outside numeric
extrema, while a function-local STRING comparator would create a second meaning.

The adopted bounded implementation therefore supports finite Number arguments
only, reusing the common finite-number comparator and Many continuation. Other
orderable overloads remain explicit implementation gaps, not claims of GoogleSQL
conformance or new language-wide prohibitions. No IEEE specials or decimal
coercions are added. NULL never skips another demanded argument; outer lazy
branches remain lazy. Singletons, repetitions and authored order remain in
canonical lowering. The unique number signature resolves immediate and all-NULL
arguments to nullable Number. Existing work, live-root, frame and workspace
limits and cancellation cleanup remain with their existing owners.

Sources: [GoogleSQL mathematical functions](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#greatest),
[STRING comparison](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/data-types#string_type),
and [conditional expressions](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/conditional_expressions).

## GoogleSQL STRING side slices and padding

The common scalar owner adopts GoogleSQL
[LEFT](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#left),
[RIGHT](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#right),
[LPAD](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#lpad)
and [RPAD](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#rpad)
for STRING Unicode scalar counts in the finite safe-integer length domain.
Negative/nonintegral/unsafe lengths and explicit empty pad patterns fail on a
demanded non-null call after all children succeed. The pattern may be a dynamic
String expression, unlike regex patterns; omission alone supplies a space.
No BYTES or collation overload is introduced.

Each operation has one ordered common source/machine array. Although LEFT can
be expressed by a fixed-start substring, symmetric explicit side operations
retain direct source identity and do not expand authored children. In particular,
SUBSTR(value,-length,length) would duplicate RIGHT's length operand; this is not
an acceptable lowering. Runtime sides and padding reuse substring's bounded
count/boundary/sizing/construction continuation instead of adding a text engine.
Padding repeats one scalar per charged poll during sizing and construction;
output storage is allocated only after complete byte/workspace admission.
Side slices preserve sound input maxima; padding drops them rather than assuming
that a dynamic target length is bounded by the input.

Existing immutable typed arrays can represent SPLIT's Array(String) result, but
that operation is not added by this decision. It requires separate bounded
split construction and array-accounting integration with the existing owners.


## GoogleSQL STRING repetition and reversal

The normative owner is [Scalar expressions](../spec/language.md#scalar-expressions).
GoogleSQL [REPEAT](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#repeat)
takes a STRING and INT64 count, rejects negative counts and returns empty for
empty input. [REVERSE](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#reverse)
reverses STRING characters. The fixed Google reference at
[`81c15b796138185c046aefe852321011fdf96615`](https://github.com/google/googlesql/blob/81c15b796138185c046aefe852321011fdf96615/googlesql/public/functions/string.cc#L1624-L1678)
validates a negative count before the empty-input shortcut and traverses Unicode
code points backward for reversal.

ActQL's adopted increment uses its existing finite binary64 Number domain for
REPEAT's nonnegative integral count. This is a new scoped adaptation, not a
claim that a FLOAT64 overload exists in GoogleSQL or an earlier ActQL law.
An additional safe-integer or INT64 ceiling would reject otherwise meaningful
empty repetitions without solving a resource problem. Accordingly even an empty
STRING with a very large valid count returns empty after successful demanded
children, strict NULL propagation and domain validation. Nonempty output is
bounded by existing storage limits before integer narrowing; complete output
admission then uses the existing work, live-value, output-byte and workspace
owners before allocation. Reversal preserves complete Unicode
scalars, including combining marks, without grapheme segmentation or normalization.
The separate existing safe-integer rules for SUBSTR and padding do not change.

REPEAT has an ordered two-element common source/machine array; REVERSE has a
direct unary body. Both preserve authored nodes and child order without folding
or frontend evaluation. REVERSE preserves its input String bounds; REPEAT drops
those bounds because a dynamic count can empty or expand the result. Their new
closed shapes, laws, grammar and dependent identities change together within
initial 0.1; complete predecessor bodies and preimages remain frozen under the
actual published Unicode parent. No BYTES, new Number domain, profile obligation,
production limit or global comparison law is introduced. Contract registration
alone does not establish execution support on an unverified target or consumer.


## GoogleSQL finite Number cube root

The normative owner is [Scalar expressions](../spec/language.md#scalar-expressions).
GoogleSQL [CBRT](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#cbrt)
returns a FLOAT64 cube root, including negative inputs, and propagates NULL.
The adopted ActQL increment admits exactly its existing finite binary64 Number
operand, with no implicit numeric conversion or new overload. Non-finite input
and the separate SAFE prefix remain outside this increment. Canonical positive
zero and the existing operand/arithmetic failure categories remain unchanged.

The selected MoonBit core math `cbrt` primitive is the implementation owner.
Using `pow(x, 1/3)` would lose the real negative-input operation and logarithmic
reconstruction would introduce an unnecessary numerical algorithm. This choice
preserves the existing finite-math accuracy/exception contracts; it does not
weaken any earlier square-root, rounding, scalar arithmetic or other specified
numeric obligation. GoogleSQL's displayed CBRT example itself illustrates that
a general cross-library last-bit identity is not part of this scoped contract.

The common direct unary source/machine body retains one authored child without
folding, duplication or frontend evaluation. Typing preserves only the Number
kind and input nullability. Grammar, closed schemas, declared laws and current
dependent identities change together within initial 0.1; complete predecessor
bodies and independent preimages remain frozen under the actual published
REPEAT/REVERSE parent. No production limit, profile obligation, Decimal law or
comparison rule changes. Registration alone does not establish execution on an
unverified target or consumer.

The implementation binding for this increment is the already adopted pinned
portable numeric kernel in `src/scalar_numeric_kernel`, not target-selected
platform math. Identical admitted inputs and selected contracts preserve exact
logical Number bits across JS, WebAssembly and Native. Independent finite
accuracy fixtures remain unchanged; they are not a universal accuracy bound
or a claim of live-BigQuery last-bit equivalence. No alternate evaluator or
new tolerance is introduced.


## GoogleSQL finite Number direct trigonometric functions

The normative owner is [Scalar expressions](../spec/language.md#scalar-expressions).
This increment admits the 12 direct unary trigonometric/hyperbolic functions
and ordered binary ATAN2 in the existing finite binary64 Number domain.
[GoogleSQL mathematical functions](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions)
define closed ASIN/ACOS domains [-1,1], ACOSH at or above 1, strict ATANH
(-1,1), radians, and ATAN2's authored first/second quadrant interpretation.
ATANH's prose interval excludes endpoints even though the illustrative table
lists only inequalities outside them. No reciprocal or regex function belongs
to this increment.

Existing strict child demand, NULL propagation, finite-result validation,
canonical positive-zero results and lazy outer expressions remain unchanged.
ATAN2 uses the core primitive directly; reconstructing atan(first/second)
would lose quadrants, zero handling and finite ratios. Raw signed zeros retain
the primitive's quadrant behavior until result normalization, while canonical
public Numbers cannot carry negative-zero wire values. This distinguishes an
internal finite-value diagnostic from a new public value representation.

Every operation uses the same already adopted pinned portable core Double
primitive in `src/scalar_numeric_kernel` across JS, WebAssembly and Native.
Identical admitted inputs and selected contracts preserve exact logical Number
bits; no live-BigQuery last-bit equivalence is claimed and no earlier accuracy
obligation is weakened.
Overflow remains an arithmetic failure; admitted finite input is not a promise
that every hyperbolic result is representable. Closed schemas, grammar, laws,
owned requirements and dependent identities change together within initial 0.1.
The complete CBRT predecessor bodies and independent preimages are frozen at
the actual published parent. Production limits, profiles and barrier bodies
remain unchanged; target and public-boundary support need separate execution
evidence.

The implementation binding for this increment is the already adopted pinned
portable numeric kernel in `src/scalar_numeric_kernel`, not target-selected
platform math. Identical admitted inputs and selected contracts preserve exact
logical Number bits across JS, WebAssembly and Native. Independent finite
accuracy fixtures remain unchanged; they are not a universal accuracy bound
or a claim of live-BigQuery last-bit equivalence. No alternate evaluator or
new tolerance is introduced.


## GoogleSQL STRING translation and occurrence position

The normative owner is [Scalar expressions](../spec/language.md#scalar-expressions).
TRANSLATE adds simultaneous scalar substitution/deletion with duplicate-source
validation. INSTR adds direction, position, occurrence and overlapping matches.
The [GoogleSQL reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions)
defines these operations; only its STRING/default binary behavior is selected.
Exact strings, including astral scalars, combining marks and NUL, are retained
without normalization. Neither operation adds BYTES, collation or regex.

Google's position and occurrence parameters are INT64. ActQL intentionally
adapts them to its finite binary64 Number domain, following the already adopted
REPEAT count adaptation: integral nonzero position and integral positive
occurrence, with no new INT64 or safe-integer cap. Check those domains before
empty or out-of-range shortcuts, then compare with bounded scalar counts before
integer conversion. Huge valid unreachable values yield zero. Earlier SUBSTR,
padding and other numeric domains are unaffected; this is not an INT64 overload.

The prose reference does not detail empty-pattern boundaries. The [pinned Google implementation](https://github.com/google/googlesql/blob/81c15b796138185c046aefe852321011fdf96615/googlesql/public/functions/string.cc#L620-L769)
forward and backward UTF-8 search branches resolve them as
length-plus-one boundaries. Forward search starts at position; backward empty
search starts at length plus position plus two. Thus the default empty/empty
result is one, ('ab', '', 1, 3) yields three, and ('a', '', -1) yields two.
These explicit adopted edges follow ordinary empty-subsequence boundaries and
are fixed independently of ActQL execution; live BigQuery verification is a
separate obligation, not implied by inspecting the reference implementation.

Common strict child demand, later child error preservation, NULL propagation,
lazy outer demand, existing resource admission and cooperative cancellation
remain unchanged. TRANSLATE retains only the input codepoint maximum because
mapping can delete scalars or expand encoded width. INSTR nullability includes
all supplied operands. Canonical arrays preserve authored optional-argument
omission; equal values do not erase identity differences or justify rewriting
INSTR as STRPOS. Initial 0.1 schemas, laws, grammar and dependent identities move
together; published predecessor bodies, profiles, barriers and limits remain
unchanged. Source admission is not execution conformance for unverified targets.

## Text enumeration remains an original Text constraint

The public task contract uses `level: {type: string, enum: [low, medium, high]}`.
The earlier closed ValueContract grammar could represent unconstrained Text and
admitted extents, but not this promised restriction. The adopted initial-0.1
extension keeps enumeration within the existing type/admission/Values owners;
it does not create a second scalar kind, Model validator or permission owner.
The normative owner is [Text enumeration constraints](../spec/language.md#text-enumeration).

Membership is exact Unicode Text intersected with the retained extents. Empty
and repeated vectors are meaningful: no non-null values in the empty case,
and unchanged membership for repetitions. Rejecting these declarations merely
because an implementation uses a unique/nonempty lookup table would invent a
language restriction. Original vector order and repetitions remain in the
checked canonical preimage. Type equality is complete checked-contract identity,
not membership equivalence; a reordered/repeated declaration cannot replace an
original, issue a reference or acquire authority.

Assignment reasons over the actual admitted finite domain, including extent
intersection and original nullability. The join is deliberately coordinatewise:
common extents, nullable OR, and left-vector-preserving union when both enums
exist. It is a conservative common supertype, not necessarily an exact union or
global least upper bound. Weakening extents can re-admit an enumerant previously
excluded by one input. This derived result is never either original contract.

All occurrences and retained/comparison/output workspace remain bounded and
accounted, including repeats and extent-excluded entries. Provider limitations
remain explicit unavailability; input/Model/Command constraints cannot be
stripped to produce success. The absent-enum bytes and legacy bound behavior
remain unchanged. Signed64 is a separate adopted logical type and this Text
extension adopts none of its proposed arithmetic overloads. Contract/schema
registration is not evidence of an actual supplier, installed Model execution,
normal funding or recovery acceptance.

### Expression-dependent Stage identity closure

The generated Stage expression-contract pointer and independent Stage, Program,
Definition and Unit-body projections follow the same current normative expression
body as Common expression admission. Extending a logical scalar therefore changes
these dependent source identities even when the authored query contains no use of
the new scalar. Complete predecessor expression bodies and projection vectors stay
independently verifiable; they do not become an alternate current expression root.
Ordinary interface freshness checks this existing Stage generator as well as the
Catalog dependency generator.

A JOIN followed by INFER uses the existing Script producer-binding path for both
explicit and omitted item keys. That path checks the actual joined prefix and its
original schemas and keys before inference. The retained-Result JOIN specialization
remains available for queries without INFER; no type conversion, inferred key or
additional authority follows from routing through Script.

## Immediate NULL comparison and signed source zero

The approved capability completion replaces the former literal-NULL comparison
prohibition with ordinary three-valued comparison against an independently typed
peer. The existing common comparison type join supplies that context; it does
not coerce distinct non-null domains, resolve unknown names, or infer a domain
for two untyped NULLs. Null predicates use a nullable Boolean annotation solely
to represent their immediate NULL child: no non-null value is converted.
Authored operands and eager failure precedence remain intact.

SQL and common expression text accept signed zero tokens and normalize their
value to canonical positive zero, consistently with scalar negation. This is a
source-acceptance change, not a change to canonical Number wire admission;
negative-zero JSON values and Parameter values remain invalid. Source expression
normalization retains the existing numeric-literal lowering owner. No identity
equivalence for arbitrary arithmetic or implicit non-null coercion is added.


## Gmail message submission completion

The Gmail connector guide formerly called a successful message submission
`accepted`, while the normative
[Effect outcome contract](../spec/execution.md#reconciliation) reserves that
variant for a pending provider operation with a genuine OperationRef and its
status, cancellation, result and reconciliation bindings. These statements
conflicted; a message ID or thread ID supplies none of that operation authority.

The selected contract makes a confirmed synchronous send, reply or forward
submission `applied`. The completed operation is submission to Gmail, not
delivery to a recipient or a read receipt. Google's
[send API](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/send)
returns a Message on success. This is consistent with a synchronous submission
Command and does not justify inventing a polling operation.

A provider projection must validate the complete bounded response against the
same original request before producing that outcome. This is not a common
`accepted`-to-`applied` conversion or success-status whitelist. Lost or otherwise
unproved responses remain `unknown`; authorization, approval, durable claim,
receipt, reconciliation, no automatic resend and physical cleanup obligations
remain unchanged. The generic outcome schema and synchronous Command declaration
do not change. Provider implementation and ordinary execution evidence remain
separate from this resolution of the documentation conflict.


## GitHub creation confirmation and outcome names

The GitHub guide requires an original request marker and confirming read-back,
but formerly named an HTTP 2xx response `accepted`. The common
[Effect outcome contract](../spec/execution.md#reconciliation) gives that name
to a pending provider operation with a genuine OperationRef and its admitted
status, result, cancellation and reconciliation contracts. GitHub's
[createIssue](https://docs.github.com/en/graphql/reference/issues#createissue)
and [createPullRequest](https://docs.github.com/en/graphql/reference/pulls#createpullrequest)
mutations return the created object. Its ID and `clientMutationId` are not
provider-operation authority.

Retain the connector's stronger read-back requirement. A correlated synchronous
creation response is provider evidence; the existing owner may finalize
`applied` only after the actual read-back confirms the original scoped object,
content and marker. This is a bounded synchronous driver sequence, not an
invented asynchronous operation. A direct-response projection alone cannot issue
a terminal row Outcome Receipt. Missing confirmation preserves evidence and
uncertainty through the existing reconciliation path, without another send or
a fabricated failure claiming that creation did not occur. Equal unmarked
content and later equivalent state do not establish the original operation.

The physical body appends two LF characters and the original marker to an
existing logical body; an absent body uses only that marker. Explicitly empty
and absent bodies remain distinct. Keep the logical input and original tag
independently retained. Cold restoration compares the complete saved physical
wire against those originals and the existing protocol CID/origin context; it
does not prepare a new request or learn authority from the saved wire. Historical
wire and component evidence keep their original scope.

This resolves the outcome-name conflict without dropping the documented
confirmation step, changing the generic outcome schema or inventing a tag,
grant or cleanup owner. It does not transfer Gmail's submission-only completion
postcondition to GitHub. Actual request/marker/read-back construction overlap,
read authority, currentness, claim, receipt and physical cleanup remain required
implementation duties. Provider-only classification is not installed or ordinary
execution evidence.


## Kintone process-status response and confirmation

The kintone guide formerly named a revision response `accepted`. The common
[Effect outcome contract](../spec/execution.md#reconciliation) requires a genuine
OperationRef and its admitted operation contracts for that variant. The
[synchronous status API](https://kintone.dev/en/docs/kintone/rest-api/records/update-status/)
returns a record revision, not such an operation. Keep the existing requirement
to confirm the declared next status by read-back, and correct the outcome name.

The selected `update_status` Command is synchronous. Its original revision
response is retained provider evidence; it is not a terminal row Outcome Receipt.
Only an actual authorized read of the same scoped app and record, matching the
saved original response's revision and declared next status, permits `applied`.
A missing response or unconfirmed transition preserves uncertainty through the
existing owner. Do not infer a failure claiming the action did not occur, resend
the mutation, or turn a record ID or revision into an OperationRef. A later equal
status or higher revision without the saved original response proves no earlier
attempt. This does not add a generic asynchronous provider-operation contract.

A declaration for this endpoint must use the existing synchronous outcome and
omit a fabricated asynchronous poll role. Actual confirmation remains an ordinary
bounded read with its original authority, current checks and capacity; removing
poll metadata does not remove the read-back duty. Retain full-diff Preview,
original revision conflict checks, process-definition correspondence and all
ALL/ANY/ONE, filter and assignee obligations. Eligibility or a predicted next
state is not observed completion.

The documented provider revision increment does not by itself select a new
ActQL acceptance restriction; this decision leaves the existing bounded revision
admission and exact returned-revision read-back correspondence intact. Provider
projections, independent declaration preimages/CIDs and dependent fixtures must
be updated together before adoption. Generic outcome schemas, approval, durable
claim, receipt, recovery, no-resend and physical cleanup laws remain unchanged.
This documentation resolution is not installed or ordinary execution evidence.

## Gmail reply participants

`ROOT-GMAIL-REPLY-RECIPIENTS-01` resolves the previously unspecified recipient
selection behind the Gmail guide's promise to keep the conversation's recipients.
The normative mapping is owned by
[Gmail reply recipients and threading](../connectors/gmail.md#reply-recipients-and-threading).
[RFC 5322, sections 3.6.2–3.6.3](https://www.rfc-editor.org/rfc/rfc5322.html#section-3.6.2)
provides reply destinations but deliberately leaves automatic participant
selection to the application. The selected mapping keeps visible participants
and preserves valid self-replies without guessing account aliases. Mailbox
comparison follows
[RFC 5321, section 2.4](https://www.rfc-editor.org/rfc/rfc5321.html#section-2.4).
Thread correspondence also retains
[Gmail's documented requirements](https://developers.google.com/workspace/gmail/api/guides/threads).

This is an explicit resolution of an underspecified provider operation, not a
claim that the standards mandate the application choice. It adds no Command
field, identity domain, permission, outcome variant or machine-schema change.
Concrete request bytes and their existing request CID must reflect the resolved
destinations together; independent positive, negative and boundary fixtures and
actual funded caller integration remain implementation obligations. Documentation
alone does not qualify an installed reply or ordinary execution.

## Gmail forwarding content

`ROOT-GMAIL-FORWARD-CONTENT-01` resolves the previously unspecified content and
addressing behind `gmail.forward(message, to[, body])`. The normative choice is
owned by [Gmail forward content and addressing](../connectors/gmail.md#forward-content-and-addressing).
This is an explicit application decision: the earlier guide selected neither
inline text reduction nor a MIME-preserving representation, subject prefix or
note placement. The Source's plain-text projection does not decide how a whole
message is forwarded.

Choose lossless encapsulation so the optional note cannot overwrite the
original body or silently discard its attachments and MIME relationships.
[RFC 2046, section 5.2](https://www.rfc-editor.org/rfc/rfc2046.html#section-5.2)
describes this forwarding composition; internationalized messages retain the
[RFC 6532 message type](https://www.rfc-editor.org/rfc/rfc6532.html#section-3.7).
[RFC 5322, section 3.6.6](https://www.rfc-editor.org/rfc/rfc5322.html#section-3.6.6)
distinguishes a new message from the forwarder from resending. These standards
support the representation; they do not mandate ActQL's subject or note choice.
Gmail exposes the complete message in
[raw format](https://developers.google.com/workspace/gmail/api/reference/rest/v1/Format)
and accepts [MIME message submissions](https://developers.google.com/workspace/gmail/api/guides/sending).
That provider capability is not an ActQL read grant or completed implementation.

The existing Command inputs and submission outcome remain unchanged; no new
identity domain, permission, operation handle or public machine-schema field
is selected. Request bytes and their existing CID must include the complete
chosen material. Actual original acquisition, independent MIME/subject/note
fixtures, bounded construction overlap, current/approval/claim/receipt, cold
restoration and ordinary execution remain implementation obligations. Neither
a declaration nor a metadata-only reader establishes forward support.

## GitHub repository and organisation Source scopes

`ROOT-GITHUB-REPOSITORY-SCOPE-01` resolves conflicting wording: the GitHub guide
allowed organisation repository listing based on token type while also declaring
every connection to be a single repository. The normative boundary is owned by
[GitHub connection scope](../connectors/github.md#connection-scope). Credential
capability does not choose or enlarge an admitted ActQL Source scope.

GitHub's [organisation repository endpoint](https://docs.github.com/en/rest/repos/repos#list-organization-repositories)
requires an explicit organisation selector and supports multiple token types.
That provider behaviour does not itself supply an ActQL publication or read
grant. The repository-only installed profile retains a stable repository binding;
it does not already represent an organisation publication. Keeping that original
binding closed while requiring a separate organisation Source original resolves
the scope conflict without removing the documented enumeration requirement.

This selects the scope boundary, not a new profile field, wire representation,
identity domain, registry or authority issuer. The organisation publication,
actual bounded acquisition and Host admission must be implemented coherently
before that route is claimed as supported. Existing repository identities,
Source/current/Account duties and Effect approval remain unchanged. A finite
repository metadata reader does not establish organisation enumeration or full
connector acceptance.
