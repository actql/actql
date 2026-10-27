# Value admission

`value_admission` checks normalized source values against an admitted
[value contract](value-contracts.md). It returns a read-only `CheckedValue`
containing the contract and domain-checked data. It does not execute expressions,
bind Parameters, calculate typed value identities or prove reference authority.

## Boundary and representation

`admit` takes a `value_contract.Contract`, owned `decode_core.Cursor` and explicit
`Limits`. Source parsing establishes NFC/LF text; this boundary checks rather than
repairs it. Raw noncanonical strings and keys, non-finite numbers and negative
zero are rejected, including inside `json`. Source spans remain original even
when source parsing normalized the text before this call.

The supported domains are string, number, int64, boolean, decimal, date, timestamp,
json, object, array and limited vector input validation. No implicit string/number
conversion, rounding, default insertion or missing-field completion occurs.
Every declared object field is required, even when nullable. Unknown fields fail;
empty closed objects accept only `{}`. Array elements are checked recursively.
Null is accepted only by a nullable contract; descendants of untyped `json` may
contain null. A `json` value supplies no static field evidence and tagged business
objects do not become typed decimals or references.

A Text enum intersects the original checked extents. Admission, computed Text
binding and runtime recheck compare exact Unicode data against the original
ordered declaration; nullability remains independent. No trimming, normalization,
coercion or replacement by the first enumerant occurs. Empty enums admit no
non-null value. The checked value retains the same constrained Contract, so
Values/row transport and Result schema emission cannot silently weaken it.

`Value` distinguishes decimal, date, timestamp and vector values from ordinary
JSON leaves. Its constructors are private. Nested arrays and object entries are
opaque, and `elements` returns detached arrays. The root retains its complete
contract, including empty-array element types. Object entries are ordered by
UTF-16 code units; no semantic metadata fields are stripped.

Decimal input is the Language's canonical fixed-scale string, not a JSON number
or an internal tagged object. The checked leaf retains precision, scale and exact
base-10 coefficient text. For example, `19.90` at precision 4/scale 2 yields
coefficient `1990`; `0.001` at scale 3 yields `1`. Leading zeros in the integer
part, leading plus, exponent notation, negative zero, wrong scale and excess
precision fail. Precision 38 needs neither binary64 nor machine-integer narrowing.
Arithmetic, numeric equality across scales and typed decimal identity are separate.

### Exact signed64 leaves

`Signed64(Int64)` is a separate immutable value arm, appended without reordering
the existing arms. Admission uses only the original `int64` Contract. It checks
the canonical signed decimal String and inclusive signed64 magnitude before
negative accumulation, including the minimum value without taking an overflowing
positive absolute value. Numbers, negative zero, plus signs, leading zeros,
fractions, exponents and out-of-range neighbors refuse without conversion.

The acquired String consumes the original admission text budget. The retained
machine-integer payload is a fixed scalar leaf in runtime recheck, logical work
and captured-value measurement; it is not retained Decimal coefficient or Text
storage. Wire emission separately accounts for the complete quoted canonical
String (at most twenty ASCII payload characters). This representation does not
supply physical capacity or acknowledge any original input lifetime.

Same-domain equality, key and author ordering compare the exact integer. Key
tuples retain a separate signed64 atom, and fixed-width sign-bit-biased keys
preserve signed order without binary64 conversion. Complete-value identity and
Parameter binding retain their distinct `int64` tags. Row acquisition continues
to require the preparation's exact original schema and contracts; an equal
schema or another prepared owner cannot replace them on capture or reuse.

This leaf adds no arithmetic or conversion overload. In particular, the existing
`to_string` signature is unchanged: canonical wire serialization is not an
author-language cast. Number, Decimal and Text domains and legacy preimages
remain separate and unchanged.

`emit_wire_value` projects an admitted value into a caller-owned `encode_core`
writer. Text, measurement and hash sinks consume the same canonical JSON wire
stream, without a second value tree or recursive traversal. Decimal leaves are
fixed-scale strings, not coefficient text or the tagged Parameter identity
projection. Business `$param` and `literal` keys remain ordinary data. The writer
accounts for structural syntax, escaped text and repeated value occurrences;
`finish_measurement_usage` returns exact bytes, value nodes and peak container
depth only after successful completion. Callers can embed several values in the
same writer so limits are not reset per cell or row.

The emitter does not select Host ceilings, construct a bound witness, perform
operation lowering or authorize publication. Its traversal frames are bounded
by value depth; the writer also retains object-key validation state. The input
value tree remains allocated, so avoiding a complete wire String does not imply
constant total memory use. Decimal leaf formatting is bounded by precision 38.

Dates and timestamps follow the [Language calendar rules](../spec/language.md#value-contracts):
years 0000–9999, valid proleptic Gregorian dates, and exact UTC timestamps with
three to nine canonical fractional digits. Millisecond-aligned values keep
exactly their original three digits; only extra trailing fractional zeros are
omitted. Offset spellings, redundant fractional zeros, leap seconds and invalid
dates fail authored admission. Vendor normalization is a separate boundary that
retains the original source.
The optional text-time profile is not required for this validation.

## Vector and reference boundaries

Vector admission verifies array shape, declared dimensions, finite numeric
components and absence of negative zero, retaining binary64 inputs unchanged.
This is not complete f32 operation admission. The Language places binary32
quantization [before scoring](../spec/language.md#nearest) and
[pooling](../spec/language.md#pool-vectors). Conversion, conversion-result handling
and operation-specific numerical restrictions belong to those consumers after
their normative dependencies are resolved. Do not infer scoring readiness from a
checked vector, or add an exact-f32-representability restriction here.

Ordinary authored admission returns `UnsupportedReference` for a non-null value
under a `resource_ref` or `content_ref` contract. A separate Host entry accepts
such a value only through an opaque issuer bound to evidence validation and a
current authorization check. Re-admission of retained rows requires the exact
previously issued occurrence; canonical wire bytes alone cannot manufacture a
new authority handle. This applies recursively inside arrays and objects.

Null follows the ordinary nullability rule even under a Ref contract: nullable
accepts the absence and non-nullable rejects it as `UnexpectedNull`. Accepting
absence does not issue a reference or make a structurally plausible non-null
authored object authoritative. An empty array with a Ref item contract contains
no visited Ref values and may pass ordinary authored admission.

## Budgets, diagnostics and ownership

`admit_usage` returns the same checked value plus consumed node and UTF-8 text
counts. `admit` delegates to that path and discards only the counters. Consumers
validating separate request fields can subtract actual usage from a shared
allowance instead of resetting limits or walking the values again to measure
them. Depth remains a per-value container bound. Failures return neither a
partial value nor success counters; a caller must not publish a partially
admitted aggregate after one field fails.

- `max_nodes` counts every value occurrence, including the root and vector
  components; object keys are not nodes. Shared subtrees count per occurrence.
- `max_depth` counts containers: scalar root 0, object/array/vector root 1.
- `max_text_bytes` counts normalized UTF-8 bytes of keys and string-valued inputs,
  including decimal/date/timestamp wire text. Contract descriptions and generated
  coefficient storage are not charged as input text a second time.

These are whole-value budgets, never reset for child values. String contracts
independently constrain normalized Unicode scalar counts and UTF-8 bytes; array
contracts independently constrain length. Exact boundaries pass, negative limits
fail before traversal, and zero budgets remain meaningful. These allowances do
not bound total heap usage, normalization intermediates or elapsed CPU time.

Traversal uses explicit work/build frames. Child nodes reserve remaining budget
before scheduling. Object views are reused; maps are not rebuilt per field.
After closed-field validation, object children are checked in UTF-16 key order;
arrays use element order. Member presence and key-byte checks precede child value
checks, and a frontier reservation can report a budget failure before inspecting
individual children. These are local diagnostic priorities, not CLI error codes.

Resumed Text enum matching borrows one original candidate and compares at most
64 UTF-16 units per transition through the same typed-admission/recheck cursor.
Cancellation clears these frames with the original source/value responsibility;
no second lookup table, worker, parser or validation Owner is introduced. Enum
metadata was charged by Contract admission and is not charged again as payload
text. The caller accounts each resumed transition as work and retains the complete
contract, candidate/value aliases and continuation workspace until their existing
lifetime ends. This is not normal numerical funding or a physical release ACK.

Errors retain source paths and spans; key failures point at key spans. No partial
checked value escapes on failure. Each call owns fresh budget state. Returned
values retain neither mutable source arrays nor mutable public views.

## Bulk row admission boundary

Use this whole-value API for individually bounded values, including Parameters,
Effect payloads and individual rows. Bulk Relation ingestion uses streaming or
explicitly hard-bounded batches; it does not build a complete dataset as source
Nodes, an owned arena and checked Values. Bounded arrays remain valid inputs.

Readers bound individual rows, pending input, decompressed bytes and in-flight
batches, with backpressure between stages. Release row/batch representations
after consumption. Account for parsing and object-allocation amplification, not
just compressed input size or `max_text_bytes`. Batch-local validation limits do
not reset the enclosing acquisition's total limits or evidence obligations.

These are integration requirements, not an implemented streaming API. Any future
normalization fast path requires an unforgeable invariant on the owned input;
a caller-supplied flag cannot bypass validation of manually constructed values.
Measure optimizations without weakening rejection, ownership or budget checks.

## Verification

[Fixed vectors](../../portability/corpus/value-admission.json) specify acceptance,
rejection and selected exact coefficients independently of product output.
`generate:value-admission` generates MoonBit cases; `check:value-admission` checks
freshness and generator regressions. Input parsing in corpus tests is the normal
source path; separate raw-Cursor tests cover rejection without normalization.

Product tests cover all supported domains, numeric bit preservation, Unicode
limits, calendar and decimal boundaries, source diagnostics, ownership, global
budgets, wide objects and depth 10,000 on JS, Wasm and native. Document checks alone
do not establish runtime or whole-Program conformance.


## Exact Timestamp values and clock roles

Timestamp extends the existing Value owner rather than introducing a Connector
parser or a second temporal type owner. Whole epoch seconds and a bounded
subsecond remainder can represent the admitted calendar range without an
overflowing single Int64 epoch-nanosecond quantity or a binary64 approximation.
Comparison, scalar and recursive ordering, keys and serialization consume the
same original checked value. Variable-length fractional strings do not have
chronological UTF-16 order. An internal padded order key is separate from Value
wire and identity; old millisecond Value, Parameter and saved-input bytes stay
unchanged. Structural sets and Graph consumers preserve their existing semantic
order and emitted values, even when the private sort representation changes.

Event clocks retain exact rational milliseconds and the authored payload. The
ordinary fixed-unit `date_diff` result still truncates its quotient toward zero
and cannot supply that extended carrier: minus one nanosecond precedes the epoch
but has a zero ordinary millisecond difference. Exact window membership, negative
floor/grid arithmetic, watermark equality, session gaps and join ties therefore
belong to the existing clock consumers. Millisecond-only helpers refuse finer
fractions instead of silently rounding them. A consumer without that connection
is an implementation gap, not a restriction on the declared Timestamp domain.

Calendar endpoint admission likewise retains exact original Timestamp strings
and compares their instants, including mixed fractional lengths. It does not
use a millisecond projection or UTF-16 ordering to define valid ranges. The
current civil Calendar range lowering is still millisecond-only and returns its
explicit precision-unavailable issue before conversion, rather than calling a
valid finer Timestamp invalid or unwrapping a failed projection. Literal and
bound Parameter endpoints share this separation; civil profile coverage and
the existing year/range requirements are unchanged.

Trusted-now, Credential expiry, authorization deadlines, rollback detection and
provenance retain their original millisecond contracts and operational issuers.
Civil Time, timezone-free DateTime and retained numeric offsets are separate
requirements; a finer UTC value does not supply their representations. Original
source text, exact projections, comparison/key buffers, decoder/recheck frames,
encoded output and escaped aliases can overlap within the same existing
retention and work owners. Parsing limits or a padded key are not capacity,
authority or physical retirement evidence.


## Original Contract in typed Object construction

Typed Object admission retains the same nested `Contract` selected by its
original `ReadTyped` frame. Its input field matching and original key/value
budgets run before construction. The private Object record projects fields
from that original Contract, and the output builder retains those exact
canonical fields. Child completion passes the selected scalar field index to
`append_contract_object_field`; the builder chooses the name from its retained
Contract and enforces exact index/length/open state.

This carries the already completed name/order admission into construction.
The generic append's repeated name normalization and order readmission are
removed from this typed path. Actual input-name matching, required-field
checks, UTF8/key budgets, source paths/spans and cancellation remain with the
original admission. JSON data keys retain their separate original path.
The private Object record still holds three references and one depth scalar;
it retains the original Contract instead of only its fields. Append frames
carry a field index instead of a second name reference. No resource policy,
tariff, grant, physical start or cleanup acknowledgement is derived here.
