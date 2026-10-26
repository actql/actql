# Local capacity plans and consumer units

## Authority and identity

`client_local_host/capacity_plan.mbt` derives one immutable policy snapshot from
original checked `GeneratedSequence` handles and their checked graph. Preparation
retains the snapshot; pre-admission quoting and Host configuration consume it.
Matching compares original handles and the admitted row ceiling, not CIDs or
structural resemblance. Copying the handle array is sufficient for these opaque
prepared owners: their exposed selection and schema APIs do not mutate retained
internals. This is not a general promise that arbitrary arrays are immutable.
A plan is an optimization proof and configuration, never execution permission,
physical supply, a Ledger, or a replacement for original admission evidence.

## Separate units

| Dimension | Meaning and consumer | Proof / conservative fallback |
| --- | --- | --- |
| Value nodes | Row containers and admitted scalar cells | Original input ports (including duplicates), cumulative intermediate outputs and projected external inputs; unknown/nested schemas retain 20,000 |
| Value text | UTF-8 value strings **and charged row field names** | Scalar IO uses original schema-name occurrence envelope; evaluator retains 500,000 unless every original expression child and generated step proves text-free |
| Guard bytes | Serialized input measurement, including numeric spellings | The [original input guard](../../src/client_local_host/captured_ledger.mbt) retains the selected generic allowance or the larger proved scalar wire envelope; value-text demand cannot replace it |
| Wire nodes | Bare rows or logical Relation envelope | Proven scalar value nodes + three wrapper nodes; otherwise 100,000 |
| Wire bytes | Encoding and transfer ceiling | The [scalar wire derivation](../../src/client_local_host/scalar_wire_capacity.mbt) checks finite Number/Boolean row bounds and Int overflow without a separate 1,000,000-byte cap; consumer wire profiles and Store ceilings remain independent |
| Schema fields / bytes / nodes / depth | Canonical schema traversal | Independent record preserving prior ceilings (100 fields, 1,000,000 bytes, 100,000 nodes, depth 64), never derived from a specialized row wire |
| Metadata name bytes | Producer bindings, bridge and completion names | Independent 1,000,000 snapshot, never narrowed with row-wire bytes |
| Bridge / completion entries | Input identities, fields, bindings and issuers | Independent metadata validation ceilings; separately funded retained metadata |
| Result view workspace | Row indices, merge scratch and exact order terms | `2R + O`; order terms count occurrences, not distinct columns |
| Publication snapshot workspace | Distinct snapshot preparation/emission counters | `max(100, 2R + O, 8 + 5F)`; no rows-by-fields cell copy |
| Result mapping work | Projection resolution and source-column lookup | Checked `F * (P + 1 + C) + O * (1 + C)`, with original projection/source counts |

The expression proof examines all original typed children, including dormant
branches. Scalar output alone is insufficient: `LENGTH(REPEAT(...))` has a text
intermediate. Only enumerated basic row kernels, Values and Append qualify;
other families keep the evaluator fallback even if their final schema is scalar.
Field-name accounting includes UTF-8 names, every port, every original output,
and external-input projection. It is not zero for numeric-only tables.

## Metadata funding

`capacity_metadata.mbt` bounds original checked inventories: maximum field count
F, input ports P, original/selected binding count B, row ceiling R, exact summed
Result order terms O, and task identity plus Result occurrence count I. Result
aliases are not bounded by task count and order terms need not be unique.
The additive slot categories are:

- bridge: `P * (3F + 2B + 8)`;
- completion: `4P + 2B + 64I + 16`;
- export / Result view: `24F + 2R + O + 64`;
- dispatch: `8P + 8I + 64`.

Each slot is funded at 256 logical bytes. Retained schema text additionally uses
`8 * (6N + 96F + 2)`, where N is total UTF-8 field-reference-name bytes of the
largest original schema. Escaping can expand a byte by at most six; checked
Number/Boolean contract spellings fit the per-field allowance. Arithmetic is
bounded before specialization; excessive or unproved inventories fall back.
For the small composition inventory F=2, N=36, P=B=2, I=2, R=100, O=0,
these categories are 36 + 156 + 312 + 96 = 600 slots and 410 schema bytes:
`600 * 256 + 410 * 8 = 156,880` logical bytes per task.

These are conservative logical allowances, not allocator-size or process-RSS
measurements. Independent provider metadata workspace is not reused to fund
simultaneously retained Host metadata.

The scalar wire proof uses the pinned finite binary64 formatter's 25-byte
maximum, including `-0.0000010000000000000002`. Each field has at most six times
its original UTF-8 name bytes, two quotes, a colon, a separator and 25 scalar
bytes. Row braces/separator add three; array plus logical Relation wrapper add
30. Exact and one-short encoder tests cover the 25-byte edge. Schema and metadata
name admission remain separate even when row wire is tiny.

## Quote, reserve and ownership

The same metadata amount enters all four relevant vectors:

1. `captured_ledger.mbt` whole-Run retained inventory;
2. its simultaneous selected-provider vector;
3. `connectors/local/driver/dispatch.mbt` offer estimate;
4. `managed_dispatch.mbt` actual selected-task retained reservation.

It is retained-only funding. Existing scratch is not charged a second time.
The adjusted retained amount flows through the existing output storage-byte
handshake; physical process stop alone does not release it. Existing retention
pins, child borrowers, settlement, disposal and release confirmation remain
necessary. Unknown-transfer charges are not erased by cleanup.

Whole-Run quoting still sums all task outputs and all input ports conservatively.
Actual materialization imports only missing copies and may borrow existing
outputs. Replacing these sums with a maximum would require a separate lifetime
proof; this plan does not make that substitution. Per-Run capacity is not a bound
on total RSS across concurrent Runs.

## Routing and backend boundaries

| Earlier route | Plan route |
| --- | --- |
| Recompute execution/import/export limits in quote and Host | Original preparation retains one snapshot |
| Row-wire node ceiling reused for schema/bridge/completion | Separate typed metadata limits |
| Metadata implicitly funded by a generic wire coefficient | Explicit retained allowance in quote and actual reservation |
| Scalar schema treated as sufficient for intermediate text | Separate scalar IO and all-child evaluator proofs |

Generic Local callers preserve their former defaults, including acceptance of
zero wire-node configuration before actual use. Native and Worker consumers of
shared MoonBit types inherit those defaults; Node-specific publication adaptation
must use the checked publication owner rather than a copied JavaScript formula.
Unsupported proof shapes retain conservative policy, not a new language rule.

## Verification obligations

- Quote and runtime retain the same original sequence/graph and row ceiling.
- Every actual consumer charge is below its selected dimension; exact and
  one-short tests exercise real scanners, encoders and Result preparation.
- Unicode field names count bytes, not code points; duplicate ports and
  cumulative outputs are not deduplicated.
- Text-producing dormant children prevent evaluator specialization.
- Controlled failure publishes no partial result and does not consume borrowed
  input ownership; cancellation and reopen preserve existing release rules.
- Backend typechecks are not claims of native execution or allocator/RSS proof.

## Installed inventory bounds

Task, Result occurrence and proven field inventories follow the original checked
graph and its bounded work, not independent structural counts. A planning work
budget is consumed before constructing inventory entries. Representation overflow
and exhausted installed resource authority remain meaningful refusals; a task
count is not itself a language restriction or a new resource grant.

The prepared profile can retain a historical row floor for canonical identity
compatibility. Closed-row proofs can narrow execution capacity without rewriting
that profile. Every consumer must distinguish the compatible profile from the
proved actual envelope; using the profile as a new estimator creates unnecessary
slack and can diverge from dispatch. Unknown shapes require a named conservative
adapter, not an inferred cardinality from observed output.

## Preparation and capacity authority

Retained bytes and execution bytes are distinct budget dimensions. Their minimum
is a conservative compatibility helper, not an additional joint memory pool.
A capacity plan is neither a debit nor an authorization to replenish either
budget. Concurrent Runs do not acquire a process-wide memory proof merely by
having individually valid plans.

Preparation and execution must use the same original request-parent Ledger.
Before parsing, checking, lowering, lazy sequence construction or serializer
proof work, the corresponding phase needs a bounded reservation. Constructed
representations overlap: a shared indexed tree is charged once by nominal owner,
while each view and newly owned array is accounted separately. Post-construction
extents can validate or narrow a pre-admitted envelope, not fund it retroactively.
Lazy replacement includes old/new overlap until original borrowers retire.

Transfer into a Run changes the owner of the same retained obligation; it must
not release one pool and acquire a fresh independent grant. Scratch release
requires the original logical owner to end and its borrowers to release;
physical resources additionally require their original cleanup acknowledgement.
None of these logical transitions asserts immediate garbage collection or RSS
reclamation. Unknown outcomes retain their original obligations.

## Publication boundary

Compute dispatch retains `ClientLocalCapacityPlan`. Ordinary Node publication
projects its typed policy from that same original capacity plan: the staged
original before dispatch and the live Run preparation after acquisition. Equal
Program shape, a repeated CID, or a freshly prepared Run cannot replace this
owner. The ABI projection is a view of checked facts, not another grant or an
independent row/field estimator. Legacy callers without an original plan retain
an explicitly separate compatibility calculator. Content serialization has its own explicit workspace capacity; that
is not evidence that ordinary Values publication is funded. The ordinary
publication retention/cleanup owner covers the incremental borrowed-view and
snapshot metadata through the retained allowance below; Content workspace is
not reused as its funding evidence.

For non-scalar source-free Results, the original generic wire/value allowance is
preserved. Newly admitted Result field/view/snapshot metadata is additionally
funded by `(24F + 2R + O + 64) * 256 + 8 * schemaByteCeiling`. Scalar metadata
already includes these categories and is not charged twice. A plan carrying
nonzero metadata cannot be quoted without the retained-input inventory.

The physical memory representation retains its reader across both row access
and awaited commit. Closing waits for readers; the Site holding releases only
after asynchronous close. Captured transformation transfers its pin into the
export, whose cancellation closes the stream before releasing the pin. Snapshot
preparation borrows the indexed table and streams one cell at a time, rather
than copying an additional rows-by-fields matrix. These lifetime facts support
the incremental retained allowance, not a claim of complete historical memory
accounting or a process-wide memory limit.

The named Node publication profile preserves its unrelated legacy depth, value
work, and generic transport defaults. Checked Result facts replace only the
previous field/workspace/mapping mismatch; proven scalar Result wire uses the
same byte-bound formula as Local compute. Text and nested publication keep
conservative wire defaults. The existing Content publication profile remains a
separate unchanged caller contract.

## Shared publication encoders

Index and progress, Result manifest and receipt envelopes use the same Common
encoders for issuance and bounded measurement. Known original names, canonical
contracts and fixed-format timestamps are measured directly. Unknown Result
bodies contribute their independently checked bounds, including escaped names
and row-count digits. The progress frontier includes an independently committed
winner as well as the current attempt's preparing, committing, unknown and
terminal records; it is not a hard-coded four-record allowance. Capture uses its
separate conservative envelope until its complete shared layout is available.

A Node preflight snapshot owns its input arrays and data records before quoting.
It reads dense own data indices and never invokes caller-supplied array methods,
iterators or property accessors. Later mutations cannot alter the measured
bindings, Result occurrences, or dependency inventories. This snapshot remains
subject to the caller's original preparation authority; measuring a wire bound
is not permission to allocate an unfunded snapshot or serializer workspace.

Store preflight, live reservations and stored-byte accounting are different
quantities. A confirmed native transaction transfers the same reservation into
stored ownership synchronously; the intermediate accounting order is not a
second concurrent grant. Unknown outcomes retain the original reservation and
recovery duty until that transaction is confirmed. None of these logical byte
quantities is an operating-system heap or resident-memory measurement.

## Installed Effect operation demand

`ClientInstalledEffectManagedPlan` retains the checked Effect/request originals,
installed contracts, ordered implementation extents, original Source
declarations/acquisitions/capture capacities and generated sequences. Its quote
contains Compute/Source demand plus the selected member and row operation
occurrences. A physical occurrence contributes one possible Start and its
transfer extent; a pure capture holder contributes live capacity without a
physical attempt. Repeated references at distinct occurrences remain separate.
Static catalogue/profile selection is DATA and does not admit this checked Run.

The fixed managed supplier admits the exact plan token. An equal numeric quote,
a copied plan or another plan for the same prepared Program cannot replace it.
The managed parent retains that original through failure and cleanup.
PrepareLedger validates the same selected inputs and actual admitted envelope
before using the retained plan; it does not repeat sequence/capacity derivation.
Legacy Compute-only Effect parents do not thereby acquire operation funding.

Uniform extent selection uses the checked member index, member/row extent class,
fixed implementation declaration slot and exact operation name. Current Run,
nominal authorization/dispatch binding, original request, Site, claim and actual
before-use debit remain separate. A row position or a copied grant/use CID is
not new authority. The same child retains its response and retirement duties.
Retirement returns live occupation; it never refunds consumed work or attempts.

The operation envelope conservatively includes every still-retained declared
child. A smaller overlap needs actual retirement of its original references.
Scratch quoting observes peak owner/row/input-row arrays in the existing schema
traversal, including failed proofs; work visits are not memory slots. These are
logical representation allowances, not physical allocation or RSS evidence.

The planned Compute opener binds the existing admitted Effect Run to this same
parent Ledger and retained generated sequences. The plan keeps the actual Local
configuration and provider allowance used by its quote. Source captures remain
on that Ledger; their downstream sequences carry an explicit offset into the
original full graph. Every sequence owner must match that graph coordinate,
and its input schemas retain the original Source fields without pretending
that an open Source has a known row count.

Opening retains the original captured DAG before fallible configuration and
provider callbacks. Reentry cannot replace it or retire the parent during that
operation. Failure retains the same cleanup responsibility and never certifies
physical release. Legacy openers remain separate until their real consumers
have migrated; the planned opener cannot fall back to a fresh Ledger or repeat
preparation from equal wire bodies.

For query-time-dependent work, the same definition preparation first binds its
original sampled context to the admitted Effect Run and request. The timed plan
entry prepares both Source requirements and generated sequences with that
already-bound context, then quotes those actual originals. Opening Compute uses
them unchanged and requires the same nominal Run admission and definition.
Equal saved wires cannot substitute newly admitted tokens for that live plan.
A cold restoration chooses its own genuine restored originals before preparing
a new plan; it cannot revive a previous process's plan. These computation facts
do not discharge current Account, physical claim, CAS or cleanup obligations.

## Ordinary installed Source demand

Static planning carries its admitted request derivatives through the existing
pending-operation registry, including deferred ingress. The funded-original
lookup can then return no submitted producer and continue ordinary checking.
This lineage retires with the same read operation; it grants no Run funding,
Source permission, execution or physical-cleanup acknowledgement.

An ordinary installed Source uses the existing Host Source/Compute manager and
per-Prepared Run inventory. Its checked capture prefix selects each installation
in occurrence order, including repeated inputs. The installation supplies an
opaque capture capacity for that actual QueryRequirement plus its existing
physical transport bounds. These are demand DATA, not a Source read grant.
The shared captured-limits calculation includes the same checked Local suffix;
it does not substitute row-source declarations for another backend or invent a
Source-empty Program. Unsupported installations keep their existing refusal.

DuckDB quotes its existing pending Native/Broad envelope before read selection.
The original checked Program/request and fixed Host manager admit one parent.
Actual selected capacities must fit that original Ledger before dispatch; a
scalar constructor cannot replace a missing, foreign or retired parent.
RowSource still requires its exact original managed read/acquisition binding.
The ordinary DuckDB capacity does not manufacture that backend's read token,
and the separate Effect plan keeps its own stronger original-plan checks.

The generic Source view captures original adapter methods and receivers once.
Each real prepared Source is privately associated with its original checked
Program and parent after the preparation await and a second current fence.
Copied, foreign and cancelled preparations cannot supply that association.
Plural installations forward the same parent through every selected capacity;
different Source occurrences are not deduplicated into one physical read.

The existing dispatch retirement predicate first settles actual Source/Compute
children and unresolved cleanup. Only then may its existing preparation holder
retire the managed parent. Source-close status, current permission, consumed
attempts, durable publication and physical FD acknowledgement remain separate.
Installation close cuts the same private inventory references after its actual
cleanup. Weak associations are not persistent grants or new cleanup owners.

## Cumulative continuation after child retirement

The existing Ledger separates cumulative work, attempted physical operations,
known/uncertain transfer and quantity consumption from live reservations,
holdings and delegations. A private continuation snapshots all thirteen usage
fields, the exact six limits, all three non-reused serial cursors and the full
quantity configuration/usage. It reuses the original-ledger snapshot and field
codec rather than constructing another resource calculator.

A continuation is available only when every live count, held/reserved byte and
delegated quota is zero. A zero-byte token is still live. Unknown cumulative
transfer and quantity debt remains unchanged and reduces later admissions;
actual quantity overruns are preserved rather than clamped. This accounting
predicate does not prove physical cleanup, resolve an Effect or authorize a
new request. Nonquiescent original children retain their existing owner and
cleanup/reconciliation path.

The private codec accepts only exact arrays and canonical integer strings. Its
output is DATA, without Journal authentication, a Run binding or capacity. The
existing authenticated Journal/service must bind those bytes to the actual
restored preparation, Allowed/Definition and request, and the same selected
operation plan before any provider call. A live export is historical DATA, not
a park fence: its existing holder prevents new work and checks the original
state again at the actual persistence boundary. This does not add a publication
wire evidence kind or reuse a Model evidence name for resource accounting.

Restore initializes one pristine, separately admitted original Ledger with
exactly matching limits. It preserves sunk consumption, peak retention,
uncertain debt and exhausted/non-reused identities. An all-zero saved state
still consumes the one-use initialization slot. Neither a new reservation nor
a settled zero-byte token is a pristine target. The Node admission retains its
same failed initializer and cleanup owner if imported limits or currentness
refuse; it never starts a second child or recreates tokens from a saved census.
The resident initialization flag is included in the existing initial-control
representation inventory. Normal authenticated cold restoration remains a
separate caller integration from these portable accounting operations.

Domain-specific installed implementations supply owned representation, value
node and raw-byte inventories to one shared preparation-to-execution fold.
Retained state and simultaneously live workspace use the existing shared
representation and value-node tariffs; the execution peak includes both. A
domain must not repeat that arithmetic, introduce another tariff or turn its
static declaration into an admission. The original checked plan and Ledger
still determine whether the quoted inventory can actually be funded.
