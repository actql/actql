# Incremental evidence connection contract

Status: scoped activation and additive registration implementation for review.
This contract alone authorizes no skip. Only `mutations-js` may adopt a
qualified protected-main original; every other registered action executes
fresh. The actual main comparison and independent final acceptance are required
before this scope can reuse anything. G owns the catalog, dependency closure, immutable receipt validation,
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

## Ordinary PR execution boundary

Contributors use the normal selected PR CI. Its Session workflow calls:

```text
node proofs/ci-evidence/collect.mjs init
node proofs/ci-evidence/collect.mjs mutations
node proofs/bounded-session/run.mjs all
node proofs/ci-evidence/collect.mjs finish
```

The existing chain/capacity steps remain at their current workflow positions.
Initialization constructs the actual acquisition plan from current
Git/runtime inputs and independently authenticated main evidence. Main always
executes fresh. The PR may omit only the qualified isolated JS mutation action;
the existing runner still records every other actual execution. Producer
finish executes the Lean checker over the complete independent inventory.

The required `check` job calls `node proofs/ci-evidence/final.mjs`. It binds
current context to the source ZIP, checks every fresh or reused original,
reconstructs required obligations and the actually executed Lean certificate,
and saves a separate final applicability artifact. A caller-supplied status or
successful producer without final acceptance cannot authorize reuse.

To add a local obligation, register its finite fixture recipe and matching
action descriptors as described in [the contributor steps](README.md#adding-a-local-obligation-through-the-ordinary-pr).
No workflow edit, execution callback or per-PR permission from G is needed.
The initial requirements remain protected; new local actions execute fresh and
need their own candidate receipts. A new derived operation claim additionally
needs independent fixture scope/binding evidence, not just a registration.

## Diagnostic CLI boundary

All files below are relative to the candidate checkout. Consumers must pin the
public revision; unpublished worktrees are not dependencies. The CLI exposes
these data/diagnostic operations. They are separate from the ordinary workflow's
acquisition/final acceptance boundary and do not grant permission to omit work:

```text
node proofs/ci-evidence/cli.mjs catalog
node proofs/ci-evidence/cli.mjs plan --request REQUEST.json --out PLAN.json
node proofs/ci-evidence/cli.mjs seal --request EXECUTION.json --out RECEIPT.json
node proofs/ci-evidence/cli.mjs check --request CHECK.json --out CHECKED.json
```

CLI `plan` reports only `execute` and explicitly disables reuse. It does not
execute tests or authorize skip. `seal` validates the supplied ordinary command
output and nonzero count before emitting canonical receipt data; it does not
create a trusted producer or a complete source artifact. Mutation receipts need
the structured observations/restoration validated by the ordinary collector.
`check` independently reconstructs the expected obligations and
candidate inputs, authenticates original receipts and runs the Lean plan
checker for fresh-only diagnostic applications. The production workflow uses
the acquisition and final acceptance checks above for mixed fresh/reused work.
No boolean supplied by a caller is a trust witness.

### Requests and candidate context

Production context binds `candidateRevision` (full tested Git SHA), repository
and head-repository IDs, workflow ID, run ID/attempt and run-head revision. The
origin separately binds the successful job ID and event/branch. Runtime manifests,
comparison and acquisition records are stored separately in the source ZIP.
The final check requires the entire catalog, not a caller-selected subset. The
main baseline is independently resolved through the existing checkpoint
procedure, not `HEAD^` or `push.before`. Candidate policy changes disable reuse;
removing a required action cannot make its obligation disappear.

Diagnostic CLI requests use these exact top-level fields:

| Operation | Request fields |
| --- | --- |
| `catalog` | No request file |
| `plan` | `candidateRevision`, `runtime` |
| `seal` | `actionId`, `origin`, `runtime`, `output`, `status`, `milliseconds` |
| `check` | `context`, `runtime`, `entries` (fresh-only; actual Actions context required) |

Runtime manifests bind the executor/compiler bytes, imported distribution/core,
target/ABI, fixed flags, OS/environment profile and reviewed input boundary.
Source manifests bind Git file bytes/modes, transitive package dependencies,
directory membership, fixtures, oracle/model, registrations and command.
Unknown dependencies cause the affected actions to execute; they never grant
permission to reuse and do not automatically invalidate unrelated closed leaves.
No inherited secret values or secret-derived hashes may enter the manifest.

The isolated JS image excludes exactly four installed-core build-owner files:
`lib/core/_build/.moon_db` and `lib/core/_build/{js,wasm,native}/release/bundle/all_pkgs.json`.
They are absent from the executor, rather than ignored or normalized when
hashing an image that can still read them. The independent image validator
rejects their reintroduction. Compiler executables, loaders, core source,
manifests, `.mi` and `.core` bytes remain bound; unreviewed files are still
included. The whole-installation runtime observation and its unresolved
boundaries remain unchanged. CPU/platform differences still force fresh work.

For the pinned Moon revision `94521dbd387b041d449918a6495346d407cfb698`,
the [selected workspace layout](https://github.com/moonbitlang/moon/blob/94521dbd387b041d449918a6495346d407cfb698/crates/moonbuild-rupes-recta/src/target_layout.rs#L634)
owns the build database. The [runner generates package metadata](https://github.com/moonbitlang/moon/blob/94521dbd387b041d449918a6495346d407cfb698/crates/moon/src/rr_build/mod.rs#L955)
in that selected workspace, and [installed-core lookup](https://github.com/moonbitlang/moon/blob/94521dbd387b041d449918a6495346d407cfb698/crates/moonutil/src/moon_dir.rs#L268)
resolves prebuilt core artifacts. This is the source-level rationale for the
isolated staging boundary, not a formal proof of the compiler binary. Ordinary
CI must still execute all thirteen assertion mutations in the resulting image,
verify byte-exact restoration and complete the existing JS/Wasm/native checks.
The policy change invalidates earlier keys; old images are not relabeled as
matching this boundary.

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
  "actionId": "mutations-js",
  "acquisition": "reused",
  "originReceiptDigest": "<sha256>",
  "originRevision": "<original full SHA>",
  "originRunId": 1,
  "originRunAttempt": 1,
  "artifactId": 1,
  "archiveDigest": "<sha256>",
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
activation, compare a successful full main origin with a later full main fresh
execution under the same closed conditional input contract. That later run's
final consumer must confirm the equal inputs and thirteen scientific mutation
observations; the whole run and final-check owner must then succeed before its
original is eligible for a subsequent ordinary PR. An unrelated PR, count match
or successful producer alone cannot qualify an original. Verify an unrelated
candidate reuses the eligible action and a relevant-source candidate executes
the affected action fresh. Also exercise oracle/registry/target changes, added or
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
