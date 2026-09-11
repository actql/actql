# Relation fragment closure audit

This is an implementation handoff, not a new contract or a release approval.
Audited lowering revision: `a02860fe55bb5a02ddbb739dffef0fce098b3eef`.
Main inspected read-only: `7069330542308ee5c75dd2efbf092c4300bb135f`.
Main's uncommitted `check_environment` work was not imported or modified.
The root-position row below includes the subsequent implementation increment;
the original audit's full-suite totals do not certify that later change.

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
| Bound expression roots | Prepared nodes retain checked expressions, sources and contracts; inline encoding and a sequence-owned root-position index are implemented | Lowering connects canonical source and demand paths to those same graph expressions; no source retyping |
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

## Shared demand/topology handoff discovered after the audit

Before implementing semantic source pointers, inspection of main found these
already committed APIs:

- `41227eb3b788f56a9bf30a0af463514baaf37b97`: immutable typed expression topology.
- `e836078fb3fe3447c347dad073ce37628045971f`: `derive_demands`, `demand_pointer`,
  `demand_tests`, owning `TypedExpression` and measured usage.
- `41971a7bfd1a2290626906ee4642ed2241c84363`: indexed pending-validation access.

The shared demand implementation already derives normalized source addresses,
shares conditional prefixes and deliberately returns no source pointer for an
implicit CASE ELSE. Lowering must consume it rather than continue its parallel
rule implementation in `lowering_relation/demand.mbt`. The latter is an interim
implementation, not a second semantic authority or the final fragment path.
Its fixed independent expectations remain useful when replacing it with a shared
API adapter.

These commits also modify `pipeline_check_context`, which does not exist at this
lowering baseline and whose main version is over 6,000 lines. Blind cherry-picking
them, or importing that entire context subsystem just to obtain demand paths,
would cross the agreed integration ownership boundary. No such import was made.

Requested main/integration handoff: a package-scoped commit (or explicitly
designated dependency sequence) providing the existing `expression_typing`
topology, indexed obligations and demand APIs, their tests and documentation,
without requiring unrelated Program/context integration. These are existing
implementations, not a request to redesign their semantics. Decode's exported
`PathSegment` alias is already present in the lowering baseline.

The standalone handoff `06742b9` is now imported as `df75931`. Lowering's
duplicate demand rules have been removed: its root-scoped adapter consumes the
exact typed owner and accumulates shared work/text/link budgets. The independent
conditional and ownership vectors are retained using semantic source pointers.
Implicit ELSE remains source-less. Final envelope source-prefix binding remains
open; this handoff does not constitute fragment admission.

The integration checklist is:

1. Retain the exact `TypedExpression` and root/binding ownership used to lower
   each root, and associate lowered occurrences with shared typed node indices.
2. Derive demands through the shared API with one cumulative budget across roots.
3. Prefix its source-relative pointers with `/roots/i/source`; preserve the
   absence of an implicit ELSE source occurrence rather than invent a pointer.
4. Retire the duplicate conditional rules and rerun the independent IF/CASE/
   coalesce/eager-boolean/literal/budget vectors against the adapter.

This handoff is separate from outer registry registration and ordered derive.
Do not add a temporary replacement opcode, source reparser or placeholder API
to bypass it. Shared files and main's uncommitted work remain untouched.

## Input evidence audit follow-up (details)

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

### Subsequent shared-contract imports: dependency closure still open

`0616d2b` is imported as `9bf67ab` (outer registration), and `6261c39`
as `c1d3bde` (empty snapshot derive evidence). Conflicts in generated document
identities were resolved by regenerating from this branch's actual specification,
not by importing unrelated main changes. The latter's package script was composed
with this branch's existing checks, without adding unavailable main-only tools.

The selected registry now has CID
`sha256:23a7f1081d1a2cdab7b20e425dddce846510355ba964058e0c809350fae33816`.
Lowering's four primitive consumers use this exact body; historical 57/58-entry
bodies and fixed hashes remain distinct. This does not admit the outer fragment.

**Unresolved handoff dependency:** the imported outer contract pins the full
expression body at
`sha256:2587ba927c08a797960ef083be3cf32cef56ce478c88df2cb12bcb306ba865e1`,
but the expression body on this branch hashes to
`sha256:aa85f7d3bbb42d890de47dcec6f3f2993fc232df3575012a114951ee7d40dbf7`.
The missing changes originate in `299be0f` (regex scalar AST contract dependency)
and `995fdf2` (text input evidence preimages). Those commits also change shared
checking/specification material beyond the handed-off capsule. Main/integration
must provide the exact dependency closure, including its schema/pins/vectors,
as an importable unit. Do not repin the outer contract to the older local body,
invent a new registry CID, or treat registration as backend support.

The new registration Node tests expose two failures from this dependency mismatch;
`check:docs` stops at the registration contract check. The derive evidence tests
and lowering registry tests pass. Ordered derive's executable row-kernel remains
a separate outstanding contract, including limits identity and measurement units.

After refreshing the primitive consumer's generated registry body/pin and its
independent selected-CID assertion, JS/Wasm/native each pass 2,200/2,200. The
initial run's single stale selected-CID assertion per target is fixed, not waived.
API equality, changed-package format, vector freshness, 873 links, 19 examples,
11 document tests and metadata checks pass. These results do not close the two
registration tests above; `check:docs` remains failing. Linux CI and global
`--deny-warn` success are not claimed.

Full-repository tests pass 2,184/2,184 on each of JS, Wasm and native at the audited
implementation revision. The two independent registry checks and all 872 local
document links pass. Existing private-component unused warnings remain; Linux CI
was not run. Green tests establish the currently implemented behavior, not the
missing contracts or fragment admission.
No shared source, schema, pin, CLI, Run or Host implementation is changed here.
