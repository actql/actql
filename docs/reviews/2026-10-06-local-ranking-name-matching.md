# Bounded Ranking reference-name matching

## Scope and ownership

This component starts at #585,
`feb175d059b17b0176106564f05f9157009a4db2`. The parent remains
unmerged; the final destination is main. It closes algorithmic input role
binding and output field matching for `merge_rankings`, not all retained
Local execution boundaries.

Ranking previously flattened a field reference and synchronously visited
every group/tie role while binding an admitted cell. Output candidate and
group lookup also compared complete Strings in one transition. Incremental
value rechecking did not bound these earlier name scans.

The existing Session now retains one borrowed name/value pair, a role probe
and an offset: four fixed workspace slots, reserved before reads. Matching
uses the parent's `relation_schema.compare_reference_fragment`, with at
most 64 raw UTF-16 pairs and eight input probes per poll. Output fixed-role
search retains its original candidate/score/rank precedence; group search
continues one group at a time. Qualification is borrowed, never flattened
into a name-sized buffer. This is spelling comparison, not identity or
schema admission; existing typed input/completion owners remain authoritative.

All roles are visited even after a match, preserving a field used by both
grouping and business tie-breaking. Different-length names need no content
scan. Small existing role lists keep their control schedules; long/wide
matching adds charged polls, accumulated across advances without a quantum
dependent discount. Output construction/value charges are unchanged.

The current field and offset survive a cancellation request. The existing
Session first confirms stop, then its separate cleanup clears the pending
field, output scratch and offset once. `ranking_name_offset` is a read-only
fixture observation, not an alternative owner or completion authority.
There is no schema, wire, CID, frontend or stored-data change.

## Independent boundaries and negative evidence

- One populated input and one empty input have a 56-poll RRF schedule:
  input 14, scratch 3, duplicate/rank validation 4, fusion 4, fused scratch
  1, output/finalization 30. A 513-unit group or candidate adds eight input
  and eight output matching polls plus nine existing output-name charge
  polls: 81/80. A renamed input rank is not an output role: 64/63.
  Workspace is `9+1+6+1 + 6 + 49 + 6 + 12 = 90/89`.
- Input group/candidate/rank and output group/candidate are each stopped
  at offset 64. Cleanup before confirmed stop refuses; offset and input
  owners remain available. Stopped cleanup clears once, without closing
  producer-owned input.
- Nine groups use initialization 9, eleven read/recheck/continued role-list
  visits 44, validation/store 12, scratch/validation/fusion 12 and output
  122 (including `1+...+9` group probes): 199/198 polls. Workspace is
  `18+15+6+57+14+12 = 122/121`.
- A long field shared by group and weighted business tie removes three
  RRF-only polls from 56 and adds two tie polls, sixteen continued input
  fragments, eight output fragments and nine measurement polls: 88/87.
  Workspace is `11+8+6+50+6+12 = 93/92`. RRF does not accept business ties;
  the fixture preserves that refusal instead of expanding its semantics.
- The ordinary Host barrier uses an unused Array of 118 elements followed
  by id, rank and a 513-unit group. Control is
  `56 + (1+2*118+3) + 16 + 9 = 321/320`; workspace is 82/81 at depth two.
  Initialization 1, unused read/recheck 240, id/rank 6 and group 3 start
  the first name fragment at poll 250. Poll 256 retains offset 448 before
  group comparison or output. Quanta 1, 7 and 256 preserve these boundaries.
- An atomic-drain mutation removes the sixteen matching continuation polls
  and fails the independent 81-poll assertion (65 observed). Its one selected
  test failed as intended: `run-GK2LmF` / `focused-test-egmosc`. The mutation
  was removed; it is negative evidence, not a successful production check.
- Existing direct/provider boundaries gain only four fixed custody slots:
  137/136 becomes 141/140, 156/155 becomes 160/159, and unused-array
  78/77 becomes 82/81. Their control boundaries remain 236/235,
  14193/14192 and 574/573. Earlier recorded numbers describe earlier sources.
- Required route evidence includes the common fragment, actual input/output
  scan custody, wide/overlapping roles, independent Host barrier and real
  public Store case. Removing a required role/public case or assigning the
  common fixture to a foreign suite is rejected.

## Executed candidate checks

Focused Ranking caller/name cases passed 16/16 (`run-uWqiWx`,
`focused-test-PzOwX4`). The expanded name/boundary file passed 3/3
(`run-F3T5p4`, `focused-test-TiSBbN`). Earlier attempts are retained:
an unsupported `--file` was refused; a mistaken `-f` file-name selection
executed zero tests and failed the guard (`run-5jNRbW`). The initial
long-name estimate omitted existing output-name measurement and failed
(`run-o4x0lM`); the correction above comes from its independent schedule,
not a measured successful total. A subsequent overlap fixture used forbidden
RRF business ties and was rejected (`run-uLCtFr`); it now uses the existing
weighted contract.

Only local-node and run-host-core were regenerated from the production source
inputs. Three actual public retained Host cases plus the evidence-gate mutation
case passed 4/4 (`run-4NDfs8`, `focused-test-pBvkRl`). They prepare/submit
ordinary JSON Programs, read three explicitly named Results against literal
expected rows, use two consumers and a real retained Store, reuse the same
request without another dispatch and request cancellation at the actual
bounded barrier. They check unavailable Results before/after stop and final
snapshot reclamation. This is checkout-runtime acceptance, not packed/HTTP.

Clean source-SHA checks, interface generation and automatic Draft CI status
are reported with the submitted PR. Candidate receipts above remain bound
to their recorded dirty tree; no later SHA is substituted for them.

## Remaining work

Preparation still copies group/tie names; schema lookup and per-poll input
availability loops are separate residuals. JSON identifier normalization,
legacy drains, final runtime buffer assembly, aggregate intermediate-byte
accounting and whole-Run physical accounting are not closed here. No full
Core, Wasm/native execution, full fault/retry matrix, packed or HTTP campaign
is claimed. Shared fragment/fixture target declarations are not evidence
that those targets were executed locally. The overall retained Local goal
remains open.
