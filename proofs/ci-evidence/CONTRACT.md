# Incremental evidence connection contract

Status: comparison implementation for review. This contract alone authorizes no
skip. G owns the catalog, dependency closure, immutable receipt validation,
candidate applicability, executable Lean checker and this family's workflow,
artifact and final-check wiring. dot's existing CI optimizations remain separate;
overlapping file sections must be coordinated rather than implemented twice. The implementation
must use the checker before reuse is enabled; a JS-only shadow verdict is not
a verified reuse decision.

## Registered actions

`bounded-session-actions.json` is the independent required inventory. It splits
the existing model, common Session, Local adapter, reviewed set/Nest connections,
Nest-specific obligations and JS mutations. Targets, commands, scope/profile,
minimum nonzero units, evidence kind and premises are part of each descriptor.
The mutation action is a costly deterministic action, not just a Lean build.
Chain/capacity and other pipeline jobs remain outside the first enabled family.

Registration is data, not an arbitrary execution callback. The runner executes
only supported descriptors. A binding cannot relabel a fixture's reviewed
coverage. Connection coverage still comes from the independent fixture table
in `bounded-session/evidence.mjs`. The package closure includes compilation
dependencies even when the test command selects one file.

## CLI boundary to wire

All files below are relative to the candidate checkout. Consumers must pin the
public revision; unpublished worktrees are not dependencies. The CLI exposes
these operations (the initial plan always executes, with reuse disabled):

```text
node proofs/ci-evidence/cli.mjs catalog
node proofs/ci-evidence/cli.mjs plan --request REQUEST.json --out PLAN.json
node proofs/ci-evidence/cli.mjs seal --request EXECUTION.json --out RECEIPT.json
node proofs/ci-evidence/cli.mjs check --request CHECK.json --out CHECKED.json
```

The eventual `plan` keeps every registered obligation and reports `execute` or
`reuse` with reasons. The comparison implementation reports only `execute`.
It does not execute tests or
authorize skip. `seal` verifies actual command output, nonzero counts, source
restoration where applicable and artifact bytes before emitting a canonical
receipt. `check` independently reconstructs the expected obligations and
candidate inputs, authenticates original receipts and runs the Lean plan
checker. Only its checked output can justify reuse at the final required check.
No boolean supplied by a caller is a trust witness.

### Requests and candidate context

Each request includes `candidateRevision` (full Git SHA), `repository`,
`repositoryId`, `workflowId`, `runId`, `runAttempt`, `policyRevision`, selected
action IDs and a runtime manifest reference. Action IDs must match the catalog;
the final check requires the entire applicable family, not the caller's subset.
`policyRevision` is a trusted main checkpoint resolved through the existing
main-baseline procedure, not `HEAD^` or `push.before`. Candidate policy changes
disable reuse. Removing a required action cannot make its obligation disappear.

Runtime manifests bind the executor/compiler bytes, imported distribution/core,
target/ABI, fixed flags, OS/environment profile and reviewed input boundary.
Source manifests bind Git file bytes/modes, transitive package dependencies,
directory membership, fixtures, oracle/model, registrations and command.
Unknown dependencies cause the affected actions to execute; they never grant
permission to reuse and do not automatically invalidate unrelated closed leaves.
No inherited secret values or secret-derived hashes may enter the manifest.

### Immutable origin receipt

Canonical UTF-8 JSON uses the existing `action-inputs.mjs` encoding rules.
The receipt has these separate fields:

| Field | Required content |
| --- | --- |
| `version` | `actql-verification-action-receipt/0.1` |
| `origin` | Repository/id, full tested revision, workflow id/path, run/attempt/job and event/branch |
| `action` | Complete registered action descriptor, including target, kind, scope and premises |
| `inputs` | Complete input manifest and action key, including unresolved boundaries |
| `execution` | Actual command, exit/status, passed/failed/nonzero units, observation digest and measured duration |
| `artifacts` | Relative names, byte counts and SHA-256 digests of original observations/results/binaries |

Original `testedRevision`, execution identity and bytes are never rewritten to
the candidate. The receipt digest is computed over its complete original bytes.
An original finite test remains `tested-refinement` after reuse.

Transport carries the original receipt and referenced artifacts in a GitHub
Actions artifact. G wires its upload, download and final required check. The
checker must compare the archive digest with current Actions metadata, read the
receipt from that archive, and validate its original run/attempt/job/revision.
An unpacked receipt plus a caller's assertion that it was downloaded is
insufficient. Archive contents are data; never execute code from them.

Initial cross-revision origins are successful, completed same-repository
`push` runs on main, from the selected workflow and trusted ancestor checkpoint.
PR/fork artifacts cannot become protected reusable origins. A fresh receipt for
the current PR must match the current run/attempt/revision and successful job;
it does not become a main origin until independently published on main.
Cancelled, failed, incomplete, expired, missing and tampered origins cannot be
adopted. Cache absence/expiry schedules fresh execution. Invalid evidence never
counts as a satisfied obligation.

### Candidate application and final result

The candidate record is separate from the origin receipt:

```json
{
  "version": "actql-verification-action-application/0.1",
  "candidateRevision": "<full SHA>",
  "actionId": "session-js",
  "acquisition": "reused",
  "originReceiptDigest": "<sha256>",
  "originRevision": "<original full SHA>",
  "originRunId": 1,
  "originRunAttempt": 1,
  "candidateActionKey": "<sha256>",
  "originActionKey": "<same sha256>",
  "kind": "tested-refinement",
  "target": "js",
  "scopeDigest": "<exact descriptor/premise identity>",
  "checkerResult": "accepted"
}
```

`fresh` and `reused` describe acquisition, independently of evidence kind.
`not-applicable` requires protected policy grounds; an expected required action
cannot use it. The final checked result binds the full candidate SHA, current
repository/workflow/run/attempt, policy/catalog digest, complete required action
IDs, origin receipt digests, application records and Lean check input/result
digests. Missing, duplicate, extra, target-swapped or scope-expanded applications
fail the final check. The workflow must not convert `skipped` into success
without an accepted application for every omitted required action.

## Comparison period and activation

Use existing normal CI observations, not a second full CI on every PR. Before
activation, compare at least one successful full main origin, one unrelated
candidate with equal inputs, and one relevant-source candidate that executes
the affected actions. Also exercise oracle/registry/target changes, added or
renamed files, branch integration, policy weakening, corrupt/missing artifacts,
failed/cancelled runs and mixed attempts through focused regressions.

For each sampled candidate, record planned acquisition versus the actual
nonzero result, exact source/runtime identity and any disagreement. Enable only
the closed family after zero unexplained disagreements and reviewed negative
coverage. This is an explicit exit from comparison, not permanent double work.

Measure saved action execution time minus checker, hashing, download and audit
cost. Then demonstrate reuse and relevant invalidation in multiple real PRs.
Interface publication, a model proof or shadow reporting alone is not the
overall completion condition. No new owner, persistent ledger, compatibility
fallback or all-language dependency analyzer is part of this contract.
