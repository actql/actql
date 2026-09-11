# Timestamp pattern admission

`timestamp_pattern.parse` checks the finite timestamp-pattern grammar and returns
an opaque pattern with ordered components and its canonical AST identity. It is
a static-checking component, not a timestamp evaluator, a locale formatter,
profile conformance claim or execution authorization.

The normative owners are [text-time](../spec/language.md#text-time), the
[finite grammar](../../spec/grammar/actql-timestamp-pattern-0.1.ebnf) and the
[AST schema](../../spec/grammar/actql-timestamp-pattern-ast-0.1.schema.json).
No new AST shape or identity domain is introduced. The AST uses
`actql-timestamp-pattern-ast/0.1`, the selected parse/format mode, ordered
components, `full_input_match: true` and `timezone: UTC`. Its CID excludes only
`ast_cid`. Streaming preimage and full-AST emitters share the same serialization;
hashing does not materialize a JSON string or byte array.

## Admission and limits

Both modes accept only the seven semantic tokens and six ASCII literals in the
grammar. Tokens cannot repeat. Hour/minute must occur together, seconds require
them, and milliseconds require seconds. Parse mode requires year, month and day;
format mode does not. Patterns are nonempty. Individual literal occurrences are
not merged, including adjacent identical literals. Non-ASCII and malformed UTF-16
fail at the first non-grammar component, without normalization or replacement.
The diagnostic offset is a UTF-16 code-unit offset (all preceding admitted
components are ASCII, so their byte/scalar offsets coincide).

Limits separately bound pattern bytes, component allocation, full AST bytes and
full AST nodes. Accepted input is ASCII, so the constant-time UTF-16 length check
is its exact byte bound; non-ASCII input cannot be admitted. Parsing is iterative,
with a fixed seven-token candidate set and at most seven seen tokens. AST depth
is fixed at three. Full wire AST accounting includes its CID field, not merely
the smaller preimage. Writer limits also apply when callers embed or emit the
AST. Usage is logical input/output size, not a total heap or CPU measurement.

`value_width` is the fixed ASCII width consumed by a parse pattern or produced
by a non-null format operation. It does not validate a date, execute formatting,
establish input nullability or bypass the selected Host output ceiling.

## Reference comparison and decision

Sketch `87dc7144` contains the corresponding checks in
`src/actql-text-time-grammar.ts` and `moonbit/src/text_time/text_time.mbt`.
The token matching, dependency checks, component order and AST preimage are
retained. Date parsing, formatting execution and regex matching are not copied.

Those implementations additionally reject literal-only format patterns. The
current EBNF and AST schema admit nonempty literal sequences, while the language
requires date components only for parsing. A format such as `--` has an exact,
locale-independent meaning and fixed output width. The normative mode paragraph
therefore explicitly admits it; no reference-only semantic-token requirement is
imported. This is a recorded clarification of an underspecified boundary and a
known compatibility difference, not a claim that the reference accepts it.
Both-mode duplicate/dependency rules are made explicit in the same paragraph.

## Evidence and remaining integration

[Fixed vectors](../../portability/corpus/timestamp-pattern.json) contain ten
accepted patterns with handwritten component arrays and seventeen rejected
patterns. Node independently canonicalizes/hashes those fixed arrays; expected
values never come from the product parser or lowerer. `check:timestamp-pattern`
verifies fixture identity, component/schema agreement and generated-test drift;
it runs through `check:docs`. The normal generator preserves fixed identities;
`--write-identities` is an explicit maintenance operation.

MoonBit tests execute the vectors on all three targets, all 127 nonempty semantic
token subsets in both modes, duplicate tokens, non-grammar Unicode/surrogates,
long repeated literals, exact/short budgets and bounded text/hash/measure sinks.
The fixed vectors prove AST and identity behavior, not timestamp evaluation.

The staged expression resolver still needs to obtain the literal or exact bound
Parameter at an owned validation site, select parse mode for parse/try and format
mode for formatting, enforce the selected policy's pattern ceiling, and attach
the admitted pattern to that occurrence. Regex pattern/replacement checking,
full expression envelope derivation, profile admission and final Program
readiness remain separate unfinished requirements. This parser is not a reason
to discharge a caller-supplied `PatternValidation` flag without that association.
