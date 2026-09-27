# Structural text AQL

The structural frontend r1 is another source representation of `actql/0.1`.
It constructs an ordinary Program through bounded source admission. The common
checker still owns types, operation contracts, binding visibility, stage
relationships and required evidence. Parsing does not authorize execution or
perform provider I/O. JSON and YAML retain their existing meanings.

The [grammar](../../spec/grammar/actql-text-0.1.ebnf) covers the structural
surface only. SQL, WHERE/SELECT query sugar, MATCH, domain aliases, INSERT and
new source-format routing are outside this implementation unit.

## Lexical rules

Input is Unicode scalar text or strict UTF-8 bytes. A leading BOM is accepted.
Outer whitespace is space, tab, CR or LF. Keywords are ASCII case-insensitive;
Program and binding names retain case. Unquoted names use ASCII letters or
underscore followed by ASCII letters, digits or underscore. Structural keywords
must be quoted when used as names. Operation names use the exact, case-sensitive
closed Grammar Manifest inventory.

Strings use single quotes. Escapes are backslash followed by a quote, backslash,
`n`, `r`, `t`, `u` and four hexadecimal digits, or `U` and eight hexadecimal
digits. Unicode escapes denote one valid scalar; surrogate escapes and values
above U+10FFFF are rejected. Backtick names are nonempty and allow only escaped
backtick, backslash and scalar `u`/`U` escapes. Raw control characters are rejected;
backtick names also reject escaped CR/LF. Raw/triple/byte strings are not accepted.

Outer comments are `--` through the next newline and non-nested `/* ... */`.
JSON bodies use the existing strict JSON parser, including duplicate-key,
normalization-collision, scalar, finite-number and negative-zero checks. Outer
comments, unquoted keys and query strings are not accepted inside JSON. Legacy
expression strings inside bodies keep the existing expression dialect.

## Structural mapping

`AQL '0.1'; PROGRAM 'id' { ... }` supplies Program version and ID. Root META,
PARAMS and BINDINGS map to the corresponding optional members. BINDINGS remain
opaque bindings, separate from DATA names. STAGE appends a stage with its exact
ID. Explicit AFTER ACCEPTED or AFTER COMPLETED is retained; an omitted AFTER is
not materialized. Common admission validates predecessor relationships.

INPUT declarations form the stage input object and precede computation. Initial
FROM is optional, occurs at most once, precedes computation and names a declared
input. STEP appends the complete JSON step. RESULT declarations form the local
or root Result object. EFFECT declarations form the Effect object; declaration
order adds no execution sequencing. EFFECTS with an empty object explicitly
retains empty Effects and cannot be mixed with EFFECT declarations. Missing and
explicitly empty permitted members remain distinct. Missing inputs and steps
become their required empty object and array. Duplicate declarations fail,
including normalized duplicate names. Common admission rejects empty required
Results and invalid optional envelopes.

The formatter reads the complete admitted source, not its metadata-stripped
identity projection. It emits explicit STEP bodies, retaining metadata at every
level, parameter defaults, expression trees/strings, arrays, unused steps and
explicit no-ops. It does not optimize or preserve comments or whitespace.

## Native DATA and producer references

DATA starts from an explicit prior producer or a generator OP. Its operations
use ordinary native JSON bodies. The final operation receives the DATA name as
its `as` field. Only the first operation receives the explicit FROM; subsequent
operations use the current result within that chain. A later DATA does not
implicitly consume an earlier DATA result. Generators occur only at the start;
explicit graph construction is a generator, while current-input graph
construction requires FROM. The checker still validates each body and Carrier.

An operation-free `DATA alias = FROM producer;` is a static alias. It creates no
identity select, additional operation or repeated computation. Alias references
are rewritten only at producer-reference positions, including native peer inputs
and stage Result sources. Literal values, metadata, expression field names and
Result names are not rewritten. Self, forward and duplicate DATA names fail.

Intermediate generators that require names receive deterministic
`__aql_native_N` names. Allocation excludes authored input/producer declarations
and producer-reference targets across the whole stage, including later ones.
Source offsets, comments and whitespace do not seed names. Generated names are
not additional authored bindings. Explicit STEP content is retained except for
resolving an authored DATA alias at a producer-reference position.

## Bounds and origins

Deployment supplies all limits. Original source bytes, retained tree nodes,
depth and string bytes, origin entries and complete encoded Program bytes use
the common source builder limits. The structural frontend additionally bounds
outer tokens (one JSON island is one outer token), syntax nodes, syntax depth,
literal bytes, name occurrences, generated steps/fields and lowering work.
JSON nodes are counted separately inside each island and cumulatively across
the document. No CTE allowance is required because this surface has no CTEs.

Syntax nodes include declarations, OP occurrences and JSON nodes; depth includes
the Program/stage envelopes plus JSON container depth. Literal bytes include
decoded outer quoted tokens and normalized retained JSON strings/keys. Name
occurrences include declarations, explicit names, DATA references and helpers.
Generated-step accounting includes retained explicit STEP entries; generated
fields count constructed envelope/step fields, while imported JSON bodies use
the common node/string bounds.

Lowering work is a deterministic budget, not elapsed time: source indexing
charges original bytes; scanning charges scalar advances, including whitespace,
comments and escapes; JSON admission charges island bytes before parsing, and retained traversal charges nodes and keys; generated
construction charges nodes. Reference scans reserve one body-node allowance
plus two per reference path; rewriting reserves one plus four per path for
bounded lookup, copy and alias resolution. Helper collision probes also charge
work. Charges precede the corresponding construction or traversal. Limits do
not claim an exact physical heap-byte ceiling.

No partial Program is returned after failure. Successful source owners expose
measured accounting; callers cannot supply trusted usage. Source origins refer
to original UTF-8 bytes, scalar coordinates and UTF-16 positions before text
normalization. Generated envelopes, helper names and rewritten alias targets
retain a generated origin role. JSON bodies keep authored ranges in the original
AQL document. Admission diagnostics preserve the offending original range.

## Identity and manifests

The Grammar Manifest binds this grammar and these structural rules separately
from the unchanged Program source-schema CID and legacy expression grammar.
Comparisons with JSON/YAML use the same applicable manifest and contract pins.
A manifest change may alter a compiled Plan identity; source equivalence does
not assert that an old Plan CID remains current. All owned contracts remain on
0.1. No Host authority, receipt or execution result is inferred from source form.
