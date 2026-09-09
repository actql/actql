# Structural and scalar decoding helpers

These leaf helpers operate on field-name arrays, Strings and Doubles, not on
JSON text, UTF-8 input bytes or complete JSON trees. They are building blocks
for decoders, not a complete source or canonical-artifact admission boundary.

## Field names

`decode_shape` compares names exactly, without Unicode validation, normalization
or case folding. `check_object_keys` reports the first missing required name in
declaration order. Once all required names are present, it reports the first
unknown or duplicate name in input order; an unknown occurrence is checked before
whether that occurrence is repeated. `unknown_key_indices` instead collects
every unknown position in input order, including repeated unknown names.
Required and allowed declarations are supplied by the caller.

Arrays of names preserve duplicate occurrences; names extracted from an already
deduplicated Map cannot recover them. JSON text duplicate-key rejection remains
the parser's responsibility. Normalized-key collision detection belongs to the
[canonical input boundary](canonical-json.md#serialization-contract).

`KeyAdmission` incrementally remembers exact names. A duplicate returns false,
does not insert another entry and does not close the state. Separate instances
are independent. Stateless helpers do not mutate or retain caller arrays, and
returned index arrays are detached.

## Scalar values

Finite and integral binary64 readers preserve accepted bits, including negative
zero. Integral does not imply safe-integer range. Safe-integer and Int32 readers
check their ranges before converting, without rounding; integer zero has no
negative-zero sign. Canonical admission separately rejects negative zero.

Int32 conversion, decimal Int64 transport strings and hexadecimal UInt64 bit
words are representation helpers, not additional language value domains.
Their consumers are internal integer adapters, wire integer decoding and
binary64 bit-pattern transport, respectively. A successful representation read
does not establish a field's semantic range. Fields requiring a
[safe integer](../spec/language.md#value-contracts) must enforce
±9007199254740991, including when their transport uses a decimal string;
`read_safe_integer` enforces that range for binary64 input. The Int64 text
reader must not be used as admission for the language's
[Decimal values](../spec/language.md#decimal-values).

The hexadecimal reader requires exactly 16 ASCII hex digits, accepts either
letter case and rejects signs, prefixes and whitespace. It reads a UInt64 word,
not a CID or general numeric literal.

The decimal text reader returns an Int64, not an ActQL Decimal value. It checks:

1. Syntax: an optional ASCII minus followed by one or more ASCII digits.
2. Canonical spelling: no leading zeroes and no negative zero.
3. Range: from -9223372036854775808 through 9223372036854775807 inclusive.

Thus `0x` is `InvalidSyntax`, `01` and `-0` are `NonCanonical`, and
`9223372036854775808` is `RangeExceeded`. No whitespace trimming or implicit coercion
is performed.

## Unicode, limits and diagnostics

UTF-8 length checks count the original text without normalization, escaping,
encoded-byte allocation or text slicing. Both Int and Int64 APIs use the same
scan. They reject negative limits first, then reject a whole-string UTF-16 length
greater than the byte allowance, then scan left to right. Each scalar is checked
for malformed UTF-16 before charging its byte width. Surrogate error offsets are
in original UTF-16 code units. An oversized malformed string can therefore report
`LimitExceeded`; a failed length check is not full Unicode validation.

The Int64 API does not narrow large allowances. Internal Int accounting windows
only batch the balance updates; their boundaries do not change error precedence.
`unicode_scalar_count` validates and counts the whole string without normalization.

For the language's [string constraints](../spec/language.md#value-contracts),
callers must first obtain the canonical string using `normalize_nfc_lf`, then
apply scalar-count or UTF-8-byte limits to that result. For example, U+0344 has
one scalar and two UTF-8 bytes before NFC, but two scalars and four bytes after
NFC. Counting raw source text instead measures pre-normalization work, not these
semantic constraints. This does not authorize repairing noncanonical artifacts;
their admission boundary must reject them as required by the
[source representation contract](../spec/language.md#source-representation).

Callers enforce field-count and aggregate text-size limits before using these
helpers, and limit the distinct names retained by `KeyAdmission`. Decimal syntax
and scalar counting scan their input; only UTF-8 length admission has its own
byte allowance. These APIs do not establish tree budgets or a global memory quota.

Failures remain local typed `Result` values or `None` for predicate-style readers.
`utf8_length_within` is the optional projection that discards the typed rejection
reason. Diagnostic codes, document paths and message rendering belong to callers;
the ordering above is not a language-wide diagnostic policy.

JS, Wasm and native run fixed numeric endpoints, lexical rejection, exact-key,
mutation-independence, UTF-8 width/offset and budget-precedence tests. Small-window
tests exercise accounting refills without requiring multi-gigabyte inputs.
