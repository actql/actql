# Check Environment envelope and admission boundaries

The normative owner is [Check Environment and source evidence](../spec/protocols/contracts.md#check-environment).
`spec/contracts/actql-check-environment.json` pins the outer schema and identity
rules; its `schema` is a standalone resource. This is not an executable registry,
backend capability declaration or admitted Host policy.

The eight evidence arrays, policy object and root self-identity match the explicit
shape at Sketch `87dc7144:src/actql-portability.ts`. That implementation also
orders each array by full member CID. Those details previously lived in reference
code rather than a pinned envelope schema. They are now explicit wire rules,
without extending aggregate hashing into evidence authorization.

The normative unique-selector rule takes precedence over the reference builder's
`sortUniqueEvidence` treatment of schema snapshots: identical duplicate snapshots
are rejected, not merged. The existing special rule for identical Contract
Envelopes still permits their canonical deduplication. No blanket deduplication
rule is inferred for capabilities or mappings. Unresolved/unknown policy bodies
can be represented and hashed without satisfying any policy-dependent compiler
obligation. Supporting the outer schema is not support for every member body.

The content preimage excludes only the root `evidence_bundle_cid`. Nested data
using that name remains hashed. `check_environment_cid` is an alias reference,
not another self-member. Fixed independent vectors cover an empty unresolved
environment, changed policy, nested identity-like data and a local schema body.
Their expected preimages and complete wire text are fixed using Node, never a
product compiler. Generated MoonBit tests verify preimage canonical hashing
and integrity-only wire admission. Negative wire cases cover missing/unknown
members, wrong section shapes, duplicate selectors/contracts and array order.
These are not full environment admission tests.
The small Node shape test covers the explicit outer schema keyword subset only.

Required implementation stages remain distinct: canonical envelope integrity;
member shape/identity and ordered section handling; exact Catalog-derived
closure; local/Connector snapshot correspondence; selected policy/component
validation; and binding that admitted environment to the exact Program context.
All supplied bodies need their governing validation, including unused evidence.
`check_environment.read` now returns a distinct opaque `WireEnvironment`, not
the final admitted checking environment. It checks closed shape, canonical full
bytes, root-excluded identity, all member object shapes and CID order, duplicate
snapshot selectors and duplicate canonical Contract Envelopes. It retains every
member with its independently recomputed full-body CID. Other component semantics
remain unverified, including malformed policy or Catalog contents represented as
objects. Such bodies are inspectable, not usable as admitted evidence.

The canonical emitter uses explicit frames and checks existing UTF-16 key order
instead of sorting/repairing wire data. Full wire and preimage go to hash sinks;
the full environment is never rebuilt as a String. Parsing, owned-tree admission
and hashing use byte/node/depth caps; the total member count is also bounded.
Per-member hashing covers disjoint subtrees, so aggregate payload work remains
linear rather than receiving an unbounded new allowance per selector. Returned
usage is full canonical body size/node count and total members, not heap usage.

`member_at` creates an opaque handle retaining the exact environment owner,
section, position, cursor and full-body CID. Re-reading identical bytes creates
a different internal owner, despite an equal content CID. Public cursors preserve
original locations and cannot mutate the owned tree. Tests cover member bounds,
ownership, noncanonical bytes and depth 1,000 without recursive emission.

`local_relation_snapshot.read_member` validates a SchemaSnapshots member using
its own computed CID and retains that exact Member in an `EnvironmentSnapshot`.
The same body in another section is rejected. Only the individual bounded member
is serialized for the existing snapshot reader; the whole environment is not.
This proves content membership plus local snapshot shape/type integrity. It does
not validate the rest of the environment or authenticate Host claims. The final
Program connection must retain this membership alongside exact source/type
agreement and the governing policy/Catalog checks, not unwrap and forget it.
`stage_local_inputs.reconcile_environment` now preserves this ownership alongside
resolved stage inputs and schema agreements. It rejects foreign member owners,
including separately read identical envelopes. Its selected member set may be
partial. `stage_local_inputs.assemble_environment` now requires every stage and
every supplied snapshot to be covered under the same source/environment owners.
This is local-Relation snapshot coverage, not admission of other sections or proof
that all inputs have the evidence their governing policy will require.

## Capacity component selection

The normative component selector is now `/host_policy_profile/capacity`, with
the existing capacity-policy contract pinned as a dependency. Sketch at `87dc7144`
uses this same property in `hostCapacityPolicy` and its reference profile. The
prior normative text required environment selection but did not specify this
location; fixing it is an explicit wire clarification, not a new policy default.
The outer profile remains an object whose other components need their own checks.

`read_capacity` validates the selected body through `capacity_policy.admit` and
returns an opaque owner retaining both the exact wire environment and Policy.
The selected CID hashes the full component, distinct from profile/environment
identity. Missing capacity is unresolved; null or an invalid supplied body cannot
be treated as absent. Only this bounded component is serialized, not the whole
environment. Independent fixture identity, limit boundaries, malformed ceilings
and separate environment owners are tested. The envelope contract CID changes
because it now pins component selection/dependency; unchanged envelope bytes do
not change their own CID. Compiler policy matching and other component admission
remain separate work, and no Host authorization follows from this reader.
