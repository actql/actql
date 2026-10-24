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
| Guard bytes | Serialized input measurement, including numeric spellings | Unchanged 500,000; not interchangeable with value-text bytes |
| Wire nodes | Bare rows or logical Relation envelope | Proven scalar value nodes + three wrapper nodes; otherwise 100,000 |
| Wire bytes | Encoding and transfer ceiling | Scalar bound `30 + R * (3 + 6N + 29F)` below the unchanged 1,000,000 maximum; unknown shapes retain the generic allowance |
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

The existing installed preparation and Host independently cap a Run at 32 tasks.
This refactor does not relabel that implementation/profile bound as a language
restriction. A six-term constant UNION/ORDER graph has 25 tasks, seven terms has
29, and eight has 33; the last is refused by standard preparation before a plan
quote. Raising that bound requires its own planning, attempts, holdings and
scheduler inventory review, not removing an optimization guard.

## Publication boundary

Compute dispatch retains `ClientLocalCapacityPlan`. Ordinary Node publication
has a separate checked policy projection bound to `PreparedClientProgram` and
its publication lifetime. Both derive Result facts through
`client_local_result_envelope`; this is not a claim that they share one object.
The adapter consumes a named ABI projection rather than recomputing row/field
formulas. Content serialization has its own explicit workspace capacity; that
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
