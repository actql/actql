# JSON source parsing

`source_value` implements the JSON part of the
[source representation contract](../spec/language.md#source-representation).
`parse_json_bytes` accepts strict UTF-8 bytes; `parse_json` accepts an existing
String and rejects malformed UTF-16. Both require explicit `ParseLimits` and
return `Result[Node, ParseError]`. Neither reads files or performs I/O.

## Accepted values

The parser reads exactly one JSON value and rejects trailing non-whitespace.
One leading BOM is permitted; a second BOM or a BOM after whitespace is not.
The generic parser permits scalar and array roots. The ActQL source profile's
non-empty object requirement and Program structure belong to higher-level
validation. [YAML source parsing](yaml-source.md) uses the same limits and result
types through separate entry points.

Numbers must have JSON spelling before conversion to binary64 with
round-to-nearest, ties-to-even. Overflow and negative zero are rejected, including
negative underflow that rounds to zero. Positive underflow may round to zero.
The parser does not impose a safe-integer range on all JSON numbers; field-specific
numeric contracts remain the consumer's responsibility.

Before binary64 conversion, the parser combines the explicit decimal exponent
with the significand's decimal-point displacement using wide integer arithmetic.
It rebases the token to one leading nonzero digit and a bounded exponent, retaining
all interior significant digits. Exponent accumulation saturates only beyond any
possible cancellation within the admitted token length. This prevents long
fractional prefixes from cancelling a truncated exponent while preserving exact
rounding midpoints and nonzero tails.

Strings and keys are decoded, validated and normalized with Unicode 16.0 NFC,
then CRLF and lone CR become LF. Object fields retain source order. Exact and
normalized-key collisions are rejected before reading the repeated key's value,
using `decode_shape` key admission rather than collapsing fields into a Map.

This is authoring-source normalization, not strict canonical-artifact admission.
It does not verify canonical textual spelling, schemas, signatures or CIDs.
Simply disabling normalization would not establish those guarantees either.

## Limits and failures

`max_input_bytes` counts the entire original UTF-8 representation, including
whitespace, BOM and escape spelling. It is not the normalized string byte limit
or serialized output limit. NFC can expand decoded text.

`max_nodes` counts every value once, including containers; keys are not separate
nodes. `max_depth` counts open containers: a scalar root has depth zero, an empty
root container has depth one. Zero limits are valid; exceeding a limit fails,
while equality is allowed. Negative limits are rejected before inspecting input.
The byte allowance is at most 2147483646 so that one-based end coordinates also
fit the `Int` fields of `Span`.

Bytes input is length-checked before strict decoding, without replacement of bad
sequences. String input uses the
[raw UTF-8 admission scan](decode-foundation.md#unicode-limits-and-diagnostics):
the whole-string UTF-16 length lower bound is checked first, then malformed
UTF-16 or byte overflow is reported in scan order. Thus a size failure need not
establish that the rest of the input has valid encoding.

After encoding preflight, JSON parsing proceeds left to right. The node allowance
is checked before reading each value; container depth is checked before opening
a container. These early checks may precede syntax errors. No partially parsed
tree is returned, and no global diagnostic-priority search is performed.

Parsing uses explicit frames, not recursion. Active paths use a segment stack,
copied only on failure. Limits bound input and tree work; they are not exact heap
or CPU quotas. Returned trees can subsequently be edited beyond those limits.

## Positions and ownership

`source_span.Span` records original UTF-8 byte ranges, zero-based and end-exclusive.
Lines and columns are one-based. Columns count Unicode scalars, not UTF-16 units,
graphemes or display cells; a tab counts as one column. CRLF is one newline, and
lone CR or LF each starts a new line. A leading BOM consumes three bytes but no
column. String and key spans include quotes and original escape spelling, even
when their decoded values are normalized.

Errors carry package-local issue variants. Syntax failures carry a source span
and structured `Key`/`Index` path segments using normalized keys. During key
decoding, the path still names the containing object. Encoding failures instead
carry a byte offset for malformed UTF-8 or a code-unit offset for malformed
UTF-16; unknown line, column or structural path is not fabricated. An absent
path differs from an empty path, which denotes the root. Public diagnostic codes,
path rendering and user-facing messages belong to higher-level adapters.

`Node`, `Value` and `Field` are editable syntax data, not sealed validation proofs.
Each parse creates fresh arrays, independent of other parses and siblings.
Later admission boundaries must establish their own ownership guarantees before
retaining caller-provided trees.

## Verification

All three targets run fixed tests for JSON grammar, numeric rounding and rejection,
UTF-8 boundaries, escapes, normalization, duplicate keys, original spans, resource
limits, error precedence and editable-tree independence. Deep-array and wide-object
tests exercise explicit frames and key admission. Fixed binary64 words are checked
independently from ECMAScript JSON parsing, not produced by the MoonBit parser.
This verifies the JSON parser subset, not full source-profile or Program conformance.
