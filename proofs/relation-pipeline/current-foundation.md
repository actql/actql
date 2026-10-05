# Current foundation after mutation build reuse

The whole-row distinct experiment in `reuse-baseline.json` is historical evidence.
Its bytes remain exactly those accepted in #148 at
`0aa3bc921362b53536d5bf9d541a889e09ccc24b`, including the original 57-file local
comparison, subsequent upstream integration, failed 40-minute CI attempt and
separate timeout correction. `DISTINCT-REUSE.md` describes that comparison.
Neither its result nor the earlier take experiment is rewritten by #149.

## Separate common correction

#149 changes verification scheduling: each production mutation is installed
once for fixed replay and required fresh JS exploration/shrinking and minima
replay. Sources are then restored exactly, and each obligation independently
executes restored success on JS, Wasm and native. No observation or execution
receipt is shared between fixed and fresh modes. Only target-separated Moon
incremental compilation under unchanged source is reused. The impact classifier,
known mutation registry, independent oracle, shrink reductions, source-restoration
assertions and all final audits remain required. The existing 90-minute limit
from #148 is retained; this integration does not increase it.

The optimization and the provenance validator are additional common review work.
They are not attributed to the original no-common-change distinct registration.
This correction changes `mutations.mjs`, `.github/workflows/ci.yml` and
`history.mjs`; it also adds orchestration/provenance regression tests, their
instrumented fixtures and this explanation. No product semantic or public
contract change is included.

## Immutable migration and per-change declarations

The accepted #148 `reuse-baseline.json` remains byte-identical. The integrated
#172/#173/#175 foundation at `16d93c2bf7c9c7aa0c485416a7ea1436fd8a060a`
is a separate, fixed migration checkpoint. Its former `current-foundation.json`
is retained byte-for-byte as `foundation-baseline.json`; its source reference is
`8f7e3db0e499dc01cc7ef9fd982364349af1f8d8`. Neither record is updated by later
changes. The migration preserves all 57 original common pins and the five
supplementary #149 files, their rationales and historical meaning.

Later changes add independent files under `foundation-declarations/<id>.json`.
There is no central index or global revision to edit. `history.mjs` combines the
frozen checks with `foundation.mjs`, a bounded provenance validator for this
existing foundation. It is not a general proof or source-merging framework.

Declarations use two-space JSON indentation and one terminal newline, as emitted
by `JSON.stringify(value, null, 2) + '\n'`; duplicate JSON keys and lossy encodings
are rejected. Each declaration names one exact source commit and its actual ordered parent
list. Each changed protected path names every parent's SHA-256 and file mode,
the committed result SHA-256 and mode, and a nonempty rationale. The validator
requires the exact changed-path set. New protected helper/test files are part
of the explicit checked scope; a refactor cannot move enforcement into an
unprotected helper. Declarations remain reviewable provenance inputs. Neither
Git identity nor a rationale proves human approval or semantic correctness.

## Contributor workflow

1. Use full Git history and integrate the migration checkpoint into the final
   checkout. Older in-flight branches may keep their original source commits:
   declare every new protected transition on those branches and preserve all
   declarations when merging. Remove the obsolete shared `current-foundation.json`
   if an old branch still carries it; its accepted bytes are already preserved
   by `foundation-baseline.json`. A boundary parent outside the newly checked DAG
   must be an ancestor of the accepted checkpoint.
2. Commit the source change first. Keep the existing mutation/oracle, source
   restoration, historical and three-target obligations. Obtain the exact
   source revision with `git rev-parse HEAD` and its direct parent with
   `git rev-parse HEAD^`. One ordinary declaration covers one source commit;
   multiple source commits need separate declarations even if later reverted.
3. Add `foundation-declarations/<id>.json` in a later commit. Use the schema
   below, exact Git-blob digests (`git show <sha>:<path> | sha256sum`) and actual
   Git modes (`git ls-tree <sha> -- <path>`). A newly added protected file has
   `null` parent digest and mode. Describe the actual reason for each change;
   a generated hash by itself is not provenance. Commit the declaration without
   modifying its already-pinned source. No declaration authorizes unrelated
   paths or changes already present in its parent.
4. Run `node --test proofs/relation-pipeline/history.test.mjs
   proofs/relation-pipeline/foundation.test.mjs` and
   `node proofs/relation-pipeline/history.mjs --write` from a clean checkout.
   The latter writes only the ignored
   `.artifacts/relation-pipeline/current-foundation.json`. Without `--write`,
   it prints the same canonical JSON to stdout. Do not commit that output.
5. Push and run the complete pipeline CI on the integrated SHA. The existing
   exact-SHA artifact contains the generated manifest alongside the independent
   pipeline evidence. Its `sourceRevision` is the actual checkout commit, which
   can be a GitHub PR test-merge commit rather than the branch head.

Ordinary declaration shape (replace placeholders with exact identities):

```json
{
  "version": "actql-foundation-declaration/0.1",
  "id": "issue-180-source",
  "kind": "change",
  "revision": "<40 lowercase hex source SHA>",
  "parents": ["<40 lowercase hex direct parent SHA>"],
  "changes": [{
    "path": "package.json",
    "before": [{"revision": "<parent SHA>", "digest": "<64 hex SHA-256>", "mode": "100644"}],
    "afterDigest": "<64 hex SHA-256>",
    "afterMode": "100644",
    "reason": "Register the new independent regression while retaining the existing gates."
  }]
}
```

Declarations are append-only. At every commit, all declarations inherited from
any parent must survive byte-identically. Independently introduced copies of
the same path must have the identical Git blob and mode. Every introduction
must strictly follow its supporting source commit in the real ancestry; the
generated report retains the complete sorted `introductions` list. Correct an
unpublished declaration before its introduction is finalized, or rebuild the
unpublished source/declaration sequence. Squash, rebase and cherry-pick rewrite
source identities: rebuild the declarations against those exact rewritten
source commits before validation. An existing ancestor-bound declaration never
silently authorizes a rewritten source. Use merge-preserving integration for
already validated source/declaration pairs.

## Integrating independent and overlapping changes

The validator enumerates the complete reachable post-checkpoint commit DAG,
not just the first-parent history, declaration list or final diff. Every
ordinary protected-file edit must have its own declaration, including edits
later reverted. Removing an earlier declaration cannot be hidden by a later
commit whose parent already contains the omitted change.

For a two-parent merge, enumerate **all actual maximal Git merge bases**. Apply
the following existing rule independently at every base and protected path:

- When neither side changed it, the committed result must match that file
- When exactly one side changed it, the result must match that side
- When both sides changed it, retain both declarations and add an explicit
  resolution, even if a textual merge was clean or both sides reached equal bytes
- Any other result, including dropping one side with an `ours` merge, requires
  an explicit resolution

For multiple bases, require the union of those obligations. An obligation binds
the source revision, actual ordered parents, path, both parent blob/mode
identities and committed result blob/mode. Equal full bindings combine their
grounds; a same-path binding with inconsistent source, parent or result grounds
rejects instead of overwriting another obligation. Each required obligation's
generated report retains every base SHA, that base's path blob/mode, the
both-changed and automatic-result derivation, and whether that base requires
resolution. This includes bases where that particular path needs no resolution.
No preferred, first or virtual base can replace the actual full set.

A multi-base resolution declaration adds `mergeBases`, the complete sorted list
of actual maximal base SHAs. Every record must match the independently computed
Git set exactly; missing, extra, nonmaximal, duplicate or reordered bases reject.
This field participates in source-binding equivalence, so a valid alias cannot
hide another record's changed grounds. Parent order and each ordered `before`
identity remain significant. The declaration's required paths and source-revision
input set must cover the entire union, including paths where the parents already
agree but one base still makes both sides changed.

The original single-base declaration and generated integration formats remain
unchanged; adding `mergeBases` to a single-base declaration rejects unless an
explicit single-base normalization supplement verifies the redundant field, as
described below. Multi-base
integration metadata uses `mergeBases` and `obligations` rather than the scalar
`mergeBase`, including an empty-obligation record when no protected path needs
resolution. No declaration is allowed for that empty case. Source/dependency,
immutability, deletion, mode and complete-history safeguards are unchanged.

The fixed [multiple-base identity fixture](fixtures/multiple-merge-bases.json)
records the inspected merge `19b0b464b983695c68df60d601016bb25a4fd06d`, its ordered
parents and the two bases `8b21ddd3f4a17fcecbb9bcf5878082148af0aa99` and
`8baa87fc6b6cb7d7caa981cef1692c9d73d88318`. Their existing-rule obligations are
5 and 20 paths, with a 21-path union. These fixed Git identities test requirement
derivation, not complete repository acceptance or product execution. Independent
temporary real-Git criss-cross fixtures test declarations, missing grounds,
both bases' exclusive paths, parent ordering and unavailable history objects.
This extension does not declare that retained source merge: its owner must add
an actual source-bound resolution after adopting the rule, then validate every
remaining historical merge and the final integrated checkout.

For example, branches adding different test registrations to `package.json`
retain their separate declarations. Resolve the actual source so both commands
remain, commit the merge, then add a new `kind: "resolution"` declaration. Its
`parents` lists both actual parents in Git order; each `before` lists both
parent identities; `afterDigest` pins the actual merged file. The rationale
explains the integration. Its additional `inputs` field is the sorted list of
all earlier source-binding groups touching any resolved path and reachable
through either parent, including original changes, reverts and prior resolutions.
Each input ID must name a retained, independently validated declaration. Raw
IDs must be sorted and unique. Equivalent aliases may name the same group;
the normalized group set must equal the complete independently derived set.
Unknown, omitted, extra, cyclic and future-source dependencies are rejected.
An alias introduced later cannot force an existing immutable resolution to
rewrite its input spelling.
Paths requiring no resolution under every maximal base do not need to be
repeated in the resolution.

### Receipts introduced after an immutable resolution

A source ancestor can receive its declaration after a downstream resolution
was recorded. The downstream original remains immutable. Complete its missing
dependency receipts with a separate, additive record in
`proofs/relation-pipeline/foundation-declarations-supplements/<id>.json`:

```json
{
  "version": "actql-foundation-resolution-supplement/0.1",
  "id": "complete-late-receipt",
  "target": {"id": "original-resolution", "digest": "<original JSON SHA-256>"},
  "inputs": ["later-introduced-declaration"],
  "reason": "Bind the receipt introduced after the unchanged original"
}
```

The target must be an independently validated resolution, bound by its exact
original bytes. Every supplement introduction follows an original introduction
and an introduction of each supplied receipt. Supplement bytes, mode, filename,
membership and every introduction are checked against real Git and retained
unchanged, using the same inheritance and working/index safeguards as originals.

At **each original introduction**, its original normalized inputs must exactly
cover every currently known required source group whose receipt was then
reachable. A supplement cannot excuse an already visible omission, change an
original input, repair a bad source/parent/blob/mode binding, or replace a
missing source declaration. Additions must be disjoint required source groups
ancestral to the original merge's real parents. Unknown, unrelated, future,
self/cyclic, duplicate, redundant and still-incomplete dependencies are rejected.
All effective source dependencies must match the independently derived complete
set, and every equivalent original record must pass independently.

The report retains original `inputs`, digest and introduction metadata verbatim.
When present, a separate `supplements` array records the new records, their
digests and introductions; affected integrations list their supplement IDs.
Without supplements, declaration and aggregate formats/results are unchanged.
This is dependency provenance, not an approval or permission to execute.

Ordinary `foundation.test.mjs` regressions use small, self-contained real-Git
fixtures. They cover failure before supplementation, success afterward,
immutability and dependency rejection, and continued success after an unrelated
commit or another independently justified supplement. They require neither an
unmerged branch's objects nor a runtime HEAD merge into historical evidence.

An optional `scripts/rehearse-foundation-supplement.mjs` command accepts explicit
source and validator commit SHAs and a canonical supplement input file. It
checks the original digest/introduction in an isolated worktree, leaves an
identical existing supplement unchanged, and locates the receipt by identity
rather than total count. Missing explicitly requested objects fail. This command
is separate from ordinary CI. The previously obtained #246 rehearsal and its
exact inputs remain in [the historical evidence record](../../docs/reviews/2026-10-03-resolution-supplement-rehearsal.md).

A resolution records reviewed source provenance; it does not establish that
both test commands are semantically correct or that a reviewer approved them.
The real-Git integration fixtures assert both independent registrations and
rationales survive in the actual merged file. The normal source review and
required pipeline tests remain necessary.

Single-base merges of disjoint protected paths require no resolution declaration
or aggregate edit when each result preserves the changed side. A different-file
criss-cross can still require a resolution under another maximal base.
For older branches, composition uses their actual old common-base blobs. If
both the checkpoint/main side and the branch changed a protected file, the
explicit resolution pins the integrated bytes while the immutable checkpoint
retains the earlier rationale. It never substitutes old branch bytes for a
newer checkpoint file without that resolution.
Octopus merges, unrelated histories, protected-file
deletions and executable-mode changes are rejected
with a diagnostic; use a supported integration shape rather than a fallback.
No product execution, allocation claim, mutation requirement or oracle is
changed by these provenance rules.

## Validation boundary

The historical and migration records are pinned Git inputs, immutable through
the post-checkpoint DAG, HEAD, index and working tree. All original negative
historical cases remain exercised against the frozen validator. The composed
validator additionally rejects missing Git objects, shallow/replaced/grafted
history, unrelated revisions, incorrect parents or hashes, duplicate/ambiguous
IDs, noncanonical paths, spurious changes, declaration edits/removals, undeclared
source changes, unsupported merges and uncommitted source/declaration drift.

The generated manifest has stable path/ID ordering and exact source/declaration
identities. It contains no clock, absolute machine path, mutable branch name or
last-write-wins value. Identical source, declarations and historical inputs
produce byte-identical output. Artifact generation does not bless working-tree
hashes or replace missing declarations. The final audit still independently
runs `checkFoundation()` against the actual restored source.

## Verification and measurement scope

The integrated configuration has eight production mutations, including the
three distinct mutations. CI must execute fixed and fresh evidence separately,
with fresh search and same-anchor local-minimum shrinking, mutated/restored
replay on all three targets, final normal corpus/model validation, independent
receipt audit and whole-report target-substitution rejection. Every execution
receipt path across the two mutation reports must be distinct when assessing
this optimization's evidence.

The earlier five-mutation timing result (35m40s baseline median to one 21m02s
pipeline sample) remains a five-mutation measurement. It is not an eight-mutation
estimate or comparison. Current eight-mutation measurements are reported with
the actual run/source/checkout identities, attempt, sample count, runner,
queue/dependency protocol and completed outcomes in the PR. Failed and cancelled
runs remain failure evidence and are not counted as completed green samples.
Local reconstructed-source runs, if any, are distinguished from exact hosted
CI, and mutation phase timings are retained in the source-bound reports.

## Source-only mutation workspace isolation

The mutation runner now materializes two process-owned source snapshots before
installing any mutation. Only the inventoried source bytes and executable modes are copied, including
vendored native headers and the native link/archiver drivers. Existing
`_build`, dependency directories, temporary fixtures and archived observations
are not captured. The pristine and mutable snapshots have separate build roots;
source and build symlinks or replaced workspace roots are rejected. The pinned
external Moon toolchain is shared as a checked, read-only input. Its compiler,
build runner, Wasm runner, core, runtime and headers are fingerprinted alongside
the resolved Node, C/C++ compiler and archiver binaries. System libraries retain the
existing CI runner/environment trust boundary.

Every mutation is applied only in the mutable workspace. Its fixed replay,
required fresh search/shrinking and three-target minima replay retain separate
executions. The source bytes are restored and checked against the original
snapshot before the next mutation. Each healthy replay then really executes in
the pristine workspace, once per obligation and target. Its input, observations,
log and receipt are new; only Moon's unchanged-source incremental build persists.
The original checkout remains unchanged and still executes the final full normal
corpus, models and independent audit on all three targets.

Each fixture compiles a boundary marker containing the source, unique workspace,
fixture, target, exact command, toolchain and non-input environment identities.
Target-conditional constants keep the complete fixture source identical across
JS, Wasm and native builds while binding each actual binary to its own target. The observation
log must emit that exact compiled marker once. A runtime environment label alone
cannot stand in for a compiled boundary. Reuse is confined to the same target,
source, fixture, flags, lockfile, tools and environment in the same workspace;
previously built artifact hashes are checked before and after each reused build.
Observation identities include the invocation and serial, and the final audit
rejects receipt or observation reuse across fixed, fresh and normal obligations.
Compile errors, missing execution output, missing observations, failed restoration
or failed cleanup are errors, never killed-mutant or successful-run evidence.

The existing owned-scratch helper removes a successful run's temporary workspaces
only after all child processes end and source/fixture restoration succeeds.
Failure preserves those workspaces for diagnosis; durable receipt, input, log and
source evidence remains outside them. `ACTQL_TEST_PRESERVE_SCRATCH=1` retains a
successful workspace when explicit inspection is needed.

This is a build-placement change, not an observation cache or a reduced gate.
All eight production mutations, both obligations, all three targets, reviewed
search/shrink domain, restoration and final audits remain required. Phase timings
still include build and execution work; a restored-phase duration is not a pure
compile cost or a promise that the entire phase can be removed.


## Convergent declarations for an existing source binding

Independently published records may describe the same exact source transition.
Every physical record first passes canonical encoding, filename/ID, actual Git
source ancestry, ordered parents, complete changed-path membership, before and
after digest/mode, nonempty rationale and every introduction check. Only then
may records share a source-binding group. Equality requires the declaration
version and kind, source revision, ordered parents, the complete path-indexed
before/after identities and modes, and the exact normalized dependency grounds.
Equal final bytes alone are insufficient. Dependency groups are checked in
source topological order, so an unverified alias cannot provide authority.

IDs, paths, record digests, rationales and all introduction commits remain in
the manifest. The integration report lists all matching declaration IDs in its
`declarations` array. No original is edited, removed, renamed or replaced by a
representative. Conflicting bindings fail closed. This does not exempt a source
or merge that lacks a declaration: it still requires its own exact Git-bound
record. It neither promotes provenance into human approval nor changes test,
execution receipt, mutation, restoration or proof-audit obligations.

### Pinned published convergence examples

[The checked fixture](fixtures/convergent-declarations.json) retains the exact
canonical bytes and Git blob IDs of these independently published records,
plus all 30 distinct dependency records used by their two input sets:

- [main-pr225-ci-resolution](https://github.com/actql/actql/blob/7c38d206d8fcc77c66c4edeba1d6fa3b2b86eb85/proofs/relation-pipeline/foundation-declarations/main-pr225-ci-resolution.json): Git blob `2bab7142e7cea72147d2d9bd3e19d16a3354490b`
- [resolve-local-guard-portable-pr-ci](https://github.com/actql/actql/blob/3a32c416ba23821694a1b8c6aac961ba6a4807ea/proofs/relation-pipeline/foundation-declarations/resolve-local-guard-portable-pr-ci.json): Git blob `49cc43f2e1b40e7ad1d96625fc194b1f4c217b31`
- [resolve-main-local-guard-ci-6520c3f59](https://github.com/actql/actql/blob/ad902e348e37b5c28e4429b4152ec456e9640ed8/proofs/relation-pipeline/foundation-declarations/resolve-main-local-guard-ci-6520c3f59.json): Git blob `f7f8f52777cdad190e3fc84fe59e2939e4120fc9`
- [resolve-main-local-guard-ci](https://github.com/actql/actql/blob/b09e8e21cc1ac366db6f4f7157711282c1e5967a/proofs/relation-pipeline/foundation-declarations/resolve-main-local-guard-ci.json): Git blob `20e95385cf3e1092a2c243eca58b9850a1f18fa0`
- [resolve-resident-source-latest-main](https://github.com/actql/actql/blob/b09e8e21cc1ac366db6f4f7157711282c1e5967a/proofs/relation-pipeline/foundation-declarations/resolve-resident-source-latest-main.json): Git blob `decd45cd1187ec7dc8c967de1084e3b0bd3ead5d`

The first four bind source merge
`6520c3f59b86307229536824fac8f8b5ac5450e4`, ordered parents
`398b85c87e0eb29a3d3db0ed21e53ea84464566c` and
`89a7fd00479c70093cb88282ac3d0cb08b7bcda2`, and 16 dependency grounds.
The protected path is `.github/workflows/ci.yml`, mode `100644` throughout.
The independently retrieved parent/result Git blobs are respectively
`60de1fca9c32adeb4507fbc87fd5942ffca6c999`,
`9aa7901c2d3805bb3d23f67dc3ea282c0815eb9c`, and
`4ec9e2cec19a3fb4be1ef6053f9c50de7c50a6a8`; their SHA-256 values match
all four records. Only IDs, rationales and original field order differ.

The fifth binds a different source merge
`3ad450f7996ccb8187de5d3d8e5288a5d4f640ed`, ordered parents
`9a3bb78f43a94ef9435f8daded7c2be76c357958` and
`88fbcc95306abb4fc41f0d488bcc6d38ec19506d`, the `package.json` path
and 15 dependency grounds. It must remain a distinct source-binding group.
Its independently verified parent/result Git blobs are
`ffef535bb30d465dc5cf31f218a01a5373857cad`,
`303047732730743e09a20c77dcd44d5de197c3ab`, and
`53632bbb1662490c14cedb82d85dfc73c968de99`, all mode `100644`.
Its published record is retained on its original branch, without being added
as main's CI-merge declaration.

The fixture test verifies original blob identities and exercises the same
binding descriptor as the composer. Separate temporary real-Git DAG tests
exercise independent validation, each-field tampering, missing declarations,
dependency omissions and inherited declaration deletion. The fixture is a
reproducible record comparison, not a substitute for composing the complete
actual branch histories. In a full checkout, `history.mjs --write` still
validates every real ancestor, original declaration and source blob.


### Completing an omitted source path

An already committed change record can be completed by a later immutable
`actql-foundation-change-completion/0.1` record in the existing supplements
directory. It names the original record and its exact byte digest, and lists
only omitted protected paths from that original source commit. Every added
entry independently matches the original commit's real parents, before/after
bytes and modes. The original remains unchanged and independently checked.

An empty, redundant, overriding, unchanged or foreign path is rejected. The
record must follow the original in Git ancestry. Each individual original's
effective path set must exactly cover its actual source diff; one completed
alias cannot excuse another incomplete alias. Effective paths also participate
in source-binding equality and later merge dependency discovery. The composed
artifact retains raw records and exposes their completed view separately.
Existing resolution-input supplements keep their existing acceptance rules.

## Repairing redundant single-base metadata without rewriting history

An immutable resolution that redundantly records its sole maximal base may be
repaired with an `actql-foundation-single-base-normalization/0.1` record in the
existing supplements directory. Its only fields are `version`, `id`, `target`
(`id` and the original bytes' `digest`) and a nonempty `reason`. The supplement
must follow an introduction of the original declaration. Duplicate repairs
for one target reject.

This does not accept arbitrary single-base metadata. The composer independently
checks that the target is a two-parent resolution with exactly one actual Git
merge base, and that the original `mergeBases` is exactly that singleton. Missing,
empty, wrong, duplicate or multi-base metadata cannot be normalized. All original
source, parent, blob, mode, path and dependency checks still run. The immutable
original and the supplement remain in the generated evidence; only the verified
redundant field is omitted when comparing effective source bindings. Without an
explicit valid supplement the existing refusal remains.
