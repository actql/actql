# Native Client CLI

`actql-native-client` is a Node-free native binary that uses the public
Client–Host HTTP protocol over mTLS. Remote operations use the existing bounded
native HTTPS adapter; the selected Host owns Run admission and retry. The source
candidate also provides explicit embedded Local preparation through the common
checker. Local execution and operations remain unfinished; preparation does not
admit a Run or establish authorization.

## Embedded Local preparation

Select `--mode local`, `--config-root` and `--config-file` explicitly. The
configuration selects a bounded Check Environment original and its evidence
bundle CID. `check --program-file <file> --format <format>` prepares the input
through the existing Native frontend/checker. External parameter declarations
are allowed only for `aql-text` and `sql`; parameter values remain separate.
Remote endpoint and authentication flags are refused in this mode.

Human output states that no Run was admitted. `check --json` returns
`kind: prepared`; it is not a verified public diagnostics report. Unsupported
inputs or operations are refused. Source alias discovery,
Local Run commands, Checkpoint answers and cross-process Local Run recovery
are not completed by this preparation entry. The source fixtures are in
`scripts/fixtures/native-local-cli`; current source changes do not establish
fresh installed-artifact acceptance by themselves.

The focused developer acceptance command
`node scripts/test-native-cli-local-install.mjs <fixed-CLI-RC>` installs the
existing `actql` launcher and matching platform artifact into an external npm
prefix using the fixed-artifact private registry. It reuses the Native ingress
cases with the installed launcher, checks exact source/artifact identity, and
retains command and nonzero-test evidence. It does not require an SDK RC or
run the Remote acceptance campaign. Its scope is preparation, value preservation
and refusal; Local Run, approval and process recovery remain separate unfinished
requirements. Run this through the existing heavy guard after preparing a
clean-source Native CLI RC with the existing artifact/release producers.

## Explicit Local Host adoption

The source candidate adds `adopt`, `connect` and `new-submission` in explicit
Local mode. These connect the existing account, adoption, journal and Submission
epoch Owners; they do not yet execute or publish a Local Run. Installed-artifact
acceptance for these commands is separate from the earlier preparation fixture.

`adopt --json` explicitly finalizes a private Host. `connect --json` opens only
the same retained Host and refuses absent state or unfinished initialization;
it never initializes keys or repairs missing originals. Both return account and
adoption identities, without a Run or Provider grant. The human form says that
no Run has been admitted. `new-submission --request-id <nonce>` returns the
existing epoch/nonce reference only when the selected execution account permits
the `principal × connection × run × submit` tuple. A reference is not acceptance
or Provider read/apply authority. No-match and delegated permission are refused
in this first slice.

`lookup-submission --submission-ref-file <file>` opens the retained Host and
authenticates the saved original epoch/nonce through its existing journal. The
reference file is read from the explicitly selected configuration root. Current
account permission for the same submit scope is required; the reference itself
grants no authority. Lookup never prepares, acquires or executes a Program, and
does not replace an expired epoch. Its Local CLI JSON has
`kind: local_submission_lookup` and the exact `submissionRef`; `history:
unresolved` is not evidence of nonexecution or permission to resubmit. Retained
records expose `preparing` or `ready` admission facts with exact decimal
revisions. A ready admission is not an execution outcome or published Result.
This source connection does not yet complete Local submit/attach execution or
establish fixed-artifact process acceptance.

In addition to the preparation settings, the selected `actql-config/0.1`
document requires `account_config` (one file name in the selected private root)
and `native.local`:

```json
{
  "account_id": "operator",
  "principal": "operator",
  "connection": "cli",
  "state_parent": "/absolute/private/state-parent",
  "state_name": "host",
  "managed_root": "/absolute/private/managed-root",
  "sqlite_library": "/absolute/path/to/installed/sqlite-library",
  "signature_library": "/absolute/path/to/installed/crypto-library",
  "submission_ttl_ms": 60000,
  "journal_record_limit": 8,
  "journal_snapshot_bytes": 8388608,
  "installation_files": ["source-installation.json"]
}
```

The configuration, state parent and managed root must be explicitly selected
private directories. Physical library paths must name the installed platform
runtimes; this candidate has not yet closed their standard Local distribution
packaging. The CLI rejects an untrusted configuration root before loading these
libraries. The three limits are explicit: TTL is at most one day, record count
at most 1024, and snapshot bytes at most 512 MiB. `state_dir`, if supplied, must
equal `state_parent + "/" + state_name` exactly.

The config file and Check Environment original are durably bound with the
account and managed-root identity. Optional `installation_files` explicitly
selects up to six additional originals in the same private configuration root,
each bounded to 64 KiB. Names must be distinct single components and cannot
repeat the account, config or environment file. The same adoption transaction
stores their exact bytes and generations; reconnect cannot replace or repair
them. Selecting an original is custody only: it does not install a Source or
Policy, prove a normalization journal, or grant Provider access. Changing selected content, replacing a
source file even with identical bytes, or losing custody refuses reconnection.
No missing original is repaired from current source files. Source/Result,
original Run recovery, typed Direct Local credentials and approval-backed
Effect remain the following execution slices.

An optional `native.local.source_file` names one of the explicitly selected
`installation_files`. Its bounded `actql-config/0.1` document contains only
`version` and `native.source`. The Source settings decoder admits the closed
physical binding, contract originals, Ledger/dispatch/search/import limits and
estimate profiles into the existing Native Source/Compute configuration types.
It does not load DuckDB, open a Source database or grant read permission. All
numeric settings are explicit; physical byte budgets are at most 512 MiB, and
unknown keys, missing required values, fractional limits and escaping DB names
are refused before Host initialization. The DB name is one component under the
adopted managed root; the execution connection must separately validate that
physical binding and current Source authority before opening it.

The input example `scripts/fixtures/native-local-cli/source-installation.json`
reuses the existing Native Source contract originals. Its library placeholder
must be replaced with the explicitly selected actual library in a test-owned
configuration before adoption. `source-program.json` authors an explicit `v`
Source View, then filter/select in acquisition and Compute; the independent
expectation is one `answer` row `{id: 3}`. Explicit selection avoids pretending
that the existing sole-view semantic completion has an empty normalization
journal. These are input/expectation fixtures for the next public execution
connection, not evidence that CLI Source/Result execution has already passed.

## Remote transport

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
commands require a caller-saved `--submission-ref-file` and an explicit
`--operation-attempt-id` for the invocation. Allocate deliberate new
work with `new-submission --request-id <nonce>` and save its full epoch/nonce
JSON before sending input. `--request-id` on `start` or `aql` only asserts that
saved nonce. `lookup-submission --submission-ref-file <file>` observes the
original identity, including after a reconnect or epoch expiry; it never
replaces the original epoch or dispatches work. Retain input and parameters
alongside that file. A missing lookup record is unresolved, not retry permission.
`lookup-request` only queries existing request history and rejects malformed
Host replies instead of reporting them as successful lookups.

`attach`, `status`, `wait`, `cancel`, `lookup-cancellation`, `reconcile`, `read` and
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

`cancel` requires a caller-saved `--cancel-id`, `--expected-revision`, and
`--operation-attempt-id`, in
addition to the original Run reference file. Obtain the revision from the
Run's current control observation before issuing a new operation, and retain
the Run reference, operation ID and revision. The attempt ID correlates this
invocation; it is not a cancellation identity or a lookup authority.
`lookup-cancellation` takes the original Run reference, cancel ID and revision and only
observes the original operation; it does not cancel again. Replies must match
the exact Run, operation ID and original revision. An accepted cancellation
must advance that revision. Lost cancel replies report `CancellationUnknown`
with the exact `cancel-ref` and lookup command. An unknown lookup is not
evidence that cancellation was refused, physically stopped, or released.
Typed invocation replies distinguish `accepted`, `already_satisfied`,
`refused` and `conflict`. A Refused certificate says only that this invocation
did not commit or consume cancellation identity. Another invocation may have
been accepted. Generic HTTP errors carry no such certificate.

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
no Run reference: `lookup-submission --submission-ref-file <file>` observes the same intent
without approving or resubmitting it. Once lookup returns `ready`, its `admission.ref` can be used with `attach`. The native CLI does not yet provide
Checkpoint answer commands; use the existing public Client operations for
that workflow.

Confirmed Host preparation rejections preserve the public input error code.
An unrecognized or lost submit response remains `SubmissionUnknown` with the
original submission-ref file; it is not a claim that no Run was accepted.

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
  --submission-ref-file saved-query-submission.json \
  --operation-attempt-id saved-query-submit-001 \
  --parameter-declarations-file declarations.json \
  --parameters-file parameters.json --request-id saved-query-001
```

The example library path is for macOS; select the installed libcurl library
for the target platform. For Pipe, change the source and explicitly select
`--format aql-text`. File extensions never select a parser. A successful Run
admission prints an object containing `ref`; save that exact object member
as the reference file for `wait`, `status`, and `read`. A held request has no
`ref` and must not be converted into one.

First run `new-submission --request-id saved-query-001` with the same
connection flags and save stdout as `saved-query-submission.json`. Then run
the command above. After an uncertain submit, use
`lookup-submission --submission-ref-file saved-query-submission.json`. This only observes the original
request. Once there is a Run reference, `read --ref-file run-ref.json
--result-name answer --attempt-id saved-read-001` reads that named Result.

| Diagnostic | Meaning and next action |
| --- | --- |
| A registered `ClientProgram*` or `ClientParameters*` preparation error | Confirmed input rejection; correct the source or declarations/values. Parameter values are not interpolated into source. |
| `SubmissionUnknown submission-ref-file=...` | Admission was not confirmed. Preserve the original epoch/nonce file and exact input and use lookup. Do not infer failure or automatically create another request. |
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
