# Relation fragment closure audit

This is an implementation handoff, not a new contract or a release approval.
Audited lowering revision: `a02860fe55bb5a02ddbb739dffef0fce098b3eef`.
Main inspected read-only: `7069330542308ee5c75dd2efbf092c4300bb135f`.
Main's uncommitted `check_environment` work was not imported or modified.

## What the current success proves

`PreparedSequence` retains one checked/bound owner. Its four handlers emit
individual AoA steps and run through one component driver. All prepared operations
execute, including unretained branches and no-ops. A `CompletedSequence` is issued
only after that driver finishes. Producer bindings check the expected bound
invocation and target; receiving projection and cumulative accounting now execute.

This success is not complete expression-fragment admission. In particular,
`emit_sequence_steps` does not emit the sealed expression fragment required by
[the common expression contract](../spec/language.md#common-expression-contract).
Neither the step array nor the private prepared kernels may be relabelled as that
artifact. Likewise, a matching registry hash is not proof that every expression
root, limit witness or input evidence has been admitted.

## Remaining work and ownership

| Requirement | Existing evidence | Remaining work / owner |
| --- | --- | --- |
| Registered four primitive signatures | Selected registry contains `REL.values`, `REL.derive`, `REL.where`, `REL.select`; runtime hashes its actual body | Retain this check; it does not establish the outer expression binding |
| Executable expression binding | `actql-expressions.json#/schemas/fragment` exists; Language specifies `ACTQL.expression_fragment/0.1` with exactly `{fragment}` | Main/integration supplies its selected registration and contract dependency pins, or points to the authoritative alternative registration mechanism |
| Bound expression roots | Prepared nodes retain checked expressions, sources and contracts; inline expression encoding is implemented | Lowering builds canonical root positions/order and demand paths, and binds them to the same emitted graph; no source retyping |
| Fragment request and re-admission | Normative request, root and limit-witness schemas exist | Connect canonical checked source, schemas, typed parameters, request ceilings and exact regeneration comparison. Shared API gaps go to main; do not invent request data or capacity evidence |
| Ordered derive | Input/prior-slot references exist; preparation reports `NeedsSharedRowKernelContract` | Main finalizes the [row-kernel handoff](row-kernel-integration-request.md); lowering then implements row-major slots and shadowing |
| Supplied input obligations | Shape/canonical-value capture and candidate-key validation run; raw captures cannot impersonate completed producers | Audit all retained evidence axes before a fragment claims them as established; component success alone cannot authenticate ranking declarations or computed witnesses |
| Producer dependencies | Exact owner/binding/target checks, projection, fresh receiving budgets and immutable retry are tested | Preserve dependency obligations as well as successful computation; do not treat arbitrary checked metadata as successful execution evidence |
| Runtime ceilings | Shared control and logical-value budgets, operation workspace, retained table slots | Connect the normative per-value byte ceilings and limit witnesses, and audit intermediate root values before exposing the fragment entry |
| Typed fragment API | All component execution remains package-private | Expose the agreed internal entry only when the above obligations are represented and enforced; not a public SDK/Run API |

The goal still includes ordered derive and the admitted typed fragment entry.
It must not be reduced to the passing private four-operation driver. Conversely,
Program/Invocation/Run construction, global capacity completion, Effects and Host
authorization remain outside this delivery.

## Precise shared registry handoff

Both inspected branches select
`sha256:b97a22de3664c1dafe3bc1e6791f1f8bcfb70324a1fcc1087450fe057e0f2311`
from `spec/dependencies/aoa-pipeline-registry.json`. That body registers
`REL.derive`, but not `ACTQL.expression_fragment/0.1`. The existing REL.values
registration is valid and must not be undone.

Main/integration should resolve the outer binding separately from the ordered
derive parameter extension:

1. Identify the registry entry or normative capability mechanism for the outer
   expression-fragment operation, with its one-Relation-input/output signature.
2. Bind the existing closed `{fragment}` parameter contract and its dependency
   identities. Do not replace the existing expression fragment with a new format.
3. Supply selected registry/pin updates and positive/negative registration vectors.
4. Confirm the ordered row-kernel's root positions and reference bindings under
   that expression binding, including empty map versus nonempty ordered array.

Lowering must not independently update shared schemas or pins. Preparation of
root metadata and pure execution can continue while the handoff is pending;
registration absence must not be converted into a permanent language restriction.

## Input evidence audit follow-up

`pipeline_typing.InputContract` accepts more than raw carrier declarations:
candidate keys, ranking metadata, combined evidence and completed-producer
descriptions can reach it. `combine_relation_evidence` explicitly says that it
does not discharge validation obligations. The current driver validates captured
keys and distinguishes actual completed producers, but has no complete evidence
admission for all other axes.

Do not solve this by rejecting every otherwise valid select/filter over a ranking
Relation, nor by implementing ranking fusion outside the agreed scope. Distinguish
the computation's completed status from inherited unresolved obligations. The
fragment entry must either discharge a required obligation using authoritative
evidence or return a specific pending condition; it cannot silently turn retained
declarations into verified producer facts. Tests should distinguish plain rows,
declared metadata and actual completed producer results with identical row values.

## Verification scope

Full-repository tests pass 2,184/2,184 on each of JS, Wasm and native at the audited
implementation revision. The two independent registry checks and all 872 local
document links pass. Existing private-component unused warnings remain; Linux CI
was not run. Green tests establish the currently implemented behavior, not the
missing contracts or fragment admission.
No shared source, schema, pin, CLI, Run or Host implementation is changed here.
