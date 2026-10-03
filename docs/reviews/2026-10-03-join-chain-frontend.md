# JOIN chain Frontend connection

## Scope and existing contract

Baseline: `b7aa6cf21e45a086f32bcb6a480d8dfdde79d24f`.
The query parser already retains multiple JOIN parts. The previous lowerer
rejected them after parsing. This unit connects INNER/LEFT/CROSS chains in
ordinary queries, DATA and CTE bodies to the existing Program JOIN operations.
It does not add syntax, a new checker, provider, task strategy or Host owner.

Each input range maps authored column names to private physical slots. ON can
reference all preceding ranges and its current right input. Forward ranges,
ambiguous names and duplicate range aliases are rejected. USING removes the
right key from unqualified visibility while retaining both qualified columns.
Explicit projection and ORDER BY use the existing scope machinery: an output
alias wins within an ORDER expression, qualified inputs remain distinct, and
sorting does not reevaluate SELECT expressions or publish private slots.
After DISTINCT, removed input slots cannot supply sorting values; an identical
selected expression reuses its output slot.

DATA uses the existing producer cache. Repeated references share their original
input/capture; the Frontend adds no acquisition owner or forced materialization.
The first JOIN projection assigns the left input's private column slots; an
additional seed SELECT is unnecessary. Selected expression evaluation and JOIN
ceilings are unchanged, and no Host capacity allowance is increased.
Standalone Values inputs are emitted once per producer. Existing JOIN output
ceilings remain enforced. FULL chains are explicitly unsupported until their
stable-row identity/coalescence boundary is adapted. Post-projection Pipe JOIN,
arbitrary ON predicates, aggregate/scope combinations and the wider original
SQL/Pipe milestone are not declared complete here.

## Independent fixtures and executed evidence

- [JOIN chain tests](../../src/query_program/join_chain_test.mbt) include a
  manually authored existing-IR Program, ordinary/CTE/DATA scope, USING,
  DISTINCT, invalid names, shared capture and an insufficient output ceiling.
- [Public cases](../../spec/frontend/fixtures/join-chain/cases.json) contain
  nine positive and four refusal expectations. They cover alias collisions,
  qualified input sorting, repeated selected expressions, NULL extension,
  CTE-body chains and an acquired producer reused by three consumers. The last
  case expects ten rows, retaining all eight combinations for the duplicated
  id=3, and exactly one source acquisition session.
- The normal external-package Local/HTTP acceptance driver consumes these
  cases and compares Named Result rows, column order and complete contracts;
  existing attach, resubmit and no-additional-acquisition checks also apply.

Executed locally on the implementation tree: targeted JOIN tests 17/17, then
the affected `query_program` JS package 168/168. Formatting and Node syntax are
checked separately. These results establish lowering and ordinary checker
admission, not public Host execution. No local full Core, all-target, packed,
native or proof campaign was run. Public Local/HTTP and other backend results
must be recorded from the submitted fixed SHA before this unit is complete.

## Follow-up to the initial automatic CI

Run [37124401491](https://github.com/actql/actql/actions/runs/37124401491),
source `2f78352b820f32353860f6f45785cdbadbd21fc7`, identified two failures:
the query-text rules digest had not been regenerated, and the first new packed
Local example failed before publication. The CI package source is test merge
`6a351574c88e316269214046ddcb7a1164db8351`; its additional NEAREST handoff
files do not alter the JOIN implementation. Do not treat the two entire trees
as identical.

A bounded diagnostic reused those normally produced packages. Tasks 0–23
completed; task 24 failed to reserve execution capacity: 539,299,328 bytes
against the existing 536,870,912-byte ceiling. The extra pure seed projection
was removed by assigning its columns in the first JOIN projection instead.
The corresponding ordinary JSON Program, submitted to the unchanged packaged
Client/Host, reached Named Result with rows `[{"y":1,"z":200},{"y":2,"z":100}]`
and ordered nonnullable number columns `y`, `z`. This checks the proposed Program
execution, **not** the updated source compiler or HTTP acceptance. The original
nine-positive/four-refusal source fixtures remain the product acceptance target.

Query-text documentation is a Grammar Manifest preimage. Regeneration changes
its rules SHA-256 to
`5bb6f784249ac4d0045be159779759a3e4c17fce84f3bb7f54c568a14199bbd8`
and the grammar body CID to
`sha256:24f53c1f64028206dbc01f6c3d0c11d991c8c9d512581fdfd007a250315f8bbd`.
Compiler identities that bind that manifest consequently change; the manifest
resource pin, normative imports and independent canonical identity vector are
updated together. Wire/schema versions stay at 0.1. Expectations are derived
independently from the normative preimage, not copied from compiler output.

NEAREST's installed Host connection is a separate D-coordinated dependency;
these pure relational changes do not enable VecA profiles or replace that work.

## Integrated history repair and exact-head CI follow-up

Source `341d505da1915c778f68bd1b90e1ecfd2c0c3e8a` normally integrates main
`b36d7864b57dc654cc03f583d8391e9ba2a506b3`. It adopts the existing #246
main-merge resolution record, unchanged, from
`5d8a0baf5f35b5f75598d0debd281dea2954720b` in #268. The actual retained
Git-history validator and automatic CI preflight pass; no validator policy,
workflow or existing declaration was rewritten.

Automatic run [37131266399](https://github.com/actql/actql/actions/runs/37131266399)
tests merge `dd1b0a441871734b7288af3f6771ba96e0496bc6`. Core's independent
Run-materials vector check found the preceding grammar-bound expected CID.
The follow-up preserves that historical vector and updates the current vector
and MoonBit fixture using the independently assembled canonical preimages,
without consulting product issuer output. The two Node vector tests pass.

Packed Local now passes the first `join-chain-alias-expression` case,
including rows, descriptions, attach and same-request replay counters. It then
fails the `join-chain-qualified-input` row comparison. That source has b.y=20
for id=1 and b.y=10 for id=2, and specifies ascending `ORDER BY b.y + 1`.
Its authored expectation lists id=1 before id=2, contrary to 11 preceding 21.
The returned rows are `[{"y":1,"z":200},{"y":2,"z":100}]`.
The fixture is retained pending an explicit correction decision; production
sort semantics must not be reversed to satisfy it. Remaining chain cases,
refusals and HTTP were not reached. This is partial public execution evidence,
not the nine-positive/four-refusal acceptance completion.
