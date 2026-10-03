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

NEAREST's installed Host connection is a separate D-coordinated dependency;
these pure relational changes do not enable VecA profiles or replace that work.
