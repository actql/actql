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
does not start the independent unary branch described above. Identify nonlinear unary Relation dependencies from their receiving edges:
a later external-input root, or an internal Step reference other than the
immediately preceding Step. Preserve the already-supported fused binary JOIN
chain and its two exact capacity obligations. Do not relabel the old test's
task index to conceal unnecessary segmentation.

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

## DATA-local CTE fork and append

At HEAD `1f8c3bee300614bf21f19b9a8e9fb187d3a17fcc`, the unchanged installed
source fixture's first six acquired DATA cases passed in Local, but
`acquired-data-cte-set-shared-producer` failed before Result publication.
The [packed job](https://github.com/actql/actql/actions/runs/37111041058/job/111169708738)
and artifact `11270162302` record that failure. Subsequent cases and HTTP were
not reached. This remains separate from shared CI/history infrastructure.

```aql
DATA copied =
  WITH chosen AS (FROM records |> SELECT amount, id)
  SELECT amount, id FROM chosen
  UNION ALL
  SELECT amount, id FROM chosen;
FROM copied |> ORDER BY id |> RESULT copied_rows
```

The later unary consumer references the same earlier `chosen` step, not its
preceding sibling. Checking only external Input references missed this fork.
Use the same exact checked-edge segmentation for this internal dependency.
Do not expand the producer, reacquire input, deduplicate append rows or change
the authored eight-row expectation in the packed fixture.

The independent machine-Program execution regression uses the existing mock
capture owner once and the existing managed Local provider for every selected
task. Both branch reads preserve `[3,1,2,3]`; append/sort returns
`[1,1,2,2,3,3,3,3]`. Both append ports keep their exact producer identities.
The shared output remains available through both consumers. Cleanup leaves
held bytes, reserved retention and reserved execution at zero. Its four-row
capture retention fixture has independently counted array sizes, 37 bytes /
nine nodes per array; no product ceiling is increased.

A second control replaces the authored append with a JOIN. It verifies the
selected JOIN retains checked step 3, its original 10000-row ceiling, and the
left/right producer ports. Missing, wrong-step and excessive ceilings reject
before callback execution and leave the resource ledger unchanged. The
existing fused multi-JOIN regression retains its original task indices.

## Executed and pending validation

Focused JS checks through `scripts/local-checks.mjs`, with a 90-second budget,
pass **14/14**: four branch/JOIN regressions and all ten existing task-projection
tests. Formatting and diff whitespace pass. This is common-owner execution
and cleanup evidence, not yet installed-source Result publication evidence.
The older 12/12 topology/JOIN result and CTE 1/1 result remain historical.

HEAD `9ab6a7daf2907908c9d04361e6041ed35dbffaae` has successful hosted Core JS
and separated-native checks, but its packed job still fails on this CTE case;
its lint job also found two unformatted assertions. This correction formats
them. Neither that partial CI result nor the prior failed HEAD establishes
final success.

All five Frontend branches normally merged main
`5178253e375fab28e98e2de5f0c13dc644161e4d` without conflicts. Existing history
declarations are retained; workflows match main. Full Core, packed suites,
proof campaigns and performance checks were not repeated locally. The next
push-triggered CI must verify the correction and remaining public obligations;
older successful or failed runs are historical evidence only. Draft status and
unmerged dependency bases remain in place.
