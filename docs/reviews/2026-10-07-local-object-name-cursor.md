# Retained constructed-Object member names

Adopted main: `40ed08757152ff4c88397e6e01965e2051909343`.
Initial integration extended #683's Field-name unit. #683 was adopted at
`be30c8fdf2b3133219f7becc74c5667619806c70` while the Object follow-up was still
local. The Object changes move to feat/local-object-name-cursor and a separate
main-targeted PR. Both concurrent integration histories are preserved. No
alternate Graph model, evaluator, scheduler or ledger is introduced.

## Counterexample and existing owners

A checked/lowered Object with a 256-unit member performed canonical wire
sizing, UTF-8 charging and builder name validation in its child continuation.
The independent bounded-poll regression failed 0/1 (`run-3O2bFX`,
`focused-test-q4A6Ai`). Separating only the measurement would leave the
builder's synchronous normalization/order scan.

The existing Value owner now exposes prepare_contract_object_value and
append_contract_object_field. The same opaque ObjectBuilder binds immutable
Fields from an admitted Contract. Indexed appends retrieve its exact next name
without normalization, comparison, hashing, sorting or copying. A caller cannot
supply a replacement name or reorder fields. Generic-name append rejects a
contract-bound builder; indexed append rejects an unbound builder, wrong index,
closed builder or extra field. Finish/cancel remain the same owner. This proves
member names only, not the child values' conformity to their field types.

Lowering already constructs Object children in this exact contract order
(lowering_relation/expression.mbt). The existing expression frame now uses the
contract-bound builder for short and long names. For long names its ObjectName
continuation first sizes canonical escaped wire one scalar at a time, then
grows the same output root, reserves the field tuple/child, pays the original
UTF-8 control charge one scalar at a time, and appends. These separate passes
preserve wire/live refusal before name-control refusal. No resume adds another
semantic entry, child consumption or successful logical work charge.

The original child root and the pending Object root stay owned by the frame
through both passes. Two cursor handles are reserved before construction;
the existing builder handle and field reservation still apply. Cleanup uses
the existing scope and cancels the same builder; it does not refund work or
release caller-owned roots. Short names retain their fixed measurement lane.

## Independent accounting

- A one-field Number Object with 256 name bytes has weight 258 and wire 262.
  Two entries plus produced/consumed scalar plus Object result require
  `2 + 1 + 1 + 258 = 262` logical work. Exact 262/261 gives the typed limit.
- The 262-byte growing Object coexists with its one-byte child: live peak 263,
  so exact 263/262 distinguishes successful completion from LiveValueLimit.
- The Number's existing small-root lane creates no measurement cursor.
  Initial view/continuation/builder handles (three), name handles (two), and
  field/child reservation (three) give workspace 8/7. This is an independent
  reserve-site sum, not a bound copied from a successful run.
- The unscoped one-field expression needs 265 control units: nine fixed
  transition/reference units plus 256 member bytes. No poll consumes its
  whole name. Batching 1/7/256 leaves result and successful logical work equal.
- At sizing or charging offset 64, a pre-existing caller Number root accounts
  for one work unit; two entries and produced/consumed child account for four.
  Work remains five after double close. Live custody is four during sizing
  and 264 during charging (caller root plus pending Object and child). Cleanup
  leaves only the caller's one-byte root, then its explicit release gives zero.
- A 197-byte Unicode name with NULL produces wire 206, coexisting with the
  four-byte child at peak 210; logical work is 203. Independently fixed raw
  Unicode/NULL wire and exact totals are checked.

Earlier fixture attempts incorrectly applied the large-value measurement
handles to a scalar, omitted the pre-existing root charge, and used the private
admission fail function as a test assertion. Those failures are retained as
fixture diagnostics, not acceptance or changes to product budgets.

## Public retained connection

The existing public name harness now also constructs a two-member Object whose
names share a 513-unit prefix. One child is nullable input data; the other is
the independent Number 9 literal. The ordinary installed Local Host uses the
real retained Store, publishes the producer and both consumer Named Results,
and compares each explicit name to hand-authored ordered expected rows.
Description requires a nonnullable closed Object (additional_properties:false)
with the two independently declared child contracts. An initial fixture omitted
this existing closed-object canonical field; the expected contract is fixed
from value_contract/encode.mbt, not by discarding the comparison.

Request reuse must not dispatch again. Cancellation delivered after positive
deriving-task work keeps snapshots until physical stop is confirmed, publishes
none of the three Results, and reclaims snapshots without another dispatch.
The public barrier is opaque, not an exact Object-name phase assertion. Common
frame fixtures prove both exact phases independently. Existing Store owner
failure/cleanup tests remain separate evidence; no new complete fault matrix
or packed/HTTPS/Native cancellation claim is made here.

Required derive roles bind Object-name limits, exact-phase stop and the public
fixture. Removing any required role fails the gate; Field/Property proofs stay
required. The unchanged operation inventory has 64 mapped routes/four typed
refusals and explicitly does not assert all-Local completion.

## Verification scope

Candidate JS batch: 37/37 (`run-FxosaE`, `focused-test-F9U6Fh`), covering the
new contract builder, Object-name limits/stop, existing construction, Field,
Property and expression/frame cases. Only Local Node/Run Host Core consumers
are rebuilt (`run-YxvpGZ`) and checked against source; bundles remain ignored.
Executed-test source is `b1c54bcf5a534dd540ce2c6dc8b867173a66b613` (JS 37/37
in `run-mWjRBN`/`focused-test-08elCT`, Node 4/4 in
`run-VNGNOP`/`focused-test-6bydgd`). Both subsequent normal history merges are
tree-identical to that source; follow-up record changes alter only Markdown.
Final submitted SHA, code-tree comparison and automatic CI are in the PR.

The generated Value API adds two functions; JS caller compilation and API
generation are checked. No schema, wire, CID, pins or language meaning changes.
Wasm/native, physical heap-layout certification, full Core, proof campaign,
packed/HTTPS and performance are not executed. #677's independent Native
runtime-capacity review is not resolved by these logical workspace tests.

Remaining synchronous boundaries include initial row-map/name preparation,
short-name worst-case Map collisions and raw Text child conversion through
admitted_aggregate_item. This unit closes Object member-name handling, not
every body-value admission or remaining retained-Store shape.
