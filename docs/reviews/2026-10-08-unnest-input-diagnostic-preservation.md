# UNNEST input diagnostic preservation

## Boundary and counterexample

Baseline: `4b3eca05227e03cb68a3cfa78881f89db1b4735d`, after #984/#985.
The existing external five-package parameter-UNNEST campaign passed its ten
Local successes, then failed at the undeclared-parameter refusal with
`ClientProgramImplementationLimit`. HTTPS was not reached. Evidence:
`worktrees/.codex-scratch/public-query-evidence-l7ZBiu/summary.json` and
`010.stderr.log`; serialized attempt `run-hwRtpx`. This failed campaign is
retained, not relabeled as successful execution.

Minimal source, with no declaration of `missing`:

```sql
SELECT element.* FROM UNNEST(@missing.nested.items) element
```

`unnest_source_element` lowers the receiver and invokes the ordinary expression
checker to establish the visible star fields. It discarded the checker's
`UnknownParameter`/`UnknownField`/`TypeMismatch` errors. No completed Program
could reach ordinary checking: star expansion failed first with
`UnsupportedProjection`. This is a Frontend error-loss boundary, not a missing
UNNEST executor or a reason to allow implementation-limit refusals in this fixture.

## Correction

- Preserve the common `expression_typing.Issue` in
  `query_program.Issue::ExpressionTyping`, including its original source cursor
  and location. Do not introduce another type checker or sample bound values.
- A known non-ARRAY receiver retains the existing authored `InvalidArguments`
  diagnostic. Correlated Relation references continue through the existing row
  resolver. Untyped empty/NULL arrays retain their existing unsupported scope;
  this change does not invent an item type.
- Keep expression work/limit classification and normal checker/Host ownership.
  The existing preparation classification treats proven typing failures as input
  violations. Its public check projection uses existing violation/undeclared
  parameter findings; private cursors are not exposed as generated SQL locations.
- E boundary: the newly retained common Issue supplies its exact kind and source
  location for any later precise diagnostic projection. This PR adds no wire,
  SDK, report-schema or diagnostic vocabulary. An undeclared parameter's exact
  `submitted.sql` byte span `[29,37)` is independently asserted internally.
- Pin the three source-type refusals to `ClientProgramInvalidInput`; preserve all
  five existing refusals and ten successes, independent JSON Program, expected
  values, NULLs, duplicate offsets, column contracts/order and execution bounds.

## Limited evidence before integration

- Red counterexample: **0/1 JS**, `run-SmYFNU`,
  `focused-test-G9WhKu`. It failed specifically because the undeclared parameter
  became `UnsupportedProjection`; the test was subsequently strengthened to
  exact common typing causes.
- Corrected boundary/callers: **19/19 JS**, `run-pNwteJ`,
  `focused-test-0mluDG`. Selection: new input diagnostics, parameter paths,
  checked ARRAYs, source UNNEST, STRUCT stars and Host preparation classification.
- Existing correlated UNNEST independent Programs: **6/6 JS**, `run-vFk56C`,
  `focused-test-76gyHy`.
- Fixture/exact refusal and admission controls: **8/8 Node**, `run-6SWoZV`,
  `focused-test-EJHD8j`.
- Selected interface regenerated using pinned
  `moon info --target js src/query_program`; owned files formatted with pinned
  direct `moonfmt`; `git diff --check` passed.

Commands use `scripts/local-checks.mjs test moon|node` with explicit JS/file
selections and 120/180-second limits. These are working-tree results, not CI
success or exact post-integration HEAD evidence.

## Separate successful public frame evidence

The unchanged frame cohort at the baseline completed packed Embedded Local and
real HTTPS: **8 successes / 14 preparation refusals per transport**, including
the four exact invalid-frame source/JSON controls. Evidence:
`worktrees/.codex-scratch/public-query-evidence-glclKq/summary.json`, complete,
passed, no evidence errors; transient installations were removed after evidence
retention. Its full row/schema/order/replay obligations remain intact.

## Remaining verification

Normally merged main `2a77b066ad2ab56278fe657ad07487e7b84688f7` without
conflicts. At clean integration revision
`41d76fa44969e5eff117414ca0da26cf924fb162`, the changed type-diagnostic,
parameter-path and Host-preparation controls passed **9/9 JS**, `run-BRWp9N`,
`focused-test-XkfIb3`. This revision precedes the final direct-file formatting
and evidence-record commit; do not relabel it as final-HEAD CI.

The integrated normal producer/public consumer attempt `run-0ACR5w` was
refused by the heavy guard before any step began. The other owner's PID 85548
had a matching live cwd in `actql-local-native-performance-profile`; its lock
was not altered. This attempt has no package-generation or execution result.

After ordinary main integration, generate the normal five packages from a clean
fixed revision, retain the original manifest and independently verify every
digest. Run the entire existing parameter-UNNEST cohort on Local and real HTTPS,
without excluding refusals or patching the generated Program. Require independent
rows/full Result.describe contracts, completed streams, repeat-request identity,
and zero Run admission/provider I/O for preparation refusals. Until then this
correction has limited evidence only. Full Core, Wasm/Native execution,
three-target API checks and submitted-HEAD CI are not established here.
