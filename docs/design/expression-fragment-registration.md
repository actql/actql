# Expression fragment registration

`ACTQL.expression_fragment/0.1` is a unary Relation operation with closed
`{fragment}` parameters. Explicit registration separates discovery of this
execution capability from validation of the contained fragment.

## Contract resolution

The selected registry is identified by `pipeline_registry_file` and
`pipeline_registry_cid` in `spec/contracts/actql-aoa.json`. Its entry is at
`/ACTQL.expression_fragment~10.1`; the slash in the operation version is escaped
according to RFC6901. The execution contract is at
`/execution_contracts/ACTQL.expression_fragment~10.1` in the AoA contract.

The execution contract pins both the complete expression contract and the
existing fragment schema at `actql-expressions.json#/schemas/fragment`. Resolve
the schema URN from this exact dependency, without a network lookup. The AoA
contract's `expression_contract_cid` identifies the same expression body.
The registry hash includes the execution-contract reference, not only the
operation's input/output signature.

## Admission and execution boundaries

Schema validation checks the closed wrapper and fragment shape. Semantic
admission regenerates the request's graph, roots, types, demand paths, limits
and profile evaluations under the selected expression contract, checks the
self-CID, and requires exactly the local source `input`. Shape and hashes alone
do not establish semantic validity.

The canonical composition retains the opcode and full fragment. A projection
used to check carrier compatibility is neither executed nor hashed in place of
that material, and supplies no expression type evidence. The inner graph is
not a standalone execution artifact.

Changing a registry body changes its identity. Historical bodies remain bound
to their original CIDs; they are not relabelled to satisfy a new selection.
A backend must support the exact registered contract and every extension used
by the fragment. Registration does not establish runtime checks, whole-Program
completion or execution authority.
