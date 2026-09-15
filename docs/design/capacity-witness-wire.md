# Capacity witness wire admission

`capacity_witness.admit` checks the common wire representation of
`actql-bound-witness/0.1` from the pinned protocol schema and the language's
[resolved-limit rules](../spec/language.md#resolved-limits). It returns an opaque
`WireWitness`: an integrity-checked **claim**, not an authenticated source fact,
validated law application, resolved limit or runnable Plan evidence.

The reader checks all five closed source forms and their exact role pairing,
all nine units, nonnegative safe-integer values (positive for author guards),
registered governing law names and all seven closed derivation operations.
Optional clamp input is absent or a CID, never null. Source strings follow the
schema, including the `$` prefix on author paths; existence of that path or
subject in its actual source is not established here.

Dependencies and minimum input references have canonical, ascending, unique CID
spelling. Repeated add operands remain distinct occurrences, although their CID
appears once in the dependency set. Every source and derivation reference must
appear in that set. Additional declared dependencies are retained for later
closure/application validation, not silently dropped or treated as verified.
The referenced bodies are not resolved by this reader.

The expected witness CID must equal both the claimed identity and the hash of
the canonical preimage with only the root `witness_cid` excluded. Hashing the
complete reconstructed wire form must also match the original bytes. This
rejects whitespace, alternate number spellings, normalization repairs and
different member order; it does not repair signed artifacts. The emitter uses
the shared UTF-16 comparator, not the platform's default string ordering.

Bytes, nodes and depth are bounded before admission. The emitter traverses only
the checked closed shape: its object/array nesting is fixed and cannot contain
an arbitrary recursive value. Hashing does not construct a full output string
or byte array. Parsing and the owned cursor do still allocate input structures;
these limits are not a total heap limit. Returned reference arrays are detached.

`capacity_host_witness.admit_wire` consumes this common result and rebuilds the
Host witness from its exact admitted policy field. Comparing the rebuilt CID
checks the complete field/unit/law/value/source/dependency application. A
self-consistent wire claim with the wrong unit passes integrity admission but
fails this Host-source boundary. Existing direct Host byte admission and wire
identities remain supported unchanged.

Fixed test cases use independently computed Node SHA-256 identities for all
source/derivation combinations and all units. Negative fixtures have correct
self-CIDs but invalid shape, roles, values, dependencies or law names. All 14
Host applications also traverse the new common-to-Host boundary.

## Arithmetic closure of wire claims

`check_arithmetic_claims` connects admitted wire claims to the CID-addressed
arithmetic checker. It resolves all operand references, checks units and exact
numeric derivations, and rejects duplicate witness identities, missing operands,
cycles, mismatched values and overflow. All supplied claims are visited, even
those not selected by a consumer. Wire minimum references are a canonical set;
add's repeated operand occurrences are retained and counted twice.

The shared budget counts declared dependency entries plus derivation operand
occurrences, before allocating converted nodes or operand arrays. Input wire
admission has its own byte/node/depth limits. The result owns its witness array,
provides indexed identity lookup, and retains the original immutable claims and
their sources rather than exposing just anonymous numeric leaves.

`ArithmeticClaims` does not establish external source integrity, governing-law
applicability or the exact semantic dependency set. It does not resolve external
source CIDs through the witness map or pretend that a numeric source claim is a
verified observation. Those requirements remain for every retained claim. An
`enforced_ceiling` fails with `UnresolvedEnforcement(index, resolved_limit_cid)`:
it cannot be converted into a source leaf merely because it has a valid self-CID.
The validated resolved-limit/enforcement boundary must support that case before
such a collection can pass. This is an implementation gap, not a language ban.

Independent sealed-graph fixtures cover every arithmetic operation, forward and
shared dependencies, repeated add operands, exact reference budgets, missing and
duplicate witnesses and detached results. Additional valid-self-CID fixtures
append unused numeric, unit, overflow and enforcement failures to a valid graph.
The lower reference checker separately tests synthetic cyclic graphs and a
10,000-node chain; these are not claimed to be real SHA-256 cyclic preimages.

Non-Host source validation, complete source dependency closure,
enforced-limit dependencies, operation-specific applicability and complete
consumer discharge remain required. `WireWitness` is intentionally not accepted
as pipeline proof. Fixed Sketch `src/actql-bounds.ts` is reference material;
its optional dependency-map validation and global witness cache are not trust
mechanisms in this implementation.

## Program proof body binding

`bind_program_proof` binds a Program-source wire claim to original canonical
proof bytes under byte/node/depth limits. It checks the source's `proof_cid`,
version, semantic reference, governing law, unit, value and exact declared
dependency set. Its opaque `ProgramProofClaim` retains the original witness,
body form and indexed proof inputs. It is not a validated operation fact and
cannot be supplied as pipeline evidence.

Two closed forms share `actql-bound-proof/0.1` in the fixed reference:

- Derived bodies contain `inputs`, retaining sorted repeated operand occurrences.
- Program bodies contain `program_definition_cid` and `dependencies`, also
  retaining sorted repeated occurrences.

Both contain `version`, `law_id`, `semantic_ref`, `value` and `unit`. The wire's
unique dependency set must be exactly the proof CID, the body's input CIDs and,
for the second form, the Program Definition CID. Mixed forms, omitted fields,
extra dependencies and noncanonical original bytes fail; none is repaired.
Repeated proof inputs are not confused with the unique wire dependency set.

These forms are implementation material from fixed Sketch
`87dc7144138edfcba108cdc59dc485ac976ba976`, `src/actql-bounds.ts::derivedWitness`
and `src/actql-compiler.ts::programUpperBound`, not a new universal restriction
on Program proofs. In particular, an enforced ceiling references a resolved
limit instead of either body form and is explicitly unsupported by this entry.
Effect-scope proofs belong to a separate owner as well.

Binding proves only that the body and claim agree. It does not validate the
referenced Program Definition, resolve input bodies, check operand multiplicity
against a particular law, or establish that the semantic operation guarantees
the claimed bound. Those source/application obligations remain mandatory.
Tests use independently computed proof and wire CIDs, retain repeated inputs,
check exact budgets and reject self-consistent mismatches and altered encoding.

## Program input closure

`check_program_claims` combines an `ArithmeticClaims` collection with bound
Program proof bodies. Every Program claim requires exactly one matching proof,
including unused claims; duplicate and foreign proofs fail. Proof arrays may
arrive in any order, but the result exposes them in the original claim order.
Ownership is bound by the admitted witness CID, not by a caller-supplied flag.

Every proof input must resolve to a witness in that same arithmetic collection.
For non-source derivations, the inputs must match the derivation operands:
preserve/multiply/clamp have their specified zero or one input, add retains both
occurrences even when their CIDs match, and minimum compares its unique operand
set while preserving the repeated proof inputs. Source proofs may depend on
other witnesses without describing arithmetic; those edges are still resolved.
These representation checks follow the fixed proof constructors, not an
assumption that membership in the law registry proves operation applicability.

The union of Program proof inputs and non-Program arithmetic operand edges is
checked for cycles with an iterative traversal. Numeric source leaves therefore
cannot hide missing inputs or cycles from this boundary. The referenced Program
Definition and other external source bodies are not witness nodes and still
need their respective source owners; no fictitious numeric node is substituted.

The witness budget counts arithmetic claims plus supplied proof bodies. The
reference budget includes the arithmetic collection's previous charges and every
proof input occurrence. Both are checked before allocating indexes or graph
edges. Results own the proof index and retain the original arithmetic collection.
Failure is atomic; no partially linked proof collection is returned.

Fixed independent fixtures cover all arithmetic forms, repeated inputs, forward
references, both proof forms, input ownership, exact budgets, missing proofs and
missing source inputs. Synthetic topology tests cover repeated edges, unused
cycles and a 10,000-node chain without claiming cyclic SHA-256 preimages.

`ProgramClaims` is still not runnable evidence: it establishes integrity,
arithmetic and Program-input closure, not source truth, author/Contract/language
authority, the actual Program subject or governing-law applicability. Complete
source/application validation and resolved-limit enforcement remain mandatory.

## Resolved-limit wire claims

`admit_limit` admits the closed `actql-resolved-limit/0.1` representation against
an independently expected CID and an existing `ArithmeticClaims` collection.
Every embedded candidate must match the complete admitted witness body in that
collection, not merely copy its CID. Admission recomputes the same-unit minimum
and strict author-guard binding, checks fail-only breach and the closed
enforcement vocabulary, then verifies preimage identity and canonical original
bytes. Candidate order is nondecreasing witness CID order; repeated candidates
remain repeated, as in fixed Sketch `87dc7144` `resolveActqlLimit`.

The opaque `LimitClaim` retains the collection, candidate indexes, subject,
enforcement, identity and canonical body. `emit_limit` reproduces that artifact
under the caller's writer limits. Missing witnesses, altered candidate bodies,
wrong units or computed fields, unknown members and alternate encodings fail
without repair. All candidates are checked, not only a winning minimum. An
iterative comparison against admitted fixed-shape witnesses precedes emission,
so malformed deep candidates cannot enter the fixed-shape emitter. Byte/node/
depth budgets cover the complete artifact; a separate candidate budget counts
repeated occurrences. No global witness cache is consulted.

This is not runnable evidence. It does not establish that all applicable
candidates were supplied, validate sources or governing law applications, bind
the subject to an actual consumer, or prove enforcement appropriate there.
Naming `static` does not discharge a ceiling. No pipeline API accepts this type
as count or execution evidence. Direct arithmetic admission still rejects
enforced-ceiling nodes. The mixed closure entry below owns their numeric and
dependency binding, without proving that enforcement has occurred.

Independent Node SHA-256 fixtures cover all six enforcement spellings, absent,
binding and equal-valued non-binding guards, guard-only limits, repeated
candidates, altered self-consistent artifacts and exact admission budgets.
Synthetic source claims in these tests do not assert source-law truth.

## Mixed witness and limit closure

`check_mixed_claims` checks an entire supplied witness/limit collection atomically,
including unused entries. It links ordinary arithmetic references, admits every
limit against that same collection, and resolves each `enforced_ceiling` to a
unique limit. Units and values must match and enforcement must be
`unit_preflight`. This entry supports the fixed compiler's Program-source form:
the proof CID is the resolved-limit CID and the exact dependency set contains
only that CID. Other source/enforcement forms are not implicitly promoted.

Limits may arrive before their dependencies. The union graph includes ordinary
arithmetic operands, enforced-witness-to-limit edges and every limit candidate
occurrence. An iterative traversal rejects cycles after all references are
resolved. Numeric leaves used internally while binding enforced claims are
never exposed on failure. The original arithmetic-only entry remains strict.
The result retains the arithmetic claims, every admitted limit and an indexed
association from enforced witnesses to their limits; caller arrays are detached.

The entity budget counts witnesses plus limit artifacts. The reference budget
counts declared witness dependencies, arithmetic/enforced operand occurrences
and all repeated limit candidates. Bytes and nodes are cumulative across full
limit artifacts, not reset per limit. Depth is a per-artifact nesting ceiling.
Witness bodies were already admitted under their own byte/node/depth budgets.

This entry closes numeric and mixed-reference consistency only. The combined
entry below additionally resolves Program proof-body edges. External source
truth, governing-law applicability, candidate completeness and actual
consumer/preflight bindings still require validation.
In particular, `semantic_ref` and `subject_ref` are retained but not equated:
the fixed graph-input constructor uses an input name for the former and
`graph-input:<name>:nodes|edges` for the latter. A separate consumer owner must
validate that relationship rather than comparing arbitrary strings as authority.
No observed count or runnable permission is issued by `MixedClaims`.

Independent fixtures cover forward references, chained limits, retained
arithmetic dependencies, mismatched units/values/proof dependencies, missing and
duplicate limits, unsupported enforcement and shared budget boundaries. A
white-box test injects synthetic cyclic topology without claiming to construct
a cyclic SHA-256 preimage.

## Combined Program and limit references

`check_mixed_program_claims` adds bound Program proof bodies to `MixedClaims`
and reruns one union dependency traversal. Ordinary Program witnesses require
exactly one proof, including unused witnesses, with the same operand-occurrence
rules as `check_program_claims`. Preflight witnesses instead retain their
already-bound resolved limit; no fictitious `actql-bound-proof/0.1` body is
substituted for that different proof domain.

The union includes Program source-proof inputs, ordinary arithmetic operands,
enforced witness-to-limit edges and every candidate occurrence. Resolving each
subgraph separately cannot replace this check: a source-proof edge may complete
a cycle through an otherwise acyclic limit. Traversal remains iterative and
failure returns no partial result. Missing, foreign or duplicate Program proofs
and missing or mismatched proof inputs fail before cycle acceptance.

The entity budget includes arithmetic witnesses, retained limits and supplied
proof bodies. The reference budget carries forward all mixed-closure charges
and adds every proof input occurrence, including repeats. The result retains
the original `MixedClaims` and proof index; `program_claim_mixed` exposes that
owner instead of losing the preflight associations. Passing only the extracted
arithmetic collection to the older entry does not bypass proof requirements.

Fixed independent fixtures exercise both Program proof forms alongside forward
preflight chains, repeated source inputs, exact budgets, missing unused proofs,
foreign/duplicate bodies and operand mismatches. Synthetic white-box topology
confirms rejection of a cycle introduced specifically by a Program proof input.
This completes the implemented internal reference-union check, not external
source validation, law application, consumer matching or execution permission.

### Extending an owned collection

`extend_program_claims` appends ordinary admitted Program proof bodies and
checks the complete resulting arithmetic and Program dependency graph. Existing
witness indices form an unchanged prefix; existing proof and resolved-limit
handles and enforced-limit associations are retained. An extension cannot add
an enforced leaf or silently replace an existing witness with an equal CID.
Duplicate witnesses and unresolved dependencies remain errors.

The closure limits apply to the entire resulting graph, including retained
limits and repeated proof-input occurrences. Admission and construction of the
additional artifacts have separate budgets. Retaining a resolved limit does not
reselect its candidates or assert applicability of a new proof to an operation:
source, producer and consumer ownership still require their respective checks.
