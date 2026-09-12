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
