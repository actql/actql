# Common typed JSON literals

`JSON '...'` is a GoogleSQL surface. Its lowering is the ordinary structured
expression `{typed_literal: {type: "json", value: "decoded JSON text"}}`.
The common expression, Value and execution owners handle the literal; the
Frontend neither executes JSON nor adds a Graph Delta-specific representation.

The selected reference is GoogleSQL at
`d82db99a923a46571f543a13899dc791a7b6f743`, specifically `ResolveJsonLiteral`
and `JSONValue::ParseJSONString` with exact numeric parsing, together with the
official [JSON literal](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/lexical#json_literals)
and [JSON type](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/data-types#json_type)
rules. This is a selected profile, not full GoogleSQL JSON coverage or live
service conformance.

## Value and type boundary

The existing non-null `json` contract describes every admitted JSON root,
including JSON null, booleans, numbers and strings. The common Value owner
retains `JsonData(payload)` around an immutable JSON-only payload. SQL NULL
remains the existing `Null` value. Ordinary scalar contracts and typed closed
objects/arrays remain separate. `IS NULL` is false for JSON null.

Existing `{literal:null}` remains SQL NULL; ordinary scalar literals retain
their inferred types. Existing untyped object/array literal inference remains
`json`. Both old object/array literals and new typed literals use this same
JSON runtime domain. No JSON Parameter type or additional coercion is added.

Raw authored JSON admission and typed-wire admission are explicit entry modes.
They share the same bounded, resumable Value owner. A decoded object member
cannot select a type, issue a reference, or bypass authorization.

## Canonical wire and identity

Every non-SQL-NULL JSON cell is encoded as `{"$json":payload}`. SQL NULL is
encoded as `null` and requires a nullable contract. A JSON object containing
`$json` is ordinary payload and receives another outer envelope. Typed-wire
admission decodes the outer envelope only where the complete checked contract
specifies JSON; authored raw data never interprets it as a tag.

The envelope is a common typed-value wire contract, used by literal IR,
retained rows, capture replay and Result delivery. It is not a Frontend-only
wrapper. Common wire size/node/depth limits include its physical encoding.
Logical JSON payload node/depth accounting counts the payload once.

Result serialization profile preimages include `json_value_wire_contract_cid`
alongside their existing version. This pins the changed JSON typed-cell
representation for JSON, JSONL and nested CSV delivery; profile CIDs change
without a version increment. Result.describe returns that selected profile CID.

JSON keys and strings retain Unicode scalar sequences and CR/LF. Canonical
encoding sorts JSON object keys in UTF-16 order without NFC or newline
conversion. Identifier and contract-field normalization remains separate.
Thus `é` and `e\u0301` remain different JSON keys and different canonical
content. Array order remains significant.

The expression contract, containing registry and dependent Program/Plan CIDs
change. Non-null JSON typed-cell wire bytes change, including existing
object/array JSON cells; ordinary scalar/SQL NULL wire bytes do not change.
Contract versions stay at the owned initial 0.1 baseline; changed bodies get
new pins. Old untagged typed JSON storage is not silently reinterpreted under
the new contract. No compatibility fallback is introduced.

Graph Delta and Graph identity-body consumers explicitly obtain the checked
JSON payload before invoking their existing semantic body parsers. Their body
format is not replaced with the typed-cell envelope. JSON properties within
typed snapshot records still use the shared typed wire.

## Effect literal source keys

The normative owners are [Source representation](../spec/language.md#source-representation),
[Effect declarations](../spec/language.md#effects) and
[Canonical identities](../spec/language.md#canonical-identities).
The previous blanket source member-name normalization conflicted with exact
JSON data keys when an authored Effect literal was later admitted under a JSON
target contract. Applying the JSON wire law only after source normalization
could not recover the lost spelling.

The adopted exception retains exact decoded member names throughout the value
subtree quoted by `{literal: value}` at a grammar-owned `EffectValue` position.
It is an explicit change to that source and identity boundary. It does not
disable normalization globally or recognize every object named `literal` as
syntax. Program syntax, Effect names, `set` and command `input` field names,
and other grammar-owned identifiers retain their existing rules. Exact
decoded duplicate source keys still fail; composed/decomposed or CR/LF-distinct
keys are separate keys inside the quoted subtree. Source escape decoding and
YAML folding still happen once before this distinction is made.

Program and Stage semantic preimages retain those source keys before the
external Mapping or Command Contract is resolved. Consequently, composed and
decomposed source keys have different Program identities even if the eventual
target is a typed Object and both spellings match the same normalized field.
Object field matching and normalization, including normalized-name collision
rejection, remain contract-directed admission work. A checked JSON target
instead preserves exact payload keys through the existing common Value and
typed-wire owners. Raw `$json` members are data and confer no type or authority.
Binding the original spelling avoids making Program identity depend on an
external Mapping or reordering contract resolution ahead of source identity.

This source-key correction introduces no new codec, Value domain, Effect
`typed_literal` grammar or Values type support. It leaves the existing
expression, kernel, JSON wire and grammar bodies and pins unchanged. Existing
historical corpora retain their recorded identities. Previously accepted
Effect literals with noncanonical source keys can acquire different Stage,
Program and dependent identities; canonical-key sources retain their preimages.
A normalization collision inside a JSON-target literal can now be admitted as
two distinct keys. The same pair remains invalid under a typed Object contract.
Saved normalized payloads cannot reconstruct discarded source spelling, and
this correction neither rewrites retained records nor supplies a migration.

The implementation scope is the public Host source and structured-Program
admission path. The generic source-builder API and its normalization behavior
are unchanged: a tree that its caller has already normalized does not recover
the earlier spelling at Effect admission. Independent fixtures must bind the
exact source payload into semantic preimages as well as check the delivered
JSON value. Existing machine-schema `typed_literal` alternatives at EffectValue
positions disagree with the language grammar; that pre-existing generator issue
is separate from this correction and does not authorize their acceptance.

The first-value rule below applies to JSON text inside a common expression
typed literal. It does not relax duplicate-key rejection in the enclosing
Program source or in an authored Effect literal subtree.

## Decoding and bounds

Duplicate keys retain the first value under exact decoded key equality.
The complete document, including discarded duplicate values, is parsed and
bounded. Invalid syntax, malformed Unicode, excessive size/depth and numeric
precision loss are explicit errors; none causes truncation or partial output.

Numbers use the existing finite binary64 value domain. The original decimal
token must mathematically roundtrip through the shortest decimal spelling of
that binary64 value. This admits `0.1` and rejects `0.10000000000000001`,
`9007199254740993` and underflow to zero. Negative zero remains an explicit
unsupported case under the existing common canonical number law. This does
not implement Google's complete signed/unsigned JSON integer domain. Numeric
tokens are limited to 1500 characters. JSON depth is at most 500, further
restricted by the caller's existing depth ceiling.

Literal preparation charges the complete JSON source text and parsed node
count, including discarded duplicates. Runtime payload validation and emission
retain existing value/work/wire ceilings. Rechecking an already constructed
raw JSON tree uses the same resumable common recheck; creating its cursor is
not admission. Only successful completion returns a checked value.

## Boundary review

A reviews common expression typing/lowering/evaluation, logical resource
accounting, capture response recheck and restoration. C reviews canonical
typed-cell wire, retained/snapshot record restoration, Graph Delta payload
access and Result publication/delivery. These are review boundaries of one
common implementation; no new execution owner, protocol executor or storage
format is introduced by the Frontend.
