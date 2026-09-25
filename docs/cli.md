# ActQL CLI

The CLI drives a durable Program Run through its ordered stages. Before each protected boundary, the runtime evaluates the execution-account configuration: `allow` continues, `deny` stops the work, and `delegate` asks the Host's decision policy, which permits or rejects immediately or defers to a sealed Checkpoint. Approval of a deferred decision resumes that Run from the protected boundary. See [stages](spec/language.md#stages) and [logical request recovery](spec/execution.md#logical-request).

```text
check (optional) -> explain (optional) -> run -> [checkpoint -> approve | reject] -> status
```

## Golden path

```bash
actql check customer-sync.aql
actql run customer-sync.aql --output customers.jsonl --receipt run.json
actql status run_01
```

`check` performs static validation with supplied contracts. `run` performs its own checks and accepts a Program, not a saved Plan or explanation. Internal Plan artifacts and their CID verification remain available to implementations.

`explain` and `run` share parameters, opaque bindings, input locators, environment flags, Result deliveries, and the stop-before setting. Explanation creates no Run, captures no input, fetches no new provider statistics, and writes no delivery destination. Estimates without admitted evidence are explicitly unknown. `explain --run <run>` reads saved evidence and marks strategy history as unavailable when not recorded.

If no decision is deferred, `run` finishes without another command. If it pauses, the command prints the Run and Checkpoint references:

```bash
actql approve checkpoint_run_01_effect_commit --signer production-approver
actql status run_01 --watch
```

The runtime creates the review projection and exact approval artifact internally. Users do not carry Prepared Invocations, Effect Previews, reviews, approvals, and apply receipts between commands. Human `status` output renders the stored review projection bound to a waiting Checkpoint. JSON responses do not embed restricted review contents.

Use repeatable `--deliver main=jsonl:answer.jsonl` (formats: json, jsonl, csv) for named Results. Destinations must be distinct and must not overwrite input bindings. `--output` delivers the sole Result (or `--result name`) with `--format` defaulting to jsonl, not an arbitrary API sink. Use Effects for external mutations.

`run --stop-before commit` persists the activating stage's complete Effect Preview and stops before the first Effect application, even when Host policy would otherwise allow it. It does not override denial or authorize work. Reads, inference, egress, and costs may occur; cross-Effect atomicity is not promised. Approve the existing Checkpoint to continue the same Run. Approval binds that concrete stage scope, not the unbound work of later stages.

Delivery follows successful Run completion. Requested deliveries use a private durable ledger and are never repeated by status polling or repeated approval. `result <run> --deliver main=jsonl:answer.jsonl` explicitly retries failed delivery or requests a new destination; completed requests are no-ops. A dispatch interrupted before its completion record remains unresolved and is not automatically resent; choose a new destination after inspecting the existing file. This is not an exactly-once filesystem guarantee.

For Runs with destination requests, `--json` returns the closed `actql-cli-run-response/0.1` envelope: `run` is the portable Run state, and `delivery_status` plus `deliveries` describe independent attempts. Delivery failure exits nonzero but still returns this JSON and the successful Run ID. Runs without destination requests retain the portable Run-state response. The local response schema is generated at `spec/contracts/actql-cli-run-response.schema.json` in the package root.

Result delivery checks retained material integrity and current local owner/read/egress policy, not old inputs or Effect policy. `result_policy: {decision: deny}` in Host config denies Result access; its default is allow for the same local owner. This is a local filesystem policy, not cloud multi-tenant authorization. All write endpoints are checked against read dependencies, each other, and private Run state, including existing path aliases.

## Checkpoints

A Checkpoint is a durable pause before protected work whose account outcome is `delegate` and whose Host decision was deferred. It may occur during preparation, before a read or data egress, or before the complete Effect Set commits. `approve` atomically records a Host-authorized Resolution and a resume intent; the worker then resumes the same Run. `approve --wait` is a local convenience that also waits for the next stable state. `reject` ends the Run. `approve` and `reject` resolve only deferred decisions: they cannot override an account `deny` or a no-match denial, and an account `allow` or an immediate Host answer creates no Checkpoint to approve.

`run` never prompts for a decision. A deferred decision persists its Checkpoint and returns `waiting_checkpoint`, so noninteractive automation can exit and later inspect it with `status` and resolve it with `approve` or `reject`. TTY presence, EOF or piped stdin, and `--timeout` expiry never approve, reject or dispatch protected work. A missing, invalid or unavailable decision is a technical failure, not an approval or a rejection.

Before a Run-scope pause, the local adapter copies every `--input` and `--replay-from` file into its private content-addressed artifact directory. Resumption reads those captured bytes, not the original mutable paths.

Effects remain separate from computation in the checked Plan. Within each stage the runtime materializes and preflights the complete unordered Effect Set. An account `allow` needs no Checkpoint, decision callback or risk claim, including for multiple Effects; a deferred delegated decision pauses for approval of that exact scope. Approval never releases only a subset. Stage order is preserved even without data dependencies. The default `after: completed` waits for completion; `after: accepted` permits progression only when every required import is also available. Failure blocks normal successors, and unknown outcomes wait for reconciliation.

The authenticated caller request ID identifies a logical request. If the caller supplies none, the CLI creates, persists and returns one. Resume and authorized recovery retain that request and the ledger's original Preview, canonical request and dispatch key; a new physical attempt does not create a new business request. The same scoped request ID with different intent is a conflict. Intentional repeated business requests use distinct IDs. Native, stamped and natural-key recovery require the corresponding admitted Connector evidence; a local ledger alone does not prove provider exactly-once execution.

## Core

```text
actql check <program> [--config <file>] [--params <file>] [--bindings <file>] [--connectors <file>] [--model-tasks <file>] [--lock <file>] [--json]
actql explain [<program>] [--config <file>] [--params <file>] [--bindings <file>] [--connectors <file>] [--model-tasks <file>] [--lock <file>] [--input <name=file>] [--replay-from <file>] [--result <name>] [--format <format>] [--source-state-in <file>] [--deliver <result=format:file>] [--output <file>] [--stop-before <commit>] [--run <run>] [--json]
actql run <program> [--config <file>] [--params <file>] [--bindings <file>] [--connectors <file>] [--model-tasks <file>] [--lock <file>] [--input <name=file>] [--replay-from <file>] [--result <name>] [--format <format>] [--source-state-in <file>] [--deliver <result=format:file>] [--output <file>] [--stop-before <commit>] [--capture-to <file>] [--receipt <file>] [--json]
```

`--source-state-in` is a local migration bridge for the private artifact written by `migrate --source-state-out`. Run seeds only an exact matching Program and source-state requirement; conflicting existing state or a different checkpoint Contract is rejected before Run creation. Explain records its locator as unverified without reading or importing it; it affects the changes-read starting checkpoint.

## Operations

```text
actql status <run> [--config <file>] [--watch] [--timeout <duration>] [--json]
actql approve <checkpoint> [--config <file>] [--signer <id>] [--decided-at <UTC>] [--json] [--wait]
actql reject <checkpoint> [--config <file>] [--signer <id>] [--decided-at <UTC>] [--json]
actql cancel <run> [--config <file>] [--json]
actql reconcile <run> [--config <file>] [--effect <name>] [--json]
actql result <run> [--config <file>] [--output <file>] [--result <name>] [--format <format>] [--receipt <file>] [--deliver <result=format:file>] [--json]
actql operation status <operation> [--config <file>] [--connectors <file>] [--lock <file>] [--json]
actql operation reconcile <receipt> [--config <file>] [--connectors <file>] [--lock <file>] [--effect <name>] [--output <file>]
actql operation cancel <operation> [--config <file>] [--connectors <file>] [--lock <file>] [--json]
```

`reconcile <run>` uses the Connector environment bound to that Run and rejects a Connector override. If the outcome remains `unknown`, the command appends a reconciliation attempt and the Run keeps waiting. `accepted` retains the OperationRef and is not provider completion; subsequent progression follows the stage's success requirement and import availability. `failed` blocks normal successors. `operation reconcile` is the standalone command with an explicit checked Connector environment.

## Integrity

```text
actql lock [--config <file>] [--connectors <file>] [--model-tasks <file>] [--output <file>]
actql verify lock <lock> [--config <file>] [--connectors <file>] [--model-tasks <file>] [--json]
actql verify output <receipt> <output> [--json]
actql doctor [--skill-manifest <file>] [--json]
```

## Discovery

```text
actql discovery describe [--config <file>] [--connectors <file>] [--model-tasks <file>] [--json]
actql discovery list [--config <file>] [--connectors <file>] [--model-tasks <file>] [--json] --snapshot <cid> [--kind <kind>] [--selector <selector>] [--cursor <cursor>] [--page-size <count>]
actql discovery read [--config <file>] [--connectors <file>] [--model-tasks <file>] [--json] --snapshot <cid> --kind <kind> --selector <selector> --content-cid <cid>
actql catalog list [--config <file>] [--connectors <file>] [--json]
actql catalog show [<connector-id>] [--config <file>] [--connectors <file>] [--json]
actql model-task list [--config <file>] [--model-tasks <file>] [--json]
actql model-task show <model-task-id> [--config <file>] [--model-tasks <file>] [--json]
actql op list [--family <family>] [--output <carrier>] [--json]
actql op show <operation> [--json]
actql op search <words...> [--json]
actql expr list [--category <category>] [--json]
actql expr show <expression> [--json]
actql expr search <words...> [--json]
actql grammar [--json]
actql schema
```

## Maintenance

```text
actql migrate <candidate> [--output <file>] [--connectors <file>] [--model-tasks <file>] [--lock <file>] [--journal <file>] [--source-state-out <file>]
actql version
```

## Output rules

Presentation commands are human-readable by default and expose stable JSON with `--json`.
`result --json` requires a file destination (`--output` or `--deliver`) and returns the command response, not Result rows. Use `result --format json` for a JSON payload on stdout. `--deliver` is exclusive with `--output`, `--result`, and `--format`.
`check --json` returns the redacted checking report; semantic validity, runtime support and execution admission are separate. A valid stage waiting for its predecessor is `pending_predecessor`, not a missing caller binding. `explain --json` returns an `actql-explanation/0.1` with checking facts, delivery intent, missing inputs, and evidence-backed or unknown estimates. Neither command emits an executable file.
Artifact commands write to their declared `--output` or `--receipt` destination; without one, the artifact uses stdout. Progress and summaries use stderr.
`run` publishes all Results and reports Run state; it does not implicitly stream Result rows. Use `result <run> --result name --format jsonl` for stdout, or `--deliver` / `--output` for files. Run receipts bind the Result Manifest, not a selected serialization. `result --receipt` exports a separate delivery receipt for `verify output`.

Private Run evidence is persisted durably regardless of receipt export. `--receipt` exports the requested receipt; it does not enable durability. Effect preview and application remain internal execution boundaries of the Program Run.

## Project configuration

The CLI searches from the current directory upward for `actql.config.json`. Paths are resolved relative to that file:

```json
{
  "version": "actql-config/0.1",
  "connectors": "./connectors.json",
  "model_tasks": "./model-tasks.json",
  "lock": "./actql.lock.json",
  "state_dir": "./.actql",
  "account_config": "./actql.accounts.json",
  "run_policy": {
    "principal": "agent:customer-sync",
    "tenant": "acme",
    "policy_contract_cid": "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "decision": "review",
    "expires_at": "2099-01-01T00:00:00.000Z"
  },
  "effect_policy": {
    "decision": "review",
    "policy_contract_cid": "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  },
  "signers": {
    "production-approver": {
      "principal": "release-approver",
      "key_id": "release-approver-2026",
      "private_key": "./keys/release-approver.pem",
      "public_key": "./keys/release-approver.pub.pem",
      "checkpoint_kinds": ["effect_set"]
    }
  }
}
```

The local CLI accepts only configured signers and checks each signer's allowed Checkpoint kinds. Evidence never supplies its own trusted public key. A managed host resolves the same authority through its policy service.

The Local Host uses durable execution, encrypted private evidence and secure key/store/policy defaults. Checkpoint Resolution, Run transition and resume-intent creation are atomic. Before provider dispatch, durable reservations and worker fencing preserve the canonical request and accounting through crash/recovery. An uncertain dispatch is reconciled before resend. SQLite or a managed store is a physical choice, not a different recovery law. See [Reference Host](design/reference-host.md).

`account_config` selects the execution-account configuration file. It assigns the execution account and routes each principal, connection, resource and operation to `allow`, `deny` or `delegate`; overlapping entries with different outcomes are a configuration error, and a tuple without a matching entry is denied as no-match. A missing or invalid configuration never means allow. The CLI reports the selected file and account; discovery of a configuration file does not by itself make it trusted.

`run_policy` and `effect_policy` are the Local Host's decision policies for delegated run-scope and Effect Set decisions. For a `delegate` outcome, `allow` permits immediately, `review` defers to a Checkpoint and `deny` rejects immediately. They apply only to delegated decisions: they never override an account `deny` or no-match, and they are not execution-account grants. Mapping and Command Contracts declare technical permission requirements, not an approval minimum.

Command flags override discovered configuration. `--config <file>` selects a different configuration explicitly. Configuration chooses host evidence; it does not enter Program semantics. Resolved contracts and policy remain bound by the Check Environment CID.

## Argument safety

Unknown commands, options, duplicate single-value options, missing option values, and extra positionals are hard errors.
Options may appear before or after positionals. An option value is never reinterpreted as the Program path.

## Exit codes and errors

`check` returns 0 for a valid template (including missing bindings or unsupported runtime profiles), and 1 for semantic invalidity. `run` requires all initial bindings and runtime support. `explain` reports missing inputs without executing. Argument errors return 2.
`0` otherwise means the CLI command completed and produced or updated the requested Run state. A Run may therefore be `waiting_checkpoint`, `needs_reconciliation`, or `failed` with exit code `0`; automation should use `run --json` and `status <run> --json`.
`1` means execution of the CLI operation itself failed. `2` means the command line is invalid. Diagnostics use stable `ACTQL_E_*` codes; human output includes the code and message, while `--json` exposes the structured Run state and its terminal outcome.
