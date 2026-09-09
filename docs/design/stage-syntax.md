# Program and stage structure

`stage_syntax` reads authored `.aql` text or UTF-8 bytes into an owned Program
envelope. It implements the outer [document structure](../spec/language.md#document-structure)
and [linear stage connections](../spec/language.md#stages). Success is structural
admission, not a CheckedProgram, Plan, execution authorization or conformance claim.

## Source selection

`parse` and `parse_bytes` default to `Format::Auto`. JSON is tried first; YAML is
tried only after JSON lexical or grammar failure. Explicit `Json` and `Yaml`
formats use only their selected parser. File extensions do not select a parser.

Malformed encoding, invalid Unicode escapes (including unpaired surrogates),
duplicate normalized keys, numeric overflow, negative zero and
source resource-limit failures are terminal. A parsed JSON value is never
reinterpreted as YAML after tree admission or Program structure rejects it.
For example, JSON `true` fails the Program object requirement without fallback.
Core YAML spellings such as `01` can be accepted after JSON grammar rejects them.

The JSON failures eligible for retry are exactly `UnexpectedEnd`,
`UnexpectedToken`, `InvalidString`, `InvalidEscape`, `InvalidNumber`,
`ExpectedColon`, `ExpectedArraySeparator`, `ExpectedObjectSeparator` and
`TrailingContent`. Other JSON failures are terminal.

When both syntaxes fail, `Alternatives` retains both original parser diagnostics.
A YAML resource or encoding failure instead returns the terminal `Parse` error.
Automatic selection can perform two bounded parsing attempts; source limits bound
each attempt, not a combined CPU or allocation allowance.

## Structural contract

The decoder checks:

- Closed root fields, exact `actql/0.1`, nonempty Program ID and stages.
- Nonempty named root parameter/binding maps when present, and nonempty root exports.
- Closed stage fields, nonempty unique stage IDs, input maps, step arrays,
  nonempty result maps and optional effect maps.
- Nonempty object shape for root/stage/import metadata, permitting arbitrary JSON
  content except reserved top-level `actql_` keys.
- No `after` on the first stage; later stages accept `accepted` or `completed`,
  with omission selecting `completed` on the immediate predecessor.
- Closed Result/receipt import envelopes, earlier producer stages and existing
  named producer Results/Effects.
- A supplied stage `from` names one of that stage's inputs.
- Closed root export envelopes referencing an existing stage Result.

Declaration names and references are compared after the source parser's NFC/LF
normalization. Stage order and declaration order are retained. Control dependencies
remain even when stages have no data imports. Neither imports nor exports perform I/O.
Declaration object views and producer port-name indexes are built once and reused
for lookups; declaration arrays retain their original order.

Local operation bodies, Result/Effect definitions, parameter/binding declarations,
ordinary Input contracts and service-defined metadata meanings remain unchecked. In particular,
ordinary Inputs retain both string shorthand and object forms; Carrier resolution
belongs to the Input checker. Likewise,
checking that `from` names an input does not establish that it is materialized
rather than a search template. Type checking, scope resolution within a stage,
reference schemas, profiles, bounds, canonical lowering and identities belong to
subsequent checks. Unknown operation bodies are retained, not executed or approved.

## Ownership, limits and diagnostics

`Limits` requires separate source `ParseLimits`, owned-tree `decode_core.Limits`
and `max_stages`. All are validated before parsing. Zero allowances are valid;
equal-to-limit values are accepted. Source bytes include trivia and a leading BOM;
tree string allowances cover the normalized strings and keys produced by parsing.
NFC expansion can therefore pass the input budget and fail the tree budget.
There is no fixed depth allowance or inferred relationship between these limits.
`max_stages` bounds the resulting stage list; it does not replace parsing and
whole-tree admission limits.

Program and Stage keep opaque owned cursors rather than editable source Nodes.
Import annotations reside beside `result` or `receipt`, not inside the reference.
They remain in the source cursor but never participate in port lookup. This layer
does not calculate CIDs or extract the Authoring Context sidecar; the compiler's
identity-specific boundaries perform that extraction, not the generic CID helper.
Accessor arrays are detached, while body cursors retain the same immutable arena
and original source spans. No public raw Node/Cursor decoder bypasses source
normalization; a future in-memory builder must establish that boundary explicitly.

`SyntaxError` distinguishes invalid limits, parser failures, owned-tree issues
and structural issues. Structural issues retain paths and spans from the offending
cursor; missing/unknown fields preserve the shared decoder's diagnostics.
Checks run root closure first, then stages in source order, then root exports.
There is no global sorting of failures or translation to public CLI diagnostic codes.

## Verification

Fixed tests cover predecessor defaults, ports, missing and unknown fields,
normalization, diagnostic paths/spans, independent accessor arrays, syntax selection,
terminal failures, exact limits and deeply nested deferred bodies. The same tests
run on JS, Wasm and native. They verify this envelope boundary only, not complete
Program semantics or execution.
