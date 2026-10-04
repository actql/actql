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
the checker/recorder/transport and transitive literal MoonBit imports. Literal
`formatter(ignore: ["file.mbt", ...])` is a reviewed non-build option; its bytes
remain in the input identity. Dynamic formatter/import expressions and unknown
options remain open for the affected action. Original Git inputs
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

## Runtime input observation (dependent unit)

`runtime.mjs` inventories actual Node executable bytes and the installed
MoonBit/core and Lean distributions after the existing setup steps. Regular
files carry mode/size/SHA-256; directories carry membership. Symlinks are
recorded without traversing their targets. Missing, unstable, nonregular and
limit-truncated inputs remain explicit coverage gaps. Each distribution has a
50,000-entry / 2 GiB observation bound, including a bounded directory reader.
Those bounds protect the observation; they are not a claim about runtime memory
or a proof that an incomplete installation is sufficient.

One immutable `runtime-distributions.json` stores the relative inventories.
Runtime summaries bind their full encoded content, member counts, bytes and
coverage gaps. Every original receipt also binds that file's exact bytes. The
final consumer reconstructs these summaries from the authenticated ZIP and
rejects missing/replaced inventories or erased gaps. It does not accept a
summary solely because its label matches. Keeping the inventory once avoids
copying the complete distribution list into each of the 26 receipts.

`runtime-measurement.json` records inventory time, entries and bytes separately
from semantic input equality. Curated execution-configuration hashes are
recorded, but arbitrary inherited names/values and credential hashes are not.
Physical root relocation is distinct from relative installation identity;
symlink substitution, content, membership and mode changes remain visible.

This unit still does **not** close OS/loaders/system libraries/CPU features,
Node built-ins, arbitrary inherited configuration, external services or
execution-time filesystem mutation. Those residuals are mandatory. An identical
inventory is insufficient to authorize reuse. Comparison still executes every
registered action; no runner savings are claimed yet. Next, a reviewed isolated
executor and protected-main comparison must establish an action-specific
closed scope before activation. Actual Linux inventory cost and corpus
correspondence are automatic-CI evidence, not the tiny local fixture tests.
# Protected-main comparison

`plan.mjs` connects the existing full-main checkpoint resolver to the original
Session artifact transport and receipt authentication. Collection stores
`comparison-plan.json` before normal execution. Every action still executes;
each receipt binds that plan's original bytes. Completion stores the actual
fresh unit counts/durations separately and binds both records in the executed
Lean certificate. The final required check reconstructs candidate inputs,
checks the fresh observations and authenticates the selected main origin again.

The comparison uses the exact recorded SHA/run/attempt, not a newer main run
that finishes during the candidate. Origin catalogs and source manifests come
from actual Git, not the candidate's relabeled bindings. New registrations,
changed policy/inputs, unavailable archives and rejected origins never satisfy
an obligation from old evidence. A checkpoint/cache miss uses complete fresh
execution without retroactive adoption if the cache becomes available later.

Checkpoint lookup, archive transfer and original inspection costs are recorded
separately at producer and consumer. Matching unit counts are only a finite
comparison of ordinary executions, not output determinism or runtime closure.
The current installed-runtime profile still has mandatory residuals; equal
inputs with those gaps remain `same-inputs-open` and cannot authorize reuse.

The preceding runtime unit (#296, `9058b626d4ebe8ac46c5482d46fc192b64b06d88`)
measured 5,876 ms, 14,096 entries and 2,572,043,660 observed bytes in automatic
run 37164996726. The authenticated archive digest is
`a9393fcbfaba184255c601944ddca840e2bbe9bb3097d457521d5d3da168eaa4`.
Lean's 2 GiB observation limit at `lib/lean/libLean.a` and MoonBit's
`lib/core/lazy_list/README.md` symlink remained unresolved. Its Session producer
checked 26 fresh receipts; this is an observation/correspondence unit, not a net
savings result. Runtime isolation, scoped activation and measured net savings
on ordinary PRs remain required for the overall task.
