# Incremental bounded Session evidence

This first implementation collects 26 existing actions in the selected
`session-evidence` job and authenticates the resulting immutable ZIP in the
required `check` job. Every existing action still executes. It changes neither
the pipeline partitioning nor the chain/capacity campaigns. The artifact reader
is now a semantic verification input and is no longer maintenance-only.

## Published interface and workflow

The [contract](CONTRACT.md) describes the eventual closed reuse boundary.
`cli.mjs catalog`, `plan`, `seal`, and `check` are the public data interface.
The initial plan returns `execute` for every registered action and explicitly
does not authorize reuse. `seal` interprets command output; it is not a trust
witness without authentication of the actual successful Actions producer.

The current workflow uses the existing executions directly:

1. `collect.mjs init` resolves the live Session job, actual checkout revision,
   run HEAD, run/attempt and repository through the read-only Actions API.
2. The existing mutation runner executes once. Its source restoration is
   checked before a receipt is recorded. The final existing bounded Session
   runner records its actual model and three-target test executions.
3. `collect.mjs finish` runs the executable Lean checker over all 26 fresh
   applications and records the exact Lean input/output digests.
4. Upload the original receipts, observations, results and certificate as
   `session-actions-<run>-<attempt>-<tested-revision>`.
5. `final.mjs` downloads that ZIP without extracting or executing it, checks
   its digest against independent Actions metadata, authenticates each
   successful producer job and reconstructs the exact required inventory,
   source inputs and certificate binding. Missing or inconsistent evidence
   fails the required check. The final consumer validates the trusted producer's
   executed Lean certificate rather than installing Lean and repeating its run.

The receipt distinguishes the actual tested PR merge revision from the run's
head revision. Fresh fork PR observations may satisfy their own current run;
they cannot be adopted as protected main origins. Raw receipts are never
rewritten to a later candidate.

## Proven and trusted boundaries

`Reuse.lean` proves checker soundness/completeness, preservation of scope/kind
and every required obligation, and equal-input observation preservation under
an explicitly deterministic observation function. `Claims.lean` fixes the
expected proposition types. The concrete plan is checked by Lean's kernel,
with an axiom audit. These are model properties; they do not prove Git
dependency extraction, runtime determinism, Actions provenance, or production
MoonBit refinement universally.

The source extractor includes byte/mode and directory membership, descriptors,
the checker/recorder/transport and transitive literal MoonBit imports. Unknown
imports/configuration remain open for the affected action. Original Git inputs
are reconstructed independently of receipt labels. The current runtime
observation intentionally retains an unresolved distribution/loader/environment
boundary. It cannot authorize cross-revision reuse. The earlier report-only
inventory has not been upgraded by removing its unresolved labels.

Next units must close reviewed runtime/action boundaries, use the existing
trusted main-checkpoint resolver, compare plans with ordinary successful
executions, enable only the accepted closed scope, and demonstrate relevant
invalidation and net savings on multiple real PRs. This unit is not completion
of the overall incremental verification task; runner savings are not claimed.

## Focused regression scope

Use the repository's bounded Node wrapper for `proofs/ci-evidence/*.test.mjs`
and `scripts/ci-targets.test.mjs`. The small checker tests execute the pinned
Lean kernel; they are not the bounded Session/chain/capacity campaigns.
Regressions cover source/oracle/import/add/delete/rename changes, registry
deletion, open runtime boundaries, whole target/profile replacement, incomplete
obligations, mixed attempts, failed/cancelled origins, missing/changed ZIP
members, certificate input/output changes and token isolation during transport.
Full correspondence and physical tests remain in their existing CI jobs.
