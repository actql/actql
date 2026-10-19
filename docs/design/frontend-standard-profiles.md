# Frontend standard profiles and common semantics

The Frontend adopts selected external semantics, not just familiar keywords.
Its source forms lower to one admitted Program and use the common checker,
planner and execution owners. An old Program field or reference kernel is not
an immutable authority when it conflicts with an adopted standard rule.
Changing that rule requires a coordinated common-contract change; spelling it
differently or approximating it in the Frontend is insufficient.

This is a design ledger, not a conformance certificate or executable grammar.
The [query specification](../spec/query-text.md), grammar and pinned laws still
define admitted behavior until their coordinated replacement is implemented.
The [migration mapping](frontend-language-migration.md) records text replacement
obligations; [semantic decision criteria](semantic-decisions.md) govern changes.

## Reference authority and feature classification

| Family | Selected reference | Interpretation |
| --- | --- | --- |
| SQL and relational Pipe | [GoogleSQL language reference](https://github.com/google/googlesql/tree/d82db99a923a46571f543a13899dc791a7b6f743/docs), revision `d82db99a923a46571f543a13899dc791a7b6f743` | Select clauses and their meaning individually. Repository features are not necessarily deployed in every Google product. |
| Graph pattern matching | [GoogleSQL graph patterns](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/graph-patterns.md); [GQL grammar provenance](https://github.com/opengql/grammar/blob/16ea71bd320ad07fd2c46a3066afbaef7d226922/README.md) | The grammar is syntax evidence, not the complete normative semantics of ISO GQL. Record selected pattern modes and contexts separately. |
| Relation-to-Graph mapping | Google's [schema overview](https://docs.cloud.google.com/spanner/docs/graph/schema-overview) and [schema statements](https://docs.cloud.google.com/spanner/docs/reference/standard-sql/graph-schema-statements), consulted 2026-10-01 | Selected Google table-mapping profile with SQL/PGQ lineage. Distinguish this from GQL graph creation and from product storage features. |
| Pure Graph-value construction | ActQL extension using the selected mapping profile | `WITH g AS (GRAPH (...)) ...` binds a computed value; it does not create a catalog object. |
| Named SGA operations | [Current Graph laws](../../spec/dependencies/actql-graph-laws.json) and [surface mapping](frontend-sga-surface.md) | ActQL operations over the admitted definition/key Graph contract; unsupported consumers reject without interpreting historical SGA identity or structural bodies. Familiar names such as reach or components do not make them standard GQL functions. |
| VecA / NEAREST score | [AoA numeric laws](../../spec/dependencies/aoa-veca-numeric-laws.json) and the common vector contract | Explicit scoring profile; not an alias for GoogleSQL distance functions. |
| Event-time windows, sessions, recognition, ASOF and interval joins | Operation-specific common contracts; external profile must be selected for each new surface | Analytic SQL frames are not event-time membership. A finite-label recognizer is not full SQL pattern recognition. ASOF spelling alone does not settle its contract. |
| INFER, non-Relation WITH, RESULT/RECEIPT, EFFECT, COMMAND, BRANCH and AFTER ACCEPTED | ActQL extensions | Preserve typed results, explicit authority and durable ownership. They do not imply SQL transactions or cross-Effect atomicity. |

Google [distinguishes SQL/PGQ table-based graph definitions from GQL graph
creation](https://docs.cloud.google.com/bigquery/docs/graph-iso-standards).
Neither the selected vendor profile nor a grammar checkout establishes complete
ISO compliance. Immutable reference revisions and selected web clauses belong
in the evidence for an implemented feature; a moving web page is not a law CID.

## Selected Graph path default

The pinned [GoogleSQL path-mode clause](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/graph-patterns.md#path_mode)
uses WALK when no path mode is authored. Adopt that default for the supported
fixed directed patterns, including named paths and node-only patterns. The
Frontend lowers implicit and explicit WALK to the same logical traversal mode;
TRAIL and ACYCLIC remain explicit restrictions. This does not add search prefixes,
optional patterns, nested paths or broader quantifiers. Shape support and
bounded resource admission remain separate from the choice of default.

## Meaning preservation and coordinated changes

`machine_program_semantics_preserved` in the adopted Frontend profile means
that lowering preserves the **applicable, pinned** checked semantics. It does
not require preserving every historical semantic choice forever. JSON/YAML
remain public machine inputs to the same owners. A standard-alignment change
must be made there too, with its affected laws, schemas, canonical preimages,
pins and independent vectors updated together. All owned contracts remain on
the agreed initial 0.1 baseline; a profile name is not version-change authority.

Classify a difference as an adopted rule, an intentional ActQL extension, a
supported subset, an implementation gap or a still-unresolved decision. A valid
standard form outside the installed subset receives an explicit unsupported
diagnostic; its rejection does not make it invalid in the reference language.
Reference execution results must be compared only for the selected types and
clauses, including NULLs, duplicates, precision, failures and ordering.

SQL relations without an ordering requirement are compared as multisets. Extra
deterministic tie handling is not permission to reject otherwise valid inputs
or assert source order. Alias resolution reuses computed slots and must not
duplicate evaluation. GoogleSQL's [logical operators](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators#logical_operators)
do not promise left-to-right evaluation or mandatory short-circuiting of AND/OR.
Conditional expressions have their own demand rules; do not classify them all
as eager. Exact failure and resource behavior belongs in the common contract.

## Graph mapping and element identity

The following notation defines the adopted mapping profile. Execution requires
the installed common constructor and supported consumers; declaration of this
profile alone is not an execution certificate:

```text
WITH g AS (GRAPH (
  NODE TABLES (
    nodes AS N KEY (id) LABEL Node PROPERTIES (id, name)
  )
  EDGE TABLES (
    edges AS E KEY (edge_id)
      SOURCE KEY (src) REFERENCES N (id)
      DESTINATION KEY (dst) REFERENCES N (id)
      LABEL R NO PROPERTIES
  )
))
FROM g |> node_rows() |> SELECT id, name |> RESULT nodes
```

Producer names, graph-local element definitions, labels and property names are
different namespaces. REFERENCES resolves an element definition, not a WITH
producer name or label. A producer reused in two definitions needs distinct definition
aliases. Static labels are graph-owned membership, separate from properties.
Changing `entity_type` must not alter a static `LABEL Person`.

| Selected mapping rule | First-profile condition or ActQL extension |
| --- | --- |
| Definition-scoped typed element keys; independently keyed edges | Require explicit ordered KEY tuples for Relation inputs. Never invent a primary key, row-position identity or concatenated-string key. Distinct edge keys preserve parallel edges. |
| NULL element keys contribute no element; unmatched endpoints contribute no edge | Do not synthesize nodes. Validate complete edge-key uniqueness before excluding unmatched rows; duplicate complete keys fail even for identical payloads. Bounded validation enforces the declared key precondition. |
| REFERENCES names the node definition | Initially require exact declared node KEY columns in order and arity; omitted columns use that KEY. Non-key reference mappings are unsupported, not reinterpreted. |
| Graph-wide property value-type consistency | After the selected case-insensitive property-name resolution, every occurrence of a property name has the same value type throughout the Graph, across node and edge definitions and across different labels. Different labels do not relax this condition. Preserve the declared nullability separately. |
| Consistent property exposure for a shared label | After the selected case-insensitive label/property-name resolution, every occurrence of a label name exposes the same property set across node and edge definitions. This condition is independent of Graph-wide property value-type consistency. |
| Node and edge static label sets | Preserve multiple labels and declared property types/nullability. Label/property lookup follows the selected case-insensitive Google profile; retain authored spelling and reject collisions. Never case-fold key values. Dynamic labels/properties are outside the first profile. |
| Default label is the element definition name; omitted properties select all columns | Support column projections/aliases, ALL COLUMNS, EXCEPT and NO PROPERTIES. Key columns can be properties; NO PROPERTIES does not remove identity. Computed properties need a separate evaluation contract. |
| Identity is distinct from content and provenance | Preserve definition-scoped typed keys in a stable mapping domain across executions and snapshots/replay of the same admitted constructor definition. Do not include actual input Artifact identities, parameter values, Run/Invocation CIDs, outer WITH binder spelling, row enumeration, physical location or current content CID in the domain. Sharing is not guaranteed with a different definition produced by changing inline VALUES or the mapping. Cross-domain algebra requires an explicit compatible identity mapping. |

The first three columns of an edge are not its identity. Endpoints, labels and
properties are content of an independently keyed element. MATCH/TRAIL,
normalization, union, equality, Delta and snapshot serialization must retain
that distinction. An unadapted consumer must reject the new contract rather
than collapse it to the historical endpoint/label tuple. Durable identity
across runs is an ActQL requirement, not an assumption about vendor display IDs.

The current Graph model, law body and operations are owned in ActQL;
`smoothhq/aoa` is not a build, runtime or acceptance dependency. The owned
[Graph laws](../../spec/dependencies/actql-graph-laws.json)
bind the constructor, typed identity and snapshot profile. Mechanized
statements must name their actual assumptions and proof coverage. The same
ActQL owners connect the model to source mapping, admission, acquisition,
capacity, cancellation and storage/replay. An old simple-Graph theorem or
conformance test does not prove the new keyed model or its correspondence to
the selected external rules.
Complete SGA mechanization is not a prerequisite added to the first vertical
unit. No second Graph engine belongs in the Frontend.

## Independent obligations for the first vertical unit

These expectations precede implementation; their listing is not a test pass.

| Input / operation | Independent expected obligation |
| --- | --- |
| Two edges with different keys, equal endpoints and labels | Both survive construction; a one-hop pattern produces two matches. |
| One node, two independently keyed self-loops, exactly two hops | WALK has four edge sequences; TRAIL has two; ACYCLIC has none. Keep duplicate projected endpoint rows. |
| Two node definitions with the same input key | Two scoped identities; REFERENCES chooses the named definition. |
| Composite keys `(1,23)` and `(12,3)` | Distinct identities retaining component type and position. |
| NULL key, duplicate complete key, missing endpoint, empty input | Exclusion, failure without partial Graph, edge exclusion, and empty typed Graph respectively. |
| Static labels, multiple labels, property/label collision | Membership independent of property values; no duplicate elements for multiple labels. |
| Person exposes numeric `score`; Company exposes String `SCORE` | Reject: case-insensitive property-name resolution finds incompatible value types, even though the labels differ. |
| A node exposes numeric `score`; an edge exposes String `score` | Reject: the same property value-type rule spans node and edge definitions. |
| Person and Company each expose numeric `score` | Do not reject under the property value-type rule; all other admission conditions still apply. |
| Label Person exposes `{name}`; label PERSON exposes `{name, score}` | Reject: case-insensitive label resolution finds different exposed property sets. |
| Omitted properties versus NO PROPERTIES | All selected source columns versus none, with identity retained in both. |
| Snapshot/reload; changed endpoint at the same edge key | Identity, labels and multiplicity survive; diff/apply recognizes a content change and reaches the target. |

Acceptance runs source -> ordinary admission/checking/planning -> real Host ->
Named Result -> snapshot/reload on Local and HTTP. Expected Programs, schemas,
values, multiplicities and errors come from the selected contract, not the
new lowerer. Capacity failure, cancellation and rejected inputs publish no
partial successful result. Construction is pure; WITH adds no implicit
acquisition, materialization, Result, sort, storage or placement boundary.

## Vector and temporal follow-through

GoogleSQL [distance functions](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#cosine_distance)
are distinct from the current VecA score. ActQL's law quantizes inputs to
binary32, returns cosine similarity with zero-vector score +0, and defines l2
as negative Euclidean distance. Negating a score does not establish matching
precision, input types or error behavior. Standard-looking distance aliases
require coordinated numeric laws and independent value/failure tests, not
just matching top-k order.

Before extending temporal vocabulary, select exact window, session, recognition
or ASOF semantics, including partition, order, duplicates, time boundaries,
NULLs, match selection and failure. Keep unsupported adopted targets visible.
An OP field exposure or JSON payload is not completion of the new source form.

For every adopted feature, keep provenance, scope, checked lowering, runtime
support, packed execution and proof coverage distinct. The
[initial alignment review](../reviews/2026-10-01-frontend-standard-alignment.md)
records concrete implementation gaps and evidence boundaries.

## Selected simple scalar functions

The query profile admits GoogleSQL STARTS_WITH and ENDS_WITH over STRING with
its default binary comparison, and SIGN over the common finite binary64
number domain corresponding to the finite FLOAT64 subset. Their common
expression owners define the same result for SQL/Pipe and JSON/YAML input.
Empty prefixes/suffixes match every non-null string, and both zero signs
produce canonical positive zero for SIGN. NULL results and inferred
nullability follow the common strict signatures, independently of row count.

This is new supported coverage. BYTES, explicit collation, non-finite numbers
and the INT64/NUMERIC/BIGNUMERIC SIGN overloads remain implementation gaps;
their omission is not a restriction of GoogleSQL. No frontend approximation,
implicit coercion, Unicode normalization or extra evaluation is introduced.
The reference clauses are Google's [STARTS_WITH](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#starts_with),
[ENDS_WITH](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#ends_with)
and [SIGN](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#sign),
consulted 2026-10-10. Source grammar, embedded schema alternatives, common laws,
execution registrations and dependent identities change together on the
initial 0.1 baseline. Earlier pinned bodies keep their earlier meanings.

### STRING position

STRPOS adds first-occurrence position to the same common expression owner for
SQL, Pipe and JSON/YAML. The adopted value rule is 1-based Unicode scalar
position, absent 0 and empty needle 1. Ordinary eager strict-NULL evaluation
and left-to-right failure precedence apply; surrounding lazy demand remains
unchanged. The [GoogleSQL STRPOS reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#strpos)
and [pinned compliance cases](https://github.com/google/googlesql/blob/81c15b796138185c046aefe852321011fdf96615/googlesql/compliance/functions_testlib_string_2.cc#L398-L413)
anchor the selected STRING/default binary subset, including empty, NULL,
multibyte and embedded-NUL cases. ActQL retains exact strings and introduces
no normalization or implicit coercion.

The common finite binary64 `number` represents these bounded string positions
exactly. This is a result-representation difference from Google's INT64 type,
not a claim of full INT64 support. BYTES and explicit collation are still
unsupported. Existing string/resource admission determines the supported
extent; the search does not add an unrelated language-length restriction.
Canonical schemas, registries and their current dependent identities include
the added common node; complete predecessor preimages retain their old CIDs.

### Finite-number ROUND and TRUNC with decimal positions

`ROUND(X[, N])` and `TRUNC(X[, N])` select the common expression Owner for
finite binary64 numbers. Unary ROUND chooses the nearest integer and breaks
exact ties away from zero; unary TRUNC chooses the nearest integer toward
zero. Neither unary form changes an already-integral value or overflows.
Adding the optional decimal-position expression preserves existing unary
canonical bodies; explicit positions retain the ordered two-child body, even
for `N = 0` or a position whose value rule leaves the input unchanged.

Both children are evaluated once, value before position, including the second
child after a NULL value. After both evaluations succeed, strict NULL applies;
otherwise N must be integral. Fractional N fails with the existing arithmetic
error. The result has nullable-OR typing. Integral N above 323 preserves the
input and N below -308 yields positive zero, without narrowing large binary64
integers first. ActQL uses its existing number representation for N and does
not claim a distinct INT64 overload or exact representation of every INT64.
ActQL's existing arithmetic canonicalizes all zero results to positive zero.
The common failure, lazy-demand, cancellation and bounded-execution Owners
remain responsible for this work, including logical charges for no-op cases.

The selected decimal-position behavior is `DecimalRounding<is_trunc>`, exposed
as `RoundDecimal`/`TruncDecimal`, in
[GoogleSQL `round_decimal.cc` at revision
`81c15b796138185c046aefe852321011fdf96615`](https://github.com/google/googlesql/blob/81c15b796138185c046aefe852321011fdf96615/googlesql/common/round_decimal.cc),
with the portable `ComputeDekkerProduct`/`Split` path of
[`Full<double>` at the same revision](https://github.com/google/googlesql/blob/81c15b796138185c046aefe852321011fdf96615/googlesql/common/double_double.h).
The normative owner is [Scalar expressions](../spec/language.md#scalar-expressions).
The fixed high/low powers of five, explicitly rounded double-double operation
order, `2^-105` correction, sticky-bit adjustment, signed integer selection and
two-stage final binary scaling are part of the selected value contract. FMA,
reassociation, multiplying by a single binary64 `10^N`, or substituting an ideal
exact-rational result can change the selected result and are not equivalent
implementations. For example, `ROUND(1.005,2) = 1`, `ROUND(2.675,2) = 2.67`
and `TRUNC(0.3,1) = 0.2`; subnormal and large-magnitude cases also expose
one-ULP differences from exact-rational proxies. ROUND overflow fails, while
TRUNC cannot overflow for admitted finite inputs and integral positions.

This extends the selected finite-FLOAT64 profile described by Google's
[ROUND](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#round)
and [TRUNC](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#trunc)
references. Explicit rounding modes, distinct INT64/NUMERIC/BIGNUMERIC
overloads and non-finite values remain unimplemented coverage, not restrictions
claimed for GoogleSQL. The pinned algorithm selection does not establish live
BigQuery equivalence or execution coverage on all targets. Existing contract
CIDs retain their predecessor meanings; new expression/schema/registry
identities propagate through the ordinary contract Owners. No adapter-specific
evaluator is added.


### STRING SUBSTR and SUBSTRING

Both GoogleSQL spellings select common `substring(value,start[,length])`,
preserving actual omission and the original scalar sequence. The adopted
[GoogleSQL reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#substr)
was consulted 2026-10-10. The existing declared fixed-arity interval law and
text-time membership change together in the common normative owner, schemas
and dependent identities; historical pins retain the prior rule. STRING uses
Unicode scalar positions, zero/overly-negative clamping and end-relative
negative positions. Strict NULL follows all demanded children; invalid index
data fails only when demanded and non-null. Known input String maxima survive
in the result, and nested profile calls retain their resource admission.

This supplies executable STRING coverage rather than the complete GoogleSQL
function domain. Indices use safe-integer-valued finite binary64 numbers;
BYTES and the rest of INT64 remain gaps. Profile-bound propagation across the
former substring envelope can conservatively widen nested profile admission,
as documented in [Semantic decision criteria](semantic-decisions.md#googlesql-string-substring-and-profile-ownership).


### Finite-number SAFE arithmetic

`SAFE_ADD`, `SAFE_SUBTRACT`, `SAFE_MULTIPLY`, `SAFE_DIVIDE` and `SAFE_NEGATE`
map to their distinct common expression operations over finite binary64 Number.
Binary operations return null for their own overflow; SAFE_DIVIDE also handles
zero divisors. SAFE_NEGATE cannot overflow in this finite domain. Strict NULL,
child evaluation order and lazy demand remain common laws; SAFE does not catch
argument-expression, cancellation or resource failures. The legacy common
`safe_div` retains its zero-only rule and is not a GoogleSQL alias.

This adopted finite-FLOAT64 subset follows the GoogleSQL
[SAFE function contracts](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#safe_add)
and [floating-point overflow rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/data-types#floating_point_semantics).
INT64, NUMERIC, BIGNUMERIC, Decimal and non-finite values are not added. ActQL's
existing canonical-positive-zero boundary remains explicit. Syntax registration
and documented scope do not certify untested backends or public consumers.

### STRING side slices and padding

GoogleSQL LEFT/RIGHT and LPAD/RPAD select the common ordered `left`, `right`,
`lpad` and `rpad` source arrays. LEFT and RIGHT remain reserved as bare query
identifiers but are accepted directly before a call parenthesis; join keyword
and quoted-name behavior is unchanged. No source expansion duplicates a value,
length or pattern expression. The common bounded text continuation owns the
Unicode scalar slicing, padding, exact sizing, retained roots and cancellation.
The safe-integer ActQL Number length domain excludes other INT64 values, BYTES
and collation. Omitted padding alone means U+0020; explicit empty pattern fails.


### STRING translation and occurrence search

TRANSLATE and INSTR select the common expression owner across SQL/Pipe and
canonical JSON/YAML. TRANSLATE admits exactly three STRING operands. INSTR
admits two STRING operands plus optional position and occurrence; omitted
values mean one without synthetic canonical children. Matching and substitution
use exact Unicode scalars, including overlapping occurrences and empty-pattern
boundaries, under the [owned contract](../spec/language.md#scalar-expressions).
GoogleSQL's INT64 search parameters are explicitly adapted to existing integral
finite Number values without an INT64 or safe-integer cap. This is scoped
STRING/default-binary coverage; BYTES, collation, regex and implicit coercion
remain outside the increment. Existing profiles and resource limits do not move.

### Exact Decimal division at a public scale

The public three-argument `decimal_divide(left, right, scale)` selects the
existing complete division body with precision 38 and division-only `exact`.
The target is static and independent of values, while the original operands
remain the two demanded children. Common uses its bounded integer coefficient
ratio and requires zero remainder before producing a fitting coefficient. An
inexact quotient fails; no frontend ratio calculation or hidden rounding mode
can make it representable. Explicit five-argument division retains its five
original rounding policies and may also select `exact`. Quantize keeps only its
original five policies.

Immediate literal NULL receives only the scoped Decimal context: the declared
nullable result for the left, and the resolved left contract for a NULL divisor.
This is not non-null input evidence or permission to type an unknown field or
Parameter. Both children remain demanded before NULL propagation, so a failing
child remains a failure. Saved complete source and machine bodies retain all
five fields; omitted fields are never reconstructed by a machine reader.

The adopted precision default closes the public explicit-scale form. The
separate two-argument spelling still lacks an adopted scale policy and remains
an implementation/documentary obligation. Existing expression bytes retain
their identities; changed containing schemas, laws and grammar are repinned
with their full predecessor bodies and independent preimages.
