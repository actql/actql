# Pipeline workspace prefix checks

The current pipeline already isolates healthy/mutated build trees and keeps its
parameterized compiled fixture stable across targets. This change does not
reimplement those mechanisms or skip any observations.

`workspaceIdentity().check()` previously inspected a common ancestor separately
for every inventoried file. It now inspects each unique prefix once within that
call. The set is discarded when the call returns. Source bytes are still read
and hashed on every call; recursive source/build link rejection, workspace/build
inode custody, source restoration and pristine comparisons remain unchanged.
This remains a synchronous filesystem inspection, not an atomic filesystem
snapshot or a guarantee against arbitrary concurrent external changes.

The new regression adds/removes an inventoried source member, then replaces
`scripts` and `docs/spec` ancestors with links after successful checks. Every
later call detects the change; no Moon invocation is made for rejected inputs.
Existing executor and mutation lifecycle tests retain stale-binary rejection,
fresh three-target observations, exact source restoration, a distinct restoration
owner and failure/cleanup custody. Their compiler process is a controlled fixture;
they are not a physical Moon/compiler campaign.

## Limited local measurement

The [raw paired record](evidence/2026-10-06-pipeline-workspace-profile.json) uses
baseline `25f132c9da9c9e2bc1690097b6add335d300986b` and candidate
`78ce1df54c1473dd0021f39edda9bd1da81503f7`. Both actual implementations inspected
the same 4,695-file candidate filesystem in one Node 22.23.2 process on macOS
arm64. Only the baseline's two relative imports were relocated; their dependency
bytes were unchanged. There were two warm-ups per implementation and nine
preselected alternating-order pairs. No favorable samples were discarded or
added. Syscall instrumentation ran separately from the timed observations.

- `lstatSync` calls per check: **20,259 -> 9,925** (10,334 fewer).
- Mean check duration: **374.74 -> 357.19 ms**, a 17.55 ms observed difference.
- Six of nine pairs favored the change. The descriptive paired t interval
  (8 degrees of freedom) is **-18.36 to 53.45 ms**; this small local sample does
  **not** establish a reliable elapsed-time improvement.

The filesystem-call reduction is established for this inventory. Whole-campaign
and hosted runner savings remain unknown. Compiler/build/hash/artifact costs and
cross-revision reuse are not measured here. The original evidence has
`reuseAuthorized: false` and `netRunnerSavings: null`.

The [read-only reproduction script](evidence/2026-10-06-pipeline-workspace-profile.mjs)
accepts the repository root, the baseline SHA and a new output JSON path. Run it
through the existing bounded `runLocalCheck` supervisor with a 60-second budget;
do not run competing builds or edit the worktree while measuring. Source digests
will differ when later inventoried files change, so retain each record at its
actual candidate revision.

The production source and regression are bound to their exact parent/blob/mode
by `foundation-declarations/pipeline-workspace-prefix-checks.json`. Historical
records are unchanged. No workflow, selector, reuse scope, acceptance obligation
or runtime product code is changed.
