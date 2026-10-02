# Frontend r1: adopted query surfaces and machine Program input

Frontend r1 lowers adopted source forms to the common Program. It does not add an
execution engine, an alternative checker, or authority to acquire inputs or
apply Effects. The [adopted profile](../../spec/frontend/frontend-profile-r1.json)
separates accepted, restricted and rejected surfaces from implementation and
execution evidence. `supported` in the imported design means adoption, not
installed functionality. The [baseline and acceptance index](../../spec/frontend/README.md)
record delivery evidence separately.

The [standard-profile ledger](frontend-standard-profiles.md) selects semantic
references and distinguishes ActQL extensions. Common Program meaning must
align with adopted rules; historical implementation choices are not fixed
merely because an existing operation already represents them.

The accepted follow-on [SGA surface design](frontend-sga-surface.md) reuses
logical DATA bindings and existing Graph operations. It remains separate from
implemented syntax and public Host execution evidence.

## One Program and one operation vocabulary

JSON and YAML remain public machine inputs. The retired internal fixture
representation records the complete
closed Program envelope: metadata, IDs, parameters, opaque bindings, stages,
inputs, explicit steps, Results and Effects. Expression strings inside JSON
bodies retain the existing expression grammar. Object order is immaterial;
array order and explicit steps are preserved. Missing optional members and
explicitly empty permitted members are not conflated. An empty Effect map can
be represented by `EFFECTS {};` in the historical internal fixture language,
not the current public source language.

In historical fixtures only, `STEP` carries an ordinary JSON step, including its metadata and output name.
`OP` selects a name from the existing closed operation inventory. The minimum
structural `DATA` form chains only native operations, for example
`DATA x = OP values {...};` and `DATA y = FROM x |> OP filter {...};`.
These record historical productions, not current public examples. `WHERE`,
`SELECT`, query expressions, domain aliases and `MATCH` use the query frontend.
The entire old envelope is rejected by public source routing. Supported
SQL/Pipe and Graph query syntax follows query-text.md; the adopted target is
broader than implemented syntax. See [migration mapping](frontend-language-migration.md).

The internal fixture formatter reconstructs the admitted structure, including unused
steps and explicit no-ops. It does not optimize the Program or preserve comments
and whitespace. It does not use the metadata-stripped identity projection as
its source. Source text and semantic identity are distinct: trivia can change
source positions without changing the canonical Program.

## Bounded construction and origins

The frontend constructs the JSON-model source through a bounded builder and
ordinary admission. No public unchecked Program constructor is introduced.
Caller-supplied node counts, depths or byte counts are not trusted. Duplicate
keys, including normalization collisions, are rejected before they can be
collapsed into a map. Construction fails without publishing a partial Program
when a limit would be exceeded.

The existing `source_map.admit` traversal supplies owner-bound annotations and
ordinary `decode_core` admission. The builder retains origins through the
existing source-map mechanism rather than creating a second cursor identity
system. `stage_syntax` remains the Program issuer; `program_check.check_parsed`
and `check_parsed_with_evidence` remain the semantic checker entries.

Origins refer to original UTF-8 input before NFC and line-ending normalization.
Byte offsets, Unicode scalar columns and UTF-16 positions are distinct. Invalid
or out-of-range spans and annotations from another admitted owner are rejected.
Generated nodes retain their originating source range and generated-node role;
they do not claim an invented textual token range.

## Identity and execution boundaries

Canonical equivalence is compared under the same applicable contract pins.
Program IDs, Effect names, explicit steps and semantic array order remain
significant according to their existing contracts. A changed Grammar Manifest
can change dependent compilation identities; frontend equivalence is not a
promise that all Plan identities survive a grammar change.

The Grammar Manifest's structural-text fields bind the withdrawal grammar
and policy, separately from the existing Program source grammar and expression
contracts. They no longer authorize a structural parser or formatter. Its
pins, dependent artifacts and independent vectors change together with those
obligations; the Program schema remains unchanged.
All owned contracts remain on the initial 0.1 baseline.

That schema statement describes structural-text retirement, not a prohibition
on later coordinated semantic changes. The profile principle
`machine_program_semantics_preserved` requires lowering equivalence under the
applicable pins. It does not prohibit correcting the common model to match
an adopted standard. Such corrections update affected laws, schemas, pins,
canonical identities and independent vectors together.

Pure checking performs no provider I/O. Execution uses the normal Host and
existing checked owners, retaining Effect declarations and acquisition
boundaries. Source translation does not prove backend support for an operation.
The 72-operation language inventory and Local execution-path accounting count
different things.

The lightweight transport SDK does not depend on the parser or Core. Existing
`aql`, `start`, `attach` and Result behavior stays intact. Historical structural tests are fixture-tool tests; they cannot submit old
text to the public Host. Public machine-input execution and new source
execution are distinct acceptance claims.
No second Run API, SQL engine, retry mechanism or Effect scheduler is needed.

## Query profiles and remaining adoption work

Query, Pipe and limited graph patterns lower into the same Program. The
profile registry records their
preconditions and rejection reasons. Restricted syntax is not expanded by
guessing schema, inserting casts, hiding acquisition, approximating computation,
or treating a runtime capability declaration as execution evidence.

Known gaps in the imported acceptance matrix are explicit fixture requirements
in the registry. They remain work to do; an empty evidence array is never a pass.

### Quoted String profile

The selected lexical reference is
[GoogleSQL lexical structure at the pinned reference revision](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/lexical.md#string-and-bytes-literals).
Query strings lower to ordinary String literals. Their decoded scalar values
are retained by the common value, canonical identity and serialization owners;
the Frontend does not introduce an alternative String representation.

| Reference form | Frontend and common meaning | Coverage boundary |
| --- | --- | --- |
| Single/double quoted String | The same bounded decoder and String expression; either quote may contain the other quote | Raw CR/LF is invalid in these plain forms |
| Standard simple, octal, hex and Unicode escapes | Decode once to the exact Unicode scalar sequence | Reject malformed escapes, surrogate values and values above U+10FFFF |
| Backtick identifier | Name resolution, separate from String data | Existing identifier escape subset remains; wider escapes are not implemented |
| Triple single/double quoted String | Ordinary String after source newline/escape decoding | Three matching unescaped quotes terminate the chunk; physical newlines are permitted |
| Raw String | Preserve each backslash and following scalar in an ordinary String | Prefix applies only to its immediate chunk; odd trailing backslash and plain-form physical newlines reject |
| Adjacent String chunks | Concatenate decoded values into one String expression, retaining the original source range | Whitespace/comment separation is required; identifiers and String/bytes mixtures do not concatenate |
| Bytes literal | Requires the reference's distinct bytes meaning | Not yet implemented; never stringify bytes silently |
| Graph LABELS annotation | Historical annotation syntax, separate from query literal syntax | Query-only escapes and raw controls do not widen annotation admission |

Independent fixtures compare decoded values and ordinary Programs, including
CR/LF/CRLF, composed/decomposed Unicode and backslash followed by `n`. The
packed source fixtures require rows, declaration-order contracts and UTF-8
extents through the same Local/HTTP Result boundary. Listed fixture obligations
do not by themselves establish execution success.

## Shared query vocabulary and scope

### Relational query bodies

The selected [GoogleSQL Pipe reference](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/pipe-syntax.md)
allows standard and Pipe syntax to be mixed, including different syntax in a
subquery and its parent. A named FROM/JOIN subquery and a CTE therefore share
the relational-body parser, original source positions and query resource
budgets. SELECT heads retain their optional ORDER BY/LIMIT; FROM heads and
SELECT heads can both use the existing pure relational Pipe operators.

Both contexts lower through the existing producer/Stage Result boundary. A
parent reads the body's output columns and range variable, not the body's
hidden source columns or displaced aliases. Parsing does not query a Catalog,
copy a source, authorize acquisition or introduce another execution engine.

The same query-expression parser covers parenthesized roots, nested
non-recursive WITH bodies and set-operation bodies. A Pipe tail after a
parenthesized or combined set producer operates on its retained output; it
does not expand that producer into another acquisition. Nested CTE declarations
retain lexical visibility and are bound after their bodies, so an inner
declaration can read an already-visible outer CTE before shadowing its name.
CTE aliases are case-insensitive even when quoted, independently of the
Source View identifier profile. Hidden body columns and out-of-scope CTEs are
not made visible by internal producer names.

An ORDER BY expression following a set is resolved only against the combined
output fields, using its first operand's output names. Existing common
expressions derive any sort-only slot once; repeated equivalent terms reuse
it. Ordinary sort and a final projection preserve the declared output without
publishing hidden sort fields. Operand range variables, non-output columns
and aliases unique to a later operand remain out of scope. This follows the
selected [GoogleSQL ORDER BY reference](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/query-syntax.md#order_by_clause)
and its [independent analyzer cases](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/testdata/orderby.test).

This does not claim every query composition is implemented. Positional numeric
ORDER BY terms remain an implementation gap and are not interpreted as
constant sort keys. INFER/Graph-query placement retains its separate boundary;
this relational unit does not make those queries executable within a CTE or
derived table.

SQL and Pipe use the adopted GoogleSQL vocabulary and one query expression
representation before lowering to existing Program expressions and operations.
They do not roundtrip generated expression strings through the legacy parser.
The source remains bounded and carries original byte positions into admission.
See [semantic decision criteria](semantic-decisions.md#vocabulary-across-representations).

SELECT aliases take precedence over input names in GROUP BY, HAVING and final
ORDER BY, subject to ambiguity, grouping and clause-visibility checks. WHERE and
the same SELECT list cannot refer to newly introduced SELECT aliases. Qualified
references retain their source binding; qualification does not authorize an
ungrouped reference after aggregation. Analytic arguments and OVER use their
own context-dependent scopes, not a copy of final ORDER BY's scope.

Ordinary SELECT may order by visible, unprojected source expressions. DISTINCT
orders only by expressions legally resolved from its projected output, including
selected-expression and alias references. Hidden sort fields never participate
in DISTINCT equality or leak into Results. Alias resolution reuses the relevant
computed slot and does not duplicate evaluation or change failure/resource
accounting. Proof-only tie completion remains the existing compiler's concern.

These name-resolution rules follow [GoogleSQL query syntax](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax)
and [window function calls](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls).
The selected ActQL profile rejects unsupported forms explicitly. NULL,
numeric and failure behavior must be compared with the selected reference;
an intentional difference needs a named profile or recorded rationale. Explicit
acquisition and authority boundaries remain common execution obligations.

| Reference term | Frontend representation | Existing semantic representation | Difference or boundary |
| --- | --- | --- | --- |
| SELECT list | Ordered projection expressions | derive and select | Preserve evaluation once and output order; duplicate output names rejected |
| Range variable / SELECT alias | Separate scope bindings | Resolved field slots | Pipe SET/DROP/RENAME retain prior range slots; Pipe AS replaces all old ranges with the current row; no helper egress |
| WHERE / HAVING | Pre-/post-aggregate predicate | filter plus existing expression tree | Three-valued logic and common demand/failure contracts; do not infer mandatory short-circuiting or evaluation order from GoogleSQL AND/OR |
| GROUP BY / aggregate call | Group keys and aggregate expressions | group | Not an analytic partition; canonical aggregate failure order retained |
| Analytic partition / window frame | OVER partition, order and ROWS frame | analytic | Not TEA event-time windows; only adopted signatures/frames |
| Final ORDER BY | Query output ordering | sort | Explicit ASC NULLS FIRST / DESC NULLS LAST; proof-driven tie completion |
| INNER / LEFT / FULL / CROSS JOIN | Scoped relation join and equality keys; USING exposes a merged unqualified key | join / cross_join plus checked output bound; FULL key through derive/coalesce | FULL needs stable row identity; no implicit representative row or key |
| UNION / INTERSECT / EXCEPT | Positional or exact BY NAME alignment | projection plus append/distinct/row-set | No implicit type promotion or missing-column padding |
| Nonrecursive CTE | SELECT or relational Pipe body; SELECT or Pipe head after WITH | Shared Stage captured input and step references | No reacquisition per reference; no recursive CTE |
| FROM subquery | Named noncorrelated query source | Checked Stage Result with a source alias | No correlated reference or independent runtime; nested source stages preserve ordinary admission |
| Parameter | Named query parameter | Existing parameter expression | New @name spelling; legacy $name remains unchanged |
| CONCAT / ACTQL.CONCAT | Closed function mapping | concat_strict / concat | Strict STRING NULL propagation versus explicit legacy null-skipping |

The table defines obligations, not implementation status. Delivery evidence
records unimplemented features separately from intentional incompatibilities.
