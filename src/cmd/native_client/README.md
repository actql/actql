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
commands require `--submission-ref-file`. First call `new-submission --nonce
<caller-nonce>` and save its JSON output before sending any Program. This
reference contains the Host-authenticated epoch and the caller nonce.
`lookup-submission` takes that same file and observes the original operation,
even when a new connection offers a different epoch. It never reopens the
Program or submits it again. `lookup-request --request-id` remains a read-only
lookup for historical request records; it is not an execution fallback.

`attach`, `status`, `wait`, `cancel`, `lookup-cancellation`, `reconcile`, `read` and
`delivery-attempt` use an explicit Run reference file. `read` requires a
caller-saved attempt ID. It accepts only a complete JSONL response with the
normal terminator and writes exact payload bytes to stdout after completion.
The whole response is bounded by `--max-response-bytes` (default 1 MiB,
maximum 16 MiB); this is a bounded CLI read, not the streaming SDK reader or
a JavaScript heap limit. A failed read reports its attempt ID and does not
cancel the Run. The terminator confirms this transport response, not durable
Owner receipt completion. `delivery-attempt` admits the published MoonBit attempt,
record and Host release receipt contracts, binds them to the requested
attempt, Run and Result, and rejects missing or contradictory evidence. It
does not request payload replay or hash payload bytes.

`cancel` requires a caller-saved `--cancel-id` and `--expected-revision`, in
addition to the original Run reference file. Obtain the revision from the
Run's current control observation before issuing a new operation, and retain
all three inputs. `lookup-cancellation` takes those same inputs and only
observes the original operation; it does not cancel again. Replies must match
the exact Run, operation ID and original revision. An accepted cancellation
must advance that revision. Lost cancel replies report `CancellationUnknown`
with the exact `cancel-ref` and lookup command. An unknown lookup is not
evidence that cancellation was refused, physically stopped, or released.

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

A submission prints the validated Owner outcome envelope. `ready` contains
`admission.ref`; `held` contains request control without a Run reference.
`lookup-submission --submission-ref-file <file>` observes either state without
approving or resubmitting. The CLI does not yet provide Checkpoint answer
commands; use the existing public Client operations for that workflow.

Durable `not_accepted`, `preparation_failed`, and `preparing` submit outcomes
are printed as JSON before a nonzero exit with `SubmissionNotAccepted`,
`SubmissionPreparationFailed`, or `SubmissionPreparing`. Lookup returns those
validated outcomes with a zero exit. Preparing is not a failed Run. Unknown
Owner reason codes remain accepted when their contract shape is valid.

A plain HTTP error, malformed response, or lost submit response remains
`SubmissionUnknown` with the full original reference and lookup command.
An HTTP preparation error code alone is not durable rejection evidence. Keep
the reference file and original input; do not infer that nothing was accepted
or automatically retry with another epoch or nonce. Input identity uses the
existing common submitted-intent Owner and preserves string values exactly.

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
# Save the original reference before submitting. Use a new caller nonce only
# for an explicitly new operation.
client() {
  ./actql-native-client \
    --endpoint https://host.example/ \
    --connection-root "$PWD" --connection-file connection.json \
    --token-root "$PWD" --token-file token.txt \
    --http-library /usr/lib/libcurl.4.dylib \
    --ca ca.crt --cert client.crt --key client.key "$@"
}
client new-submission --nonce saved-query-001 > submission-ref.json
client aql --program-file query.sql --format sql \
  --parameter-declarations-file declarations.json \
  --parameters-file parameters.json --submission-ref-file submission-ref.json
```

The example library path is for macOS; select the installed libcurl library
for the target platform. For Pipe, change the source and explicitly select
`--format aql-text`. File extensions never select a parser. A successful Run
admission prints a `ready` outcome containing `admission.ref`; save that exact member
as the reference file for `wait`, `status`, and `read`. A held request has no
`ref` and must not be converted into one.

With the same connection flags, use `lookup-submission --submission-ref-file
submission-ref.json` after an uncertain submit. This only observes the original
request. Once there is a Run reference, `read --ref-file run-ref.json
--result-name answer --attempt-id saved-read-001` reads that named Result.

| Diagnostic | Meaning and next action |
| --- | --- |
| JSON with `kind: "not_accepted"` | The Owner durably recorded rejection for this exact intent and reference. Parameter values are not interpolated into source. |
| JSON with `kind: "preparation_failed"` | Durable acceptance preceded preparation failure; this is not pre-acceptance rejection. |
| JSON with `kind: "preparing"` | Acceptance is recorded, but no terminal preparation outcome is confirmed. Observe the same operation. |
| `SubmissionUnknown submission-ref=...` | Admission was not confirmed. Preserve the original reference file and intent and use lookup. Do not infer failure or automatically create another request. |
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
