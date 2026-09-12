# SourceView resolution

`sourceview_resolution` connects one prepared Program's authored inputs to one
typed Check Environment Catalog. The opaque result retains both exact owners,
the original input cursor and the selected SourceView request contract. A
SourceView's self `contract_cid` is retained separately from its full-body
membership hash. Equal hashes do not replace environment ownership.

Resolution indexes the complete supplied view set once. It validates the
data-policy address and full-selector uniqueness before examining any input,
including unused views. It neither filters candidates by request compatibility,
permissions or selected read modes nor infers the Resource from `resource_kind`.
Explicit selection uses the full triple; omitted selection requires exactly one
candidate and records `actql.source.sole-view-completion` without rewriting source.
Ambiguity diagnostics sort names by UTF-16 with budgeted iterative merge sort.

Resource addresses are delimited by the already known Connector instance and
view name, not guessed by splitting at arbitrary slashes or fragment markers.
The normative owner is [Connector SourceViews](../spec/language.md#sourceviews).
Sketch at `87dc7144` likewise matches against the output data-policy address,
not ResourceKind. Its additional URI-prefix/slash cleanup is not adopted:
the language's exact instance and Resource selectors do not introduce those
aliases. This clarification preserves literal percent escapes and internal
delimiters and permits two Resources of the same kind to expose the same view.
The earlier Catalog integrity check's kind-based duplicate-selector test cannot
establish this property and is deferred to this policy-aware boundary.

Limits bound input count, view count and cumulative work, including the preceding
authored-input collection. Work is charged before indexing, text copying and
candidate sorting; failure returns no partial result. SourceView shape, typed
request/Carrier and data-policy proofs remain prerequisites, with their own
admission budgets. These limits are not a whole-process heap ceiling.

The result is not a final CheckedProgram or an execution permission. Request
binding and value validation, read-mode selection, source snapshots, authority,
policy enforcement and runtime obligations still require their own checks.
No lowerer, evaluator or backend adapter is implemented by this package.

## Direct read-mode selection

`select_direct_mode` consumes one owned ResolvedInput. An authored `scan.mode`
selects that exact advertised mode; otherwise the validated Contract default is
used. Missing support does not fall back to another mode. A watch selection is
statically unsupported in ActQL 0.1 even though advertising watch is legal.
An explicit snapshot can override a watch default when snapshot is advertised.

The opaque DirectMode retains the exact input, selected mode contract, selection
origin, diagnostic cursor and this pass's work usage. Advertised-mode lookup is
indexed by environment member, with same-environment and section checks. A
foreign member with equal bytes or CID cannot select a mode from this proof.
Explicit-selection diagnostics refer to the authored `scan.mode`; default-mode
diagnostics refer to the selected Catalog mode body. Returning obligations makes
a fresh array and cannot mutate the retained selection.

Every selection retains runtime mode-support revalidation. Every changes
selection, explicit or default, additionally retains two distinct unfinished
obligations: prove the requested page/range is bounded, and build the normative
content-addressed source-state requirement using the actual Program Definition,
input, SourceView and checkpoint contract. The latter is static planning work,
not a runtime check to be postponed. No provisional Program identity or concrete
checkpoint is invented here. Advertised boundedness alone proves neither actual
range admission nor capacity, consistency or completeness.

This follows [read modes](../spec/language.md#sourceviews), not the broader
execution limitations in `87dc7144:src/actql.ts`. That reference rejects all
advertised unbounded changes and required acknowledgements at the same boundary.
This selector retains the range obligation and leaves delivery/backend support
to their explicit checks; it does not claim those selections are executable.

DirectMode is not a keyed-join mode proof and does not classify a declaration's
consumer. The external-join checker still rejects authored scan, requires a
bounded default snapshot/changes mode and checks the keyed acquisition contract.
Program integration must discharge those consumer-specific obligations rather
than substitute a DirectMode as proof of keyed compatibility. Per-call work is
separate from the retained input-resolution work and must be budgeted cumulatively
by that integration boundary.
