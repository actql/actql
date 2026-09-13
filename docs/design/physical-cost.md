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
