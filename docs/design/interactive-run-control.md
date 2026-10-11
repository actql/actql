# Negotiated Interactive Run Control boundaries

The initial negotiated wire registry lives in
[`actql-interactive-run-control.json`](../../spec/contracts/actql-interactive-run-control.json).
Its closed shapes and identity domains are separate from the unchanged closed
`actql-run-state/0.1`, legacy start intent, and Run Definition. Registration
does not install a scheduler feature or confer execution authority.

## Existing-Owner connection inventory

| Boundary | Existing authority or fact | Negotiated connection |
| --- | --- | --- |
| Original request | Submission epoch/reference and request journal | Normalized requested Profile and optional expected Plan in original intent; duplicates restore that same intent. |
| Original preparation | Checked logical IR and admitted Compiled Plan | External immutable map, deterministic Step/port keys, then resolved Profile/admission. Plan preimages are unchanged. |
| Run state | Common Run/control revision and claim/fence | Separate negotiated projection; no second lifecycle, clock, or terminal decision. |
| Formal resumption | Checkpoint/Resolution Owner | Genuine original evidence, distinct from a manual command origin. |
| Operation lookup | Original accepted operation and journal | Immutable initial receipt plus separately linked later outcome; absence is not resend permission. |
| Inspect | Existing currently authorized Owner-local observations | Explicit non-atomic composition and provenance; no global synchronized snapshot claim. |
| Stored output | Existing material/publication/Store custody | Actual producer output or receiving input locator, not a synthetic produced Step. |
| Local storage binding | `client_local_run.issue_local_result_durable_binding` | Existing original nominal Run/invocation/retention with current account validation and observed physical bytes; no Sample, commit, or Run outcome is inferred. |
| Retention | Existing resource claims and cleanup | Separate Sample, full-intermediate, and continuation lifetimes; registering a Sample shape allocates none. |
| Cost | Existing checked Ledger quantities and selected tariff/scope | New finite amount syntax only; no new price, currency Catalog, budget, or charging Owner. |

The portable `run_publication` package admits canonical shapes and their
registered self-CIDs with the existing parser, schema-validation cursor and
canonical sealer. Its cross-record checks detect Plan/map/profile/request/Run
substitution. These checks do not prove that a map was compiler-issued or that
referenced Sample values were originally admitted under their Carrier/type
contracts: those facts remain with the named Owners. An adapter cannot acquire
authority by sealing an arbitrary sidecar.

Logical Step keys bind the original Plan, checked Stage ordinal and actual
semantic occurrence. Input-only Relation output uses `input_output`; it has
exactly one actual input and output of the same Relation contract. Ordinary
operation keys retain their checked operation ordinal and typed compiler tag.
Port keys bind Plan, Step, role and ordinal. A receiving input retains its
original producer/source locator. IDs are never physical task numbers or
runtime dispatch order.

## Legacy consumer truthfulness

The old SDK continues to expose only its original RunState. A negotiated
paused state, or manual-origin resuming state, refuses old projection with
`RunStateVersionUnsupported`. Where an exact legacy projection exists, Run,
status, timestamp and the original integer control revision must agree.
Formal-origin resuming does not invent approval: real Resolution, continuation
generation and fence evidence still require their existing Owner validation.

The generated client-wire additions are types and shape validators, not
pause/resume methods. Installed capability publication must distinguish static
Plan reading, authorized Inspect, durable control, each Carrier's Sample
capture, full intermediates, Cost Guards and execution batches. A missing
runtime is not made available by recognizing its schema.

## Exact amounts and independent projections

Negotiated `amount_micro` is a decimal string in the nonnegative signed-Int64
domain, matching existing checked Ledger `cost_units` aggregation. Values
above JavaScript's safe integer range retain exact digits. Decimal-unit facade
normalization is distinct and never uses binary floating-point arithmetic.
This finite protocol domain is not a language-wide mathematical Money limit.
Currency syntax alone does not establish ISO support, a tariff, or a price.

Relation presence is independent of NULL. Graph Samples retain original typed
definition/domain/key/edge identity without inferring complete topology.
Vectors preserve original dimensions, precision and component positions;
Events preserve occurrence identity and only available order/clock evidence.
These are bounded projections, not full snapshots, continuations or formal
Results. `forbidden` carries no source, count, shape or references; ambiguous
input selection is `selection_required`, not a silently chosen port.

Read-only PlanView/Inspect may be connected independently. Durable execution
control, Sample capture, Cost Guards and other Host/runtime profiles require
separate original-Owner implementations and acceptance; they are not implied
by these contract definitions.
