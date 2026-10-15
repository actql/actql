# ActQL CLI

`npm install -g actql` installs the small npm launcher and its platform Native
executable. Protocol operations run in Native. Current release candidates are
macOS arm64 and Linux x64/glibc; support depends on acceptance of the exact
platform artifact. Installation alone does not adopt a Local Host or confer
execution permission. See the [package guide](../packages/native-cli/README.md).

Remote Client transport remains the default. The fixed Darwin arm64
private-integration cohort from source
`eb2f8b3b0a096e8dd86548bffbc6bafb6e79fc20` completed the source-free
Local path below in an empty external consumer: seventeen CLI operations,
including three expected refusals and no skips. This evidence belongs to that
exact cohort, not the latest main. The tested minimum is macOS 26.0, using
Node 22.22.0 for the npm launcher.
This fixed-package acceptance does not publish npm packages or claim registry
availability. Remote connection settings apply only to Remote mode.

The [target CLI experience](design/cli-target-experience.md) preserves the
broader adopted workflow. Local `run`, source-free `explain` and saved `status`
below have fixed-cohort acceptance. `approve`, `reject`, `result`, `op` and the
other unconnected target commands are not current executable instructions.
Remote has no `run` or `approve` command.

## Accepted source-free Local baseline

Use the installed `actql` command from the matching CLI/platform cohort.
No source build, separate Host, token, mTLS, internal configuration JSON or
absolute SQLite/crypto library path is required. Explicit adoption is a trust
operation; neither installation nor `connect` grants adoption implicitly.
The product defaults cover only source-free computation and the private Result
Store. They do not install Sources, grant external I/O or authorize Effects.

The following Native command grammar was exercised by that fixed consumer:

```sh
actql --mode local adopt --json
actql --mode local connect --json
printf 'SELECT 1 AS n\n' > query.sql
actql --mode local check --format sql --program-file query.sql --json
actql --mode local explain --format sql --program-file query.sql --json
actql --mode local new-submission --request-id installed-select-1 > submission.json
actql --mode local run --json --format sql --program-file query.sql \
  --submission-ref-file submission.json --request-id installed-select-1 \
  --operation-attempt-id original-submit > admission.json
```

`check` returns `kind: prepared`, without Run admission. The accepted SQL
`explain` returns the compiler-owned static `actql-plan-view/0.1`, with zero
Provider I/O and no Run ID. It is not an execution permit. Local `run` delegates
once to the existing `aql` intake with the same original Submission and explicit
operation attempt; it does not allocate a replacement identity or retry.
A successful publication reply has
`kind: local_run_published` and an exact `ref` object. Save that object as
`run.json`, rather than using the whole reply as a Run reference. The Node
runtime already used by the launcher can save the returned JSON field:

```sh
node --input-type=module -e '
  import {readFileSync, writeFileSync} from "node:fs";
  const reply = JSON.parse(readFileSync("admission.json", "utf8"));
  writeFileSync("run.json", JSON.stringify(reply.ref) + "\n", {flag: "wx"});
'
actql --mode local lookup-submission --submission-ref-file submission.json
actql --mode local status --ref-file run.json --submission-ref-file submission.json --json
actql --mode local read --ref-file run.json --submission-ref-file submission.json \
  --result-name answer --purpose cli-read --format json \
  --max-output-bytes 65536 --attempt-id original-read
```

`status` reads the saved original Run observation through current RunRead and
original custody checks. `status --run-id <original-run-id> --json` selects the
same retained original; use its real `state.run_id`, not a Program CID or Run
Definition CID. Omitting `--json` gives the human label and the same original
metadata. Missing old observations are Unavailable; status does not recompile
or rerun them.

Saved Run success is separate from Result availability. The accepted status
kept `result_available: false` and `result_availability.answer` as
`state: unknown`, `reason: verification_pending`, even after the independent
Result read succeeded. Neither status nor control revision silently verifies
or authorizes Result delivery.

The read returns `[{"n":1}]`, with a JSON number and sole column `n`. Lookup
uses the original immutable Submission and same Run, without needing the source
document or recompiling it. A reference is not read authority: current Account,
original Result Policy and the adopted stdout purpose are checked separately.

Inspect the original delivery without reopening payloads:

```sh
actql --mode local delivery-attempt \
  --ref-file run.json --submission-ref-file submission.json \
  --result-name answer --purpose cli-read --attempt-id original-read
```

The accepted attempt has a durable succeeded record, the payload digest/byte
count and a matching Host release receipt. Repeating `read` with
`original-read` is refused with `LocalReadAttemptAlreadyStarted`. Only an
explicit new operation such as `--attempt-id explicit-new-read` can read the
retained Result again after current authorization. A lost or incomplete reply
does not authorize a new attempt or resubmission automatically.

The fixed consumer completed all seventeen CLI operations, including absent
adoption, missing original Run and same-read-attempt refusals, with no skips.
The earlier `109564ef9a4f8241096292843b875d4c81fbb6f3` cohort retains its
original eleven-case `aql`/Result evidence; it does not gain the later commands
by relabelling. Source/Model/Effect/approval/cancel/Debug profiles, other Local
platforms and their failure matrices remain unaccepted. This baseline does not
certify legacy-runtime migration, all temporary holders or final Run deletion.

## Remote prerequisites

Use an installed Host that supports the submitted Program/frontend, a saved
connection JSON, a scoped token file, and the Host's CA/mTLS credentials.
Select the installed libcurl runtime for this transport profile. Tokens and
private keys remain in files, outside command-line values.

```sh
actql_remote() {
  actql --mode remote --endpoint "$ACTQL_ENDPOINT" \
    --connection-root "$PWD" --connection-file connection.json \
    --token-root "$PWD" --token-file token.txt \
    --http-library "$ACTQL_HTTP_LIBRARY" \
    --ca ca.crt --cert client.crt --key client.key "$@"
}
actql_remote connect
```

This is a command example for an already configured Remote Host, not an
executed acceptance result or a replacement Local quickstart. Do not place
credentials in URLs. See the [Native transport reference](../src/cmd/native_client/README.md#remote-transport)
for the connection document and exact profile requirements.

## Submit and retain the original identities

Allocate a deliberate new Submission reference and save it before sending:

```sh
actql_remote new-submission --request-id select-one-01 > submission.json
actql_remote aql --program-file program.json --format aql-json \
  --submission-ref-file submission.json --operation-attempt-id submit-01
```

`aql` accepts an explicit format (`json`, `yaml`, `aql-json`, `aql-yaml`,
`aql-text`, or `sql`) without inferring it from a filename. The Host must have
that frontend. `start` instead accepts a JSON Program object:

```sh
actql_remote start --program-file program.json \
  --submission-ref-file submission.json --operation-attempt-id submit-01
```

These are alternatives for one new operation; do not submit both to perform
recovery. Parameters use `--parameters-file`. External declarations use
`--parameter-declarations-file` only with `aql-text` or `sql`. The optional
`--request-id` on submission asserts the nonce in the saved reference.

Save the exact Run reference from a valid admission as `run.json`; the whole
admission reply is not a Run reference. Reconnection and lookup use the saved
original documents. After a lost response:

```sh
actql_remote lookup-submission --submission-ref-file submission.json
```

Lookup observes the original operation. Missing or unresolved history is not
permission to resubmit, replace the epoch or create another Run.

## Observe, read, and cancel

```sh
actql_remote attach --ref-file run.json
actql_remote status --ref-file run.json
actql_remote wait --ref-file run.json
actql_remote read --ref-file run.json --result-name answer --attempt-id read-01
actql_remote delivery-attempt --ref-file run.json \
  --result-name answer --attempt-id read-01
```

Use the actual Named Result declared by the Program. `read` writes payload
bytes only after a complete bounded JSONL response, including its terminator.
The response bound is `--max-response-bytes` (default 1 MiB, maximum 16 MiB).
It is not the SDK streaming reader. An interrupted/incomplete read is not
Complete and does not cancel the Run. Inspect the original attempt; an explicit
new attempt is a new read operation, not payload replay by lookup.

Cancel requires its own saved operation identity and the expected control
revision observed for that Run:

```sh
actql_remote cancel --ref-file run.json --cancel-id cancel-01 \
  --expected-revision 3 --operation-attempt-id cancel-invocation-01
actql_remote lookup-cancellation --ref-file run.json \
  --cancel-id cancel-01 --expected-revision 3
```

The revision above is illustrative; use the actual current revision.
Cancel acceptance, physical stop, unresolved Effect responsibility and resource
release are separate facts. Lookup never substitutes the current Run state for
the original cancel outcome. `reconcile --ref-file run.json` uses the Host's
existing original-operation reconciliation. Unknown results are not resent.

## Checkpoints and Local boundaries

There is currently no Native Remote `run` or `approve` command. Use the
[public SDK Checkpoint API](../packages/sdk/README.md#historical-held-requests-and-run-checkpoints):
`checkpoints`, `reviewCheckpoint`, and `resolveCheckpoints` have independent
current authorization; a signer supplies a proof for the exact Checkpoint.
A stored answer alone does not certify resumed execution. Do not allocate a
historical held request to replace an original new Submission.

Current source Local mode explicitly selects adopted configuration and uses
existing Host/journal/Store owners. Its `check --program-file <file> --format
<format> --json` returns `kind: prepared`, not a public diagnostic report or
Run admission. The Source execution/read/recovery connections and selected
Reviewer registration remain separate from fixed-package acceptance.
`checkpoint-state` reads metadata and is not approval. Source-free bootstrap,
bundled dependencies, execution, original Run lookup and retained Result delivery
are covered by the accepted Local baseline above. Source and Effect execution,
approval, cancellation and Debug remain separate unaccepted profiles; an
internal compiler or fixture pass does not establish their product acceptance.

## Failures and retained evidence

Transport failures exit nonzero. `SubmissionUnknown`, `CancellationUnknown`,
and incomplete reads retain the original identity for lookup. Valid domain
JSON still needs inspection: transport success does not certify Run success.
Launcher failures use 64 for unsupported platform/libc, 65 for artifact identity
mismatch, and 69 for missing package/start failure. No implicit download,
alternate binary, new submission or automatic retry is performed.
