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

## Current validation reference and trust boundary

The source correction is committed first. A separate commit adds
`current-foundation.json`, referring to that exact correction revision rather
than trying to put a commit's own hash into its source. The record is a proposed
common-foundation change reviewed with #149. It does not assert human approval.
Git provenance and SHA-256 identity alone do not prove review or correctness;
the committed record and validator are explicitly reviewable trust inputs.

`checkFoundation()` checks:

- The historical baseline exists and is byte-identical to its fixed #148 Git
  revision; all 57 historical common digests still match their original pinned
  corrected foundation revision
- The current record exists and equals its committed HEAD blob, and its current
  reference is an ancestor of HEAD with the exact historical baseline identity
- Every historical common file matches the current reference's Git blob and
  actual working-tree bytes; the exact changed-common set has unique, known
  paths, matching old/new hashes and an explanatory reason
- All five explicitly listed supplementary files match their reference blobs
  and working-tree bytes; omitted, duplicate or changed entries fail

Reasons are explanatory and cannot relax checks. No missing-file fallback,
blanket hash refresh, unlisted-file exception or mutable branch name is accepted.
HEAD equality rejects an uncommitted record edit; it is not a cryptographic
approval mechanism. Any later common correction requires a separately reviewed
source commit, explicit record update and fresh current-source validation.

The early Node test phase runs the real repository foundation check before the
expensive pipeline job. Synthetic failure cases exercise missing history/records,
baseline edits, unlisted changes, incorrect hashes, CI edits, record/source
co-tampering, omitted supplementary files and invalid ancestry. They do not
replace the real Git-object and current-file audit.

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
