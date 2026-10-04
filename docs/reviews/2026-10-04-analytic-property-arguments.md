# Property arguments in existing analytic navigation and frame calls

## Scope and fixed baseline

This independent branch starts at main
`7e32faa5a455dc4beafa02a8cd06313e83772d50`, including #388's Draft CI policy.
There is no unmerged code dependency. It repairs one Frontend boundary:
`lower_analytic_call` used scalar-only expression lowering for the first
argument of `LAG`, `LEAD`, `FIRST_VALUE` and `LAST_VALUE`, although the common
Expression and analytic contracts already admit nullable object properties.

The [adopted query scope](../spec/query-text.md#scope-and-lowering) resolves
SELECT siblings and analytic arguments against the input snapshot. The
[common analytic contract](../spec/language.md#analytic) retains navigation's
argument domain with nullable output and evaluates first/last value within
explicit ROWS frames, respecting NULL values. Window order determines the
calculation and does not itself order a public Result. The first profile's
frame/offset restrictions and required deterministic position evidence remain.

## Independent counterexample and repair

```sql
SELECT id, LAG(payload.score) OVER (ORDER BY id) AS previous
FROM objects
```

The [complete handwritten Program](../../src/query_program/analytic_property_arguments_test.mbt)
contains Values, one ordinary analytic operation with a structured property
argument, and a final projection. Its ordinary checker acceptance succeeds.
Both SQL and equivalent Pipe lowering fail at the scalar reference boundary
before repair: baseline **1/3**, `run-aBhb6C` / `focused-test-lWWgJ1`.
Neither the expected Program nor the result expectations come from compiler
or provider output.

The repair changes only the argument's expression entry to
`append_with_properties`. Existing longest-prefix scope resolution supplies
the receiver slot; the common checker validates object members and nullable
propagation. Evaluation remains inside the common analytic call. No eager
derive, sibling-alias expansion, copied evaluator or extra physical boundary
is introduced. Frame aggregates, partition/order-key expressions, ON keys,
CTE capture, assertions, Effect and acquisition are separate boundaries.
Checker, planner, provider, Host, SDK, wire, grammar and saved data are unchanged.

The focused regressions cover SQL/Pipe full-Program equality, quoted/qualified
arguments, all four functions, computed properties, input-versus-output aliases,
Pipe SET's current receiver and retained range snapshot, exact stale/unknown
reference refusals, existing frame/offset refusals, common rejection of missing
members/scalar receivers, and the existing expression work limit.

## Public acceptance obligations

The [public fixture](../../scripts/fixtures/analytic-property-source-input.mjs)
contains ten positives (one handwritten JSON control and nine source cases) and
seven preparation refusals. Input order is 2,1,3; the explicit final ID sort
produces 1,2,3. Payload scores in analytic ID order are 20,10,NULL, so LAG must
return NULL,20,10 and LEAD must return 10,NULL,NULL. Selecting another object as
`payload` must not rebind that SELECT's analytic argument. After Pipe SET,
the old range receiver still gives original scores while offset-zero navigation
of the current receiver gives 5,30,15. Frame values, arithmetic, a typed zero
offset, a nullable member and empty typed output have independent expectations.

The usual harness compares Named rows, full ordered `Result.describe()` column
contracts, NULLs, internal-column exclusion and completed streams. Resend,
lookup and attach must return the same Run without additional acquisition.
Refusals retain existing typed public input errors, zero durable Run admissions
and zero provider I/O. The cases run in the normal packed corpus; the focused
`--analytic-property-only` flag only limits local selection. It does not bypass
normal pack, clean-source, digest or publication checks, and no generated Program
is patched in the test.

## Executed checks

New focused JS tests pass **9/9** (`run-6V6eUq`, `focused-test-JTDWyC`). Existing
OVER callers pass **3/3** (`run-VWa3F0`, `focused-test-X3Pq87`). A test diagnostic
pattern initially used Issue where the API returns Diagnostic and was corrected
before submission. The SET assertion's private index was corrected to the
three-column input's existing naming rule; public values and expected Program
did not change. These intermediate failures are not execution passes.

Formatting, three changed Node syntax checks and `git diff --check` passed.
These tests verify lowering and the ordinary checker under the independently
authored test environment. That environment includes analytic capacity policy;
its acceptance does not establish support in the standard Host's installed policy.

One clean normal-pack run used source
`60df510d171e815ff7e2878707736aad41837b47`, recorded as
`public-query-evidence-wEuzDW`. Its preliminary README Local/HTTPS controls passed.
The analytic selection then stopped at the **first independent JSON control**:
public submit returned `SubmissionUnknown`, caused by `ClientHostFailure` with
HTTP status 500. No analytic positive completed. The nine text positives, seven
refusals and analytic HTTP selection were not reached. In particular, no public
zero-admission/provider-I/O assertion is claimed from that ambiguous response.
Command 012's stdout/stderr, exit status and elapsed time, source identity and
digests are retained in that receipt; its temporary installation was removed
after evidence preservation. No additional packed run was made after this failure.

| Package | Tarball SHA-256 |
|---|---|
| client-wire | `52fe3218df346cfb9dae0adc248071563fe68918bded16f8d733415e65584fc0` |
| sdk | `f81bf27c3bb42a007bc16b6f89a15542a89c7fb844e2893870d1161a8e8abc6d` |
| run-host-core | `65b6408c2bb93597b8c92fc424b010b5e1d3e8b75ba414ad006bd30d57999a86` |
| local-node | `3940ec557abfde9eab64d0586ca0d8f1d4f5f225b53a3130ea64db78dd96263b` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

## Standard Host policy boundary and handoff

The private JS bridge built from the same product source identifies a separate
ordinary-checker blocker with the repository base environment: all ten positive
fixtures return `check_unclassified`, with
`LocalConstructionFailure.Closure(ConstructionFailure.UnresolvedOperation)` and
requirement `AnalyticEnvelope`. The independent JSON's occurrence is stage 0,
step 1, group 0, index 3. This is preparation diagnosis, not public execution
or a trace of the private cause inside the pristine packed Host.

The [scalar-only handwritten control](../../scripts/fixtures/analytic-envelope.repro.program.json)
also returns the same code and occurrence. It contains one Values row `{id: 1}`
and `LAG(id)`, with **no object/property expression or Frontend involvement**.
Its independently required Named `answer` is `[{id: 1, previous: null}]` with
columns `id` (nonnullable number), then `previous` (nullable number). This keeps
the profile omission separate from the repaired property lowering.

The [common envelope resolver](../../src/pipeline_check_context/analytic_envelope.mbt)
intentionally returns unresolved when any required ceiling is absent. The
[standard base policy](../../spec/local-check-environment.json) and its
[Embedded installation](../../adapters/host-node/embedded-local.mjs) omit:

- `max_analytic_input_wire_bytes`
- `max_analytic_output_wire_bytes`
- `max_analytic_partition_wire_bytes`
- `max_analytic_frame_memberships`

`max_relation_output_rows` is present. The public acceptance application reuses
that base Host policy; Embedded adds Graph construction ceilings, not analytic
ones. The test-only checker policy already has all four analytic ceilings.
Absence is not zero usage or permission to choose implicit defaults.

The standard Host/profile connection belongs with the shared integration owner;
questions about analytic enforcement belong with the common analytic owner.
Those boundaries need an explicit installed policy and its ordinary closure,
capacity enforcement and refusal tests. B does not insert test-only ceilings,
remove `AnalyticEnvelope`, drop OVER, copy an evaluator or weaken public rows.
The 500/error-classification boundary also needs to preserve deterministic input
failure versus genuinely unknown submission; this PR does not change SDK or
diagnostic owners. No common-owner repair SHA has been adopted here.

To reproduce without another packed campaign, use this source's normally built
JS bridge. Import `connectors_builtin_node.js` from the JS release build, create
the environment with `clientProgramCheckEnvironment` using
`spec/local-check-environment.json` and flags
`false, false, true, true, false, false, false`, then call
`clientProgramPrepareEffectFreeWithParameters` with the saved control, format
`json` and no parameters. `clientProgramPreparationReady` is absent;
`clientProgramPreparationIssueCode` is `check_unclassified` and
`clientProgramPreparationIssue` holds the occurrence above. This performs no
provider I/O and is not a replacement public route. The base-environment
diagnostic does not install the standard Host's numeric/property-graph profiles.

After the shared policy connection, resume all ten positives and seven refusals
through the existing focused command:
`node scripts/test-packed-public-query.mjs --analytic-property-only`.
Run normal pack from the fixed integrated source and keep the authored rows,
full ordered type contracts, reuse checks and zero-admission/I/O refusals.
Do not change the fixture to accept a preparation failure as success.

Submitted-HEAD CI remains unverified. Full Core, all targets, native, proof,
performance and a Google service differential run are not local checks for this
unit. This Frontend implementation and focused checker evidence are separate
from **incomplete public Local/HTTP acceptance**. Keep the PR Draft; Draft
preparation is not merge validation, and `awaiting ready_for_review` is not a
rerun request. No merge is performed.
