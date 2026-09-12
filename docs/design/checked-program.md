# Checked Program construction

This is the construction contract for the main-side boundary described in
[Pure operation checking](pure-operation-checking.md#main-and-lowering-ownership).
It specifies the orchestration target, not an already available API or a new
wire artifact. Language and the pinned machine contracts remain authoritative.
Existing `pipeline_check_context` results are implementation components of this
boundary; adding another component is not itself end-to-end completion.

## Entry and success

The intended entry is `program_check.check`. It takes source and admission
material, not a caller-assembled list of checker successes. Its conceptual
arguments are:

| Argument | Meaning and checks performed inside the boundary |
| --- | --- |
| Parsed Program | The normalized, source-owned `stage_syntax.Program`, including paths/spans. Parsing is a separate bounded entrance, not repeated by the checker. |
| Check Environment | The canonical integrity-checked `check_environment.WireEnvironment`. Integrity alone does not establish Catalog closure, policy validity, issuer trust or usable input evidence. |
| Supplied values | Parameter values and the applicable typed opaque-Binding evidence. Parameter declarations, defaults, used-name selection and binding ownership are derived from this Program, not supplied as a second declaration set. |
| Check configuration | Explicit selected language profiles, pinned semantic capabilities and available profile artifacts. These are checked against their governing contracts; backend availability is not a language admission rule. |
| Check budget | Aggregate admission/work/text/node/hash limits and per-traversal depth limits. These are not execution resource ceilings or Host authorization. |

These argument groups describe responsibilities; concrete auxiliary type names
are not additional accepted public structs. In particular, Binding evidence is
not an arbitrary JSON value plus a `validated` flag. A supplied claim is usable
only through the applicable existing admission boundary and its exact owner.
Inputs unavailable in an implementation produce a specific unsupported or
unresolved diagnostic, not empty evidence or fabricated values.

Success returns only an opaque `CheckedProgram`, constructible through the
validating entry. All selected semantics are static-ready for lowering; every
remaining execution check has a typed binding as described below. Missing caller
bindings, inconsistent evidence, unsupported static handling or an unresolved
mandatory static requirement produce an error with no partial CheckedProgram.
Public planning variants such as `needs_bindings` and `pending_predecessor` are
separate protocol results, not successful CheckedPrograms with weaker guarantees.

Future Result values do not have to exist at Check. Their declared typed ports
and producer/gate correspondence do. A value-dependent condition remains an
execution obligation only when the governing rule permits that deferral and its
dependencies are connected. Check does not manufacture an observed Invocation,
completed predecessor, acquired row, receipt or issuer permission.

## Internal construction

The entry orchestrates existing admission and checking code rather than creating
parallel implementations of the rules. Its dependency order is:

1. Prepare the Program's declarations, effective Parameters and source-role
   inventory. Validate the environment components that are required or present
   under their existing contracts, and select input registrations from admitted
   source/contract evidence. Whole-environment integrity and membership remain
   distinct from the later local identity projection.
2. Check stages in source dependency order. Prepare a producer's Relation Result
   ports before checking consumers; resolve imports against those exact ports.
   Preserve all source stages, unused operations and repeated producer visits.
   Do not silently replace an earlier registration with an equal-shaped type.
3. Derive each stage's topology, types, bound references, conditional evidence,
   order strategies, resource applications and publication requirements. Reuse
   the same resolved-order owners when ports and contexts share them. Validate
   cross-producer proof ownership and the selected policy and binding owners.
4. Resolve expression and operation static requirements from their complete
   owned inventories. Derive local source/declaration/contract/import projections
   from these same owners. Check the required semantic identity relationships;
   process handles and step indices never substitute for these identities.
5. Build the exhaustive obligation coverage described below, validate dependency
   and application correspondence, and seal the result atomically. There is no
   alternate constructor that skips this final check.

This order is a dependency graph, not a requirement to reconstruct earlier
results at every phase. Private incremental assembly can retain immutable
intermediates. Public low-level helpers remain useful for focused tests, but
their existence is not an alternative formal Program compilation entrance.

Shared work is counted once for an exact retained owner; additional branch work
and join validation are still charged. No phase resets the Program budget.
The final retained usage distinguishes parsing/prior admission where applicable,
integration work, emitted bytes/nodes and execution limits. Index allocation and
iteration are bounded before retaining entries. Runtime data is not materialized
as a whole Program-sized row tree to satisfy this constructor.

## Exhaustive obligation coverage

Coverage starts from the source, expression, operation, input, publication and
incoming-dependency inventories, not from the list of successful resolutions.
Each owned occurrence has exactly one disposition:

| Disposition | Required content |
| --- | --- |
| Statically resolved | The typed resolution and its exact source/producer/binding/policy owners. Conditional assumptions link to the execution checks that enforce them. |
| Execution check connected | A typed execution binding with subject, application point, prerequisite evidence/dependencies and prescribed failure behavior. |
| Unsupported or statically unresolved | A construction error. This disposition cannot appear inside a successful CheckedProgram. |

A nonempty execution-check collection is normal. An unclassified occurrence,
foreign resolution, duplicate disposition, missing dependency or unconsumed
resolution is not. Matching counts is necessary but cannot replace checking the
specific occurrence and its owner. Repeated references are separate occurrences
even when they share a resolved contract or execution dependency.

Classification matches the full typed obligation variants exhaustively, including
nested operation-family variants. No catch-all branch maps a new kind to success
or runtime. A coverage check compares the registered inventories with the handler
set so that a new kind in a previously irrelevant family also requires review.
Handling remains operation-specific; there is no universal `safe` or
`preserves_evidence` flag.

An execution binding retains:

- the protected typed subject: input, producer output, operation occurrence,
  expression occurrence, Result port or incoming gate;
- the enforcement point required by the law, such as input admission, before
  consuming a producer, during an operation, or before publication;
- the exact selected rule, bound quantity/strategy and evidence from which it
  was derived, plus references to prerequisite checks;
- the specified failure outcome and which output/continuation cannot be
  exposed when the check fails.

This is a semantic enforcement requirement, not a backend callback or a promise
that a backend already implements it. Its dependency graph cannot reference
another Program, an omitted producer or an unavailable future prerequisite.
Cycles in enforcement prerequisites are errors; this does not prohibit cycles
in Graph data admitted by the language. For example, a conditional candidate
key retains uniqueness admission, and a resolved capacity retains its quantity,
target and enforcement obligation. Neither becomes unconditional proof merely
because its static arithmetic or CID matches.

## Identity boundaries

[Local contract closure](local-contract-closure.md) separates the selected
contract set from source occurrence evidence and concrete execution decisions.

Contract selection is defined before its canonical JSON representation. It
includes the direct semantic dependencies and their required transitive
dependencies, including domain, guard, permission, scope and failure rules.
Unrelated Catalog additions do not become local semantic dependencies. Repeated
uses remain associated with their sites even if canonical storage shares a
contract. Unknown dependencies and conflicting pins prevent closure; dependency
cycles require an explicit governing rule rather than truncation at a visited set.

The contract closure identity, Unit Definition and concrete Invocation remain
different roles. Selected policy/capacity evidence belongs to the identities
specified by its governing rule, not automatically to source Definition. The
whole Check Environment or Catalog CID is not a fallback local preimage.
Membership/authenticity still have to be validated where required; excluding
them from a local hash does not waive those checks. Semantic preimages and fixed
independent vectors are established together with the selection rules.

The result retains source Program/Stage identities and required local definition
projections. Observation-dependent identities are not fields populated with
placeholder CIDs. They are constructed later from admitted concrete observations
and this result's exact semantic dependencies. Static readiness is neither an
Invocation nor authorization to run it.

## Lowering reads

Read-only count/index access exposes the source-owned stages, role-tagged input
edges and producer ports, checked operations and Carrier contracts, selected
bound values, exact order strategies and their dependencies, resource witnesses
and protected applications, local identity projections, and obligation bindings.
Paths/spans and embedded-expression ranges remain available for diagnostics.
Returned collections cannot mutate the sealed result, and large arrays are not
copied before the caller can apply its preparation budget.

Lowering consumes these decisions without re-resolving names, re-inferring keys
or order, choosing substitute policy or combining independently supplied checker
results. It verifies that its selected registry/backend can represent every
operation and required execution binding. Failure to represent one prevents an
executable Plan; it does not retroactively change language type acceptance.
Plan structure/identity validation and actual execution are downstream checks.

## End-to-end acceptance

The integration fixtures enter through the formal check entry, not through a
test helper that seals preassembled successes. Establish these paths early:

| Program | Essential coverage |
| --- | --- |
| Local, no external acquisition | A small typed local input or generator, transformation and named Result; actual source/Parameter/environment preparation through sealing. |
| Multiple stages with Result import | Producer port construction, consumer registration, local identities and incoming success requirements, with a failure in the later stage exposing no partial Program. |
| SourceView and capacity | Selection from the admitted Catalog, request/binding validation, quantity-specific capacity and producer dependency, with execution checks retained rather than performed. |

For each path, fix expected semantics independently of the product constructor.
Test equal-content evidence from another Program/environment, missing dependencies,
conflicting pins, repeated/unused branches, exact/short aggregate budgets and
late failures. Runtime checks remaining in a successful result are asserted by
subject, application and dependency, not merely by count.

The three paths start integration; they do not replace the complete agreed
operation scope. Extend a coverage matrix by operation, Carrier alternative,
evidence generation/transfer/invalidation and downstream consumer, selecting
representatives of distinct code paths rather than a Cartesian product.
Run JS/Wasm/native, API, format, document and metadata gates throughout this work.
Linux CI is checked for exact intermediate revisions as they become available,
not inferred from local success or postponed as the only final check. CI execution
does not authorize publishing a branch or modifying another worktree.
