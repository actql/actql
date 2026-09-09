# JSON encoding

This implementation guide describes the shared `encode_core` package. It is not
a second language specification or a canonical-artifact admission API.

## Kernel dependency

The [kernel law manifest](../../spec/dependencies/aoa-kernel-laws.json) is the exact
`aoa-kernel-laws/0.1` body pinned by the
[AoA contract](../../spec/contracts/actql-aoa.json). Its CID is SHA-256 of the
UTF-8 canonical JSON of the entire object: sorted object keys, preserved array
order, no whitespace, no excluded fields. This manifest is ASCII-only.
`check:encoding` verifies that identity without changing the contract pin.

The manifest lists law names; it does not contain the complete definitions of
all kernel laws. The scalar rules below resolve the encoding subset. Canonical
object ordering, normalization and CID composition remain outside this package;
the complete canonical-JSON contract and its pinned identity tests are required
before implementing that layer.

## Scalar spelling

Finite binary64 numbers use shortest round-tripping decimal digits, choosing
the closest decimal and then an even significand on ties. Formatting follows
[ECMAScript 2025 Number::toString, radix 10](https://tc39.es/ecma262/2025/multipage/ecmascript-data-types-and-values.html#sec-numeric-types-number-tostring),
including its nearest/even recommendation: ordinary notation for magnitudes
from `1e-6` inclusive to `1e21` exclusive, otherwise lowercase `e` with an
explicit exponent sign and no leading exponent zeroes. Positive zero is `0`.
ActQL rejects negative zero, infinities and NaN rather than repairing them.

For finite values other than negative zero, AoA's `normalizeNumber` has the same
spelling as scalar `JSON.stringify` and radix-10 `Number::toString`. Its integer
branch already returns that spelling. Exponential output occurs only outside
the ordinary-notation interval, where it returns before the `toFixed` fallback;
that fallback is unreachable. Shortest ordinary output has no redundant trailing
fractional zeroes to trim. This equivalence does not extend to rejected numbers.

For valid Unicode strings, escaping follows
[ECMAScript 2025 QuoteJSONString](https://tc39.es/ecma262/2025/multipage/structured-data.html#sec-quotejsonstring).
Unlike that operation, this writer rejects unpaired UTF-16 surrogates.
It preserves all other scalars, using short escapes for quote, backslash and
the five named control characters, and lowercase Unicode escapes for other
characters below U+0020. It does not escape solidus, normalize text or fold
line endings. Keys remain in emission order; duplicate exact keys are rejected.
Canonically equivalent but differently spelled keys remain distinct here.

The [fixed vectors](../../portability/corpus/json-encoding.json) identify numbers
by binary64 bits and strings by UTF-16 code units. Their expected text is
independent of MoonBit output. `check:encoding` checks those expectations against
Node's scalar JSON spelling, with explicit ActQL rejection rules, and checks
the committed generated MoonBit tests. `generate:encoding` regenerates tests,
not expectations. This is not a proof for all binary64 values.

## Canonical JSON boundary

The `canonical_json` layer must normalize string values and keys with
`normalize_nfc_lf`, reject duplicate keys after normalization, and sort normalized
keys using `compare_utf16` before emission. For example, composed and decomposed
spellings of the same key collide there even though this writer accepts both.
The writer's exact-key check does not replace normalized-key validation.
Canonical-artifact admission remains separate: it rejects noncanonical input
rather than silently repairing signed or hashed content.

## Structure, limits and failure

Every writer requires explicit byte, node and depth limits. Bytes count the
complete emitted UTF-8 JSON, including punctuation and escapes. Each value,
including each container, counts as one node; object keys are not nodes.
A scalar root has depth zero; each open array or object adds one.

Typed `EncodeFailure` exceptions close the writer. Subsequent operations report
`ClosedWriter`; callers cannot publish or continue partial output. Successful
finalization also closes it. If an input violates several conditions, the first
check encountered during emission determines the error, not a separate
whole-input validation pass.

Measurement uses the same accounting and rejection rules without retaining
output text. It still allocates traversal frames, key sets and scalar formatting
temporaries: output limits are not a general CPU or memory quota.

`EncodedDocument` seals complete text together with byte, node and depth counts.
Embedding charges the entire subtree and parent punctuation. It never accepts
caller-supplied raw JSON or counts. `emit_json` traverses borrowed in-memory JSON
iteratively, preserves its object iteration order and retains no aliases after
the call. Callers must not mutate that input during emission.

JS, Wasm and native run the same fixed vectors, exact/short byte-budget cases,
structural misuse, closed-writer, measurement and embedding tests. These checks
establish the tested encoding behavior, not full ActQL execution conformance.
