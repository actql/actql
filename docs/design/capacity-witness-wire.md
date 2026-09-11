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
