# Native Client transport CLI

`actql-native-client` is a Node-free native binary that uses the public
Client–Host HTTP protocol over mTLS. It uses the existing bounded native
HTTPS adapter. It does not load a Local kernel or a Cloud SDK, and it does not
implement Run admission or retry itself. The selected Host must provide the
corresponding operations.

Build with the pinned MoonBit toolchain using `moon build --target native
--release src/cmd/native_client`. The resulting binary is
`_build/native/release/build/cmd/native_client/native_client.exe`. Supply an
HTTPS endpoint, CA, client certificate and key, the installed libcurl library,
and a bearer token file. The token stays out of command-line arguments.

The connection JSON contains the public `mode`, `owner`, `consentRefs`,
`runners`, optional `durability` and Hybrid `movementPolicyRef`. Local-owned
Hybrid also requires a registered `cloudConnectionRef`; Cloud-owned Hybrid
requires at least one selected Runner. The CLI
negotiates that exact connection before each operation and rejects a Host
profile with a different mode or owner, or a downgrade from requested durable
to volatile. The `aql` command takes an explicit `--format`: `json`, `yaml`,
`aql-json`, `aql-yaml`, `aql-text`, or `sql`. It sends the bounded source to the
Host without inferring its language from a filename. The installed Host must
provide the selected frontend and admits the generated Program through the
ordinary checker. Query-only source can take a JSON
`--parameter-declarations-file` in the existing Program `params` shape; values
remain separate in `--parameters-file`. JSON/YAML Program documents cannot
take external declarations. `start` takes a JSON Program object. Both
commands require a caller-saved `--request-id` so
an ambiguous submission can be looked up or resent with the same intent.
`lookup-request` only queries existing request history and rejects malformed
Host replies instead of reporting them as successful lookups.

`attach`, `status`, `wait`, `cancel`, `reconcile`, `read` and
`delivery-attempt` use an explicit Run reference file. `read` requires a
caller-saved attempt ID. It accepts only a complete JSONL response with the
normal terminator and writes exact payload bytes to stdout after completion.
The whole response is bounded by `--max-response-bytes` (default 1 MiB,
maximum 16 MiB); this is a bounded CLI read, not the streaming SDK reader or
a JavaScript heap limit. A failed read reports its attempt ID and does not
cancel the Run. `delivery-attempt` admits the published MoonBit attempt,
record and Host release receipt contracts, binds them to the requested
attempt, Run and Result, and rejects missing or contradictory evidence. It
does not request payload replay or hash payload bytes.

This is a transport development artifact. The binary does not include
embedded Local providers. The mTLS fixture in
`scripts/test-native-client.mjs` uses a mock Host. The mock verifies request
shape and response handling; it does not prove Host frontend admission or a
native end-to-end Program Run. `scripts/test-native-sga-public-source.mjs`
separately exercises authored DATA / GRAPH queries through an installed
public HTTPS Host and Named Results. Its machine-Program control remains distinct
from source execution. Run the focused installed acceptance with
`node scripts/test-packed-public-query.mjs --graph-native-only`; see the
[fixed-source acceptance record](../../../docs/reviews/2026-10-03-native-graph-source-acceptance.md)
for independent rows, descriptions, refusal counters and its coverage limits.

A held submission prints the validated request control reply as JSON. It has
no Run reference: `lookup-request --request-id <id>` observes the same request
without approving or resubmitting it. Once lookup returns `found`, its Run
reference can be used with `attach`. The native CLI does not yet provide
Checkpoint answer commands; use the existing public Client operations for
that workflow.

Confirmed Host preparation rejections preserve the public input error code.
An unrecognized or lost submit response remains `SubmissionUnknown` with the
original request ID; it is not a claim that no Run was accepted.

## Query source example

This example requires a Host that publishes the `records` alias and supports
query source input. Host routing acceptance is tracked separately from the
native transport tests. Keep the following files in one protected directory:

`connection.json`:

```json
{"mode":"remote","owner":"remote","consentRefs":[],"runners":[]}
```

```sql
-- query.sql
SELECT id FROM records WHERE amount >= @minimum ORDER BY id;
```

Use `{"minimum":{"type":"number"}}` in `declarations.json` and
`{"minimum":20}` in `parameters.json`. The token file contains only the scoped
bearer token; keep it and the client key readable only by their owner.

```sh
./actql-native-client \
  --endpoint https://host.example/ \
  --connection-root "$PWD" --connection-file connection.json \
  --token-root "$PWD" --token-file token.txt \
  --http-library /usr/lib/libcurl.4.dylib \
  --ca ca.crt --cert client.crt --key client.key \
  aql --program-file query.sql --format sql \
  --parameter-declarations-file declarations.json \
  --parameters-file parameters.json --request-id saved-query-001
```

The example library path is for macOS; select the installed libcurl library
for the target platform. For Pipe, change the source and explicitly select
`--format aql-text`. File extensions never select a parser. A successful Run
admission prints an object containing `ref`; save that exact object member
as the reference file for `wait`, `status`, and `read`. A held request has no
`ref` and must not be converted into one.

With the same connection flags, use `lookup-request --request-id
saved-query-001` after an uncertain submit. This only observes the original
request. Once there is a Run reference, `read --ref-file run-ref.json
--result-name answer --attempt-id saved-read-001` reads that named Result.

| Diagnostic | Meaning and next action |
| --- | --- |
| A registered `ClientProgram*` or `ClientParameters*` preparation error | Confirmed input rejection; correct the source or declarations/values. Parameter values are not interpolated into source. |
| `SubmissionUnknown request-id=...` | Admission was not confirmed. Preserve the original request ID and intent and use lookup. Do not infer failure or automatically create another request. |
| JSON with `kind: "held"` | No Run exists yet. Observe the request and use the existing Client Checkpoint workflow for answers. |
| `IncompleteResultStream attempt-id=...` | The read did not reach its normal terminator. This does not cancel the Run or prove the Host sent nothing. |

## Query text and machine input

`aql-text` accepts the implemented query language, including Pipe and admitted
Graph patterns; `sql` selects SQL query heads. The retired
`AQL / PROGRAM / STAGE / STEP / OP` envelope is rejected by the Host before
Run acceptance and provider I/O. JSON/YAML Program remains supported machine
input. Text is never retried as another format, and extensions do not choose
a language. Removal of the old surface does not claim that every adopted
Graph, VecA/TEA or Effect surface is implemented.
