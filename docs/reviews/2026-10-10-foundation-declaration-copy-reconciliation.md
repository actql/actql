# Exact declaration-copy reconciliation

The integration of #1287 copied one immutable foundation declaration in
`8f1e5e5b8337ef21b666d7f0c768bd748ff81688` without its source ancestry. The
original declaration commit is `4d48f6a6f1380f711ce90aec49dcf8501a0f49b0` and
its supporting resolution is `f4ebdb8bd45861b24b6fd587aba658157ca3ecdf`.
The existing verifier correctly refused this history. Adding ancestry later
alone cannot change that earlier introduction's parents.

The user approved a narrowly recorded copy reconciliation for Draft review.
The immutable declaration and all existing history remain unchanged. #1291,
adopted in main `a66e107a4d511d8ce7a8975612533f2ae30de935`, restores bounded
historical artifact fixtures; it does not repair declaration-copy ancestry.
This change extends the existing foundation composer, with no duplicate replay
consumer or historical artifact compatibility path.

A canonical, closed `actql-foundation-declaration-copy/0.1` supplement names an
exact declaration ID/digest, the original introduction, the copied introduction,
and a later reconciliation merge. Each commit binding includes its ordered
parents and is independently checked against the complete real Git DAG.

Acceptance requires all of the following:

- The supporting source is in the current checkpoint-to-HEAD ancestry. Its
  declaration still passes every ordinary source, mode, maximal-base,
  changed-path and dependency-group check.
- Original and copied introductions are single-parent commits that add only
  this declaration. Their parent trees omit it; their bytes and `100644` mode
  exactly equal the retained current declaration.
- The original introduction follows its actual supporting source. The copied
  introduction does not have that source ancestry.
- Reconciliation has exactly two ordered parents. The second is the exact
  original declaration commit. The first contains the exact copy and does not
  yet contain the original. The complete reconciliation tree equals the first
  parent's tree and the independently recomputed, conflict-free normal merge.
- Every introduction of the supplement follows that reconciliation merge.
  Duplicate reconciliation records are rejected. Only the exact recorded copied
  introduction is reconciled; every other introduction must pass the existing
  source-ancestor check.

The composed report preserves both original and copied introduction SHAs and
includes the independently verified supplement. This is provenance, not human
approval, semantic correctness, fresh execution, or authenticated Actions
proof. The normal merge and any changed protected verifier source still require
their ordinary complete foundation declarations. The supplement cannot waive
those obligations or admit an unmerged source.

The new real-Git fixtures include retained original bytes, missing ancestry,
wrong commits/parents/digest/mode, bundled changes, early records, unrecorded
copies, duplicate records, ordinary unlisted changes, and an `ours` merge that
silently drops an original file. Hosted CI remains stopped; local results are
reported separately in the PR.
