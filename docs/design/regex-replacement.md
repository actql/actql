# Regex replacement AST admission

`regex_replacement.parse` checks canonical replacement text and constructs an
opaque AST under the existing
`spec/contracts/actql-production-profile-schemas.json#/schemas/regex_replacement_ast`
contract. It is a static-checking component, not a regex matcher or replacer.
The normative owner is [text-time](../spec/language.md#text-time).

## Closed grammar and canonical identity

`$$` emits one literal dollar. `$1..$99` emits a capture part, greedily consuming
at most two ASCII digits with a nonzero first digit. Consequently `$100` is
capture 10 plus literal `0`; it neither means capture 100 nor requires that
larger capture to exist. Bare dollars, zero/leading-zero capture forms, named
references, braced references and Host-specific dollar operators reject.
Backslash is ordinary literal data, not an escape for a dollar.

Adjacent literal characters and decoded dollars form a single nonempty literal
part. Captures retain occurrence order and repetition. Empty text has no parts.
The AST records exact UTF-8 bytes of all literal parts, total capture occurrences
and the maximum referenced capture (zero without references). These are not
source byte size, distinct capture count or a replacement-output ceiling.

The existing `actql-regex-replacement-ast/0.1` identity includes those parts and
statistics and excludes only `ast_cid`. The same bounded emitter writes the
preimage and full AST to text, measurement or hash sinks. It never uses Host
regex parsing or produces a complete JSON string just to hash the AST.

Input requires well-formed UTF-16 and NFC followed by LF canonical text, checked
without repair. Accepted literal parts retain canonical text. Diagnostic offsets
for invalid dollar forms and malformed surrogates are UTF-16 code-unit offsets
in the supplied replacement. Literal byte accounting starts from validated raw
UTF-8 length and subtracts only capture syntax and the extra dollar in `$$`,
avoiding another scalar-to-UTF-8 implementation.

## Reference and specification alignment

Sketch `87dc7144:src/actql-text-time-grammar.ts` provides the corresponding
`parseActqlRegexReplacement`. Its maximal two-digit tokenization, literal
coalescing, repeated capture accounting and canonical preimage are retained.
The language now explicitly records those rules because an AST shape alone does
not determine tokenization or canonical literal grouping. No schema shape or
identity domain changes. The older helper checked NFC only; this reader also
requires LF canonical text as required by ActQL value admission. It does not
accept and silently normalize a noncanonical replacement artifact.

## Budgets and evidence

Limits bound original UTF-8 input bytes, part count, full AST bytes and full AST
nodes. The full AST has seven fixed nodes and three per part. Integer arithmetic
is checked before multiplication, and component construction is iterative with
linear string building. Literal accumulation is bounded by input admission;
part limits do not claim to bound all retained text or total heap memory.

[Independent fixed vectors](../../portability/corpus/regex-replacement.json)
contain sixteen accepted replacement texts with handwritten parts and thirteen
rejections. Node computes statistics, canonical text and SHA-256 from those
fixed parts, never from the product parser/lowerer. The drift check uses the
existing schema's part definitions and runs through `check:docs`.
`generate:regex-replacement` preserves expected identities; the separate
`--write-identities` option is an explicit fixture-maintenance command.

MoonBit tests execute the fixed vectors and all 99 capture tokens, extra-digit
boundaries, Unicode byte totals, malformed surrogates, NFD/CR rejection, long
literal coalescing, repeated capture occurrences, exact/short limits and bounded
streaming sinks across JS, Wasm and native. These prove AST admission, not regex
matching, replacement evaluation or profile conformance.

## Remaining connection

Capture existence is deliberately not certified by this parser: it has no
associated admitted regex. The staged static resolver must obtain the exact
literal or bound Parameter, parse the regex, verify each replacement's maximum
capture against that regex's capture count, retain both ASTs and their occurrence
owner, and bind the selected policy. A raw caller-supplied count or these
statistics alone is not such a proof. Pattern/envelope/profile closure and
Program readiness remain unfinished; runtime handling of unmatched captures is
also outside this package.
