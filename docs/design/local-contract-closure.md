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

Concrete Host policy decisions, capacity observations and resolved numeric
ceilings belong to the applicable Plan/Invocation evidence, rather than being
inserted into Unit Definition because the checker consulted them. Authored
guards remain in the Unit body. Policy and capacity *interpretation contracts*
remain in the contract closure. An actual contract-version change is distinct
from a new policy value interpreted under the same contract.

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
