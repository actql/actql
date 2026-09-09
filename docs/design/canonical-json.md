# Canonical JSON and CID

This guide describes the canonical-JSON subset of the
[kernel dependency](json-encoding.md#kernel-dependency) and the
[language identity contract](../spec/language.md#canonical-identities).
It does not define semantic envelopes or imply conformance to all AoA laws.

## Serialization contract

Canonical JSON is compact, without whitespace outside strings. Null and booleans
use JSON literals. Finite binary64 values use the
[scalar spelling rules](json-encoding.md#scalar-spelling); negative zero,
infinities and NaN are rejected. Numeric representation metadata does not
override the binary64 value.

Each string and object key is validated as well-formed UTF-16, normalized with
Unicode 16.0 NFC, then has CRLF and lone CR replaced by LF. Other scalars,
including other line separators, remain unchanged after NFC. String escaping
uses the shared JSON writer. Object keys that collide after normalization are
rejected, then the remaining keys are sorted lexicographically by UTF-16 code
units. Array order is preserved; these rules apply recursively to every value.

The AoA kernel's JSON.stringify-based serialization escapes unpaired surrogates;
this layer rejects them as the ActQL language contract requires. This stricter
input restriction does not change identities for well-formed input.

A CID is the lowercase prefix `sha256:` followed by 64 lowercase hexadecimal
digits of SHA-256 over the canonical text's UTF-8 bytes, without a BOM.
The supplied value is the entire preimage. No field, including a field named
`cid` or `identity_cid`, is implicitly removed, zeroed or interpreted.
Envelope construction and any contract-specific self-field exclusions belong
to the caller.

Identity-specific boundaries construct their own preimages: semantic envelopes
exclude annotations only at the language's permitted authoring positions, while
Authoring Context, Plan Document and review identities bind their prescribed
annotation content. There is no generic include/exclude-metadata switch. A business
field named `meta` inside literal or observed data remains ordinary hashed data.

## Admission and ownership

`from_json` normalizes an in-memory JSON value into a read-only
`CanonicalValue`. Collections are copied and no mutable backing array is
exposed; `array_values` returns a detached array. Input mutation after admission
does not change the tree or its CID. Concurrent mutation during admission is
unsupported.

This is not a JSON text decoder or strict canonical-artifact validator. Exact
duplicate keys already collapsed by a parser's Map cannot be recovered here.
Signed or hashed artifacts require separate admission that rejects noncanonical
content instead of normalizing it into acceptance.

## Explicit limits and failures

Admission requires a node limit, depth limit and aggregate raw UTF-16-unit limit.
Keys and string values consume the unit limit before normalization; supplementary
scalars consume two units. Every value, including containers, consumes one node;
keys do not consume separate nodes. Shared subtrees count on each occurrence.
A scalar root has depth zero; even an empty root container has depth one.
Minimum child counts are checked before building container output, and traversal
uses explicit frames rather than recursion. Cycles exhaust node or depth limits.

Admission raises package-local `CanonicalFailure` variants for invalid numbers,
unpaired surrogates, normalized-key collisions or input limits. The Unicode error
offset is within the original key or string, in UTF-16 units; it is not a document
path. If several conditions fail, traversal and early budget checks determine
which error is returned. No partially admitted tree is returned.

Serialization, measurement and CID generation each require explicit output
UTF-8-byte, node and depth limits and propagate `EncodeFailure`.
`emit_value` instead uses a caller-owned Writer and charges its enclosing output.
There are no implicit unlimited or abort-on-error convenience APIs.

Input units and output bytes are different budgets: NFC can expand text, and JSON
escaping adds bytes. These are work-size limits, not exact heap or CPU quotas.
CID generation currently materializes canonical text and UTF-8 bytes; it is not
a streaming hash sink.

## Verification

`check:canonical` verifies the
[fixed corpus](../../portability/corpus/canonical-json.json), every machine-body
pin registered in [spec-family](../../spec/spec-family.json), lookup schema pins,
the fixed lookup envelope's bytes/CID, and the kernel manifest. It checks
generated MoonBit tests against those inputs. `generate:canonical` regenerates
tests, never contract pins or corpus expectations from product output.

Node supplies independent normalization, spelling and SHA-256 checks; committed
corpus text and existing contract CIDs remain the expectations. The generated
tests use core JSON parsing only to load fixtures, not as product decoder
conformance. JS, Wasm and native execute the same tests. Deep-tree, collision,
ownership and exact-budget tests exercise admission and output separately.
