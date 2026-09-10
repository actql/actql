# Cross join checking

`relation_join.check_cross` checks the closed
[`cross_join`](../spec/language.md#cross-join) body
`{with, select?, right_rows?, max_output_rows?}` against two complete flat
Relation schemas. The pipeline resolves `with` and its current/step-selected
left operand, preserving ordered left and right occurrences even for a shared
target. There is no `left` override, equality key, join kind or null-key mode.

The output qualification and optional alias projection share ordinary join's
implementation. Both sides retain their original field contracts, without null
extension. A nonempty `select` map can alias a qualified source more than once;
output names are flat and retained in canonical UTF-16 order. Unqualified or
unknown source references fail. A raw qualified operand needs an explicit flat
projection before another join. Empty flat schemas are valid and imply nothing
about the number of rows.

`right_rows: one` is retained as a mandatory singleton validation, never as a
request to select or truncate the right input. The checker does not infer it
from an empty schema or a projection. Output enumeration is left-major, then
right input occurrence order; operand identity products are not represented by
a fabricated field. Product bounds, Host ceilings, positive guard admission,
operand identity and order remain unresolved obligations until their evidence
boundary discharges them. This structural checker does not execute the product
or claim a proven numeric bound without input bound evidence.

The optional guard uses ordinary join's positive safe-integer literal or whole
numeric Parameter rule. A Parameter default is not read to pretend binding is
complete. The checked result retains the symbolic guard and binding obligation.

Whole source/operand/Parameter preflight and projection share cumulative
work/text/node limits, with iterative nested traversal. Tests cover exact limits,
nullable contracts, aliases and detached collections, empty schemas, malformed
assertions/guards, repeated pipeline operands and explicit Result projection.
The generated embedded Program schemas and their artifact CIDs are checked by
`scripts/cross-join-schema.mjs`. These checks are not row execution or physical
resource conformance evidence.
