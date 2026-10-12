# ModelTask Decision contracts and physical precision profiles

## Version decision

The reviewed October 11 INFER provider specification explicitly adopts
`actql.model_task/0.2`. This is a coordinated addition, not a blanket advance of
the initial owned-contract baseline. The closed generation-only
`actql.model_task/0.1` schema, canonical bytes, self-CID rule and reader remain
unchanged. Task `version`, private physical-port ABI, external SDK versions and
npm package versions are independent domains.

Invocation evidence and its embedding capture bundle have a separately
approved coordinated revision. Their readers and writers are not migrated by
the Task/Decision contract change. Historical captures retain their original
schema and provenance. Merely admitting a Decision Task grants neither a
provider capability nor execution authority.

| Contract | Existing reader and compatibility boundary |
| --- | --- |
| Task 0.1, generation | `check_environment/model_tasks.mbt` retains exact closed fields, original self-CID and generation meaning. |
| Task 0.2, generation | The same checked input/output and generation contract; the schema discriminator changes its own canonical preimage. |
| Task 0.2, Decision | Checked question/output correspondence, but the installed synchronous physical profile refuses it before Model acquisition. |
| Invocation evidence 0.1 | `model_execution/invocation_evidence.mbt` and the registered `run_publication` admission keep their original body/pin and historical metadata meaning. |
| Embedded capture bundle 0.1 | Existing bounded export, `run_publication/model_capture_bundle.mbt` and verified/partial restore retain original bytes, references and custody. |
| Invocation evidence/capture bundle 0.2 | Separate coherent registration, issuer and replay integration; not silently inferred from the new Task reader. |

Old closed-schema consumers are not taught to reinterpret a new body as 0.1.
The common typed generation accessor now returns an optional value, so physical
consumers explicitly reject a non-generation Task rather than dereferencing
fabricated settings. This source-interface change is distinct from preserving
stored 0.1 artifacts. The only generation-accessor runtime consumer is the
existing Model physical preflight; normal infer preparation and dependency
admission continue through their existing checked owners.

## Common checked correspondence

Both Task revisions retain the common authored model selector, prompt reference,
closed non-null input/output contracts, schema pins, handling restrictions and
existing execution dependencies. Task 0.2 uses `task_kind` as a discriminator:
generation requires `generation_config` and forbids `decision_config`; Decision
requires exactly the native configuration and forbids generation settings.
There is no dummy token cap, seed, temperature or panic-based accessor.

The existing `actql-model-prompt/0.1` envelope binds its unmodified payload. A
Decision payload uses `format: "actql.decision_prompt/0.1"`, `state_input` and
ordered `questions`. Question discriminators are `type`, not `kind`. Boolean
criteria are not part of the initial closed payload. The common checker checks
the selected input field and constructs the output type from the original
questions; exact type equality is checked with the authored output contract.
Existing field-name and value contracts apply without adding JS prototype-name
restrictions. IDs, instructions, Unicode and newlines are not repaired.
Instructions, option descriptions and level descriptions are required Strings;
the empty String is retained, while absence and null are refused separately.
IDs, state-input selectors, type and format remain nonempty.

The answer shape is generic and separate from a physical rounding profile.
Choice/Score distributions preserve original option/level order and require
every member once. Native-required Tasks reject absent/null distributions.
The outer answer contains all and only the admitted question IDs. Boolean
answers are numeric P(true), not booleans or confidence values.

## Initial TypeSafe/Jev physical profile

The initial `actql.decision_probability_profile/0.1` body has profile
`typesafe_jev_2dp`, decimal precision 2, half-unit `d = 0.005`, arithmetic margin
`e = 0.000001`, and scaled-grid margin `0.0000000001`. Its full canonical body
CID is separate from the generic `actql.decision_answers/0.1` identifier.
The registered schema and generated MoonBit helper originate from the same
body; a caller cannot supply a response-controlled tolerance.

After finite range, precision, arity, uniqueness and correspondence checks,
the validator uses ordered finite sums:

```text
abs(sum(p) - 1) <= n*d + e
abs(score - sum(i*p[i])) <= d*sum(i) + d + e
abs(x*100 - nearest_integer(x*100)) <= 1e-10
```

Choice must be one of the actual maximal returned probabilities. Exact ties
are preserved, not broken again. Score uses zero-based level indices. Values
are never normalized or rounded into a new answer. Coefficients exceeding the
exact finite integer domain are refused, not wrapped or clamped. The grid's
nearest integer is used only for validation; it is not returned or adopted.
Other precisions require a separately registered capability/binding profile,
not a different answer shape or an untrusted metadata override.

## Execution boundary

The current synchronous generation profile refuses Decision with the existing
typed `InvalidProvider` before creating a Model Ledger or acquiring an input
use. Physical-plan construction independently refuses a missing generation
configuration. These guards are intentional until the conforming asynchronous
Decision port is connected. Generation retains its original token lower bound.

Dependency admission validates the Decision prompt/output correspondence using
the remaining cumulative work budget after the three dependency envelopes.
Its checked Decision object borrows the original Task and prompt. This is not
an adopted production holding allowance: asynchronous record/response/export
custody still requires the separately reviewed complete retention sum.

Independent literal fixtures cover old/new identities, malformed variants,
question/output mismatch, native distributions, rounded sums, maximal ties,
fractional scores, precision and exact/adjacent tolerance boundaries. Work
expectations are derived from fixed traversal rules, not success measurements.
