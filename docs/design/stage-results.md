# Source-bound stage Results

`stage_results.check` connects every stage's authored `results` map to its exact
pipeline from [source-bound operation collection](stage-parameters.md).
It derives the Result source from the retained Program, not a caller-supplied
replacement map, and invokes the existing
[Relation Result checker](relation-results.md). The immutable result retains
the operation collection and each checked Result set.

## Grammar and references

Language's `ResultDefinition` is closed over `from`, `fields`, `order_by` and
optional `meta`. The first three are structural selectors, not Parameter value
roles. Their existing readers reject Parameter-shaped objects; an additional
`$param` member also rejects. Annotation content remains opaque business data.
Thus Result validation, rather than a generic JSON reference scan, establishes
that these admitted bodies do not add Parameter occurrences.

The fixed Sketch `87dc7144` Parameter resolver also classifies `results`,
`fields` and `order_by` as structural keys. Its generic path-based discovery and
older unstaged annotation positions are not reused as authority for this
composition. The current normative grammar and existing Result admission are
the governing rules.

## Limits and obligations

Result count, visited nodes and text bytes share one allowance across all stages.
Depth is the existing per-traversal maximum. `max_work` includes the retained
operation-reference collection's reported work, one registration unit per stage
and every Result check's reported work. A budget smaller than already consumed
operation work rejects before Result checking. Exact aggregate limits pass;
failure returns no partial checked Program. Result failures retain the stage
index and existing diagnostic path/span.

These limits do not retroactively account for earlier parsing, declaration
admission or pipeline type checking. They are bounded composition accounting,
not a wall-clock or heap quota. A complete checking entry must additionally
compose those earlier budgets.

Every Result still retains `TotalDeterministicOrder` as an obligation. This entry
does not resolve publication order, capacity, input provenance, cross-stage
Result-import contracts or runtime execution. It also does not inspect Input,
Effect or opaque-binding value roles or establish complete Program usage and
identity. The operation reference index remains operations-only; a successful
Result check does not silently rename it a full Program semantic index.

Tests cover all-stage attachment, retained pipeline ownership, metadata opacity,
Parameter rejection in structural slots, unresolved publication obligations and
aggregate exact/one-less work, node, text and Result limits.

## Source-bound Result imports

`bind_ports` attaches prepared [Result ports](result-ports.md) to one
`stage_parameters.CollectedStage`. It requires both the exact checked pipeline
and the actual stage's `results` cursor, including arena and node identity.
Rechecking an equal replacement map does not establish that ownership. The
opaque `StagePorts` retains the source-bound stage and all its publications.
This is an attachment check over already admitted handles, not another source
or pipeline traversal.

`resolve_imports` selects every Result import from the requested stage's actual
syntax, using a registry of those opaque producer owners. Every supplied owner,
including unused entries, must belong to the same prepared Program source and
an earlier stage. Duplicate producer registrations reject. Stage and Result
names are looked up in indexes; schema equality is never a substitute for the
selected Result. Repeated references retain separate input names while sharing
the same immutable port. Missing checked producers reject even when structural
parsing already established that their authored names exist.

The returned `ResultImports` retains the consumer source/index and indexed
entries. Each entry retains its input name, producer stage and named Result
port. `input_producer` exposes that port's projected, publication-ordered
conditional input to pipeline checking. It does not bind unrelated external
rows or mint an Invocation identity. Producer execution obligations remain.

Registry entries and all syntax import visits share `max_work`; stored producer,
input and reference names share `max_text_bytes`. `max_imports` bounds Result
entries. Receipt imports are visited but are not resolved or counted as Result
entries. Indexed syntax access avoids copying a whole import collection before
budget admission. Indexed Result lookup avoids scanning every publication for
each reference. Earlier parsing, type checking and port preparation retain their
own reported budgets; these limits cover this attachment pass only.

This is deliberately a Result-import subpass, not a complete stage-input
checker. Receipt schemas, ordinary Input contracts, stage activation, effective
bindings and complete input-name coverage still need
their own checks. Callers must retain the opaque import collection rather than
treating a detached `ProducedInput` as proof of Program membership. No import
performs a provider read. Root export and full Program identity checks remain
separate.

`attach_imports` closes the Result-specific consumer attachment: the collected
consumer must have the exact source and stage index, and every named Result
input must retain the exact resolved `ProducedInput`, even when unused. An
equal schema or a port prepared for another Program cannot substitute for it.
The opaque attachment retains both the import collection and the source-bound
consumer. Its work limit includes import-resolution work and one check per
Result entry; it does not re-charge earlier operation-reference collection.

Regressions cover repeated imports into source-bound downstream `take`, foreign
Program/pipeline/Results owners, non-earlier and duplicate registrations, absent
producers, substituted consumer inputs, isolated caller arrays and exact
work/text/import limits.
