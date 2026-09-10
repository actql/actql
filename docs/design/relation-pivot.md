# Pivot type checking

`relation_typing.check(Pivot, ...)` checks the closed
[pivot contract](../spec/language.md#reshaping) using the common aggregate result
rules for its six functions. Input and output are Relation schemas, including
qualified index/value references. No row is evaluated or materialized.

The checked pivot retains authored index occurrences and values separately from
canonical generated column order. Repeated index names produce only one output
field. Empty values and empty index are admitted without skipping validation.
`PivotPartitioning` retains the obligations to establish index groups even for
unmatched/null column values and synthesize the global empty-input group.

`fill` has the exact whole-value CellValue boundary, not an expression parser.
Literal payloads use contextual value admission (including decimal wire strings).
Parameter fills retain the declared contract and name with `BoundFill`; runtime
values and constraints are not guessed from defaults. Assignability does not
introduce decimal precision widening or implicit conversions. A literal NULL
can fill a nullable result without constructing a reference. Other literal
payloads use value admission's existing reference-evidence restrictions.

Literal admission is done once per operation, not per generated column. It
reserves a conservative additional source traversal from the shared work,
node and text budgets, with bounded value admission beneath that reservation.
Recursive contract comparisons are likewise reserved and charged cumulatively.
The budget is logical admission work, not a heap-memory ceiling.

`first` retains `StableInputOrder`; sum/avg on binary64 retain numeric observation
obligations. Capacity, bucket null exclusion, fill application and publication
remain downstream work. Checked types are not stable-order or cardinality proofs.

Existing reference paths reject empty axes or out-of-domain pivot values,
enumerate generated columns in authored order, or restrict decimal fills.
Those paths are not authority for changing the current specification. AoA
lowering must bridge these differences before claiming execution compatibility.
