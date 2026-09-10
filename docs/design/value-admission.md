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

The supported domains are string, number, boolean, decimal, date, timestamp,
json, object, array and limited vector input validation. No implicit string/number
conversion, rounding, default insertion or missing-field completion occurs.
Every declared object field is required, even when nullable. Unknown fields fail;
empty closed objects accept only `{}`. Array elements are checked recursively.
Null is accepted only by a nullable contract; descendants of untyped `json` may
contain null. A `json` value supplies no static field evidence and tagged business
objects do not become typed decimals or references.

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

Dates and timestamps follow the [Language calendar rules](../spec/language.md#value-contracts):
years 0000–9999, valid proleptic Gregorian dates, and UTC timestamps with exactly
three fractional digits. Offset spellings, leap seconds and invalid dates fail.
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

A visited `resource_ref` or `artifact_ref` contract returns
`UnsupportedReference`, including when its input is null and the contract is
nullable. This is an implementation scope restriction, not a language prohibition.
An empty array with a Ref item contract contains no visited Ref values and may
pass. Reference envelope/CID validation, issuer evidence and current usage
authorization require a separate boundary; authored JSON cannot establish them.

## Budgets, diagnostics and ownership

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
