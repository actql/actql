# Parameter declarations and binding

`parameter_binding` implements the pure declaration and invocation-value part of
[Parameters and binding](../spec/language.md#parameters). It does not establish
whole-Program use proofs, substitute expressions, admit
opaque `bindings`, publish protocol envelopes or start a Plan/Run.

## Declaration grammar

`read_declarations` accepts an optional owned Cursor for the Program's `params`
map. Absence means no declarations; a present map is nonempty. Names use
`[A-Za-z_][A-Za-z0-9_]*`, remain case-sensitive and are stored in UTF-16 order.
Source parsing and owned-tree admission precede this boundary.

`value_contract.read_parameter_syntax` is the trusted type adapter. It constructs
the same private, immutable Contract representation as the general readers while
retaining Parameter-only constraints. It is deliberately a syntax result, not
proof that its preserved `default` or `meta` cursors are valid. Only
`read_declarations` performs the complete declaration/default admission.

Parameter types are string, number, decimal, boolean, timestamp, date, closed
object and homogeneous recursive array. `nullable` defaults to false throughout
this Parameter grammar. General authored and checked value contracts still require
explicit nullability. Number integer/minimum/maximum, string duration format and
array length/max_items constraints apply at their respective recursive positions.
`integer: false` imposes no integer restriction. `integer: true` does not introduce
a safe-integer ceiling. Both numeric bounds are inclusive and finite; their
intersection is checked against values without adding general satisfiability
inference to declaration admission. `length` is positive and safe; `max_items`
is nonnegative and safe. Consumer-specific bounds remain separate.

`default` and annotation `meta` belong only to named declarations, not nested
type contracts. Metadata is nonempty canonical JSON-model data with reserved
top-level `actql_` keys rejected; it never participates in binding decisions.
A field named `meta` is ordinary object data. Neither default values nor supplied
business objects are searched for `$param` holes or recursively substituted.

Every default is validated at declaration admission, even if a caller will later
supply an override. Defaults satisfy both the base value contract and recursive
Parameter constraints. Decimal uses canonical fixed-scale wire strings and exact
coefficients, dates use the Language calendar, and nullable fields remain required.

## Semantic declaration projection

`emit_declaration` emits the annotation-free declaration required by the
[stage/Program semantic envelopes](../spec/language.md#local-approval), including
the `type` member of a canonical Parameter reference. It takes an admitted
Declaration, whose original owned source is retained privately. It removes only
that declaration's top-level `meta`, preserving defaults, authored optional type
fields, recursive constraints, and business fields named `meta`. It does not
expand a checked contract, insert omitted `nullable: false`, substitute a default,
or apply the typed-value identity projection to a default's wire spelling.
Changing a default remains a semantic declaration change; presentation annotation
changes do not affect these bytes.

Keys are emitted in canonical UTF-16 order, using text validated by declaration
admission. Explicit continuation frames avoid recursive traversal and a second
full value tree. Arrays use indexed reads; objects retain sorted field handles
while being emitted. The original admission limits bound source size, and the
shared Writer bounds emitted bytes, value nodes and open-container depth with
the same text/measurement/hash behavior. Output limits are not sorting-work or
heap-memory quotas, and the declaration keeps its source arena alive.

This is an internal identity-preimage API, not public explain: the output can
contain literal default values. It emits one declaration, not a Program/stage
envelope, used-name proof, canonical reference index or authorized Invocation.
The reference implementation's older `$.field[index]` paths are not reused;
the current reference contract requires RFC 6901 pointers and explicit sorting.

## Binding result

`bind` takes admitted declarations and an optional supplied-value object. Unknown
supplied names fail before resolution. A missing supplied value uses its complete
default if present, otherwise contributes a missing name. Explicit null never
selects a default. There is no deep merge or implicit value conversion.

All selected values are checked before returning a result, so a missing value
cannot hide an invalid supplied value. `Ready` contains an immutable complete
set; `NeedsBindings` exposes only the sorted missing-name list, not partially
ready values. Both accessors return detached arrays. Each bound value records
`Supplied` or `Default` separately from its checked typed value. These origins
are not typed identity inputs. `Ready` privately retains the admitted Parameter
types alongside the values; callers cannot pair the values with another declaration
set when computing identity.

BoundValues also retains the exact Declarations owner, exposed by
`bound_declarations` for internal composition checks. `bound_value_count` and
`bound_value_at` provide bounded indexed access without copying the full array.
Owner identity is not emitted or hashed and changes no Parameter identity bytes.
Consumers such as author-guard binding can reject values admitted under a
different declaration set before resolving usage-specific constraints.

Duration validation parses `[0-9]+(ms|s|m|h|d)` with ASCII case-insensitive units,
including leading-zero digit sequences. Exact integer conversion to milliseconds
must be positive and no larger than 9007199254740991. No binary64 parsing,
fractional tokens or zero duration are accepted. The checked value remains a
string with its source-normalized spelling; duration operand lowering consumes
the millisecond interpretation. Parameter identity emission applies that same
interpretation without replacing the stored string.

## Parameter Values identity

`emit_values` emits the exact version/values preimage defined by the
[Parameter identity wire contract](../spec/protocols/contracts.md#parameter-value-projection).
`stringify_values`, `measure_values` and `parameter_values_cid` use the same
emitter with text, measurement and incremental hash sinks. Their input is the
opaque `BoundValues` from `Ready`, not `NeedsBindings` or an independently supplied
declaration/value pair. The output is the hash preimage, not the wire envelope
including `parameter_values_cid`. External artifact admission and whole-Program
or extracted-unit used-name proofs remain separate.

Decimal uses the versioned coefficient/precision/scale preimage. Duration uses
positive safe integer milliseconds. Business objects containing `$actql_value`
are escaped into sorted name/value pairs; ordinary values are not universally
wrapped with their declarations. Origin, metadata and admission-only constraints
do not enter the value preimage. All values come from trusted binding; tags are
never interpreted from arbitrary input JSON.

Emission is nonrecursive and uses read-only indexed access to owned values and
type fields, scheduling one child at a time. It creates no second projected tree.
The hash sink does not materialize a serialized String or byte array. Bytes,
nodes and depth limits cover the complete emitted preimage, including version,
maps, tags, decimal bodies, escaped pair containers and pair-name strings. These
are output budgets, separate from binding's input budgets. Object keys are not
nodes; escaped pair names are string values and are nodes. Text and hash paths
make the same admission decisions. Writer failure prevents finalization or reuse;
no partial body or CID is returned. Retained input, writer key tracking and
traversal state still use memory, so output limits are not total-heap limits.

The result is immutable, but enforcing one retained set across attempts/resume is
the later Run boundary's responsibility. Usage across stages and prohibition of
structural-selector substitution require semantic traversal; scanning raw JSON
for `$param` is not a substitute. Public explain projections and privacy policy
also remain outside this value-bearing API; results do not derive debug printers
that automatically expose bound values.

## Resource limits and diagnostics

Declaration limits bound parameter count and the complete raw declaration tree:
nodes include map/declaration/constraint/default/meta values, keys consume UTF-8
text bytes, and depth counts containers with a scalar root at zero. Full-tree
preflight bounds the sum before per-declaration type/default validation. Each
subtree pass has the same caps but cannot admit more total source material than
the whole-tree preflight permitted; this is not a separate allowance per default.

Binding limits bound all selected value trees together. Nodes count each selected
root and descendant; the outer supplied map is not a value node. Text includes
each selected parameter name plus all string values and object keys. Missing names
are bounded by the admitted declaration set. Default and supplied values consume
the same allowance. Each selected root has independent root depth zero, with the
same depth ceiling. No partial result escapes on budget failure.

Traversals are iterative, child frontiers reserve node budget, and maps are
opened once per collection rather than per field. Exact boundaries pass, negative
limits fail, and budgets are input/work limits rather than total-heap guarantees.
Errors preserve original paths and spans, including default locations. Preflight
failures can precede domain diagnostics. Declarations and effective values are
visited in canonical name order; nested constraints use field/index order.
These are package issues, not final CLI codes.

## Verification

[Fixed cases](../../portability/corpus/parameters.json) cover declarations,
recursive constraints, defaults, explicit null, missing values and rejection.
`generate:parameters` emits tests from fixed expectations; `check:parameters`
checks freshness, schema consistency and tooling regressions. The two embedded
Program schemas share the generated recursive Parameter type definition.
`generate:parameter-schemas` updates those definitions and their artifact pins;
document metadata and identity fixtures are updated with their existing commands.
Decimal schemas enforce scale <= precision at both declaration and recursive type
positions. Schema shape checking does not replace duration conversion or the
validation of complete typed defaults.

The [identity corpus](../../portability/corpus/parameter-identities.json) fixes
canonical text and CIDs independently of MoonBit output. `check:parameter-identities`
verifies those expectations with an independent projection and SHA-256, generated
test freshness and schema regressions. `generate:parameter-identities` regenerates
tests without rewriting expectations. `generate:parameter-identity-schema` updates
the projected-value schema and artifact pins; use the metadata and canonical
identity generators afterward. Product tests check exact output budgets and
text/hash parity in addition to these fixed identities.

Product tests additionally exercise whole-set budgets, metadata, source locations,
ownership, wide maps and deep recursive declarations on JS, Wasm and native.
They do not establish full compiler, Run or reference conformance.
