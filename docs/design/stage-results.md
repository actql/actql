# Source-bound stage Results

`stage_results.check` connects every stage's authored `results` map to its exact
pipeline from [source-bound operation collection](stage-parameters.md).
It derives the Result source from the retained Program, not a caller-supplied
replacement map, and invokes the existing
[Relation Result checker](relation-results.md). The immutable result retains
the operation collection and each checked Result set.

## Grammar and references

Language's `ResultDefinition` is closed over `from`, `fields`, `order_by` and
optional `meta`. The first three are structural selectors, not Parameter value
roles. Their existing readers reject Parameter-shaped objects; an additional
`$param` member also rejects. Annotation content remains opaque business data.
Thus Result validation, rather than a generic JSON reference scan, establishes
that these admitted bodies do not add Parameter occurrences.

The fixed Sketch `87dc7144` Parameter resolver also classifies `results`,
`fields` and `order_by` as structural keys. Its generic path-based discovery and
older unstaged annotation positions are not reused as authority for this
composition. The current normative grammar and existing Result admission are
the governing rules.

## Limits and obligations

Result count, visited nodes and text bytes share one allowance across all stages.
Depth is the existing per-traversal maximum. `max_work` includes the retained
operation-reference collection's reported work, one registration unit per stage
and every Result check's reported work. A budget smaller than already consumed
operation work rejects before Result checking. Exact aggregate limits pass;
failure returns no partial checked Program. Result failures retain the stage
index and existing diagnostic path/span.

These limits do not retroactively account for earlier parsing, declaration
admission or pipeline type checking. They are bounded composition accounting,
not a wall-clock or heap quota. A complete checking entry must additionally
compose those earlier budgets.

Every Result still retains `TotalDeterministicOrder` as an obligation. This entry
does not resolve publication order, capacity, input provenance, cross-stage
Result-import contracts or runtime execution. It also does not inspect Input,
Effect or opaque-binding value roles or establish complete Program usage and
identity. The operation reference index remains operations-only; a successful
Result check does not silently rename it a full Program semantic index.

Tests cover all-stage attachment, retained pipeline ownership, metadata opacity,
Parameter rejection in structural slots, unresolved publication obligations and
aggregate exact/one-less work, node, text and Result limits.
