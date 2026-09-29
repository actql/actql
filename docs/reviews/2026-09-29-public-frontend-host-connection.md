# Public Frontend Host connection boundary

This integration branch merges the committed Host base
`d49d77952a8f6256157da235001a47e113912594` with the public SDK and
native CLI source-routing branch `f28a8b19b1bd1c212e1cd0bea4352e31951a82ff`.
It does not include the Host owner's uncommitted capture or Checkpoint work.

## One preparation operation

The Host installs an immutable alias publication together with its admitted
Check Environment. The publication is a bounded list of
`{name, sourceRef, sourceViewContractCid, schemaContractCid}` and the exact
`evidence_bundle_cid` of that environment generation. Its names are parsed by
the existing query-name parser, not split by the Node adapter. Publishing
checks that each source and schema refers to the same admitted Source View;
duplicate names under the query resolver are rejected. The alias is a name
binding, not a read grant.

For an AQL or SQL source request, the B-owned Node preparation adapter accepts
the ordinary Client request, the admitted Check Environment owner, and this
publication. It passes source text, the explicit format, optional typed
parameter declarations, separate parameter values, and the generation-bound
alias list to one in-process MoonBit operation. The operation returns the
existing `ClientProgramBridgeOutcome`: a `PreparedClientProgram` or a typed
preparation issue. It performs no physical I/O and neither accepts a Run nor
creates a second request owner.

The C-owned `client_program_bridge.mbt` should expose
`clientProgramPrepareSourceWithParameters(document, format, environment,
aliasesWire, declarationsWire, parametersWire)`. It validates the alias
publication against the exact admitted environment, constructs the existing
`query_program.Context`, calls `source_frontend.lower`, then passes the lowered
Program JSON and separate values to
`prepare_effect_free_client_program`. It must preserve typed frontend,
parameter and checker refusals. JSON/YAML Program requests continue through
`clientProgramPrepareEffectFreeWithParameters`; external declarations are
rejected for those formats.

The existing `clientProgramPreparationIssueCode` projection should return
`source_invalid_input` for source syntax or wrong language, `source_rejected`
for unknown aliases or invalid query semantics, `source_unsupported` for an
unsupported query form, `source_missing_input` for an unbound required input,
`source_declarations` for malformed external parameter declarations,
`source_limit` for frontend bounds, and `source_encoding` only for an internal
emission failure. The Node adapter maps these to existing public typed errors;
it does not turn a confirmed refusal into `SubmissionUnknown`. The checker
retains its existing issue categories after lowering.

The C-owned `embedded-local.mjs` call site supplies its installed publication
and environment to `installNodeClientProgramPreparation` and otherwise keeps
the existing submit, durable Run acceptance, dispatch, recovery and Result
owners. The installed source-profile loader publishes `queryAliases` from
installation input after validating them against the composed environment;
it does not infer aliases from physical table names. The same preparation
operation is used behind in-process Local and HTTP Host transport.

The proposed call-site argument is
`sourcePublication: {environmentCid: evidenceCid, aliases:
sourceProfile?.queryAliases ?? []}`. The B-owned Node adapter checks the exact
generation and bounded wire shape before calling the bridge. The bridge must
also check each member's admitted Source View and schema, parse alias names
with `query_syntax.parse_relation_path`, and reject same-rule collisions.
Neither the Node shape check nor an alias CID alone grants source read access.

## File ownership and acceptance

B edits `adapters/host-node/client-program-preparation.mjs`, a new
`adapters/host-node/public-source-preparation.mjs`, their focused tests,
Frontend name resolution, the SDK and CLI. B proposes the narrow call-site
diff in this document and applies no change to C's in-progress Host files.
C edits `adapters/host-node/embedded-local.mjs`,
`src/connectors_builtin_node/client_program_bridge.mbt`, installed source
publication, and capture/Store/Checkpoint files. B runs the shared packed
Local/HTTP/CLI application once C's call sites are committed.

The acceptance application is
`scripts/fixtures/public-query-input.mjs` plus
`scripts/fixtures/native-query-input.mjs`. It compares independent Named
Result rows and confirms that malformed SQL, undeclared parameters and
unknown aliases produce no accepted Run and no provider I/O. A successful
module test alone is not product-route evidence.
