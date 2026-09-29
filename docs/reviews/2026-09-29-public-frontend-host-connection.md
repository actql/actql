# Public Frontend Host connection boundary

This integration branch merges the committed Host base
`d49d77952a8f6256157da235001a47e113912594` with the public SDK and
native CLI source-routing branch `f28a8b19b1bd1c212e1cd0bea4352e31951a82ff`.
It does not include the Host owner's uncommitted capture or Checkpoint work.

## One preparation operation

The C integration adds `clientProgramCheckingEnvironmentCid(environment)`
for the admitted Check Environment owner. The existing
`clientProgramCheckEnvironmentCid(prepared)` accepts a prepared Program,
not an environment; its signature and callers remain unchanged. The Node
source preparation adapter uses the new accessor. This is an owner-type
correction, not a CID or wire change.

C's initial call-site regression covers SQL filter/select through the
installed HTTP Host to the existing Named Result publisher. It also checks
that malformed source, an unknown alias and an undeclared parameter have no
accepted Run. This is not the full B acceptance application: ordered Result
Plan/publication connection and packed Local/HTTP/CLI acceptance remain open.
The initial plain-select probe reached DuckDB candidate preparation and was
refused there, before Run admission; that provider shape is not silently
rerouted to a different realization. Its current generic failure projection
also remains a limitation, not a passing public refusal case.

B's registry fixture/CID correction is pending separately. Continue with
`d4b566a272e8aa0127f33cbddeb03079a01ba41b`, then validate the integrated
correction SHA without weakening independent fixture expectations.

Local connection evidence (C working tree, before the connection commit):

- Focused source/alias/HTTP preparation cases: 9/9.
- Full `public-source-preparation`, `embedded-installation`,
  `remote-checkpoint-host` and `connector-node-bundles` Node tests: 69/69.
- Runtime packages rebuilt; `moon info --target js,wasm,native`,
  `moon fmt --check` and `git diff --check` completed.
- Full Client/Host jobs, packed B acceptance and final-SHA Linux CI have
  not run for this connection change.

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

## Checked Result transformation

This integration branch also adopts the independent B-owned
`run_publication_host/client_result_transformation.mbt` module. Its
`prepare_client_result_transformation(prepared, resultIndex, bytes, nodes,
depth)` selects the checked Result occurrence and existing logical Result
Plan. `start_client_result_transformation(selection, completedOutput,
limits)` drives the existing bounded projection/order export. The direct-root
path remains valid only when no Result transformation is required; its
`RequiresResultTransformation` refusal must not be removed to publish raw
producer output under an ordered Result identity.

C connects the selected transformation in
`client_values_plan_graph.mbt` and `client_task_plan_graph.mbt`, retains the
exact completed producer through export, and uses the existing publication
receipt/evidence/Store owner. `client_program_bridge.mbt` exposes the narrow
selection and bounded export controls needed by the installed Host. B owns
the separate transformation module and regression; the JS targeted test
passes on this combined source, while packed Result acceptance awaits those
call sites. The [detailed handoff](https://github.com/actql/actql/blob/06472a38cb36785a5475df22f5b51bf8fa37a198/docs/reviews/2026-09-29-result-transformation-handoff.md)
records the module's ownership and cleanup rules.

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
