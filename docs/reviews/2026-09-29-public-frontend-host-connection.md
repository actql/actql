# Public Frontend Host connection boundary

## Current integration status

D's recovery handoff remains the pushed commit
`c58699ce9915b738e221dce9e6f0d863dc7de2fe`; B integration does not block it.
The later sections retain the investigation sequence, including failures
subsequently fixed. Current C connection evidence supersedes those earlier
partial results:

- Ordered/projected Results are connected through checked Plan selection,
  retained completion owners, bounded transformation and publication.
- Native-candidate refusal can select the existing bounded broad acquisition
  before I/O, only under its explicitly declared capability. Physical failure
  does not trigger a second acquisition route.
- The unchanged `exercisePublicQueryInput()` now passes against the actual
  HTTP Host: all five successful queries, six invalid inputs, request replay,
  changed-input conflict, attach, lookup and bounded Result reads. Counters
  read real durable request rows and wrap the native statement execution
  entry; they are not diagnostic notifications. Successful queries exercise
  the counter, while rejected inputs and replay cause no additional calls.
- Bridge tests pass 28/28. The old expected rejection of a projected Result
  Plan is replaced by exact projection-node/edge/root assertions and rejection
  of a changed projected field. Direct untransformed publication still rejects
  that wider producer.
- The preceding four-file Node run passed 70 tests; its bridge file could not
  load because the invocation omitted the pinned MoonBit PATH. The separate
  corrected bridge run above is the replacement evidence for that file.
- Focused MoonBit tests pass 21/21; public-interface consistency checks pass
  for JS, wasm and native. This is not the complete three-target Core suite.

The Result/acquisition connection is committed as
`c80eb9c220c0106b003b4fd54b9dad8fd6b09d2b`. On that product code, the DuckDB
CI job passed: 187 transport/ownership tests, one paired-provenance test and
the three Host entry builds. Its transport suite took 464.6 seconds locally.

The new `node scripts/test-packed-public-query.mjs` driver packs and installs
the public packages outside the repository, copies B's unchanged acceptance
application, and runs it with `@actql/node.connect()` in Embedded Local and
HTTP modes. Both passed. The child verifies that `moon` is unavailable; the
driver's pack step uses the pinned build toolchain. The fixture publishes its
alias and both acquisition capabilities explicitly. Real SQLite admission
counts and native DuckDB statement calls cover refusal and replay assertions.
This test is connected to the Client CI job, without changing B's expected
rows or refusal cases. It does not test a real Cloud service or Salesforce org.

To repeat with the pinned toolchain on PATH:

```sh
node scripts/test-packed-public-query.mjs
```

The printed external directory retains the installed packages, Host roots,
fixture and acceptance log for diagnosis. CLI acceptance remains B's task;
final integrated Host/Client/Core jobs and Linux CI remain open. There is no
new pushed B handoff SHA yet.

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

## C integration probe: Result Plan and source acquisition

On the working tree based on `fcdaacc89`, the new Result Plan connection
regression passes on JS. It checks separate checked projection/order nodes,
unchanged direct roots, and rejection of modified order/root material.
This is not a fixed-SHA handoff or complete transformation acceptance yet.

After rebuilding `local-node` and `run-host-core`, the public HTTP source
test runs all five unchanged `querySuccesses` expectations as subtests:

- SQL, Pipe and empty-result cases reach the expected Named Result rows.
- Nullable-parameter OR and IS NULL cases still fail at source preparation.
  `prepareCapturedDuckDBSource` receives `ClientDuckDBAcquisitionIssue.Candidate`
  from `clientProgramPrepareDuckDBAcquisition`, before physical acquisition.
  The installed adapter currently requires the narrow native filter/select
  candidate; its compiler supports a direct scalar comparison, not these
  predicate forms. The HTTP caller currently sees `SubmissionUnknown`.

The remaining work is to connect the existing bounded acquisition realization
for those checked requirements and preserve accurate pre-acceptance refusal
classification, not weaken the acceptance fixture or pretend an unsupported
native predicate ran. B's pending registry-fixture/CID correction is separate.
The bounded Result transformation owner/export connection and packed acceptance
remain open; the three successful HTTP subtests do not prove those complete.

The Plan now retains the exact checked transformation selections, including
through Effect compilation, rather than discarding them after emitting nodes.
Transformed Values compilation binds the complete graph's logical CID;
direct Values retains its existing pipeline logical CID. A regression changes
only publication direction and requires a different logical CID. The existing
`client_program_test.mbt` regression and the new connection test both pass
on JS. Export still needs to consume the retained selection through the
bounded transformation entry; private selection retention alone is not that
connection.

C adds `client_compiled_run_result_transformation(compiled, prepared, index)`
and the internal `clientProgramCompiledRunResultTransformation` bridge. They
retrieve the retained selection only for the identical checked owner and a
valid Result position. A direct Result returns `None`; a missing position or
foreign owner is rejected, including separately prepared identical content.
The Node control also requires its existing compiled-run WeakMap token. B's
selection/start/advance/finish interfaces remain unchanged. This retrieval
is not an export, a holding, or dispatch permission.

C's captured transformation wrapper now owns the existing Result borrow while
the bounded preparation runs, transfers it to the publication export on finish,
and releases it on cancellation. Managed completion uses the representation-
neutral borrow, not the cell-only borrow. It verifies the exact managed
completion and the completed re-admission bridge using existing owner checks.
The augmented transformation regression passes on JS: close the ordinary task
port after acquiring the borrow, finish ordered export, then release it with no
remaining execution reservation. Foreign Program/Result/bridge, repeated
finish, and cancellation are covered. The standard Host's managed export now
uses the retained selection with bounded advancement, yields and cancellation.
The cell-backed export now uses that same advancement and cancellation path,
with its existing captured Result borrow and no managed bridge. Both runtime
packages build successfully. This is not yet full publication-path acceptance.

Effect publication plans now obtain their Result selections from the retained
Effect compilation, checked against the original Effect owner. This does not
reconstruct an Effect-free preparation. The additive internal bridge is
`clientProgramEffectCompilationResultTransformation`; B's transformation
interfaces remain unchanged. The existing Effect compiler test file passes
8/8 on JS, including direct Results, invalid positions and a foreign owner
with identical content. The Node Local Plan and bounded export control tests
pass 12/12, including cell-backed completion and cancellation. End-to-end
transformed Effect publication remains unverified.

The added acquired Effect / ordered Named Result HTTP regression initially
failed before approval. It keeps the two Effect members on `rows` and publishes
a separate descending `ordered` Result. After raising the fixture's explicit
pin ceiling from two to three required local Results, capture reaches the
dependency inventory and failed with `UnusedDependency`. The former export
set includes the final Unit's non-Effect Result although no imported Manifest
or Effect root reaches it. Do not remove the inventory's unused-body refusal.
The connection must separate complete local Manifest construction from the
exact durable dependency closure, and preserve release ownership for any
temporary exports excluded from that closure. The regression retains the
required descending rows, four writes and no additional writes after restart;
the initial failure is preserved here as the reason for the correction.

The export set now separates complete Manifest construction from durable
payload selection. It retains member roots and all payloads of actually
imported Manifests, then releases other temporary prepared payloads through
the existing release/retry owner before returning the set. Inventory admission
still rejects unused bodies. The ordered case now passes through approval,
restart, four writes, descending Named Result and a further restart without
additional writes. It independently asserts two durable dependency payloads
despite three local Results used during preparation. The nine acquired HTTP
regressions pass, including read deny/delegate, ordinary and transformed
success, unknown, cancellation, rejection and missing/corrupt input isolation.

Commands used for this probe:

```sh
moon test --target js src/query_integration/client_result_plan_connection_wbtest.mbt
npm run build:runtime-packages -- local-node run-host-core
node --test --test-name-pattern='public HTTP source text' adapters/host-node/remote-checkpoint-host.test.mjs
```

The initial HTTP test failed two of five cases. The broad acquisition
connection below now closes those cases; no final gate or Linux CI success
is claimed for this uncommitted integration.

## Broad acquisition connection in progress

Native DuckDB selection rejects the nullable OR and IS NULL cases before I/O.
The existing broad receipt path already evaluates the checked residual query;
it must be selected before dispatch, not used to retry a failed native read.
The Host now has an exact broad Source capture wrapper. Its three JS-target
MoonBit tests pass, including foreign-attempt rejection and close invalidation.
Broad Source Evidence issuance has been added behind the same live identity
and exact requirement checks; encoding is private and shared with native
issuance. Broad issuance requires the process-evidence capability contract,
not the native two-receipt contract. Its package typecheck passes.

Candidate preparation and Node execution are now connected. Only the typed
native-candidate-unavailable result selects broad preparation, before any
database I/O. A failed native execution is never retried through broad.
The installed declaration must explicitly include the process-evidence
contract `sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89`
in its sorted `capability_contract_cids`; a native-only declaration is not
silently expanded. The acceptance fixture declares both and recalculates
its environment identity. An initial unsorted fixture and an incorrect
eleven-slot broad cost estimate were corrected (broad has eight work slots).

After runtime regeneration, all five unchanged B success cases pass through
actual public HTTP: SQL, Pipe, nullable parameter, IS NULL and empty Result.
Invalid syntax, unknown alias and undeclared parameter also reject before
Run admission in this test. Full `exercisePublicQueryInput`, packed Local,
outside-repository tarball and final integrated CI remain outstanding.
