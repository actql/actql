# Pipe column and range scope

The query frontend follows the adopted GoogleSQL/Pipe scope rules and lowers
them into ordinary Program operations. The common checker, planner and Host
retain ownership of typing, identity, ordering, authority and execution.
JSON/YAML Program remains a public machine input through those same boundaries.

| Source operation | Current columns | Existing range variables | Program representation |
| --- | --- | --- | --- |
| SET | Replace named values; all assignments see the input row | Original names and value slots remain | derive into private value slots, then explicit projection |
| DROP | Remove named current columns | Original names and value slots remain | current visible projection, with old slots retained only for demanded references |
| RENAME | Replace current names, retaining their value slots | Original names and value slots remain | named projection of existing slots |
| AS | Preserve current column names, order and values | Remove all old variables; bind the new name to the current row | change the compiler's scope bindings; no new read, execution or save boundary |

AS can reuse a displaced name. Quoting preserves spelling and syntax but does
not change the adopted case-insensitive range/column comparison. An old alias
cannot be recovered from the initial FROM name after AS. A dropped or renamed
current column can still be selected through its original alias before AS;
after AS only the new current row can be addressed. Internal slots never become
public fields merely because an alias refers to them.

These rules are documented by the
[GoogleSQL Pipe specification](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax),
particularly SET, DROP, RENAME and AS. They are not an attempt to retain an
incompatible legacy behavior. The normative owner is
[Query text profile](../spec/query-text.md#scope-and-lowering).

## Adopted KEEP target and source lowering

INFER and NEAREST with KEEP establish a new output scope. Only explicit KEEP
columns and the result STRUCT are visible; prior input aliases do not provide
a bypass to omitted columns. Required item/query/candidate keys remain inside
the result STRUCT even when KEEP is omitted. Named keys, nullability and
identity roles must be projected from the existing checked contracts rather
than inferred from row order or unverified names.

KEEP permits column references, aliases and known-schema wildcard expansion
in fixed input column order. It rejects output-name collisions and never adds
hidden fields or implicitly grants model egress. New calculations belong in
SELECT/EXTEND. Repeating a query's retained fields for several nearest matches
does not preserve query-only uniqueness.

NEAREST's proposed surface supplies query rows on the left and names the
candidate source explicitly. Lowering must wire the common nearest operation's
candidate input and `queries` reference correctly, then use common typed
projection and checked correspondence for KEEP. This does not redefine its
metric, exactness, ties or identity. INFER's nullable non-success value supports
known-field typed NULL; unknown fields remain errors. Outcome refinement and
correlation must use existing common evidence, without a frontend-only success
proof or a changed infer wire shape.

INFER's source parser and lowering now construct ordinary infer, one-to-one
join-back and object projections. This does not implement its shared checker,
ModelTask acquisition or evidence owner. Normal Host preparation continues to
reject execution before Run acceptance or source I/O. NEAREST KEEP retains
its explicit original-source unsupported diagnostic. These temporary gaps are
not permanent language prohibitions. The adoption profile and corrected FX-03
requirement distinguish source lowering from executed KEEP cases.

## Separate follow-on units

NEAREST KEEP and shared INFER execution remain subsequent completion units;
INFER source parsing/lowering is implemented separately from runtime acceptance.
Removing the older public STEP/OP surface is also separate: first inventory
public routing, SDK/CLI, documentation and distribution tests, then specify
their migration and removal. The column-scope change removes no input format.

The subsequent semantic matrix must address numeric domains and overflow,
STRUCT names/order/comparison, CAST and SAFE behavior, NULL and three-valued
logic, and ordering/tie evidence. Effect-only export and durable NULL-policy
recovery remain separate design/implementation units. These obligations are
not claimed complete by alias tests or by the earlier limited query milestone.
