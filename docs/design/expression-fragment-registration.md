# Expression fragment registration

The shared registry now explicitly registers `ACTQL.expression_fragment/0.1`.
Its existing unary Relation signature and closed `{fragment}` parameters come
from Language's common-expression contract, not a new lowering representation.
Sketch `87dc7144:src/actql-expression-pipeline-v2.ts` implements the same binding
through a separate validator while leaving its legacy registry unchanged.
This registration replaces that implicit capability discovery with an exact
shared contract reference. It does not replace sealed-fragment admission.

## Handoff

- Registry: `spec/dependencies/aoa-pipeline-registry.json`, root pointer `""`.
- Registry CID: `sha256:23a7f1081d1a2cdab7b20e425dddce846510355ba964058e0c809350fae33816`.
- Entry: `/ACTQL.expression_fragment~10.1` (RFC6901 escaping is significant).
- Contract: `spec/contracts/actql-aoa.json#/execution_contracts/ACTQL.expression_fragment~10.1`.
- Contract CID: `sha256:3cf4269dcf6c78f77bac984a228a18b743501905821fef41fa926b055f75d2e1`.
- Fragment schema: `spec/contracts/actql-expressions.json#/schemas/fragment`;
  resolve its URN from the pinned dependency, without fetching it over a network.

The contract pins both that schema and the complete expression contract, whose
CID is also the AoA contract's `expression_contract_cid`. This closes a previously
stale embedded expression pin. Schema validation checks the closed wrapper and
fragment shape; semantic admission still regenerates the request's graph, roots,
types, demand paths, limits and profile evaluations under the exact contract,
checks self-CID, and requires exactly the local source `input`. It is not enough
to verify shape or hashes alone. Keep the opcode and full fragment in the
composition; a carrier-check projection is never executed or hashed instead.

The 58-entry values registry remains byte-preserved in
`portability/fixtures/pipeline-registry-values.json`, with CID
`sha256:b97a22de3664c1dafe3bc1e6791f1f8bcfb70324a1fcc1087450fe057e0f2311`.
The new body adds only this registration. REL.values and all other entries are
unchanged. Historical lowering fixtures remain bound to their historical CIDs.
Current consumers resolve the newly selected registry instead of relabelling
an old body. The containing AoA contract and its dependent document pins change.

`scripts/expression-fragment-registration.mjs --write` maintains the new entry
and execution contract. Its check and independent fixed-hash Node tests are in
`check:aoa`; mutations cover signature, pointer, file, body, dependency and old
registry selection. These are registration tests, not a fragment lowerer or
evaluator. Ordered derive's shared row-kernel remains a separate delivery.
Backend support, runtime obligations, Program completion and execution authority
are not established by registration.
