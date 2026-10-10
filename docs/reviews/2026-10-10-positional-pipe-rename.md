# RENAME over positional Pipe input

## Existing requirement and preserved counterexample

Pipe RENAME changes current authored column lookup while retaining values and
positions. Positional set operands do not require unique authored labels.
The current scope and immutable range rules in `docs/spec/query-text.md`
remain authoritative; this repair does not introduce a new language contract.

At baseline `dc875a84a65e4676ca4e7f67f4e90aa07cfc91d7`, this complete source
fails with UnsupportedProjection:

```aql
SELECT 0 AS a, 0 AS b
UNION ALL (
  FROM t |> SELECT x AS kept, -x
  |> RENAME kept AS renamed
)
ORDER BY a, b
```

For input x=1,2, the independent expected rows are (0,0),(1,-1),(2,-2).
Baseline guard `run-64hN80` is 1/3: both positive source tests fail, while the
independently authored ordinary JSON control passes the common checker.
The source is preserved in
`/private/tmp/actql-b-positional-pipe-rename-dc875a84a-baseline.mbt`.
This proves a frontend refusal, not a wrong published Result.

## Minimal connection

Continue the positional-role search through RENAME. Reserve future authored
destinations when allocating the existing anonymous/duplicate private slots:
a user may legitimately name a column `AQL_SET_ANONYMOUS_4`, and it must not
become storage for a different value. Use the existing identifier comparison
and physical-slot allocator rather than banning a namespace prefix.

Use the existing RENAME target and range checks. When a rename introduces
duplicate current labels, assign distinct physical occurrences through the
existing positional duplicate allocator and ordinary select. Current-name
ambiguity checks use the same physical-to-authored correspondence as DROP
and star exclusion. Named receivers remain ambiguous; ordinal access and DROP
of all matching current names remain valid. Original and newly introduced
duplicates cannot be resolved by choosing an arbitrary occurrence.

Anonymous values remain previously evaluated slots. Removed names and old
input ranges are not restored. Do not add an execution owner, fallback,
consumer-side Program patch, wire contract or capacity exemption.

## Independent public obligations

Ten normal cases cover an independently authored complete JSON control,
submitted text, current renamed expression plus WHERE/ORDER/LIMIT with
opposing original values, quoted sequential rename, newly duplicate labels
with ordinal ORDER, destinations resembling both private namespaces,
introduced duplicate removal, nullable values and typed empty output.
Ten refusals cover private and repeated targets, original/new ambiguity,
removed current names, old ranges and the actual private value slots after
reserving an authored destination.

The Values-based JSON control has zero Source reads. Text cases require one
Source acquisition. The existing public consumer compares Named Result
values/order, complete Result.describe column contracts and column order,
hidden-field absence, same-request Run reuse, and zero Run admission/provider
I/O on preparation refusal. It does not alter lowering output.

Both normal and selected packed registration retain all cases. Registration
alone is not execution evidence. Full data-only inventory: 3,494 occurrences,
2,208 normal, 1,239 refusal and 47 execution failures, digest
`f116dc41ac84b16dec63114fef8440eae1a7f8798f3f704ded024577146a5cd3`.
The existing selected cohort has 211 cases per transport (130 normal,
81 refusal).

## Integration and validation

The product repair is preserved in commit `6e2f7657d`. Normal merge
`6fab586765607d5de11a2fff0a1139dd650080a7` adopts main
`bea64a0c5c90d36689aa08fb9f01813daeafb685`, including merged DROP #1307.
Two overlaps from the merged DROP patch preserve the RENAME addition and its
comment; all incoming main contract/identity/generated changes remain intact.
No unmerged parent dependency remains. Final destination is main.

Before that main integration, guard `run-eROlS5` passes 40/40 focused JS
cases across RENAME, DROP, SET, ordinary RENAME scope, positional duplicate
columns, ordinal ORDER/LIMIT and projection helper callers. This is evidence
for that earlier worktree state, not for the later integrated source.
After integration and public fixture registration, `run-k8uq0T` passes 52/52
targeted Node cases (16 fixture and 36 inventory consumer cases).

Integrated focused JS guard `run-mmVC4b` passes the same selected 40/40
cases. Both successful guards have complete output and released locks.
Exact clean-HEAD normal five-package Local/HTTPS execution is pending. Submitted-HEAD required CI is also unverified; keep
the PR Draft. No full Core, all-target, proof, performance, full packed or
Cloud campaign is claimed. The wider frontend objective remains active.
