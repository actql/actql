# Retained expression field-name cursor

Adopted main: `0f89dc64d680f0847c76b328800603e9cb27e42b`.
Branch: `feat/local-field-name-cursor`; parent: #681. The parent is still
unmerged. This unit extends its existing expression frame, not the Frontend,
Run controller, scheduler or ledger. The sole Graph contract remains unchanged.

## Counterexample and implementation

A normally checked/lowered 256-unit Field expression synchronously charged its
entire name in one poll, then hashed/compared the String in Map.get. The
independent bounded-poll regression failed 0/1 before the change
(`run-E23bdr`, `focused-test-awyGDb`). Splitting only the charge would leave the
unbounded lookup, so the same frame now holds FieldNameState for long names.

The cursor pays one scalar's original UTF-8 control charge per poll. Only after
the complete name is paid does it read a prior slot or iterate borrowed input
entries. Each input poll reads one linked Map entry or compares at most 64
UTF-16 pairs. The pinned core's Map.iter/next follows its linked head/next
references; it does not copy the row, hash a key, or scan the backing capacity.
Matching does not normalize either spelling. The caller's existing immutable
input/slot lifetime contract remains necessary.

Entry and Return still pay their original transitions and logical events.
Resumption adds no logical work or control transition charge. Two cursor
handles are reserved before construction and released before Return. Failed or
cancelled frames use the existing close path; caller-owned inputs are never
cleared. Names at most 64 units retain the existing short path. This does not
claim worst-case hash-collision bounds for that path, close initial row-map
construction/name accounting, or close Object construction-name measurement.

## Independent boundaries

- The 256-byte name needs 258 unscoped control units: Entry, 256 bytes,
  Return. A missing input needs 257 before MissingValue; 256 fails with
  ControlLimit first. Number and explicit NULL bindings remain distinct from
  a missing binding.
- A Field returning Number or NULL needs two logical work units: its entry
  and one scalar result. Exact 2/1 and cursor workspace 2/1 check typed causes,
  with frame batching 1/7/256 producing the same result/work.
- A 63-ASCII/supplementary/65-composed-scalar name has 197 UTF-8 bytes and
  needs 199 control units. Exact/one-short and finite polling are explicit.
- Cancellation inside matching at offset 64 closes twice without refunding
  spent work, releasing a caller-held root, or deleting its input binding.
- An ordered derive's long prior-slot reference ignores a same-named input
  decoy, propagates the slot's NULL, and rejects an absent slot. Earlier fixture
  attempts used an invalid multi-binding derive body and failed decode; they
  are not product acceptance or a changed language rule.

## Public retained connection

The existing property-name Host harness also runs an independent ordinary
Field Program. A Values producer declares a 513-unit nullable Number column.
A later Stage derives it, projects id/value, and feeds two consumer Stages.
The public installed Local Host and real Store publish exactly published,
consumed_a and consumed_b. Each reads the independent ordered rows
`[{id:1,value:7},{id:2,value:null}]`, with the expected nullable Number schema.
Same-request reuse performs no additional dispatch.

Delivered cancellation after positive work in the deriving task preserves
retained snapshots until physical stop confirmation, publishes none of the
three Results, and reclaims snapshots without another dispatch. The public
opaque barrier does not identify the field-name phase; the common frame test
establishes that exact phase separately. These are checkout public Host tests,
not pristine packed Local/HTTPS or Native cancellation evidence.

Required derive resource roles bind the field-name limits, stop and public
fixtures. Removing any one is rejected; the existing property proof remains
required. The actual checker reports 64 mapped routes/four refusals without
asserting whole-Local completion.

## Verification

Focused candidate checks: JS 28/28 (`run-fftMcs`, `focused-test-scApZy`),
Node 3/3 (`run-k9OHUq`, `focused-test-ZmI9nR`). Node includes the two actual
public Host cases and evidence-removal regression. The source-only runtime
build (`run-icdFJv`) prepares just Local Node and Run Host Core; ignored bundles
and tracked wrappers were checked against those sources. Final fixed-SHA
verification is recorded in the PR, separately from these candidate receipts.

No public API, wire, identity, schema or pin changes are introduced. JS API
generation has no tracked difference. Node Host/Workers fixture freshness,
resource inventory and changed-file formatting remain checked. Full Core,
Wasm/native, proof/capacity campaign, packed/HTTPS and performance were not run;
CI is a separate exact-SHA observation, not inferred from these local results.

The independent #677 ProducerRead runtime capacity review remains with G.
This unit neither adopts its runtime-layout claim nor resolves that dependency.
