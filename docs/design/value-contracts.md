# Value contracts

`value_contract` implements the [closed value contracts](../spec/language.md#value-contracts)
and their four shared type relations. It does not validate runtime values, resolve
Parameters, check a Program or establish reference authority.

## Admission and ownership

`read_author` and `read_checked` accept an owned `decode_core.Cursor` and explicit
`Limits`. They implement distinct closed grammars for all twelve types. Both
return the same read-only checked `Contract`; raw construction and mutation remain
private. Validated assembly functions can combine admitted children. `fields`
returns a detached array in UTF-16 key order; `field_count` and `field_at` provide
read-only indexed access without copying the array.

Authored objects expand to `additional_properties: false`; authored vectors expand
to `element_type: f32`. Those fields are rejected at the author entry and required
with their exact values at the checked entry. Checked string extents are not author
vocabulary. Optional members stay absent when omitted; explicit `null` is rejected.
Every contract, including array items and object properties, requires `nullable`.
Parameter-specific omissions, defaults and constraints belong to the separate
Parameter grammar and binding boundary.

Text may additionally retain an ordered `enum` vector in both general grammars
and the Parameter adapter. It intersects the existing extents; it is not another
scalar kind. Absence differs from an empty vector. Empty strings, repeated entries
and exact vector order are retained. Enumerants are well-formed Unicode data,
not NFC/LF identifiers: no normalization or inferred default is applied.

`read_parameter_syntax` is a separate [Parameter type adapter](parameter-binding.md).
It applies recursive Parameter nullability shorthand and preserves constraints,
default and metadata cursors for declaration admission; it does not validate the
default or metadata itself. It does not import Parameter defaults or `format`
into the general `read_author`/`read_checked` grammars.

## Public ModelTask type normalization

The public Task `input` and `output` records are field maps. The existing
`check_environment` Owner normalizes these maps with
`read_public_model_task_contract`, independently of Provider/default selection.
Only type positions expand a scalar name to `{type: name, nullable: false}` or
add omitted `nullable: false` to a typed record. Object `fields` and array `items`
recurse through that same adapter; enum members and schema field names remain
data. The intermediate parser preserves exact object keys, so a raw Cursor's
noncanonical name is still rejected rather than silently normalized. The complete
result passes through `value_contract.read_author_usage`.
Unknown fields, checked-only extents and Parameter-only rules are retained for
rejection, rather than ignored. General authored and checked contracts still
require explicit nullability. An unsupported logical type cannot become Number,
Decimal or String merely because those representations are available.

The private result retains the original immutable field-map Cursor, the admitted
Contract, its complete checked canonical wire/CID and charged work/semantic
node/UTF-8 usage. Checked schema identity comes from the existing canonical
emitter and SHA-256; authored key order does not alter it, whereas retained enum
order/repetitions and explicit nullability do. No result is an installed Task,
Provider binding, authority, numerical allocation or evidence of currentness.
The original Task/configuration and the actual registration still require their
existing nominal admission before execution or restoration.

`ModelTaskLimits.contracts` bounds the aggregate semantic tree. Its `bodies`
limits bound intermediate normalization and checked output bytes/JSON nodes/depth;
`max_members` additionally bounds the top-level field count. Separate complete
parser, admission, emitter and hash traversals are reserved against `max_work`
before those operations, using the caller's body bounds. The transformer uses
active-ancestry frames and indexed children rather than a detached field map.
Failure returns no partial checked schema. Original Cursor/tree, temporary wire,
parser/admission trees, checked Contract/enum backing, emitted wire, hash work and
returned aliases can overlap and belong in the existing consuming Owner's
retained/workspace inventory, including the intermediate UTF-8 byte backing;
these structural limits supply no physical funding.
The schema reader does not own external I/O, cancellation ACK or resource release.

Both entries allow empty object fields. Field names follow the Language rule,
including line breaks, and reject dots, blank names, `__cid` and the `__actql_`
prefix. A field named `meta` is ordinary schema data, not an annotation. The
value-contract envelope itself does not acquire an annotation member.

The identifier boundary requires normalized NFC/LF text. Source parsers establish
this for object keys before admission. Contract readers check rather than repair
noncanonical field names and reference-kind/media strings from other cursors.
Enumeration data has its separate exact-Unicode rule above. These readers are not
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
members. A present Text enumeration additionally charges its array and every
entry, including duplicates and extent-excluded entries. `max_depth` counts
child-contract edges: a root contract has depth zero. The enum array adds an edge
and each enumerant adds another; an empty root enum therefore needs depth one.
`max_text_bytes` counts type-tag values, checked `f32`, object field names and
reference-kind/media strings and every exact enumerant in UTF-8. Fixed property
names are not charged again.
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

### Constructing inferred contracts

`primitive`, `string_contract`, `decimal_contract`, `vector_contract`,
`array_contract` and `object_contract` construct checked contracts without a
JSON serialization/admission round trip. They retain the same type domains as
the readers: safe-integer size bounds, decimal precision/scale, positive finite
integral vector dimensions, and canonical closed object field names. Object
assembly rejects duplicate or noncanonical names, sorts by UTF-16 code units,
and owns its field array. It accepts an empty field set. It neither normalizes
names nor adds cross-bound satisfiability restrictions.

`string_enum_contract` validates the complete enum metadata against explicit
`Limits`, then detaches the caller's vector. Existing `string_contract` keeps its
old signature and absent-enum behavior. `TextEnumeration` has no public mutable
backing or constructor; indexed `text_enumerant_count`/`text_enumerant_at` views
distinguish absence from empty without copying the vector. Returned Strings do
not establish original installation, authorization or reference identity.

These are type-description functions, not proofs about runtime values or the
evidence for inferred bounds. `with_nullability` changes only root nullability;
it does not change child contracts or establish that a value is non-null.
The type checker remains responsible for justifying every refinement.

Assembly shares immutable admitted children rather than recursively copying or
rechecking them. Object limits count the newly supplied fields and their UTF-8
names only; they are not whole-tree limits. A caller constructing a sequence of
contracts must account for cumulative work and tree depth separately. Indexed
field access returns `None` outside the field range.

### Comparing contracts

- `type_equal` compares complete checked contracts, including optional bounds and
  nullability. Object source order is irrelevant; enum order and repetitions are
  part of the checked preimage and therefore significant.
- `assignable(actual, expected)` implements directional compatibility without
  coercion. Outside the finite Text-enum proof, actual upper bounds must be no
  larger, lower bounds no smaller, and absent bounds do not prove a restriction.
  Non-null can flow to nullable.
  An actual finite enum is inspected against its own extents before testing each
  allowed value against the expected extents and enum. Excluded entries remain
  retained data, not actual values. An absent enum cannot by itself prove a finite
  expected domain; this is not a general satisfiability solver.
- `join_nullability` preserves the same recursive base structure and fixed
  decimal/vector/ResourceKind parameters, ORs nullability and retains the least
  restrictive common bounds. Different Artifact media restrictions join to absent.
  Two present Text enums retain every left occurrence and append only right
  members not already present. If either enum is absent the join's enum is absent.
  Extents and membership are joined coordinatewise: this is a conservative common
  supertype, not necessarily the exact denotation union or global least upper bound.
  Incompatible types return `None`; a budget failure returns no partial join.
- `key_comparable` compares non-null key domains. Decimal precision/scale may
  differ; ResourceKind must match; Artifact media restrictions may differ. Object,
  array, JSON and vector are not admitted key domains. It does not compare values.

The first three relations require `max_pairs`, counting scheduled contract pairs
including the root. Pending pairs reserve budget; zero is insufficient for a root
comparison and negative limits are invalid. Traversal is iterative. Key comparison
only inspects the root domain and needs no recursive-pair budget. Relations apply
the specified structural rules, not general satisfiability or expression inference.

Present-enum relations additionally charge enum traversal and comparison work
against that same finite relation allowance. Each enum transition, or each block
of at most 64 UTF-16 comparisons, consumes a unit; scalar scans keep a trailing
surrogate pair together. Exact equality
defers long enumerant comparisons through its existing continuation and can be
cancelled without exposing a partial result. Joins charge before growing their
output vector; all immutable input and transient output holdings still coexist.

## Canonical output and verification

`emit_checked` emits the whole checked contract through a caller-owned bounded
Writer. `stringify_checked` provides text with explicit byte/node/depth limits.
Text, measurement and hash sinks share the same canonical emission. Omitted bounds
are not synthesized, object field names are UTF-16 sorted, and no field is removed
from the preimage. Output limits use the Writer's JSON accounting, not contract-node
accounting; objects, fixed fields and scalar members consume that budget normally.

Enum emission uses the existing bounded array/String writer cursors one member
at a time. JSON Schema projection retains the same vector, including in nested
nullable types; unsupported additional extents still refuse rather than being
erased. The original enum backing, Strings, lookup/comparison continuations and
join/output workspace remain part of the consuming Host/Run's retained/workspace
inventory. Structural limits are not a physical reservation or numerical profile.

[Fixed vectors](../../portability/corpus/value-contracts.json) include empty object
types and line-break field names. `generate:value-contracts` emits MoonBit tests
from these fixed expectations; `check:value-contracts` verifies generated freshness,
embedded field-name/empty-object schemas and their registered CIDs. It does not
derive expected contracts from product output or certify runtime conformance.
Package tests cover all types, rejection boundaries, the four type relations,
ownership, source diagnostics, output budgets and 10,000 nested contracts on
JS, Wasm and native. Field and value validation by downstream consumers remains
outside this package.
