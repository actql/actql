# Salesforce Effect review R2 status

Review baseline: `15904a32f31573a86a3507253f3eaa1b010adf78`.
Prior implementation and verification baseline:
`40ef6ad720e93b98c2c42e6f7ec0bb170682f135`.

The follow-up review in `02-salesforce-effects (2).md` repeats this
coordinate finding and distinguishes it from the still-open ordinary Run
integration. Its fixed SHA predates the coordinate and Host regressions
recorded below. The finding is not a second implementation task.

## Coordinate and execution boundary

The Stage-to-physical-Task Effect source mapping was already present before
this follow-up. The additional standard Host regression now executes three
source shapes: a Result after a split Stage, the split Stage's final Result,
and its intermediate Result. It verifies the exact producer Task, projected
rows, port close behavior, pin lifetime, and cleanup.

The two-member source test now also runs with a split producer. It first
forces a late pin-capacity failure, then confirms both independent pins use
Task 4 and that releasing one does not invalidate the other. The surviving
pin exports the checked rows after the ordinary output port closes.

The regression exposed two adjacent execution defects. A managed consumer
rejected Task 0 even when the Run root was Compute, and the source-free Local
Effect Host did not install the existing SGA provider. Both now use the common
Run and Local provider boundaries. The selected physical Task's exact Step is
also retained while generating its sequence. No Effect-specific graph resolver
or second execution state machine was added.

## Verification

- Standard Client/Local Host tests: 13/13 (rerun after the split shared-pin
  extension).
- Query integration: JS 556/556, Wasm 556/556, native 556/556.
- MoonBit formatting and Node connector assembly: passed.
- Isolated Connector addition gate: baseline and extended all-target checks,
  third-Connector JS/Wasm/native tests, and real Node Host test passed. Its
  isolated fixture needed the Client wire package; the unrelated duplicate
  test match that failed `--deny-warn` was removed.

These are local tests, not a same-SHA Linux CI run or a live Salesforce org
test. No live org credentials or write authorization were supplied.

## Still open

R2-G1 remains a completion condition: connect the checked/captured inputs,
whole-set Preview and apply admission, durable claims, physical writes,
reconciliation, and final publication through one ordinary multi-member
Effectful Run. The current standard Host regression stops at owned input
export; it does not prove the mutation or final Receipt path. Missing/foreign
late-pin failures and local HTTPS no-send cases still need top-level coverage.

The checked Effect preparation now exposes a private per-member Plan CID so
the eventual Preview can bind the exact static Plan without reauthoring it in
JavaScript. It is a static identity accessor, not input capture or an apply
permit. Product connection and the review's fault-injection matrix remain
open. Same-SHA Linux CI and live Salesforce are not yet verified.

The installed Host now connects a live Preview input to the generation-checked
managed Result importer and the common canonical Result cursor. For each row,
MoonBit compares the checked Plan selector and intended changes against the
admitted private Preview before releasing prepared Result bytes. Exact row
count and pin liveness are checked before returning the relation receipt.
The Host fixture verifies matching update rows, altered changes, swapped
targets, and a released pin. This is payload evidence only: it neither admits
current target guards nor issues an apply permit, dispatches writes, or commits
an Effectful Run. Prepared-output sinks must reclaim partial bytes on failure.

At `24bff12682889e5004ea60de347ff0c580a2a588`, the grouped Client
distribution gate passed: 73/73 Node tests, packed Node/browser Client smoke,
and native Client mTLS. This does not replace the missing Effectful submit and
apply E2E or same-SHA Linux CI.

The next Plan sub-inventory now issues an opaque proof only after the checked
Result cursor and its completed export receipt both finish. The private
Preview, exact member, and live input pin must still match when the proof is
used. An inventory check requires one distinct proof for each Plan-bearing
member and rejects missing, duplicated, foreign, and released proofs. This
does not cover members without a Plan, current guards, whole-set write
footprints, or apply authority. The proof constructor remains inside the
product bridge rather than the generic row comparator, because arbitrary
rows supplied to that comparator do not prove Result provenance.
