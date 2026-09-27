# Bounded generated Program source

A generated source tree is untrusted authoring input. The builder creates no
CheckedProgram, execution permission or input-acquisition evidence. Its output
enters `stage_syntax.admit_generated_source`, which uses the same closed-envelope
decoder as JSON/YAML. The resulting Program still goes through
`program_check.check_parsed` or `check_parsed_with_evidence`.

## Ownership and origins

`frontend_source_map.document` admits original Unicode text with a byte limit.
`document_bytes` additionally rejects malformed UTF-8 without replacement.
The immutable scalar-boundary index records byte, scalar and UTF-16 offsets,
plus scalar and UTF-16 columns. CRLF is one newline and a leading BOM does not
advance the initial column, matching the source parser. NFC and line-ending
normalization of semantic values do not rewrite that index.

`range` issues an opaque origin for valid scalar boundaries. `validate_span`
requires every supplied coordinate and source locator to match that document.
Origins distinguish authored from generated nodes; neither kind confers
external authority. A builder rejects origins issued for another document,
even if its text and locator are identical.

`program_source_builder.create` starts an owned construction session. `add`
accepts a scalar, an array of owned nodes, or ordered object fields containing
owned nodes and key origins. Child arrays are copied, and issued nodes are
immutable. A node from another builder is rejected. Reuse within one builder
is allowed; every expanded occurrence is included in the final size bounds.

`finish` uses the existing `source_map.admit` implementation to own the tree
and its annotations together. `origin(source, cursor)` and
`key_origin(source, cursor)` return annotations only for that admitted tree.
This retains distinct key and value origins, including generated-key roles,
without introducing another cursor map or trusting structural path strings.
The map uses immutable annotation handles and does not keep a path array per
node. The builder's original document index need not be retained by the result.

A failure closes the builder and publishes no partial Source. `discard`
explicitly closes unfinished construction. There are no physical resources or
provider callbacks to cancel; callers release their ordinary node/document
references when done. Previously issued nodes cannot reopen a closed builder
or enter another one.

## Accounting

The limits cover original input bytes, generated nodes, container depth,
individual and total normalized string bytes, origin entries, and encoded
Program bytes. They are supplied by the caller's current policy, not a new
language maximum.

Before retaining a node, the builder checks both allocated construction nodes
and expanded root occurrence counts. It also checks cumulative new string
storage and expanded string usage. Shared subtrees therefore cannot hide
exponential output or annotation expansion. Object keys count toward string
and origin budgets. A scalar has depth zero; a container adds one, as in the
existing parser and decoder. Exact limits are inclusive.

Text is preflighted before normalization using the larger of the source-byte
allowance and the remaining per-string allowance, then NFC/LF-normalized and
checked against the retained string budgets. Duplicate normalized object keys
are rejected. Numbers use the existing finite canonical encoding boundary;
negative zero is rejected. Scalar encoded sizes come from the existing bounded
measurement writer, and container sizes are summed with overflow-safe checks.
No whole-Program stringify/parse buffer is introduced.

`import_parsed` accepts editable `ParsedSource` data for interoperability. Its
claimed `usage` is ignored: bounded iterative traversal validates every span,
key and value and goes through `add`. Cycles and repeated expansion terminate
at the node/depth limits. Final common admission independently measures retained
tree usage. The original input byte count comes from the admitted document,
never from caller-supplied accounting.

Program issuance rechecks the Source against the consumer's current source and
tree limits before decoding stages. Stage limits and structural errors use the
ordinary decoder. Later `validate_reuse` applies the same measured retention
checks as for JSON/YAML Programs.

## Minimal use

The frontend keeps the original document, constructs nodes with explicit
origins, and passes the finished Source to the existing Program issuer:

```text
document = frontend_source_map.document(original_text, input_byte_limit)
builder = program_source_builder.create(document, builder_limits)
origin = frontend_source_map.range(document, start_byte, end_byte)
node = program_source_builder.add(builder, value_with_owned_children, origin)
source = program_source_builder.finish(builder, node)
program = stage_syntax.admit_generated_source(source, program_limits)
checked = program_check.check_parsed(program, environment, parameters, limits)
```

Every fallible operation returns a Result; callers handle it before continuing.
`import_parsed` is a bridge for already decoded syntax, not a reason to serialize
a new frontend's tree. Structural text can construct the same nodes directly.
The lightweight transport SDK has no dependency on these packages.
