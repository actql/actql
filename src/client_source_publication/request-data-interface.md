# Explicit published Source request DATA

- Responsibility: carry an optional explicit literal request from an installed
  alias into its existing Captured Source input. Publication admission is not a
  read grant, execution decision or request-schema defaulting mechanism.
- Inputs and outputs: a present request must be an object. Omission remains
  absent and explicit null, scalar and array roots refuse. An empty object is
  retained as written; subsequent existing Source input admission may refuse
  it. Missing, unknown, value-type and correlation checks remain with their
  existing Source and Request owners.
- Identity: the request stays attached to the same resolved alias, SourceRef,
  SourceView, schema and nominal Environment. Prepared geometry is readable
  only with that same Environment. Equal CIDs and replacement publications do
  not recover the original prepared owner or an in-progress Request quote.
- Ownership: immutable admitted literal DATA is copied using the existing
  Source emitter into the retained Captured input. No caller object, mutable
  reader or parameter value is retained. Direct request-field singleton
  `$param` and `$binding` forms refuse because the existing slot reader would
  interpret them as references. Nested business objects keep literal meaning.
- Synchronization: measurement precedes allocation of each copied input's text
  and index. The existing Request retains its publication, Environment, parsed
  query, declarations, quote and output, and reserves before lowering. Failed
  grows cannot swap inputs or perform a second successful lowering.
- Failure: publication shape/identity and existing writer bounds still refuse.
  No missing-to-null repair, selector repair, new reference support or weaker
  Request guard is introduced. LIST_FILES selector-conflict and keyed-request
  correlation rules remain owned by their unchanged existing implementations.
- Cancellation: the existing installation and Request owners retain their
  normal borrower, abort and physical cleanup duties. A cursor, measurement or
  geometry projection does not acknowledge cleanup or fund future work.
- Resources: the prepared publication retains independent maxima for actual
  request nodes and key/value UTF16. Each lowerer external input needs an
  authored relation occurrence with at least one original query token. CTE reuse
  keeps its captured Result instead of expanding that external input. The
  complete original token count conservatively bounds initial alias imports,
  not all later snapshot invocations. Four separate live construction lanes
  cover later copies as derived below. Each lane includes the request field/parent wrapper, concrete builder and
  Source-map/index inventory, Writer and emitter overlap through the shared
  representation tariff, added before the same Request capacity grow. The
  installing Host must separately fund original publication parsing, each
  copied input, Catalog/Mapping/Context construction and retained lifetime.
  A literal-copy quantity is not a whole-publication constructor quote.
- Extension: no new Run, ledger, manager, policy authority, serializer or query
  lowering behavior is added. The existing builder quantity API owns its own
  implementation families; absence adds zero request-copy charge.
- Verification: native focused tests cover nulls and required literals, missing
  and invalid Request values, root/reference forms, Source/alias/Environment
  identity, unchanged retained data, exact emission and one-short emission.
  Request tests exercise repeated alias copies, both capacity dimensions and
  exact retained original reuse. They are component evidence, not whole Host
  construction, physical source, Model or end-to-end execution acceptance.


## Request-copy lifetime derivation

Let T be the original admitted query token count, N the largest retained
request subtree node count plus its enclosing input node, and U the largest
original key/value UTF16 total plus the seven units of `request`. The maxima
belong to the exact prepared Environment. A distinct external input import
requires an authored relation occurrence. Script input binding caches the
original input in `ScriptSources.bound`; CTE and continuation references import
an existing Result instead of replaying that Source. T therefore bounds initial
request occurrences, including joins, set arms and nested producer bodies.
It does not by itself bound prefix or member copies.

The constructor composition has four separate live lanes per occurrence. Each
lane conservatively includes a full annotated builder tree, Source-map plain
tree, Decode index, constructor views/work, normalization and scalar Writer:

1. Original import: `compile.mbt` and `query_script_inputs.mbt` import Captured
   declarations into the single selected Construction. The annotated tree is
   retained through prefix probing and final `finish`.
2. Full prefix: `infer_prefix_program.mbt::checked_query_prefix_pipeline`
   snapshots the complete prior/current stages. This snapshot remains charged
   through member resolution and Common checking, including diagnostic refusal.
3. Member copy: `member_resolution.mbt::MemberResolution.finish/copy` imports
   the complete Source when replacements exist. During the preceding scan,
   `member_program_prefix.mbt::source_prefix_carrier` instead imports prior
   stages and current inputs/steps into another Source. It calls Common
   registration/checking, not the frontend or another member resolver. Its
   borrowed input Source remains in lane 2. The scan ends before `finish`
   starts, so those two lane-3 constructions cannot be active recursively.
4. Demand copy: `query_script_program.mbt` completes member resolution and
   checking before `query_binding_prune.mbt::prune_query_binding_source`
   imports retained inputs/steps. The original checked topology and demand
   pipelines still refer to the pre-pruned Source, which stays charged. Pruning
   does not invoke another member-resolution pass.

These are lifetime lanes, not invocation counters or a backend GC assertion.
The proof does not release a Source while a Cursor still addresses it:
`InferPrefixProjection.checked` is consumed inside `lower_infer_steps` before
that operation returns. The nearest CheckedPipeline is consumed inside one
`lower_nearest_steps` call. Script checked-prefix pipelines are consumed before
the next carrier operation; only Carrier/schema/name facts enter the
`ScriptSources` maps. Carrier, Knowledge, value Contract, and graph definition
records contain no Source Cursor. `RetainedResult` likewise contains generated
Nodes and names, not checked prefixes. The Common checker does not call back
into the frontend. A failed probe terminates or defers that same scan and its
diagnostic Source stays in its occupied lane. No reservation is refunded based
on presumed physical collection.

All later copies read normalized object keys and unchanged scalar values.
The common NFC/LF retained-output bound plus U bounds their text; NFC/LF
idempotence prevents repeated exponential growth of this bound. The builder's
scalar measuring Writer is bounded from normalized-key output as well.
Final emission separately includes the Stage-owned traversal inventory and
Writer alongside all four lanes. Quotation is O(T * (N + U)) representation
units; it does not multiply probe count, nesting count and occurrence count.

The independent correspondence tests keep original/full-prefix/member/pruned
Sources reachable together, check dense and deep request node/text counts and
foreign tree indices, and exercise both nested Source-prefix and outer checked
prefix refusal. These are constructor/lifetime evidence, not a heap profiler
or proof that unrelated native Environment construction is funded.
