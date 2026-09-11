# Source-bound local Relation inputs

`stage_local_inputs.prepare` reads the actual input slots of one stage retained
by `stage_parameters.Source`. Every non-import slot is passed to the local
Relation declaration reader; unsupported Carrier or Connector declarations fail
explicitly rather than disappearing from coverage. Source-admitted Result and
receipt imports are excluded from this local pass and remain obligations of
their own import checkers. Successful preparation is not evidence that those
imports were resolved or that another stage was checked.

The opaque result retains each name and declaration owner, including unused
local inputs. `input_at` supplies either the exact declared KeyedInput or the
exact CarrierInput, without Host augmentation. The compiler uses these handles
when checking the stage pipeline. Registration arrays can be reordered; input
names, not positions in those arrays, determine the later correspondence.

`attach` requires the same prepared Program source and stage index as the
source-bound pipeline collection. For each local name it verifies the original
pipeline registration variant and its exact Carrier/key owner. Checking only
the derived Carrier would lose key provenance; checking only `input_key` would
also admit a differently registered candidate-key collection. `pipeline_typing`
therefore retains and exposes each original InputContract handle in detached
storage, alongside its existing derived evidence views. The source-only path
does not accept a producer, ranking or candidate-key registration as equivalent
merely because the schema or selected key matches.

This is an ownership restriction on this specific assembly path, not a language
ban on Host evidence or richer input registration. Reconciliation of admitted
Host snapshots against source assertions needs a separate checked owner. Neither
this attachment nor handle equality admits that external evidence, graph Delta
contracts or other separately supplied policies. The final Program boundary must
still integrate those paths and their dependencies.

## Bounds and remaining obligations

`reconcile_schemas` checks a partial name-indexed set of supplied complete
Relation schemas against the exact declarations in one `Prepared`. Names resolve
only within that stage's local slots; unknown or repeated names fail, including
byte-identical repetitions. Each comparison uses `local_relation_input.check_schema`
and retains its declaration owner and stronger actual schema. Omitted slots have
no agreement, not an inferred snapshot or an empty schema. The returned opaque
`SchemaAssertions` keeps results in declaration order and does not retain caller
arrays. A later failure returns no partially successful batch.

The batch includes the prepared source work/nodes/text once, indexes all local
slots, visits every supplied entry, and shares the remaining type-node/work and
UTF-8 allowances across comparisons. Supplied selector names are charged before
lookup. Depth bounds each type comparison; it does not replace the source depth
check already performed during preparation. Repeated shared type objects are
charged per use, without a cross-input budget reset.

This is deliberately not `AdmittedSnapshot`: it does not verify a snapshot CID,
Check Environment membership, source-ref mapping, materialization or Host authority.
It does not change `input_at` or enter the source-only `attach` path as augmented
input evidence. The later admitted snapshot boundary must retain this exact
prepared owner and validate those external links before registering stronger
types. In particular, equal input names in another stage are not global selectors.

`reconcile_snapshots` now joins integrity-checked `local_relation_snapshot.Snapshot`
bodies to a `stage_source_refs.Index` and this exact prepared stage. It requires
the index's original Program source owner, resolves each snapshot's own selector
(not a separately supplied label), and rejects resolutions to another stage.
It then uses `reconcile_schemas` for the complete supplied batch. Each opaque
binding retains the original snapshot, resolved input and exact declaration/type
agreement; no caller may pair a snapshot CID with unrelated asserted fields.
Snapshot order is retained while schema assertions stay in declaration order.
Missing snapshots remain missing, and late failures expose no partial binding.

The aggregate includes full snapshot byte/node sizes per occurrence, source-index
resolution costs, prepared-source costs, schema comparison costs and the indexed
binding assembly. Shared node/work/text caps do not reset per snapshot. Depth
limits the new type comparisons; already checked source/snapshot passes retain
their original depth checks. Snapshot bytes here are conservative evidence-size
charges, not a claim of exact retained heap size. No duplicate cost is subtracted
based merely on matching CID or equal types.

`CheckedSnapshots` closes source correspondence and assertion agreement, not
Check Environment membership, Host authority, materialization validation or
runtime key/order obligations. It does not alter source-only `input_at`/`attach`
registration and is not the final Program's admitted external-input boundary.

`reconcile_environment` connects a selected stage's `EnvironmentSnapshot` values
to this same source/type reconciliation, retaining an exact `WireEnvironment`
owner in opaque `EnvironmentInputs`. A member from a separately read environment
is rejected even when the environment bytes and CID are equal. The returned
member positions correspond exactly to the returned snapshot bindings, independent
of wire CID order or source declaration order; caller arrays are copied.
Membership enumeration adds to the existing cumulative snapshot costs. This pass
does not charge or re-admit unrelated environment bodies. Partial or empty selected
sets remain partial evidence, never proof of complete environment coverage.
Final Program assembly must check all required inputs and all supplied evidence,
governing policy and provenance, and retain this owner when combining stages.
This does not change source-only pipeline registration or grant Host authority.

`assemble_environment` collects exactly one `EnvironmentInputs` for every stage
of the same source and wire environment. Input array order is immaterial; the
opaque result indexes stages in Program order and copies the caller collection.
Every supplied SchemaSnapshots member must occur in the checked stage results;
omitted members and repeated stages are rejected. This is the local-Relation
assembly path: unsupported snapshot kinds cannot be silently skipped to obtain
its coverage result. Their future dedicated readers must integrate explicitly.
An input without a supplied snapshot is not implicitly rejected or marked
materialized. Determining required evidence from declarations and policy remains
the compiler's responsibility, distinct from accounting for all supplied bodies.

Assembly charges prior stage costs cumulatively plus stage/member indexing and
coverage checks, with no equal-CID cost discount. Depth is not re-traversed here;
prior readers retain their own depth caps. Other Check Environment sections are
not validated by this result. Catalog closure, policy/authority checks, stronger
pipeline input registration and final lowering-ready Program assembly remain open.

Preparation charges stage input enumeration and import-name indexing, then each
local declaration's source nodes as logical work. Node and UTF-8 allowances are
shared across all local declarations, including metadata; depth is measured from
each declaration root. Import bodies and outer input names belong to prior source
admission and the separate import pass, not this local text allowance. The local
reader reports consumed source nodes/text so later fields cannot reset the caps.

Attachment includes all preparation work, the source-bound stage collection's
work, one pipeline input-name registration per input and one owner check per local
declaration. Exact limits succeed and late failures expose no partial attachment.
Independent passes retain their costs; future Program assembly must subtract
shared costs only after checking exact shared owners. These are logical-work and
source-size limits, not runtime row limits or process heap accounting.

Declared key admission and duplicate normalization remain conditional. In
particular, `first_by_order` still requires independent total-order resolution,
the selected raw/normalized input policy and runtime validation before selection.
This attachment neither discharges those requirements nor authorizes execution.
`pipeline_check_context.attach_local_inputs` now joins one such attachment per
stage to the intermediate all-stage context and Result wiring, requiring exact
shared CollectedStage owners and cumulative costs. This is still not the final
lowering-ready compiler output; the obligations above remain unclosed.

Tests cover keyed and unkeyed inputs, unused slots, reordered and mutated caller
arrays, equal-looking reread declarations, dropped keys and candidate-key
substitution, foreign sources, aggregate exact/short budgets and the separation
of local slots from Result/receipt imports.
