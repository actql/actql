# Acquired DATA branch dispatch

## Failure evidence

PR #242 HEAD `2a137155d38a3422fc1c74d25c1f43a2284c970a` failed its
[push-triggered packed job](https://github.com/actql/actql/actions/runs/37109158518/job/111164192416).
The tested merge revision was `402cba6129bf89dbfff14da499cb6d52d71ab150`.
The first acquired DATA source succeeded; the second, below, ended with
`ACTQL_E_UNPUBLISHED_RUN` before publication. Later acquired inputs and their
HTTP counterparts were not reached. This is a product execution failure,
separate from the shared CI selector and history repairs in #241/#243.

```aql
DATA selected = FROM records |> WHERE amount >= 20 |> SELECT id;
DATA complete = FROM records |> SELECT amount, id;
FROM complete |> ORDER BY id |> RESULT all_rows
```

Independent input: `[{"id":3,"amount":30},{"id":1,"amount":null},
{"id":2,"amount":20},{"id":3,"amount":30}]`.
Expected rows, with declared column order `amount, id`:
`[{"amount":null,"id":1},{"amount":20,"id":2},
{"amount":30,"id":3},{"amount":30,"id":3}]`.
The source must be captured once. The narrowed branch cannot replace the
complete captured input, and duplicate rows must survive.

The single failing source was reproduced using the exact CI packages from
[artifact 11268834186](https://github.com/actql/actql/actions/runs/37109158518/artifacts/11268834186),
after verifying the manifest's package digests. No local runtime rebuild was
used for that reproduction. Separate diagnostic copies exposed
`Dispatch(Dispatch(Implementation(ForeignCandidate)))`; the Local issue before
the bridge's generic projection was
`Preparation(Materializing(Candidate(ComputeUnsupported)))`.
Diagnostic package copies are not pristine distribution evidence.

## Correction

The consumer Stage contains two branches reading the same retained input.
Its whole sequence is not a linear bounded-provider shape. Extend the existing
physical task segmentation to select those checked Relation steps only when
every external operation port has an exact retained Relation predecessor and
supports the existing managed Relation view. Keep the acquisition task and
original checked owner unchanged. Do not add an execution lane, reacquire the
source, remove the unused declaration or loosen capacity admission.

[The independent machine Program regression](../../src/query_integration/acquired_relation_branch_wbtest.mbt)
checks the single captured prefix, selected step coordinates, owner identity,
the branch's exact input edges, complete port mapping and the task limit.
The existing packed source fixture and its expected rows remain unchanged.

## Unary branch versus a binary JOIN

HEAD `1f8c3bee300614bf21f19b9a8e9fb187d3a17fcc` exposed an over-broad
segmentation condition in [native CI](https://github.com/actql/actql/actions/runs/37111041058/job/111168940065).
`task_projection_wbtest.mbt`'s existing JOIN ceiling test failed while reading
the two input ports of its fused task. A binary JOIN's repeated peer input
does not start the independent unary branch described above. Limit the new
condition to a later unary operation reading an external retained input;
preserve the already-supported fused binary JOIN chain and its two exact
capacity obligations. Do not relabel the old test's task index to conceal the
unnecessary segmentation.

The existing JOIN failure was reproduced as one focused JS test before the
correction. Afterward, the new branch test and binary JOIN topology control,
together with all ten existing task-projection tests, pass **12/12** through
`local-checks` with a 90-second budget. They cover exact owners/ports, multiple
JOIN and aggregate ceilings, start rejection without spending an attempt,
sort/take execution and failure. This remains distinct from the pending
installed-source Result acceptance. No native suite or packed suite was
repeated locally.

The former CTE fixture also expected a nonrecursive body to reject an existing
outer producer with its future CTE name. Update that expectation to checked
success, and retain an independent rejection case with no outer producer.

## Executed and pending validation

Focused JS checks through `scripts/local-checks.mjs`, each with a 90-second
budget, passed: CTE shadow/recursive regression 1/1; captured Relation branch
topology regression 1/1. Changed MoonBit formatting and diff whitespace pass.
The topology regression does not establish successful Result publication.

All five Frontend branches normally merged main
`5178253e375fab28e98e2de5f0c13dc644161e4d` without conflicts. Existing history
declarations are retained; workflows match main. Full Core, packed suites,
proof campaigns and performance checks were not repeated locally. The next
push-triggered CI must verify the correction and remaining public obligations;
older successful or failed runs are historical evidence only. Draft status and
unmerged dependency bases remain in place.
