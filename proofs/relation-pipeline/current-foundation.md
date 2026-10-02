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
any parent must survive byte-identically. A declaration has exactly one
introduction, strictly after its supporting source commit. Correct an
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

Two-parent merges require a unique Git merge base. For each protected path:

- When neither side changed it, the committed result must match that file
- When exactly one side changed it, the result must match that side
- When both sides changed it, retain both declarations and add an explicit
  resolution, even if a textual merge was clean or both sides reached equal bytes
- Any other result, including dropping one side with an `ours` merge, requires
  an explicit resolution

For example, branches adding different test registrations to `package.json`
retain their separate declarations. Resolve the actual source so both commands
remain, commit the merge, then add a new `kind: "resolution"` declaration. Its
`parents` lists both actual parents in Git order; each `before` lists both
parent identities; `afterDigest` pins the actual merged file. The rationale
explains the integration. Its additional `inputs` field is the sorted list of
all earlier declarations touching any resolved path and reachable through
either parent, including original changes, reverts and prior resolutions.
The validator derives this complete input set itself and requires exact equality.
Other paths composed from one side do not need to be repeated in the resolution.

A resolution records reviewed source provenance; it does not establish that
both test commands are semantically correct or that a reviewer approved them.
The real-Git integration fixtures assert both independent registrations and
rationales survive in the actual merged file. The normal source review and
required pipeline tests remain necessary.

Different-file merges require no resolution declaration or aggregate edit.
For older branches, composition uses their actual old common-base blobs. If
both the checkpoint/main side and the branch changed a protected file, the
explicit resolution pins the integrated bytes while the immutable checkpoint
retains the earlier rationale. It never substitutes old branch bytes for a
newer checkpoint file without that resolution.
Octopus merges, multiple merge bases, unrelated histories, protected-file
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
