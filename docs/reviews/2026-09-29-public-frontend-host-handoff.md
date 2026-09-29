# Public frontend input and Host handoff

This records the agreed SDK request shape and the narrow Host dependency for
the first public SQL/Pipe/structural-AQL routing slice. It is an implementation
handoff, not evidence that the installed Host route is complete.

## Public request

`client.aql(text, {format, parameterDeclarations?, parameters?, requestId?})`
keeps the existing Client and Execution semantics. The explicit `format` is
`json`, `yaml`, `aql-json`, `aql-yaml`, `aql-text`, or `sql`. `aql-text` admits
structural AQL and query-only SQL/Pipe/limited Graph; `sql` admits SQL only.
No format fallback occurs after a parse error. The lightweight SDK transports
source without parsing it. `start(program)` remains the Program-object entry.

For a query-only source, `parameterDeclarations` is the existing Program
`params` map and `parameters` is the existing separate values map. The Host
places declarations in the generated Program before ordinary check and binds
values through the existing checker. JSON/YAML Program input and structural
AQL cannot acquire external declarations through this option. Parameter values
are never interpolated into source. A confirmed undeclared parameter is an
input rejection before durable Run acceptance, physical start, or provider I/O;
a lost response remains `SubmissionUnknown` under the original request ID.

## Published query names

The proposed minimal installation record is a bounded list of
`{name, sourceRef, sourceViewContractCid, schemaContractCid}`. `name` is the
explicit SQL/Pipe relation alias. The Host publishes the list with one admitted
Check Environment generation and records that generation's
`evidence_bundle_cid`; no client-supplied alias record is trusted. A published
Host retrieves the list from its installed source profile, never by guessing
from a physical table name or a test fixture. For each record, publication
must verify that `sourceRef`, Source View and schema refer to the same member
of the admitted Check Environment. It rejects aliases that collide under the
existing query relation-name rule. Name resolution and compile use this same
snapshot; a generation change requires a new published snapshot. Missing or
ambiguous names are rejected without another Resource fallback. The alias
selects a source; read authorization still runs on the ordinary acquisition
path immediately before protected I/O.
The Host parses each installed `name` through
`query_syntax.parse_relation_path` before calling
`source_frontend.bind_query_context`; it must not split quoted names itself.

The smallest profile extension proposed for C's publication code is:

```json
{
  "queryAliases": [
    {
      "name": "records",
      "sourceRef": "connector://crm/main/records#snapshot",
      "sourceViewContractCid": "sha256:<admitted Source View CID>",
      "schemaContractCid": "sha256:<admitted output schema CID>"
    }
  ]
}
```

This is installation input, not a new Client request field or a grant. The
Host obtains it at profile installation, checks it against the composed
environment, and retains the resulting immutable snapshot with the admitted
`evidence_bundle_cid`. Submit reads that exact snapshot. The public `connect`
profile can advertise source-format capability without exposing private
Resource names or turning a capability snapshot into future authorization.

`source_frontend.bind_query_context` accepts only an already validated,
generation-bound in-process alias list and emits the existing
`query_program.Context` (`adhoc.query`, `main`, `rows`, `answer`). Its
`PublishedAlias` includes the generation CID and checked `Input`; it does not
publish or authorize aliases. `source_frontend.lower` lowers the chosen source
to a normal JSON Program. The Host then uses its current Program preparation,
check, request identity, admission, Run start, and acquisition owners. It must
not accept a query-only Program against a different Check Environment
generation after lowering.

## Host ownership and acceptance

C owns the installed profile publication and public submit connection in
`adapters/host-node/embedded-local.mjs`, the installed source profile loader,
`adapters/host-node/client-program-preparation.mjs`, and the in-process
MoonBit bridge in `src/connectors_builtin_node/client_program_bridge.mbt`.
B owns `src/source_frontend`, query name comparison, SDK wire/types, and the
CLI. The bridge should expose one bounded lower-and-prepare operation that
receives the selected format, source, declarations, values, and admitted
environment, returns the existing prepared owner, and preserves typed
pre-admission failures. It must reject malformed or undeclared query input
before Run acceptance or provider I/O. Neither side creates another checker,
Run state machine, request ledger, or parser in the SDK.

Acceptance on C's installed Host: from clean packed packages, the same app
function and Program source with Local and HTTP connection options reaches
Named Result; a published explicit alias works in both, while an absent or
generation-mismatched alias is rejected. A syntax error, undeclared `@p`,
missing/wrong-typed value, or unsupported source form creates zero accepted
Runs and performs zero provider I/O. Retry with the same request ID preserves
the established intent and unknown-submission behavior. The tests must use
the installed profile, not a test-only alias injection.
