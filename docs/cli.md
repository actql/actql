# ActQL CLI

`npm install -g actql` installs the small npm launcher and its platform Native
executable. Protocol operations run in Native. Current release candidates are
macOS arm64 and Linux x64/glibc; support depends on acceptance of the exact
platform artifact. Installation does not install a Host or confer execution
permission. See the [package guide](../packages/native-cli/README.md).

The distributed CLI's established profile is Remote Client transport. Standard
embedded Local installation and initialization are being completed separately;
the current source's Local connections do not establish an empty-environment
Local `SELECT 1` acceptance. Remote connection settings below apply to Remote,
not to the planned standard Local entry.

The [target CLI experience](design/cli-target-experience.md) preserves the
adopted future workflow. Its `run`, `explain`, `approve`, `reject`, `result`,
`op` and other command proposals are not current executable instructions.

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
`checkpoint-state` reads metadata and is not approval. Standard Local bootstrap,
Source-free execution, automatic dependency detection and external-install
acceptance remain unfinished; no compiler build or internal Host assembly is
presented here as the finished installation procedure.

## Failures and retained evidence

Transport failures exit nonzero. `SubmissionUnknown`, `CancellationUnknown`,
and incomplete reads retain the original identity for lookup. Valid domain
JSON still needs inspection: transport success does not certify Run success.
Launcher failures use 64 for unsupported platform/libc, 65 for artifact identity
mismatch, and 69 for missing package/start failure. No implicit download,
alternate binary, new submission or automatic retry is performed.
