# Retained property-name expression cursor

Base main: `b98a50ff763d1367e344fdfa8aea380ec8749132`.
Branch: `feat/local-property-name-cursor`; target: main, without an unmerged
parent. This is independent of #663, #666 and #677 and retains the sole Graph
model/current identities. It closes an expression scan, not all Local retention.

## Counterexample and existing owner

The property continuation already measured a large receiver incrementally, but
then synchronously charged all member-name bytes and compared its complete
spelling. A valid 256-unit property expression exceeded 64 control units in one
frame poll on main. The independent expected-bounded regression failed 0/1
(`run-Is1ITx`, `focused-test-z323ZF`).

The existing expression frame now retains PropertyNameState for names longer
than 64 UTF-16 units. It pays one scalar's original UTF-8 control charge per
poll, then compares at most 64 UTF-16 pairs. Names are not normalized. The
existing semantic Return paid this transition; resumes add no expression entry
or logical value work. The two cursor handles are admitted before construction.
The receiver root and continuation stay owned through name measurement and
matching; successful selection releases them once before the normal result
event. Closing a suspended frame uses the same root/workspace cleanup path.

The complete authored name is charged before inspecting type/member failure,
preserving ControlLimit precedence. NULL receivers retain NULL propagation.
Short names retain the existing statically bounded path. This does not close
ordinary input Map hashing, authored field-name lookup, Object construction-name
measurement or other synchronous evaluator callers.

## Independent limits

- A borrowed Object with a 256-byte member and Number 7 has weight
  `1 + 256 + 1 = 258`. Two entries, produced receiver, consumed receiver and
  Number result give `2 + 258 + 258 + 1 = 519` logical work.
- Its wire is 262 bytes: member bytes plus braces/quotes/colon/number. Exact
  live bytes 262/261 and logical work 519/518 retain typed failures.
- Nine measurement slots, one continuation and two cursor handles require
  workspace 12/11. Cancellation at name offset 64 preserves spent work 518
  and the live 262-byte receiver until frame cleanup; double close returns
  live bytes/workspace to zero without refunding work.
- Without logical measurement, four transitions, seven payload-reference bytes
  and 256 name bytes require 267 control units. NULL succeeds at 267 and
  refuses 266; an invalid member at 266 gives MissingValue, while 265 fails
  earlier with ControlLimit. Those controls isolate the name budget from the
  additional existing receiver-measurement polls.
- A 63-ASCII/supplementary/65-composed-scalar member fixes 197 UTF-8 bytes,
  preserves the surrogate boundary, and requires 208 successful unscoped
  control units. Frame batching 1/7/256 keeps result and total unchanged.

## Public connection and evidence

The ordinary public JSON Program has a Values producer with a 513-unit declared
Object member and a nullable receiver. A later Stage derives the property and
projects mandatory columns, then two consumer Stages read them. The installed
Local Host and real retained Store publish three explicit Named Results, each
equal to the independent ordered rows `[{id:1,value:7},{id:2,value:null}]` with
the expected Number/nullable column contracts. Request reuse does not dispatch.

The public test delivers cancellation after positive work in the deriving task,
keeps retained custody while physical stop is unconfirmed, and checks all three
Results remain unavailable after confirmed stop and snapshot reclamation. Its
opaque Host barrier does not identify the exact property-name phase; the common
frame fixture pins that phase and its root lifetime independently.

Candidate shared/existing tests passed 17/17 (`run-nnl79B`,
`focused-test-ytytnI`). Public acceptance passed 1/1 (`run-9iHPb6`,
`focused-test-oewSFV`). Required-evidence removal passed 1/1 (`run-ho4sYN`,
`focused-test-jvR22G`), and the actual resource checker keeps the current 64
executable routes and four refusals without asserting full completion. Earlier
fixture attempts incorrectly used the small-value logical helper and a control
ceiling excluding receiver measurement; they were failures, not product fixes
or acceptance. Final submitted-SHA receipts are recorded in the PR.

Only Local Node/Run Host Core runtime dependencies were built from the changed
source. Bundles remain ignored. No language/wire/CID or public API change is
introduced. Full Core, proof, performance, Wasm/native, packed/HTTPS and whole-Run
physical accounting were not run. These are checkout Host checks, not pristine
packed distribution evidence; CI is reported separately without manual retry.
