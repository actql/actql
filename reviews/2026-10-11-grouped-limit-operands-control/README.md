# Grouped LIMIT and OFFSET operands

Status: independent Frontend connection; guarded runtime and public acceptance
are not yet executed. Baseline Git object:
`6d0f42f54ce7380fda012c641025ac3ea21060a5`. This preserves the main Model,
Graph, Python, publication and Native Owner work. The attempted SSH fetch
failed with a DNS error; the named local remote-tracking object was already
available and is the exact adopted source, not a claim of a later server main.

## Counterexample and reference

```sql
SELECT amount, id FROM records WHERE id > 0
ORDER BY id LIMIT ((@count)) OFFSET (@skip)
```

Baseline `QueryParser::limit_integer` accepts a Parameter token or directly
calls `safe_integer`, which requires a Numeric token. The opening parenthesis
therefore fails with `Expected safe integer literal`. This is source-inspected
evidence, not an executed baseline failure. The existing common `take` Program
already represents count and offset independently as Parameter slots.

The selected [GoogleSQL LIMIT/OFFSET reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#limit_and_offset_clause)
allows constant expressions, literals and parameters. Removing transparent
grouping around an already supported integer or Parameter does not evaluate
or change its value. This unit connects that subset only. General constant
arithmetic, casts and calls remain coverage gaps. The common positive-count
requirement (including rejection of zero) and proven input order remain
unchanged; they are not restrictions of GoogleSQL itself.

## Implementation and independent expectations

Use the existing bounded expression parser only at a grouped operand entry,
strip Parenthesized nodes and require Number or ParameterReference. Reuse the
existing digit-by-digit safe-integer validation, zero policy and work charging.
The AST still carries the existing QueryInteger; the lowerer still emits the
ordinary `take.count` / `take.offset` slots. There is no new evaluator, Owner,
cast, parameter default, JSON correction, fallback or resource-limit change.
Frame-boundary grammar stays separate so LIMIT grouping does not silently
admit grouped ROWS distances.

The syntax controls distinguish count and offset names, safe integer endpoints,
zero offset, grouped quoted parameters, expression budgets and explicit refusal
reasons. Complete independent Values Programs cover bound and literal operands;
ordinary checker controls retain missing/invalid binding rejection. These tests
are authored but are not executed evidence.

The existing `limit-parameter` public fixture gains five normal and five refusal
cases; no new driver or selector is introduced. Expected rows and full schemas
are handwritten. For source IDs 3,1,2,3,0 with a nullable amount, `count=2` and
`skip=1` produce `[{amount:20,id:2},{amount:30,id:3}]`; reversed operand roles
would produce a different count. Pipe `count=1,skip=2` produces one row, while
zero offset retains the SQL NULL and duplicate id=3 rows. Typed empty input
retains ordered columns `amount` (nullable Number), `id` (non-NULL Number).
The source WHERE remains `id > 0`; the existing expected acquisition count is
one. Existing public hooks retain same-request and Result reread checks.

The independent authored inventory has 3,892 declared occurrences, digest
`cb0c6a0c7a19cba0de812541c5f49bfa3edb50e06c974a5088aa5e73f1151f8b`.
Enumeration is data preparation, not execution of those cases. Existing
`--limit-parameter-only` and full registration consume the same fixtures.

## Identity and generated artifacts

Preserve the complete old main grammar/Values/Program/Run preimages in
`scripts/fixtures/pre-grouped-limit-operands-values-identities.json` and the
current independent preparation here. Only query grammar/rules change;
grammar-bound Template, Executable, Compiled and Run identities change.
AoA/barrier contracts, Values Unit/proof/ResultPlan and Program/semantic
identities remain unchanged from adopted main. Current fixed expectations
come from the normative preimage oracle, never a product Run CID.

Existing generators update compilation pins, metadata/family imports and
canonical vectors. Regeneration also registers main's already-present capture
schemas and three INFER requirements as pending evidence. No common Model
contract or implementation is authored here. Old identity vectors and failures
remain retained. D was informed of the exact parser function boundary; no CTE,
assert, Effect, Source predicate or JOIN-upper-bound function is edited.

## Verification and handoff

Read-only freshness, JavaScript syntax, formatting and whitespace receipts are
separate from compilation/runtime/public checks. B's prior process-inspection
guard rejection is neither retried nor bypassed. Prepared bounded commands are
tracked in [prepared-checks.json](prepared-checks.json) for an independently
authorized owner using its own clean fixed-source worktree. Public Local/HTTPS
needs normal same-source five packages and a separately coordinated Heavy slot;
none is started or reserved here. Wasm/Native runtime and CI remain unverified.
This connection does not claim full Frontend completion or close the separate
NULL set-context, nullable multicolumn or common zero-take gaps.
