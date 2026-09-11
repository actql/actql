# Relation lowering implementation

## Scope and decisions

Work is isolated on `work/lowering-rel`, based on `92b9d45`. The first delivery
is values, derive, filter and select, with field/literal/bound-parameter,
arithmetic, comparison, boolean and conditional expressions. This is a minimum
delivery, not an authoring allowlist. Additional expressions that the common
implementation correctly supports need not be rejected merely for being outside
that minimum.

The implementation consumes public checked APIs. It must not reparse source,
infer types or order independently, or recursively replace parameter-looking
business data. Retained checked payloads are preparation metadata, not another
semantic IR. Executable computation must use the normative AoA representation.

These packages are intended as production building blocks. There is no separate
test evaluator, arbitrary-AoA-JSON execute API, public SDK export, or Program
execution authorization in this increment. Explicit supplied relations and
existing validated parameter bindings are in scope; Connector acquisition is not.

Host authorization, Checkpoints, durable Runs, Effects, Result publication,
final Plan identity, static capacity completion and DuckDB dispatch remain out
of scope. Local physical limits do not become language restrictions. Runtime
limits are explicit, enforced, and separate from static capacity evidence.
No implicit truncation, partial-success output or engine fallback is allowed.

Internal implementation decisions proceed locally. Changes to accepted language
behavior, evaluated meaning or canonical contracts require coordination and an
explicit decision. Main's shared typing, evidence, schemas and pins are not
edited here. Main synchronization is needed at integration/API boundaries,
not after every upstream commit.

## Authority and reference material

The normative owners are [algebra lowering](../spec/language.md#algebra-lowering)
and [generated identifiers](../spec/language.md#generated-identifiers), together
with the pinned [AoA contract](../../spec/contracts/actql-aoa.json).

`src/lowering_relation/registry-preimages.json` preserves the exact registry and
module preimages recovered from sketch. Construction follows sketch's
`src/actql-aoa-contract.ts`: registry input/output signatures from
`AOA_PIPELINE_OPS`, and the core/rela/sga/veca/tea module subset from
`ACTQL_MODULES`. The registry distribution matched the archived dependency
`smoothhq-aoa-pipeline-0.12.0-integration.20260906.2.tgz` whose SHA-256 is
`be37097b180634e6fbb3e5c1b026661b70f314fb7babead507dc4798ba18fcf4`.
That dependency version is provenance, not an ActQL contract version.

`node --test scripts/lowering-registry.test.mjs` independently verifies both
full preimages against the existing pins. It also checks the four preparation
signatures against the registry plus normative target requirements. In
particular, `REL.values` is a target requirement, absent from the base registry.
These signatures do not prove operation-parameter or expression admission.
Historical module descriptions are not substituted for newer normative rules.

sketch MoonBit's relation evaluator informs ownership and budget design. AoA
informs node/parameter representation. Smooth Cloud's local lowering and DuckDB
fragment compiler inform the engine boundary. Their restrictions (for example
discarding empty transforms or rejecting empty derive) are not imported as laws.

## Current increment: preparation only

`lowering_relation.prepare` retains one CheckedPipeline and checked operation
payloads, allocates ASCII `input_<index>` and `<preferred-operation>_<step-index>`
identifiers, checks collisions, preserves resolved input occurrence order, and
retains diagnostic cursors. These namespaces are disjoint. Author aliases never
become node identifiers; explicit branch references resolve to their original
producer rather than the immediately preceding step.

The allocator implements document-order/preferred-name identifiers; it does not
claim identity parity with a historical compiler. Generated identifier bytes,
nodes (including input handles), reference occurrences and work have explicit
overflow-safe limits. Returned reference arrays are copies. A late unsupported
operation returns an error and no partially prepared pipeline.

There is deliberately no executable fragment or Plan emission yet. Preparation
does not discharge expression obligations, parameter binding, operation-parameter
contracts, final serialized size or any Program-level authorization.

## Remaining implementation and release conditions

| Area | Current state | Condition for closing |
| --- | --- | --- |
| Four-operation wiring | Implemented preparation | Keep tests as executable lowering is connected |
| AoA parameter/expression lowering | Not implemented | Fixed normative node vectors; preserve derive snapshot/slot semantics and no-ops |
| Bound parameters and external rows | Not implemented | Existing admission plus owner association; literal opacity and alias tests |
| Pure fragment evaluator | Not implemented | Independent expected values, NULL, conditional demand, errors and resource tests |
| Additional expression obligations | Not implemented | Discharge the specific profile/pattern/other obligation before evaluation |
| Other operation handlers | Not implemented here | Add normative lowering and evaluator support, then replace coverage-status tests |
| Product Run/publication | Outside this increment | Separate integration with main's acceptance and capacity boundaries |

Unsupported-operation tests describe implementation coverage, not permanent
language rejection. Implemented common paths must not grow a separate restrictive
allowlist. Evaluation failures must not expose partial results.

Completion requires the entire agreed four-operation path, the minimum expression
set, supplied inputs/parameters, independent lowering and execution vectors,
ownership and budget cases, JS/Wasm/native, API equality, formatting and relevant
documentation checks. Commit lowering and execution in functional units, report
known failures and remaining integration requirements, then stop rather than
expanding into more operators or Host implementation.

## Preparation verification

On the initial preparation increment, the five fixed preparation tests passed
on JS, Wasm and native (5/5 on each). The two independent registry tests passed.
`moon info` produced identical package interfaces on all three targets (SHA-256
`501534a8608460d83bbc4cdc88cb7b356737410dd3c68969632c84cb0c9a258e`).
Package format checks and `npm run check:docs` passed (839 local links and
19 parsed example programs). These are preparation/documentation checks, not
evidence of expression execution or full Program conformance. No full repository
MoonBit test-suite result is claimed for this increment.
