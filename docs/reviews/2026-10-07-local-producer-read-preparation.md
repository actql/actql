# Bounded retained receiving-input preparation

## Base and counterexample

Base main: `b98a50ff763d1367e344fdfa8aea380ec8749132`.
Branch: `feat/local-bounded-producer-read`; target: main. Neither #663 nor #666
is a required parent. The Graph-only model and current identities are retained.

The existing chain charged one handoff step while `prepare_producer_read`
measured and compared complete column names synchronously. A 256-unit name
Program reaches the first child's real completion, then the next advance starts
the second child without suspending metadata preparation. The independent
expected-yield regression failed 0/1 on the base (`run-ipSTnZ`,
`focused-test-KwCRTq`); it passed only after the cursor connection.

## Common owner and product connection

`start_prepare_producer_read` retains the exact existing BoundProducerInput and
receiving schema. `advance_prepare_producer_read` visits one metadata transition
or at most 64 UTF-16 units plus a surrogate partner. Qualified references are
borrowed as prefix/leaf parts rather than flattened. Projection entries use the
checked owners' indexed readers, avoiding a complete defensive array copy.
The original synchronous API drains this same cursor; its entry/name-byte
limits, receiving-column order, aliases and binding identity remain intact.

Only complete preparation returns ProducerRead. Each advance checks current
output availability; a revoked input returns ProducerUnavailable without a
partial read. Cancellation clears pending mappings, and cancellation after
transfer cannot erase the completed read's column array.

The existing selected Relation chain retains a receiving-input cursor through
pending handoff. External occurrences, predecessor probes and common metadata
steps share the existing productive work balance. It creates no second ledger,
scheduler, retry or publication owner. Cancellation observes stop before input
preparation/parent outputs are reclaimed. Cleanup does not recompute a child.
Both productive and zero-work child completion branches use the same connection.

The old one-unit small lane remains only for statically bounded shapes: at most
eight preceding steps/external inputs, two operation ports, eight receiving and
physical columns/projection entries, and 64-unit spellings. The same cursor is
drained under that fixed bound. Larger shapes retain it and charge every poll;
work is not rounded or reset at yield. General child-start schema preparation
and initial external-read preparation remain separate residuals.

## Independent quantities and actual acceptance

- One 256-unit receiving column requires two entry visits and 512 name bytes.
  Field + four receiver chunks + column + four actual chunks + four spelling
  comparisons + terminal = 15 common polls. Entries 2/1 and bytes 512/511
  distinguish success from typed Limit and retain the source on failure.
- A 63-ASCII/supplementary/65-composed-scalar name fixes 197 bytes per visit,
  including the surrogate at the fragment boundary. Exact total is 394 bytes;
  cancellation and lost availability cannot produce a partial read.
- Chain setup, port and predecessor, 15 common polls, and exhausted ports
  require 19 handoff polls. After 18 polls no child has started; poll 19 starts
  it. Quanta 1/7/256 retain this count and report one work unit per metadata
  poll. This is the handoff component, not a newly derived whole-task limit.
- Two additional fixed metadata-handle envelopes add 512 bytes to the existing
  declared chain capacity before execution. The column maps are transferred to
  the child rather than copied. The existing conservative-overlap fixture adds
  that component explicitly; this declaration is not a proven Native heap upper.

The normal retained Host runs two Values sources -> same-task Append -> renamed
select -> two consumer tasks. The producer and both consumer Results are fixed
to `[{id:1},{id:2}]`, and reusing the same request adds no dispatch. A 1024-unit
column requires multiple metadata polls after Append progress. The Host's held
unit-work/zero-row barrier delivers cancellation before the selected child runs;
before release it cannot claim physical stop or drop holdings, and afterward
all three Results remain unavailable and snapshots are reclaimed.

The common/operator selection passed 15/15 (`run-Xadqxy`,
`focused-test-lKSS0P`); the real retained Host case passed 1/1 (`run-XTaRHw`,
`focused-test-WnyAjY`). Required-evidence removal passed 1/1 (`run-nzkgqE`,
`focused-test-JsLlF0`), and the real resource checker retains 64 executable routes
plus four typed refusals without claiming full boundary completion. Final
submitted-SHA receipts are recorded in the PR. API artifacts use moon info;
only Local Node and Run Host Core runtime dependencies were rebuilt.

## Capacity evidence requiring owner review

The existing constructor-source recipe already rejects the unmodified base:
its selected-provider pin is `7662c1e802515661034647ae045a03bccfdd69f25d88710ae467f644c14a3b9a`,
while the actual base blob is
`fa58443b462168a1c9d3682740453b492a9d0cf202bf16d4f5883f6b596f121c`.
The generated-sequence premise also differs after the integrated Graph changes.
The constructor-only review now records the current pins together with exact
Git-blob correspondence tests: only two additional false-branch exclusions and
the integrated Graph constructor spelling differ in the generated sequence.
All other bytes remain equal to the prior reviewed source after removing those
explicit deltas. Historical pins and source variants remain in the review.

The entire selected provider factory has identical pre/post bytes:
`f2fb44c23c59859a7c4324684c7afe3b50218ebe287d8e7e9ce62c9ff5e94256`.
The eleven records, four callbacks and original construction capture inputs
are unchanged. Runtime callback execution adds the cursor and changes start_next
to accept prepared inputs; the parent state also retains input_preparation.
G's source/census and Native parent observation therefore need to cover
these execution/lifetime changes separately. Original recipes, Native receipts
and conditional models remain unchanged and tied to their original sources.
The touched constructor source tests pass 12/12 (`run-NWg3bJ`,
`focused-test-M5u56N`), including stale/changed-source rejection. This certifies
only the unchanged candidate construction component. Current Native parent
correspondence is unverified; G's execution/census review remains a merge
dependency. No old Native receipt is promoted to current-source evidence.

No full proof campaign, Native/Wasm execution, packed/HTTPS acceptance, whole-Run
physical budget proof or CI success is claimed. Checkout public acceptance and
constructor-only equality are narrower evidence than those requirements.
