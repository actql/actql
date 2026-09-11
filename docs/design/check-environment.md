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
product compiler. Generated MoonBit tests verify preimage canonical hashing;
they do not verify full environment admission or member-array ordering.
The small Node shape test covers the explicit outer schema keyword subset only.

Required implementation stages remain distinct: canonical envelope integrity;
member shape/identity and ordered section handling; exact Catalog-derived
closure; local/Connector snapshot correspondence; selected policy/component
validation; and binding that admitted environment to the exact Program context.
All supplied bodies need their governing validation, including unused evidence.
An integrity-only reader must expose a distinct type and cannot create the final
admitted checking environment. The current local snapshot/source/type agreement
objects are ready to be consumed there but do not yet prove membership.
