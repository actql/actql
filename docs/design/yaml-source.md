# YAML source parsing

`source_value.parse_yaml` and `parse_yaml_bytes` read YAML into the same editable
`Node` model as [JSON parsing](json-source.md). Both require explicit `ParseLimits`
and return `Result[Node, ParseError]`. The caller selects the format; there is no
autodetection, filesystem access or Host dependency.

The boundary implements YAML input under the language's
[source representation contract](../spec/language.md#source-representation),
using [YAML 1.2.2 Core resolution](https://yaml.org/spec/1.2.2/#1032-tag-resolution).
Generic roots can be objects, arrays or scalars. The ActQL profile's non-empty
object requirement and Program grammar remain higher-level checks.

## Syntax and values

Block and flow mappings/sequences share one iterative container stack, including
compact and indentationless sequences. Flow collections allow trailing commas
and string-key pairs. Both implicit and explicit mapping keys must resolve to
strings; the parser does not coerce numeric or boolean keys to field names.
Implicit keys are single-line and limited to 1,024 Unicode scalars by YAML syntax.

Plain, single-quoted, double-quoted, literal and folded scalars are decoded before
Unicode NFC and CRLF/lone-CR-to-LF normalization. Quoted escapes, physical-line
folding, indentation indicators and strip/clip/keep chomping belong to YAML
decoding. Block scalar content retains literal comment characters and colons.
NFC does not perform compatibility normalization or case folding.

A block scalar ending at end-of-input without a line break has no final newline
([YAML 1.2.2 production 165](https://yaml.org/spec/1.2.2/#8112-block-chomping-indicator));
ActQL does not synthesize one, since doing so would change the value and its CID.

Empty mapping values and sequence items resolve to null. A quoted empty string
remains a string. Core resolution recognizes decimal integers with optional signs,
unsigned `0o`/`0x` forms and decimal floating-point forms such as `.5`, `1.` and
`1.e2`. `yes`, `on`, dates, signed hexadecimal/octal spellings and underscore
spellings remain strings. Quoting prevents implicit numeric/boolean/null resolution.

Decimal conversion reuses the exact-significand conversion used by the JSON
parser after validating Core spelling. Hexadecimal/octal conversion retains the
leading significant bits and guard/sticky bits, then rounds once to binary64 with
ties to even. Recognized numeric overflow, non-finite values and negative zero
are errors; they do not fall back to strings. This does not impose a safe-integer
restriction on all source numbers.

Keys retain source order and are checked once after normalization with
`decode_shape` key admission. Exact and normalized collisions are rejected before
the repeated key's value. Tags, tag directives, anchors, aliases and plain merge-key
spellings are rejected, not expanded. Quoted `"<<"`, `'<<'` and equivalent
escaped string keys are ordinary data and use the same duplicate-key checks.
No graph or executable scalar is constructed.

In flow collections, TAB may separate tokens after the required space indentation
has been satisfied. Only leading spaces count towards that indentation; a TAB
cannot replace them. Block indentation remains space-only. Source bytes are not
rewritten, and TAB still counts as one source column.

A single leading BOM and optional single-document `---`/`...` markers are allowed.
Additional documents are rejected. An explicit empty document resolves to null
at this generic layer; an absent document is rejected. A `%YAML` directive must
select 1.2 and precede the document-start marker. Reserved directives are ignored;
they cannot enable tags or change scalar resolution.

## Limits, positions and diagnostics

JSON and YAML share `ParseLimits`: original UTF-8 bytes, value-node count and
container depth. Keys are not separate nodes; scalar roots have depth zero and
root containers depth one. Equality is accepted. Negative limits and malformed
input encoding use the same preflight as JSON, before any YAML interpretation.
Every block and flow value, including implicit nulls and implicit flow-pair
objects, consumes the same node allowance. Container depth is checked before
pushing a frame. There is no separate fixed flow-depth ceiling.

Spans use original UTF-8 bytes and one-based Unicode-scalar line/column coordinates,
with CRLF counted as one newline. Scalar spans include their source quotes or
block header; trimmed separation is not part of a plain scalar. Block containers
end at their final value and flow containers include their closing delimiter.
An implicit null has a zero-width span after its value indicator, or after a key
with an omitted value indicator. These coordinates are not positions in the
normalized output.

Errors retain typed local issues and structured paths. Normalized-key collisions
point to the repeated key. Encoding preflight does not invent line or path data.
Traversal follows source order with early resource checks, not a global ranking
of all errors. Readers of purportedly canonical artifacts need a separate
reject-without-repair boundary; these parsing APIs are for authored source.

## Verification

Fixed tests cover value resolution, syntax and prohibited features, Unicode and
key collisions, original positions, byte/text equivalence, implicit values,
resource boundaries and independent returned trees. Deep flow and compact block
inputs exercise depth 10,000; indented blocks and wide mappings exercise the same
budgets. JS, Wasm and native run the same expectations. These tests do not establish
Program validation, canonical-artifact admission or execution conformance.
