# Using the physical cost helper

This source-checkout MoonBit API compares supplied serial latency estimates.
It does not execute a Connector or produce an executable PhysicalStrategy.
See [design and limitations](design/physical-cost.md).

Import `actql/actql/physical_cost` as `cost` in a MoonBit package. For example:

```moonbit
let duration = @cost.assess_serial(3, [
  { work_slots: [0], milliseconds: Some(3L) },
  { work_slots: [1, 2], milliseconds: Some(7L) },
], 8).unwrap()
let choice = @cost.choose_serial([duration], None, 1).unwrap()
// Complete(10) and EstimatedFastest(0, 10), respectively.
```

The three slots are physical accounting positions supplied by the caller.
A bundle covers slots 1 and 2 once. Give each additional required transfer,
conversion, capture or cleanup work its own inventory position, unless already
included in a bundle. Never omit required work to obtain a complete estimate.

When duration information is missing, pass `None`. Incomplete totals remain
`Unknown`; they are not zero. With any unknown candidate, `choose_serial`
returns `Deferred` unless a full Host priority is supplied, for example
`Some([1, 0])` for two candidates. Such a choice is reported as `HostPreferred`,
not as a fastest estimate. Priority cannot replace separate execution admission.

Planning entry limits are exact counts of inventory entries, estimate lines
and coverage references (assessment), or candidates and priority entries
(selection). The example assessment needs eight entries: 3 + 2 + 3.

No CLI placement switch, provider dispatch, durable capture, or Program/Plan
integration is exposed by this helper. Existing Local Relation execution APIs
and their ownership and budget checks remain separate.
