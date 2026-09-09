# Owned tree decoding

`decode_core` admits an editable `source_value.Node` into a bounded, privately
owned tree and exposes opaque `Cursor` and `ObjectView` handles. It is a structural
reading boundary, not a parser, canonical-artifact validator or Program checker.

## Admission and ownership

`admit` validates raw Unicode strings and keys, rejects exact duplicate keys,
checks explicit limits, and copies the input structure. It preserves field order,
string spelling and numeric atoms. It neither normalizes text nor sorts keys.
Thus `é` and `e` followed by a combining acute accent remain distinct keys, and
NaN, infinity and negative zero in manually constructed Nodes remain raw numbers.
Numeric readers apply their own constraints after admission.

The [JSON source parser](json-source.md) already normalizes authoring text and
rejects invalid source numbers. Those guarantees come from parsing, not from
`decode_core`. Neither boundary proves canonical-artifact or domain validity.

Admission is a synchronous snapshot; callers must not mutate its input concurrently.
After success, input arrays can be changed without affecting any cursor. Returned
element arrays, field-name arrays, paths and shallow views are detached. No API
exposes the private Node storage or mutable field index. A child cursor retains
the owned tree until the cursor is released.

Traversal and copying use explicit continuations and a flat arena. Child references
and parent links are indices; navigation does not repeatedly concatenate full paths.
Paths are materialized iteratively only when requested or when producing an issue.
Shared input subtrees are copied and charged for each occurrence. Cyclic input is
rejected through the node or depth allowance, not treated as a shared graph.

## Resource limits

Every call supplies all four `Limits` fields; there are no implicit allowances:

| Field | Meaning |
| --- | --- |
| `max_nodes` | Every value occurrence, including containers; keys are not nodes |
| `max_depth` | Open containers: scalar root zero, root container one |
| `max_string_bytes` | Raw UTF-8 bytes of each individual key or string value |
| `max_total_string_bytes` | Sum of those raw bytes across all key and value occurrences |

All fields are nonnegative Int values. Zero is valid, equality is accepted, and
negative values are rejected before traversal, including in directly constructed
records. Byte accounting subtracts from the remaining allowance rather than
summing potentially overflowing totals. These limits bound this admission work;
they do not account for source-span metadata, JSON encoding overhead or process
memory as a whole. Callers remain responsible for their supplied metadata and
schema declarations, including allowed field-name lists.

The byte checks do not implement the language's normalized string constraints.
Those require canonical strings, as described in the
[scalar helper contract](decode-foundation.md#unicode-limits-and-diagnostics).

## Reading and failures

`open_object` permits all names; `closed_object` checks allowed names in source
order without imposing required fields. `field` distinguishes missing, explicit
null and non-null values. `lookup` returns a cursor for explicit null, whereas
`required` rejects both missing and null. No operation inserts defaults or coerces
types. Nullable required fields can use `lookup` or `field` explicitly.

`text` and `boolean` require exact kinds. `finite_number`, `safe_integer` and
`int32` delegate the numeric bounds to `decode_scalar`. Finite reads preserve
negative zero; conversion to an integer yields zero. `decimal_int64` accepts the
internal canonical decimal Int64 spelling, not the language's Decimal type or a
proof of a field's safe-integer constraint. It reports syntax, spelling and range
failures as `InvalidDecimal`. `view` exposes raw numeric atoms without implying
that a numeric reader would accept them.

Issues carry a local typed kind, a detached array of key/index path segments and
the supplied source span. Key failures use key spans; value failures use value
spans. Missing fields append the missing name to the path and use the containing
object's span. Admission preserves this provenance but does not authenticate
source coordinates. Public diagnostic codes and messages belong to consumers.

Negative limits fail first. Traversal then follows source order, checking node
allowance before container depth and minimum immediate child count before copying
children. For each object entry, key Unicode/bytes and exact duplication are
checked before its value. Text scanning uses the tighter remaining per-string or
aggregate allowance and retains the scalar helper's lower-bound/scan precedence.
Consequently a budget failure can precede malformed Unicode or a later duplicate.
All exceeded resource limits report `BudgetExceeded`; no partial cursor is returned.

Whole-tree admission precedes object closure and field reads. Across separate
reader calls, the consumer determines error order; there is no global diagnostic
sorting. A failed reader does not change the cursor or prevent other reads.

Tests run the same ownership, presence, span, Unicode, numeric and budget cases on
JS, Wasm and native, including depth 10,000, wide containers, shared subtrees and
cyclic input. These are structural-reader tests, not execution conformance.
