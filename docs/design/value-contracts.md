# Value contracts

`value_contract` implements the [closed value contracts](../spec/language.md#value-contracts)
and their four shared type relations. It does not validate runtime values, resolve
Parameters, check a Program or establish reference authority.

## Admission and ownership

`read_author` and `read_checked` accept an owned `decode_core.Cursor` and explicit
`Limits`. They implement distinct closed grammars for all twelve types. Both
return the same read-only checked `Contract`; recursive child contracts and field
arrays cannot be constructed or mutated through the public API. `fields` returns
a detached array in UTF-16 key order.

Authored objects expand to `additional_properties: false`; authored vectors expand
to `element_type: f32`. Those fields are rejected at the author entry and required
with their exact values at the checked entry. Checked string extents are not author
vocabulary. Optional members stay absent when omitted; explicit `null` is rejected.
Every contract, including array items and object properties, requires `nullable`.
Parameter-specific omissions, defaults and constraints belong to the separate
Parameter grammar and binding boundary.

`read_parameter_syntax` is a separate [Parameter type adapter](parameter-binding.md).
It applies recursive Parameter nullability shorthand and preserves constraints,
default and metadata cursors for declaration admission; it does not validate the
default or metadata itself. The general `read_author`/`read_checked` grammars are
unchanged.

Both entries allow empty object fields. Field names follow the Language rule,
including line breaks, and reject dots, blank names, `__cid` and the `__actql_`
prefix. A field named `meta` is ordinary schema data, not an annotation. The
value-contract envelope itself does not acquire an annotation member.

The cursor boundary requires normalized NFC/LF text. Source parsers establish
this before admission. Contract readers check rather than repair noncanonical
field names and reference-kind/media strings from other cursors. They are not
canonical JSON text parsers: whitespace, token spelling, duplicate source keys,
signatures and issuer evidence remain the enclosing admission boundary's work.
Reading checked bounds does not prove the evidence from which those bounds arose.

Decimal precision is 1–38 and scale is 0–precision. Array and checked string bounds
are nonnegative safe integers, including zero. Vector dimensions follow the
positive finite integral number domain; no safe-integer ceiling is added where
the contract specifies none. Dimensions are stored as binary64, not narrowed to a
machine array length. Actual allocation and supported dimensions are later checks.
Reference kind and present media type are nonempty canonical strings; no additional
identifier, MIME or nonblank grammar is inferred. Admission preserves declared
bounds without adding a cross-bound satisfiability requirement.

## Limits and diagnostics

`max_nodes` counts contract occurrences, including the root, rather than JSON
members. `max_depth` counts child-contract edges: a root contract has depth zero.
`max_text_bytes` counts type-tag values, checked `f32`, object field names and
reference-kind/media strings in UTF-8. Fixed property names are not charged again.
These limits supplement the source/owned-tree budgets; they do not replace them.
Zero limits are legal, exact boundaries pass, negative limits fail before reading.

Traversal is iterative. Pending children reserve node budget before they are
queued, and input declaration views are reused. Field arrays are sorted once;
declaration width does not cause repeated map construction. Budgets bound admitted
work, not total heap usage or elapsed CPU time.

Decode errors retain shared typed issues, paths and spans. Contract-specific
errors identify invalid types, names, fixed members, ranges, normalization and
budgets. Invalid field names point to the key span. Structural/type selection
precedes local field checks; children are read in source order. Admission can reject
an entire child frontier for insufficient budget before examining child contents.
These are package diagnostics, not stable CLI codes. No partial contract escapes.

## Type relations

- `type_equal` compares complete checked contracts, including optional bounds and
  nullability. Object source order is irrelevant.
- `assignable(actual, expected)` implements directional compatibility without
  coercion. Actual upper bounds must be no larger, lower bounds no smaller, and
  absent bounds do not prove a restriction. Non-null can flow to nullable.
- `join_nullability` preserves the same recursive base structure and fixed
  decimal/vector/ResourceKind parameters, ORs nullability and retains the least
  restrictive common bounds. Different Artifact media restrictions join to absent.
  Incompatible types return `None`; a budget failure returns no partial join.
- `key_comparable` compares non-null key domains. Decimal precision/scale may
  differ; ResourceKind must match; Artifact media restrictions may differ. Object,
  array, JSON and vector are not admitted key domains. It does not compare values.

The first three relations require `max_pairs`, counting scheduled contract pairs
including the root. Pending pairs reserve budget; zero is insufficient for a root
comparison and negative limits are invalid. Traversal is iterative. Key comparison
only inspects the root domain and needs no recursive-pair budget. Relations apply
the specified structural rules, not general satisfiability or expression inference.

## Canonical output and verification

`emit_checked` emits the whole checked contract through a caller-owned bounded
Writer. `stringify_checked` provides text with explicit byte/node/depth limits.
Text, measurement and hash sinks share the same canonical emission. Omitted bounds
are not synthesized, object field names are UTF-16 sorted, and no field is removed
from the preimage. Output limits use the Writer's JSON accounting, not contract-node
accounting; objects, fixed fields and scalar members consume that budget normally.

[Fixed vectors](../../portability/corpus/value-contracts.json) include empty object
types and line-break field names. `generate:value-contracts` emits MoonBit tests
from these fixed expectations; `check:value-contracts` verifies generated freshness,
embedded field-name/empty-object schemas and their registered CIDs. It does not
derive expected contracts from product output or certify runtime conformance.
Package tests cover all types, rejection boundaries, the four type relations,
ownership, source diagnostics, output budgets and 10,000 nested contracts on
JS, Wasm and native. Field and value validation by downstream consumers remains
outside this package.
