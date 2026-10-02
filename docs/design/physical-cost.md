# Physical cost comparison

The `physical_cost` package is a pure, bounded latency-estimate helper. It is
not a Connector SPI, a canonical Plan builder, capability validation, Host
admission, a reservation, or a dispatch permission. Its integer addresses are
local accounting positions, not semantic identities or evidence references.
The normative boundary is [physical strategy](../spec/language.md#plan-documents):
cost information cannot change checked meaning, access scope or logical guards.

## Composition and selection

The caller inventories every required physical work item before estimating it.
That inventory includes applicable acquisition, compute, transfer, conversion,
capture, holding work and cleanup. One estimate can cover several work slots,
but each slot occurs at most once. A bundled estimate and its breakdown cannot
both contribute to the total. Missing slots and unknown durations produce an
unknown total. Negative values, overlapping coverage, invalid addresses and
integer overflow are malformed estimates, not unsupported capabilities.

Durations are nonnegative integer milliseconds. Composition assumes serial
work with completion-wait edges, not overlap or task-to-task streaming. A
holding duration must be a real contribution to serial elapsed time, not an
additional charge for time already included in another item. Physical memory
capacity and retention lifetime must be tracked separately; summing durations
does not establish either. Money, bytes and capacity are not converted into
milliseconds or added to the latency score.

Among complete estimates, selection minimizes estimated latency; exact ties
use the supplied Host priority, or enumeration order when priority is absent.
Host priority never overrides a strictly lower complete estimate.
If any candidate has an unknown estimate, the helper
does not claim a global fastest candidate. A supplied Host priority, expressed
as a complete permutation of this candidate list, selects a candidate with an
explicit `HostPreferred` result. Without it selection is `Deferred`. Priority
cannot admit a candidate that fails meaning, authority, retention or enforced
budget checks. The caller must supply only eligible candidates and must retain
the association between positions and its candidate objects. Empty inventory
and empty candidate lists have distinct zero-cost and no-candidate meanings.

The helper validates priority even when durations are complete, so an invalid
Host configuration is not silently ignored. It performs no I/O or implicit
statistics acquisition. An invalid estimate can be retained as a diagnostic
and treated as unknown by the integrating planner, without removing a valid
capability merely because its estimate was malformed.

A complete permutation is intentional: the fastest tied subset need not include
the first preferred candidate. Selection consults the ordering within that
subset, while unknown totals use its first entry without a fastest claim. The
caller maps a fixed Host preference to candidate positions; registration order
alone is not a stable Host preference.

## Boundedness and limits of the helper

`assess_serial` charges one entry for each required work slot, estimate line
and covered-slot reference. `choose_serial` charges one entry for each candidate
and supplied priority entry. List lengths are checked before traversal and
bookkeeping allocation; failures do not mutate inputs. These are planning
bounds, not language logical-work budgets or promises about process RSS.

The inventory must come from the selected physical work and transfer paths.
This helper cannot detect a transfer omitted from the inventory itself, prove
semantic coverage from integer slots, validate estimate provenance/freshness,
or decide whether a retention contract is sufficient. Those are obligations
of strategy construction and validation. It does not implement monetary tariff
aggregation, shared reservations, parallel scheduling, retries or state-based
replanning. It neither constructs nor substitutes for acquisition evidence.

Representation and evaluator choices remain separate from this accounting
helper. The default row representation and the accepted evaluator/completion
boundaries are unchanged. Their recorded performance limitations are not
reclassified as a passed performance gate by adding a planner helper.

## Installed DuckDB acquisition

The installed Host connects two existing implementations for one checked
`QueryRequirement`: DuckDB's native validation/query receipts, and a broad
DuckDB receipt followed by the Local residual. They share one requirement and
capability registry. The Host excludes a missing source capability contract or
unsupported native compilation before calling `choose_acquisition_candidate`.
The exact selected `PreparedAcquisition` is retained by the existing physical
configuration; an equal name, requirement CID or recreated candidate cannot
replace its payload. Execution failure never selects another implementation.

Every `actql-installed-duckdb-source/0.1` profile now requires an explicit
`acquisitionPlanning` field. There is no compatibility 10 ms estimate:

- `{ "policy": "estimatedLatency", "candidates": { ... } }` supplies optional
  evidence under the fixed `nativeQuery` and `broadQuery` keys. With two
  eligible candidates, missing comparable durations produce `Deferred` and
  no acquisition I/O. The diagnostic lists missing evidence, mismatched input
  conditions and unknown/missing work-slot durations.
- `{ "policy": "priority", "priority": ["nativeQuery", "broadQuery"] }`
  explicitly requests that order among eligible candidates. The reversed
  order is also valid. Both names occur exactly once. This profile contains
  no latency evidence and the existing chooser reports `HostPreferred`,
  never an estimated-fastest claim or an implicit missing-estimate fallback.
- A sole eligible candidate requires no relative cost comparison. The Host
  supplies the existing singleton priority when its duration is unknown and
  reports `selectionBasis: "onlyEligible"`. Missing mandatory resource limits
  still refuse the preparation; a sole candidate is not permission to run.

A provided candidate-evidence object has exactly these fields:

- `inputConditions`: `requirementCid` and `source`, whose `database`, `schema`,
  `table` and `sourceRef` must equal the installed physical source exactly.
  The requirement CID binds the checked request, parameter values, contracts
  and logical guards. Physical source names are compared as exact strings,
  not after canonical text normalization. Foreign conditions leave the
  candidate's duration and quantities unknown.
- `unit`: exactly `"milliseconds"`.
- `basis`: nonempty Host-supplied provenance, at most 1024 characters. This is
  an attributed estimate basis, not a claim that the Host measured or verified
  the predicted latency.
- `estimates`: the existing disjoint serial lines, spelled
  `{ "workSlots": [...], "milliseconds": <integer or null> }`. Numeric values
  are nonnegative safe integers. Missing slots or `null` remain unknown;
  duplicate/out-of-range slots and malformed inputs are refused.
- `quantities`: `transferBytes`, `retainedBytes` and `moneyUnits`, each a
  nonnegative safe integer or `null`. They remain optional estimate facts,
  separate from the latency score, physical receipts and required limits.

The native work inventory is, in order: session/catalog, validation scan,
validation transfer, validation admission, SQL filter/select, native transfer,
native admission, demand measurement, observation capture, retention and
cleanup (slots 0–10). Broad acquisition uses session/catalog, source scan,
receipt transfer, receipt conversion, Local residual, observation capture,
retention and cleanup (slots 0–7). A line spanning all slots is one bundled
estimate, not a per-slot charge. An empty `candidates` object is a legitimate
unknown estimate inventory, not a zero-cost assertion.

Before comparison the installed adapter checks the current source-read gate
and the existing mandatory transport/capacity limits. A delegated read keeps
its structural preparation for the existing Checkpoint owner and postpones
selection until resumed read authority is available. The provider rechecks
current authority immediately before its session opens. No cost, capability
or priority grants access or substitutes for a reservation or physical limit.
The existing capacity allowances are unchanged and are not measured heap
bounds. Preparation owns an immutable validated transport-limit snapshot;
opening it with changed limits is refused before I/O, even when the caller
mutated the original object. A different policy needs a fresh preparation.

The existing Host diagnostic callback receives `acquisition_selection`, then
the selected owner in `acquisition_started`, and the actual completed capture
document in `acquisition_completed`. Candidate names identify these two
realizations; comparison indices are local addresses, not new canonical
identities. The checked requirement CID, exact live candidate custody and
actual receipt/observation identities remain distinct. Int64 diagnostic
durations and quantities use decimal strings; unknowns use `null`.

The current public Local/HTTP submit-error envelope is code-only. It does not
carry a structured `Deferred` outcome or the missing-item list. This connection
uses the existing `ClientProgramRejected` preparation refusal for insufficient
comparison evidence, with no admitted Run; `ClientProgramUnsupported` is
reserved here for an empty eligible inventory. The common planner/Host
diagnostic exposes the precise `Deferred` reason and missing items. Providing
that detail directly to an ordinary SDK caller remains a Client-Host protocol,
schema/pin and SDK change; the operator diagnostic must not be described as
full public Deferred support.

The bounded two-source installation remains Native-only. Each acquisition has
one eligible implementation in that profile; it retains the original shared
ledger and capture/cleanup owners. This connection does not add plural broad
acquisition, a new cost objective, a new execution ledger or statistics I/O.
