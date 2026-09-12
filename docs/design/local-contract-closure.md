# Local contract closure

This design specifies the dependency selection and representation required by
[Checked Program construction](checked-program.md#identity-boundaries). The
normative owner is [local contract selection and identity](../spec/language.md#local-contract-closure).
The wire shape is `schemas.local_contracts` in the stage contract registry.
Registration of that shape and its identity vectors does not prove that a
compiler has selected every required dependency.

## Inherited expression dependency

The expression contract's `inherited_text_time_profile_cid` identifies the whole
body in [the base text/time profile](../../spec/dependencies/actql-text-time-base.json),
at JSON Pointer `""`. Its CID is
`sha256:2d41f38bd3bf8217d9bc394b1ca2ed9dfe6695b0088cd6a489328dabdee61dcc`.
The preimage excludes the profile envelope's `contract_cid`; the schema CIDs
inside the body identify its embedded schemas independently.

This body is an inherited dependency, not a replacement for the current expression
contract. Current language rules and explicit expression-contract refinements
continue to govern acceptance. Recovering the body does not waive traversal of
its own declared dependencies or prove that the complete expression closure is
available. In particular, Unicode data and regex/timestamp grammar references
remain distinct dependencies; their CID-shaped strings are not an invitation to
scan arbitrary business data for dependencies.

The [inherited dependency bodies](../../spec/dependencies/actql-text-time-base-dependencies.json)
resolve the following declared edges. Each pointer identifies an independently
hashed body, not a hash of the containing collection:

| Reference in its owner | Body pointer |
| --- | --- |
| Base `data_contract_cids.regex_grammar_cid` | `/regex_grammar` |
| Base `data_contract_cids.timestamp_pattern_grammar_cid` | `/timestamp_pattern_grammar` |
| Base `data_contract_cids.unicode_data_cid` | `/unicode_semantics` |
| Regex grammar `ast_schema_cid` | `/regex_ast_schema` |
| Regex grammar `replacement_ast_schema_cid` | `/regex_replacement_ast_schema` |
| Timestamp grammar `ast_schema_cid` | `/timestamp_pattern_ast_schema` |

Despite the base field's name, its `unicode_data_cid` references the Unicode
semantics descriptor. That descriptor's `data_cid` references the actual data
table, also referenced directly by the base's NFKC and case-fold bound laws.
These are different bodies and must not be substituted for one another.
The [Unicode data body](../../spec/dependencies/actql-text-time-unicode-data.json)
at pointer `""` resolves that data edge with CID
`sha256:4a84a6d133b6282a5d50ba743ef8cab3fc87d4ccc91612663c5fc0d02f705dd4`.
It contains combining classes, canonical and compatibility decompositions,
composition pairs, default full case folding and expansion bounds. It is Unicode
16.0.0-derived data covered by the bundled
[Unicode license](../../vendor/unicode/16.0.0/LICENSE.txt); distributions retaining
this dependency must retain the associated copyright and permission notice.
The `source_sha256` entries describe its original input bytes, not additional
semantic Catalog references. This immutable dependency is distinct from the
generated NFC implementation tables and does not itself prove normalization
execution conformance. Its original DerivedNormalizationProps source is not part
of the current NFC generator's vendored input set; resolving the pinned body
does not claim independent regeneration from that absent source.
The inherited AST schemas are the exact pinned schemas; a newer current schema
with similar purpose is not a substitute at those CIDs. Embedded JSON Schema
`$ref` paths resolve within each schema's declared scope, not as Catalog IDs.

`check_environment` exposes this fixed family through
`InheritedTextTimeContract` and constant-time count/index dependency access.
Each edge retains its JSON Pointer and typed target. Repeated NFKC/case-fold
references remain separate edges even though their target is shared. Unknown
pins do not resolve to leaf nodes. The generated graph verifies the actual
body pins and declared reference positions before publication into product code.
This lookup identifies globally pinned semantics, not a Program owner: selecting
the root from an owned expression requirement and charging traversal work remain
the responsibility of Program closure construction. It does not interpret the
current expression contract's other dependencies or discharge any execution check.

For a prepared Program, `stage_identity_expression_contract_cid` reads this root
from the same owned Stage semantics used by identity emission. It is present for
every Stage, including an empty local computation; expression liveness does not
remove the governing interpretation contract. `stage_identity_inherited_text_time`
resolves the inherited edge from that root without accepting a replacement CID.
An unsupported root remains unresolved. Equal globally pinned contracts do not
merge Stage/Program owners or establish that their other requirements agree.
These indexed reads do not emit a new preimage or change the retained work/hash
usage. A closure traversal must still account for its own visits and allocations.

`stage_identity_expression_body` connects the same Stage root to its declared
body-reference graph: inherited text/time, current regex AST representation and
consumer-capacity law. The regex representation in turn references its current
AST schema. Both inherited and replacement schemas retain their own identities;
the replacement's explicit scope, not deletion of the inherited dependency,
determines the accepted AST representation. The EBNF path and byte hash are
verified as a pinned byte resource, not reinterpreted as a canonical-JSON CID.

The `ExpressionContractBody` graph exposes these reference sites through
count/index access and reuses the inherited graph without copying it. It is not
the complete Unit root inventory: selected operation/profile laws, source
declarations, publication and incoming interfaces still contribute their own
governing contracts. A successful lookup is neither an execution capability nor
a consumer-capacity proof; those checks retain their own owners and obligations.

## Three different identities

A contract-closure CID identifies a set of interpreted contracts. A Unit
Definition additionally identifies the local body, namespace, used declarations
and incoming interfaces. A concrete Invocation additionally binds effective
values, observations and applicable execution evidence. Neither the contract set
nor the full Check Environment substitutes for either of the latter identities.

Contract selection has two inputs: the complete source-owned Unit inventory and
the admitted interpretation of its contract-bearing roles. The compiler derives
these inputs; a caller-provided list of CIDs is not proof of completeness.
Successful graph membership, Catalog resolution and whole-lock integrity remain
required separately. Locality of a hash does not waive those checks.

## Selecting roots

The source grammar resource is the complete embedded Program schema at
`spec/contracts/actql-protocol-schemas.json`, JSON Pointer
`/artifact_schemas/executable_plan/properties/execution_material/properties/program`.
The copy under `plan_document` is identical. Its independently hashed body is
`sha256:a6bfc4b6c00d89f521ccee9e99e1dbbd7385675fd55478f1536f36f860b1ef0a`;
this is not the CID of either containing artifact schema. The containing pins,
copy equality and local reference resolution are verified by generation.

This selection preserves the resource's `$defs` scope, including recursive
Parameter and value contracts. Hashing only `params.additionalProperties` would
discard required definitions. Hashing the enclosing Plan schema would instead
include unrelated execution-envelope structure. Internal `$ref` edges are not
external contract roots. A new external reference or nested schema resource
requires explicit dependency handling, rather than silently treating it as a
leaf. Each owned Stage retains a source-grammar occurrence, including stages
without Parameters; body storage is shared. This grammar contribution does not
replace the governing semantic laws or the required declaration/value checks.

Each owned Stage also selects the registered `actql-stage-contracts.json`
`/source` and `/laws` bodies. Their existing spec-family pins identify,
respectively, source/declaration/binding rules and common lifecycle, identity,
admission and failure rules. These are the registered semantic contract units,
not a new hash of the whole Stage schema registry or concrete activation data.
Generation checks those exact registered pointers and pins; existing independent
identity vectors verify their bodies. Repeated Stage uses retain their own
coordinates while sharing body storage and traversal charges. Selecting the
contracts does not discharge their rules: in particular it does not manufacture
completed predecessors, runtime validation, authorization or executable support.

The Stage also selects the existing registered `/schemas/local_contracts` and
`/schemas/local_dependencies` bodies: they govern the contract-set and local
dependency envelopes interpreted by Unit identity construction. These are schema
body CIDs, not the as-yet-constructed envelope's identity or a substitute hash of
the whole registry. Selecting the contract-set schema creates no self-reference
to the concrete set CID. Their local property definitions are part of the schema
body; CID-shaped property constraints are not dynamic contract dependencies.

The same Stage inventory retains the Check Environment interpretation contract
from its owned admission context, including for a Local Program with no Catalog
inputs. Policy admission interprets absence as well as presence: selecting this
root only when an optional Host component happens to be present would make a
concrete policy choice change the semantic dependency set. Its declared edges
include capacity and text-time policy grammars; lookup execution's grammar and
absence/selection rules are embedded in the interpretation body. Changing an
unused component or its valid limits can change the concrete environment CID
and check work, but not these interpretation roots. The environment envelope
CID and concrete policy component CIDs are not substituted for the contract.

Selection includes every contract interpreted for the Unit's declarations,
operations, expressions, publication, imports and incoming gates, including
domain, guard, permission, scope and failure semantics. It is not a liveness
analysis: unused declared inputs, unselected expression branches and authored
no-ops remain part of the inventory. Repeated occurrences retain their sites
and owners even when they resolve to the same contract.

For an admitted SourceView declaration, select the contract references belonging
to that selected SourceView, not every member of its enclosing Catalog. The
declaration's complete contract includes its advertised read-mode contracts;
choosing a mode for one acquisition does not erase the other declared modes from
the declaration's contract. Selecting an unrelated SourceView or Command solely
because it shares the same Catalog is incorrect. Request values, observed rows,
checkpoint values and leases are not thereby contract roots.

For operation and expression semantics, roots are the governing pinned contracts
and selected semantic profiles. The root inventory includes the rules used to
interpret evidence and deferred execution checks, not only result-type rules.
An operation's quantity-specific capacity law is a semantic dependency; a
concrete Host ceiling or measured row count is an application of that law.

Every owned operation occurrence selects the existing
`actql-bound-transfer-laws/0.1` body at
`spec/contracts/actql-bound-transfer-laws.json`, pointer `""`, pinned as
`sha256:014682262d00c8435f300731e823e5b267ec66b78f980c765c4fd3772c68c911`.
This is the governing operation classification, including carrier-specific and
explicitly unknown cases, not a proof or a replacement for quantity-specific
law bodies. Source sites retain Stage, producer visit and step coordinates;
shared storage does not merge those owners. The registered body has no external
contract-reference fields. Its classification labels are not Catalog IDs.

Quantity-specific root selection uses an exhaustive checked-operation dispatch,
including an exhaustive distinction between node/edge and Events/Vectors
projections. A named `ClassificationOnly` disposition retains the common
transfer-classification root without adding a quantity-specific body in that
dispatch. It is not proof that no further semantic contract is required, nor a
successful Unit-closure disposition. Adding a checked operation requires an
explicit selection decision; a wildcard must not silently classify it as a leaf.

Concrete Host policy decisions, capacity observations and resolved numeric
ceilings belong to the applicable Plan/Invocation evidence, rather than being
inserted into Unit Definition because the checker consulted them. Authored
guards remain in the Unit body. Policy and capacity *interpretation contracts*
remain in the contract closure. An actual contract-version change is distinct
from a new policy value interpreted under the same contract.

Common Relation transfers additionally select
`spec/contracts/actql-bound-relation-laws.json`, pointer `""`, with CID
`sha256:163a0d75d56310803ac755d5f4f02069f442651711209037d6e3f512954c97ab`.
The body fixes input-bound preservation and the global-group, take/top_k,
append, unpivot and unnest count rules, including dependency multiplicity,
safe arithmetic and empty-input distinctions. It packages existing rules,
not a new permission to execute an operation or replace unknown counts by zero.

Every unary Relation operation, window-group, append, nest and set-operation
occurrence selects this common interpretation body. This includes authored
no-ops and repeated producer visits; storage is shared by body CID, not by
source occurrence. Per-Stage selection follows the owning occurrence, and a
Stage without such operations does not inherit another Stage's root. There are
no external reference fields in this body; its law names do not stand for
unresolved Catalog links. Selecting these common rules does not complete the
quantity-specific Carrier laws for joins, Graphs, Vectors, windows, acquisition
or publication, nor the final Unit contract closure.

The join family additionally selects `spec/contracts/actql-bound-join-laws.json`
at pointer `""`, pinned as
`sha256:75f9c5ce5188d28a2e3b42213e0fb3a479475c06e280eb02ef7b001a355d1600`.
Equality, cross, interval and as-of join occurrences retain their own root sites
while sharing the body. The contract fixes empty-input bounds and conditional
uniqueness refinements, not the truth of a cardinality assertion or acquisition
completeness. Its law names are not external dependency edges. Concrete bounds
and validation evidence remain applications rather than contract-set members.

Window occurrences select `spec/contracts/actql-bound-window-laws.json`, pointer
`""`, with CID
`sha256:a5045688150b6b5aaf0c992b2e528ba3b5f1dd49e0db14e5673c9515af82ac3a`.
The common body governs fixed/sliding multipliers for both accepted Carriers;
the selected operation retains its actual Carrier and source occurrence. Fixed
step validation is not erased because the multiplier is one. Concrete bound
values and their admission dependencies are not inserted into the contract set.
This body has no external contract-reference fields.

Graph construction, structural combination, normalization/bounds, subgraph,
matching, node/edge projection, components/degree and traversal/shortest
occurrences select `spec/contracts/actql-bound-graph-laws.json`, pointer `""`,
pinned as `sha256:5e9a00ff401f42059f037c52babb40f8440201b3dccaffa90da297058d6adc89`.
This body fixes quantity-specific conditional transfers and selector extents;
it does not treat path enumeration as node emission or make arbitrary Graph
operations nonexpanding. Roots retain their owning operation; the body has no
external contract-reference fields. Graph input enforcement and concrete
observations are separate from these transfer rules.

Nearest, text-rank and ranking-merge occurrences select
`spec/contracts/actql-bound-ranking-laws.json` at pointer `""`, CID
`sha256:655fa88f2d24a15794a12abdbdc967f51517f5f92aa1316f74f6df1617fcf0c7`.
Time-series and calendar operations select
`spec/contracts/actql-bound-series-laws.json` at pointer `""`, CID
`sha256:c85b84631add903652807808fc4faa9015e59cf9bfd0fb11bf170c85139dcf05`.
Calendar bucket uses the body's preservation distinction, not its generator
bound. These semantic bodies do not contain external contract-reference fields;
selected lexical/calendar profiles and concrete bound values retain their own
roles. Per-occurrence selection does not combine different Program owners.

The existing exhaustive operation-profile classification also exposes adopted
AoA law roots: RelA scalar/primitive laws, SGA structural/identity laws, and VecA
numerical laws. Reads from an `OperationProfileResolution` retain the same owned
site; repeated producer visits are not merged because their law CIDs match.
The law pins are verified against the shared bodies, independently of any
selected backend registry. Adopting a law does not establish backend support.

This is deliberately an **adopted-law** inventory, not all profile dependencies.
TEA, Calendar and TextRank have no entry in these five adopted manifests; zero
here does not erase their ActQL rules, selected timezone/tokenizer artifacts,
identity rules or execution checks. Likewise, scalar expression requirements
are selected through their own expression roots rather than inferred solely
from an operation's output Carrier. New operation/profile variants must be
classified by the existing exhaustive match, not a duplicate name list.

Operation roots must be selected from all owned producer pipelines, not merely
the list of resolved profile obligations. Ordinary RelA operations may require
no such obligation and would disappear from a resolution-only inventory.
`program_identity_producer_count` and `program_identity_producer_at` provide the
retained per-Stage visits for this traversal, including unused authored producers.
The existing pipeline step/profile accessors then supply the adopted-law roots.
Reads retain exact pipeline ownership without copying arrays or rehashing;
visiting and collecting roots still consumes the caller's aggregate work budget.
Repeated visits are not silently collapsed at this source-occurrence boundary.

`collect_core_contracts` performs this traversal from one `ProgramSourceIdentity`.
It retains every Stage source-grammar, semantic-rule, environment-interpretation
and expression root, every adopted-law occurrence across
all producer visits, and selected SourceView contract-reference occurrences.
Source selection is derived internally from the identity's own input context;
the caller cannot supply a substitute Catalog or a second source inventory.
Each selected body is interpreted through that context's existing admissions,
including request-owned lookup facts and pushdown contracts. An unsupported body
or unknown governing grammar rejects the entire collection with its stage,
input and reference coordinates, even for an unused input.
The result retains the original identity owner; shared body CIDs cannot replace
that owner. Expression dependency edges retain their declared positions through
the typed graph accessors, including repeated edges to one Unicode table.

Each `values` occurrence also selects the pinned `actql-bound-values-law/0.1`
semantic body, including empty rows and repeated producer visits. The root
retains Stage, producer and step coordinates; only body storage is shared by
CID. A Stage without such a root does not inherit it from another Stage.
The law body has no declared dependency edges. Its selection does not validate
a count proof, bind cells or certify execution, and does not stand in for other
capacity laws. The law-name registry is not substituted for a semantic body.

The work limit includes prior identity work once, plus root collection, producer,
step and profile visits, source selection and body interpretation, and each
unique grammar body's outgoing edges. Repeated direct Catalog-reference edges
are charged at each occurrence. Independent caps
bound retained roots, unique bodies and traversed edges before array growth.
Traversal is nonrecursive. Exceeding any cap returns no inventory, including
when the failure occurs after collecting the last Stage's roots. Indexed reads
do not copy retained arrays. A CID index shares body storage without a quadratic
scan of Catalog occurrences. Known expression and adopted-law targets use the
same traversal as those reached from Catalog grammars; shared storage never
substitutes for the retained reference roles or exact Program owner.
Body inventory order is discovery order, not canonical contract-set order; it
must not be hashed as the final set without the prescribed canonical sorting.

This is the core expression/adopted-law and selected Catalog contribution, not a
completed local contract set and not a Unit identity. Declaration, selected profile
data, publication and incoming-interface contributions must still be selected
and joined under the same Program owner before the final closure is emitted.

Calendar and TextRank operations additionally contribute the exact admitted data
profile that determines their semantics. Calendar retains the checked transition
table; TextRank can retain a profile directly or consume the existing owned
profile-link checks when the operation initially deferred selection. An enabled
profile flag is not a substitute for that data. Missing TextRank data rejects
collection, and profile checks from an equal-content but different Program reject
before their results can be reused. The retained checks share their prior work
with the identity prefix rather than counting it twice.

Each operation occurrence retains its stage/producer/step coordinates, while an
identical profile body is stored once. These profiles have already passed their
closed canonical-body admission. TextRank's embedded laws and exact byte-resource
pins are validated there; raw Unicode/vector file hashes are not reinterpreted
as canonical-JSON contract bodies. The retained profile owns those resources.
Collecting an operation's embedded profile alone does not waive the separate
Host-selection match or other pending profile checks required for final closure.

The collector derives incoming sites from the same source identity and Result
wiring, rather than accepting a caller's list of interface CIDs. Each Result
import selects the registered `/schemas/result_import_interface` body in
`actql-stage-contracts.json`; each predecessor milestone additionally selects
`/schemas/gate_requirement`, with common Stage laws retained by its Stage roots.
Repeated and unused imports retain separate sites, while the grammar body is
shared. Accepted and completed milestones remain distinct in the retained site;
choosing the same interpretation contract does not equate their gate semantics.
Unsupported receipt interpretation rejects collection rather than using the
Result interface grammar as a substitute.

Incoming collection shares the identity prefix with the other branches. Name
units are charged to aggregate work as well as its separate name limit, before
lookup or insertion. The collector retains the exact incoming inventory for
subsequent interface construction. Selecting this grammar is not construction
of the interface value, its producer Unit identity, or proof of Result availability.

For a predecessor with no Effect declarations, `prepare_incoming_gate` constructs
the registered `gate_requirement` envelope from the owned incoming success check.
Its four Effect/completion maps are empty because the source check established
that no such contracts require interpretation, not because missing contracts
default to empty. An unresolved success-contract check prevents construction.
The milestone and producer node name come from the retained source identities.
`empty_items` still requires successful computation and preflight; neither
milestone nor empty maps imply observed success or permission to activate.

The gate self CID hashes the canonical whole envelope except `self_cid`. The
bounded preimage and full-envelope emitters share the same field encoding; the
hash path does not materialize a complete String. Hash bytes/nodes and aggregate
work are retained separately. Equal gate CIDs do not make distinct Program
admission owners interchangeable. Nonempty Effect contracts and Receipt gates
remain separate unsupported interpretation paths, not this empty-Effect form.

The retained inventory distinguishes the Program-wide shared body store from
each Stage's selection. A Stage reaches only its own source roots and their
declared dependencies. Consumer import grammar does not become a producer root;
nor does a consumer inherit a predecessor's entire Catalog contract inventory.
The incoming interface projection carries the required producer relationship
separately. Equal contract bodies may be shared without merging these scopes.

Dependency adjacency is retained from the validated edges, not rediscovered by
scanning CID-shaped strings. Repeated uses share adjacency; all original root
occurrences and edge-validation charges remain. Stage selection uses bounded
iterative traversal with work charged before allocation or visits, and exposes
indexed reads without array copying or re-traversal. These selections cover the
supported root inventory only: they are not yet a completeness certificate or
a substitute contract-set CID for the final Unit boundary.

Import/interface and gate construction supplies its local semantic contract
references. Full predecessor Program revisions, Captured Runs, receipts and
whole manifests are not substitutes for those projections. A required projection
that cannot be constructed is unresolved, not an empty dependency set.

## Result import interfaces

The [Result import interface](../spec/language.md#result-import-interface) binds
the local consumer input name to the producer's typed namespace, Unit Definition,
Result name and declared row contract. Graph `data_requirement` alone cannot
serve this role: it names nodes and ports but does not bind the producer's local
semantic definition. Conversely, a whole Result artifact would introduce concrete
Invocation ancestry into a static Unit identity. The registered Result interface
fills the existing external import-interface role; it is not another Result
artifact family or a replacement for runtime data requirements.

The canonical row contract records types; producer identity retains the authored
Result projection and its semantic dependencies. Equal row types are not equal
producer interfaces. Consumer input names distinguish repeated imports, while
sorting the interface list by those names removes source object enumeration as
an identity input. Receipt interfaces retain their separate correlation and
completion requirements and cannot be approximated by this Result-only form.

This fixes a previously external, unspecified preimage. The pinned Sketch
reference `87dc7144138edfcba108cdc59dc485ac976ba976` exposes only the external
import-interface reference role in `src/actql-stage-contracts.ts`; it does not
supply a body encoding to reuse. The choice follows the language's local-approval
identity requirements rather than a compiler's temporary ownership handles.

## Transitive dependencies

For each reached contract, enumerate the contract-bearing roles prescribed by
its registered governing contract. Follow each reference using its exact pinned
identity and kind. Continue until no new contract is reached. This includes
indirect numeric, schema, permission, guard, scope and failure dependencies.

Do not scan arbitrary JSON strings for CID-looking values or recursively treat
business `$param`, `literal`, `$ref` or metadata as contract dependencies. The
registered grammar decides which positions carry contract references. Equally,
an unrecognized contract body is not assumed to have no dependencies. An
unsupported dependency grammar prevents closure construction.

Unknown required dependencies, conflicting pins for a contract identity and
references of the wrong kind reject. Complete-contract integrity is checked
under that contract's existing identity rule; the closure builder does not
invent metadata stripping or another hash preimage for an already pinned body.

Finite reference cycles are traversed with a visited set and all reached members
are retained. Cycle acceptance still requires the governing reference grammar
to permit the cycle; a visited set must not suppress a prescribed cycle error.
In particular, this rule does not permit cyclic execution prerequisites. Local
recursive schema references are interpreted by their schema contract and do not
automatically create additional external contract nodes.

Catalog interpretation dependencies use declared JSON Pointer positions, not a
scan for CID-looking strings. The Check Environment interpretation body refers
to the value grammar, Graph laws, pushdown laws and expression grammar, and the
text-time and capacity policy grammars. These are contracts describing policy
values, not selected Host policy values or the enclosing Catalog's identity.
Graph identity and value roles remain separate edges even when they share a
body. A value-contract body's governing grammar is the canonical value grammar;
other admitted Catalog shapes can instead use the Check Environment grammar.
Resolution checks both the declared role and its exact pin. Unknown or
mismatched dependencies are unresolved, never silently treated as leaves.

## Canonical set representation

The selected closure is represented by:

```text
{version:"actql-local-contracts/0.1", contracts:[contract_cid, ...]}
```

`contracts` contains every reached CID exactly once, in ascending code-unit
order. CIDs use the existing lowercase `sha256:` form. Canonical JSON of this
whole object is the hash preimage; no self-CID, source location, dependency
traversal order or enclosing environment CID is added. The empty set has the
same explicit versioned representation, rather than a magic null or zero CID.
This representation does not assert that an actual Unit has no governing laws.

Root occurrences and dependency edges are retained as typed construction
evidence, but are not duplicated in the set's hash. Their meanings are already
bound by the Unit body/interfaces and the reached contracts. Consequently,
repeated uses of a contract can share a closure CID without making two Unit
bodies identical. A changed reference role cannot be hidden by comparing only
contract-set CIDs at the Unit validation boundary.

JSON Schema can enforce the closed envelope, CID syntax and absence of duplicate
entries. Canonical ordering, exact reachability, reference interpretation,
identity/kind consistency and source ownership require separate semantic checks.
An arbitrary sorted set is not a validated closure.

## Construction and verification boundaries

The compiler retains the exact Unit inventory and admitted registry owners while
selecting roots and traversing dependencies. Work, retained nodes and reference
visits have shared explicit limits; repeated reference visits are charged even
when a reached contract is stored only once. Traversal is nonrecursive, and the
result is sealed only after every required role is covered. A budget error or
late missing dependency exposes no partial closure.

Independent vectors cover an empty set, a direct dependency, a shared transitive
dependency, repeated roots, input enumeration changes, an unrelated Catalog
addition, a changed reachable pin, missing/wrong-kind/conflicting dependencies,
and cycles under their governing rules. Phase tests distinguish a changed Host
policy value from a changed policy interpretation contract. Unit tests separately
confirm that equal closure CIDs do not erase body or import differences.

The canonical representation, registered reference owner, selection rules and
fixed vectors have distinct verification responsibilities. Shape and hash tests
do not certify the compiler's source inventory, contract grammar coverage or
dependency admission. Those checks remain mandatory at the opaque construction
boundary; a generic JSON/CID helper is not a substitute.
