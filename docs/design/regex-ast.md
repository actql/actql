# Scalar-preserving regex AST contract

The normative owner is [text-time](../spec/language.md#text-time).
`spec/contracts/actql-regex-ast.json` pins the existing standalone
[AST schema](../../spec/grammar/actql-regex-ast-0.1.schema.json) with a scalar-safe
representation. The expression contract selects it at
`spec/contracts/actql-expressions.json#/regex_ast_contract`.

The contract CID is
`sha256:9c4e0107ad1e6a1eb374e8365c07615c74773416b0b43f9a1e02db5e551efc78`;
the schema CID is
`sha256:cc114653eb3db3bdf94bf233f34c0baa5f4c5bc305aeb07ed66283706054d3d9`.
`regex-ast-contract.mjs` verifies both the schema's scalar shape and the exact
expression dependency. The spec-family manifest pins the contract and the
enclosing expression contract; neither pin substitutes an admitted backend.

## Evidence and decision

Sketch `87dc7144:src/actql-text-time-grammar.ts` decodes regex `\\r` to a
`{kind: "literal", value: "\r"}` node and hashes the complete AST core with
the ordinary AoA canonical JSON CID function. The corresponding `\\n` node
contains LF. Normal canonical JSON converts CR to LF, so these different scalar
expressions produce the same preimage and CID. With capture count zero and
`actql-regex-ast/0.1`, the shared old CID is
`sha256:340dd92e3cd44ba619e1028dfd7cf29f3fe7d22b696d259f36168f290901eabd`.
The regression check reproduces that collision using the independent Node
canonicalizer. This contradicts the language's explicit distinction between
CR and LF in regex matching. A raw string hash would merely create a second,
noncanonical identity rule; it would not repair the AST contract.

Literal nodes now use exactly `kind: literal` and integer `codepoint`.
Ranges use integer `start` and `end`. Values are Unicode scalar ordinals,
including unassigned scalars, not UTF-16 units: `0..1114111`, excluding the
surrogate interval. Numeric payloads cannot be changed by string normalization.
This uniform representation avoids a CR-only special node or a second escape
language inside the AST. Class escapes, anchors and other fixed vocabulary
remain strings. No global JSON canonicalization rule is changed.

The local dependency explicitly overrides inherited text-time AST representation
and identity; other grammar, matching, flags and demand laws remain inherited.
Old string-valued literals and range endpoints are rejected, not repaired or
quietly reinterpreted. This changes literal/range AST CIDs and the expression
contract CID. It is a coordinated correction at the owned initial 0.1 baseline,
not a compatibility claim or a rewrite of existing history.

## Syntax versus semantic checks

The schema rejects nonintegers, out-of-range values, surrogates, unknown fields
and the old string shapes. Range ordering still needs a semantic check: a range
whose valid scalar start exceeds its valid scalar end is shape-valid but invalid.
Ranges crossing the surrogate gap select members of the scalar universe, not
surrogate code units. Capture numbering/counts and quantified-expression rules
also remain semantic obligations. A valid CID is not evidence of these checks.

Decoded `\\r`, `\\n`, `\\t` become codepoints 13, 10, 9 after source-text
admission. Their values are not normalized again as text. This preserves the
existing source NFC/LF boundary while distinguishing an escape from a raw source
line break. AST identity hashes the complete core with only `ast_cid` omitted,
using ordinary canonical JSON and preserving prescribed occurrence order.

## Verification and handoff

[Fixed vectors](../../portability/corpus/regex-ast-scalars.json) contain 29
schema/identity cases, including the old collision, CR/LF literals and ranges,
sequence order/repetition, captures, scalar endpoints, unassigned characters,
surrogates, malformed payloads and a reversed shape-valid range.
Node checks this schema's explicit keyword subset and independently computes
canonical bytes/CIDs from the handwritten ASTs. Its test-only interpreter is
not a product validator or complete regex semantic checker.

Generated MoonBit tests verify the sixteen accepted AST core identities on
JS, Wasm and native using the existing canonical JSON implementation. They are
not regex parser or evaluator tests. Contract/schema/dependency drift checks and
fixture regeneration are connected to `check:docs`; replacement ASTs retain
their existing distinct contract and string-literal representation.

Main's regex parser and static resolver must produce and consume these scalar
nodes, then establish grammar, captures and occurrence/policy ownership.
Lowering/backends must declare the exact new expression/AST contract support and
preserve the scalar meaning; the old pinned registry is not relabeled as capable.
Until that support is implemented, executable admission rejects that path.
The change does not authorize a Program or establish whole-profile conformance.
