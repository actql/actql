# Portable text-time extent derivation

`text_time_bounds` implements the numeric portion of the language's text-time
bound laws. It is not an evaluation envelope, an expression checker, a backend
capability claim or Program admission. It can emit and hash input-evidence
content, but assigns no argument, demand-path, step or envelope CID. Those
identities require the owning expression and Program integration boundary.

## Inputs and ownership

`from_contract` accepts only complete string or timestamp contracts with an
admitted text-time policy. String scalar and UTF-8 bounds tighten each other:
points are bounded by bytes, and bytes by four times points. When neither bound
exists, the selected policy ceilings become a RuntimePreflight requirement, not
a fact about data already examined. Known bounds exceeding Host limits are
rejected rather than silently clamped to the policy. Timestamp wire width is 24.

`from_value` takes an immutable CheckedValue of those same domains, counts actual
Unicode scalars and UTF-8 bytes under a caller scan cap, and retains that exact
value and policy. An explicitly known null has zero input text, unlike an unknown
nullable field. This follows the specification's strongest-available input rule;
it does not skip static pattern validation or introduce expression constant
folding. Output formulas remain the fixed conservative formulas even for null.
The reference's literal shortcut recognizes only strings and otherwise falls
back to the declared type or policy. Retaining exact zero for a known null is
an intentional stronger input fact, not a claim that an unknown nullable field
is empty or that undemanded static obligations may be skipped.

`from_output` consumes a child's checked output contract and rechecks it against
the same policy's input limits. It retains the exact Output as its producer,
rather than laundering runtime-dependent evidence into an unrelated contract
fact. This is constant work; it does not recursively scan prior derivations.
The integration owner must still bind these local results to actual typed nodes,
selected Parameter values and runtime enforcement. Origin enum names are local
provenance categories, not new wire spellings for `envelope.input.source`.

## Output laws

The fixed reference inspected is Sketch `87dc7144`,
`src/actql-expression-profile-v2.ts::checkTextTimeProfileV2`. The language and
expression contract remain authoritative, especially the refined substring and
truncate laws. With input points P and bytes B:

| Operation | Output-byte ceiling |
| --- | --- |
| split_part, regex_extract | B |
| substring | min(B, 4 × bound safe nonnegative length), otherwise B |
| utf8_truncate | min(B, bound safe nonnegative max_bytes), otherwise B |
| try_number | 32 |
| regex_match | 5 |
| parse_timestamp, try_timestamp | 24 |
| format_timestamp | admitted format pattern's fixed width |
| nfkc | P × 18 × 4 |
| case_fold | P × 4 × 4 |
| regex_replace | B + (P + 1) × (replacement literal bytes + capture references × B) |

Regex replacement additionally checks P+1 against max_replacements. Invalid or
dynamic length operands retain the conservative B bound; this component does
not evaluate them or introduce a new static error for invalid conversion data.
Output nullability follows the input, with try_number, try_timestamp and
regex_extract additionally nullable. `additional_nullable` only widens this
result when the owning typed expression has nullable non-value operands; it
cannot remove input or operation nullability. String outputs retain their derived scalar
and byte limits for the next consumer.

All arithmetic uses exact integers. Admitted contract/policy ceilings fit safe
integers, so multiplying a contract scalar limit by four fits Int64. Potentially
much larger regex products use cap-aware multiplication and addition before the
operation, and fail on genuine ceiling excess without overflow or truncation.
There is no floating-point bound sum and no intermediate safe-integer rejection
before a specified minimum can tighten it.

Operation variants identify formulas only. A timestamp format pattern is mode
checked here, but pattern-byte policy, regex capture existence, argument domains,
profile admission, expression/demand identity and Unicode law availability still
belong to their owning validators. A caller cannot treat these Output objects as
complete sealed envelopes. No matcher, lowerer or runtime enforcement is added.

## Verification and remaining connection

Tests use explicit independent arithmetic examples for all twelve operations,
multibyte and null inputs, cross-constrained field bounds, invalid/dynamic length
operands, exact output/replacement ceilings, large integer products and retained
child provenance. Both ownership and the distinction between derived output
allowance and a parent's input admission are tested. The main
[context-bound integration](pipeline-check-context.md#context-bound-text-extents)
now derives Inputs from actual typed children and selected bindings and retains
the producer and selected policy. The full demanded envelope remains to be
constructed under shared Program budgets. This
package alone does not close HostEnvelope obligations.

## Input evidence identities

`emit_input_evidence` writes to the common bounded canonical emitter;
`input_evidence_cid` uses its hash sink without a serialized String/Bytes copy.
`input_evidence_source` maps local provenance to the three existing wire cases.
The normative owner is the language's `text-time.input-evidence-preimages`
requirement and `actql-expressions.json#/laws/input_evidence_preimages`.

The previously unspecified preimages are now explicit: complete checked
contract for value_contract (including derived output); versioned resolved
wire value for literal; versioned complete contract and policy for runtime
preflight. This follows the fixed Sketch reference's preimages, with the already
documented known-null extent extended to a null literal preimage. Timestamp
values use their canonical wire string. These identities describe text extent,
not typed-value identity; the owning typed expression still distinguishes
timestamp/string and carries nullable/type evidence.

No producer tree, local handle, or step index is serialized. In particular a
derived contract can have the same evidence CID as an independent field
contract without making their provenance interchangeable. Existing producer
links and runtime obligations remain required. Literal evidence does not hash
the policy, while the containing envelope must still bind that policy. Runtime
preflight hashes the full policy, including non-input ceilings.

Five independent fixed preimages/digests cover contract, multibyte literal,
null, timestamp and runtime preflight. Tests exercise text/measurement/hash
agreement at byte, node and depth boundaries, failure closure, policy changes,
and equal content identities with distinct producer provenance.
