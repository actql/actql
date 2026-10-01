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
| Pure Graph-value construction | ActQL extension using the selected mapping profile | `DATA g = PROPERTY GRAPH (...)` binds a computed value; it does not create a catalog object. |
| Named SGA operations | [ActQL SGA laws](../../spec/dependencies/aoa-sga-identity-laws.json), [structural laws](../../spec/dependencies/aoa-sga-structural-laws.json), and [surface mapping](frontend-sga-surface.md) | ActQL operations, not standard GQL functions merely because names such as reach or components are familiar. |
| VecA / NEAREST score | [AoA numeric laws](../../spec/dependencies/aoa-veca-numeric-laws.json) and the common vector contract | Explicit scoring profile; not an alias for GoogleSQL distance functions. |
| Event-time windows, sessions, recognition, ASOF and interval joins | Operation-specific common contracts; external profile must be selected for each new surface | Analytic SQL frames are not event-time membership. A finite-label recognizer is not full SQL pattern recognition. ASOF spelling alone does not settle its contract. |
| INFER, DATA, RESULT/RECEIPT, EFFECT, COMMAND, BRANCH and AFTER ACCEPTED | ActQL extensions | Preserve typed results, explicit authority and durable ownership. They do not imply SQL transactions or cross-Effect atomicity. |

Google [distinguishes SQL/PGQ table-based graph definitions from GQL graph
creation](https://docs.cloud.google.com/bigquery/docs/graph-iso-standards).
Neither the selected vendor profile nor a grammar checkout establishes complete
ISO compliance. Immutable reference revisions and selected web clauses belong
in the evidence for an implemented feature; a moving web page is not a law CID.

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

## Property Graph mapping and element identity

The following is adopted target notation, not currently executable source:

```text
DATA g = PROPERTY GRAPH (
  NODE TABLES (
    nodes AS N KEY (id) LABEL Node PROPERTIES (id, name)
  )
  EDGE TABLES (
    edges AS E KEY (edge_id)
      SOURCE KEY (src) REFERENCES N (id)
      DESTINATION KEY (dst) REFERENCES N (id)
      LABEL R NO PROPERTIES
  )
);
```

Producer names, graph-local element definitions, labels and property names are
different namespaces. REFERENCES resolves an element definition, not a DATA
name or label. A producer reused in two definitions needs distinct definition
aliases. Static labels are graph-owned membership, separate from properties.
Changing `entity_type` must not alter a static `LABEL Person`.

| Selected mapping rule | First-profile condition or ActQL extension |
| --- | --- |
| Definition-scoped typed element keys; independently keyed edges | Require explicit ordered KEY tuples for Relation inputs. Never invent a primary key, row-position identity or concatenated-string key. Distinct edge keys preserve parallel edges. |
| NULL element keys contribute no element; unmatched endpoints contribute no edge | Do not synthesize nodes. Validate complete edge-key uniqueness before excluding unmatched rows; duplicate complete keys fail even for identical payloads. Bounded validation enforces the declared key precondition. |
| REFERENCES names the node definition | Initially require exact declared node KEY columns in order and arity; omitted columns use that KEY. Non-key reference mappings are unsupported, not reinterpreted. |
| Node and edge static label sets; consistent property exposure for a shared label | Preserve multiple labels, property types and nullability. Label/property lookup follows the selected case-insensitive Google profile; retain authored spelling and reject collisions. Never case-fold key values. Dynamic labels/properties are outside the first profile. |
| Default label is the element definition name; omitted properties select all columns | Support column projections/aliases, ALL COLUMNS, EXCEPT and NO PROPERTIES. Key columns can be properties; NO PROPERTIES does not remove identity. Computed properties need a separate evaluation contract. |
| Identity is distinct from content and provenance | Preserve definition-scoped typed keys in a stable admitted mapping domain across snapshots/replay. Outer DATA spelling, row enumeration, physical location and current content CID do not define that domain. Cross-domain algebra requires an explicit compatible identity mapping. |

The first three columns of an edge are not its identity. Endpoints, labels and
properties are content of an independently keyed element. MATCH/TRAIL,
normalization, union, equality, Delta and snapshot serialization must retain
that distinction. An unadapted consumer must reject the new contract rather
than collapse it to the historical endpoint/label tuple. Durable identity
across runs is an ActQL requirement, not an assumption about vendor display IDs.

The Graph algebra model and its operations belong in AoA; mechanized statements
must name their actual assumptions and proof coverage. ActQL connects that
model to source mapping, admission, acquisition, capacity, cancellation and
storage/replay. An old simple-Graph theorem or conformance test does not prove
the new keyed model or its correspondence to the selected external rules.
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
| Omitted properties versus NO PROPERTIES | All selected source columns versus none, with identity retained in both. |
| Snapshot/reload; changed endpoint at the same edge key | Identity, labels and multiplicity survive; diff/apply recognizes a content change and reaches the target. |

Acceptance runs source -> ordinary admission/checking/planning -> real Host ->
Named Result -> snapshot/reload on Local and HTTP. Expected Programs, schemas,
values, multiplicities and errors come from the selected contract, not the
new lowerer. Capacity failure, cancellation and rejected inputs publish no
partial successful result. Construction is pure; DATA adds no implicit
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
