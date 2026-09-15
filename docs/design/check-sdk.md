# Check SDK boundary

The standard check interface accepts a Program document or an admitted parsed
Program, supplied Parameter values, an environment of available inputs and
contracts, and compile limits. It constructs the
[CheckedProgram](checked-program.md) without requiring the caller to reproduce
compiler phases, contextual producer visits, or derivable capacity proofs.
Checking does not perform source I/O, authorize execution, select a physical
backend, or claim that runtime validation has completed.

## Inputs and outcomes

Document and parsed-Program entry points use the same semantic checking body.
Only the parser's admitted representation is reusable; an arbitrary internal AST
is not a checked input. Reuse avoids charging parsing that is not performed,
but retained document size, structure and depth must still satisfy the limits
of the current call. Source locations survive both paths. File and URL readers
belong to Host conveniences, not to Core checking.

The reusable Program owns measurements from its original parse and immutable
tree admission. Raw input bytes include a BOM, trailing whitespace and YAML
comments; a root span is not a substitute for document size. Parser node/depth
measurements and admitted-tree node/depth/text measurements remain distinct.
Admitted text bytes include field names, with both a largest-string limit and
an aggregate string limit. These measurements describe retained input, not
CPU work repeated by reading them. A child cursor's admission measurements
describe its whole owned tree, not the child subtree.

Reuse checks each current retention limit without reparsing, rebuilding the
tree or repeating structural stage validation. An exceeded retention dimension
is a diagnostic, not an external evidence request. It retains the source name
without fabricating a source span for an aggregate size failure. Semantic
checking and its current environment, bindings and compile budget still apply;
successful retention validation alone does not construct a CheckedProgram.

The checker distinguishes three outcomes:

- A complete opaque CheckedProgram, constructed only after static closure.
- Typed requests for missing external facts or explicit contract selections.
- Diagnostics for invalid or contradictory input, unsupported implementation
  paths, exhausted budgets, and other failures.

A request identifies its target, the needed fact or selection, admission
conditions and available original diagnostic locations. It is not a successful
check, permission to execute, or a guarantee that the unvisited remainder of the
Program is valid. Only requests established at the current checking frontier
need be returned; exhaustive recovery and complete multi-error enumeration are
not part of this interface.

The caller supplies additional environment or evidence inputs and invokes check
again. Responses are untrusted inputs, not `fulfilled` flags. The checker must
validate their applicability to the current Program, bindings and contracts;
it must not silently reuse a response after a changed source position points to
another operation. No suspended checker state or general resume protocol is
required. Implementation gaps, contradictions and exhausted search budgets are
not external evidence requests.

Existing runtime obligations remain runtime obligations when their contracts
permit that phase. A statically required fact cannot instead be deferred to
execution. Runtime checks retain their subjects, phases, dependencies and
atomic failure behavior.

## Evidence supply and derivation

Explicit evidence is an advanced input, not the center of ordinary SDK use.
Three dimensions remain separate:

| Dimension | Meaning |
| --- | --- |
| Authored location | Stage ID, original step ordinal, input or Result name, and where needed aggregate output or operand role |
| Purpose | The typed quantity and use, such as output rows, a right-input bound, or aggregate array items |
| Applicability | The exact Program/Unit, bindings, contracts and checked owner under which the evidence may be used |

An authored location locates a target; it is neither permission to apply a
proof nor a persistent identity. Definition-level facts, application to a named
consumer input/import path, and completed observations or execution attempts
are distinct. Repeated imports can share an applicable definition fact without
collapsing their input occurrences or equating separate observations. Evidence
body CID equality does not establish checked-owner equality. Existing bound
wire bodies are not rewritten merely to simplify target lookup.

For supported Programs, the compiler constructs the facts necessary for formal
check completion that follow from existing inference rules and admitted
premises. It preserves existing candidate collection and selection rules; this
does not require enumerating every derivable proof. Host-supplied facts and
selected runtime capacity contracts are not invented. Failure to finish a
derivation within the compilation budget is a budget failure, not absence of a
key, proof or external fact.

The input-responsibility split for the supported formal-check domain is:

| Rule family | Compiler-owned derivation | External premise | Explicit selection / remaining boundary |
| --- | --- | --- | --- |
| Stage topology and Parameters | Named imports, producer occurrences, effective bindings and typed uses | Program and supplied values; available input declarations | No caller-provided visit order; unavailable values may require a request |
| Local input and SourceView interpretation | Reconcile declarations, select applicable type/request contracts and retain source policy dependencies | Admitted environment, Local snapshot assertions, Catalog bodies and source contracts | Selected policy remains authoritative; checking does not acquire data |
| Relation keys and logical order | Existing exact-copy/projection/key-transfer rules and operation-specific order completion | Declared or otherwise admitted keys/order facts with their required validations | Runtime uniqueness is not statically asserted; unsupported inference is not added |
| Values and generated sources | Bound-cell admission, known row counts, typed-wire/recursive measurements and their existing proof forms | Parameter values and the declared value contracts | Host ceilings and selected numeric/calendar contracts are not inferred from compile limits |
| Capacity composition | Apply existing transfer/count laws to the actual input occurrences; collect applicable candidates and select prescribed limits | Applicable admitted external bounds and their owners when needed | Preserve author guards and selected capacity policy; retain atomic enforcement |
| Numeric, Calendar and lexical interpretation | Bind the selected profile and retain operation/slot identities and dependencies | Admitted profile data and contracts | A missing explicit profile is not permission to choose another meaning |
| Aggregate, nest, window and search limits | Existing producer-bound candidate selection and quantity-specific obligations | Required input bounds and selected ceilings | Rows, items, memberships and search work remain distinct; not all are output-row bounds |
| Policy, publication and incoming requirements | Existing dependency transfer, Result/import interfaces, Unit identity and runtime-check linkage | Admitted policies, source assertions and applicable evidence | No completed observation or authorization is fabricated; effect/receipt paths outside the supported domain remain unsupported |

This table assigns responsibility, not conformance by operation name. Carrier
alternatives and operation-specific prerequisites still govern each rule. In
particular, the existence of a wire grammar for a path does not make that path
supported by the formal checker. An implementation gap must remain a diagnostic,
not a request for the caller to manufacture a successful checker result.

## Owned information and preparation

Operation consumers depend on the owned pipelines, effective bindings, selected
policies, capacity context and retained resolutions they actually need. They do
not traverse unrelated Calendar, lexical, expression or identity preparation
wrappers to recover that information. Phase-specific checked types still record
what was validated; retaining a narrow shared reference does not make an earlier
phase a later successful one.

Shared information is immutable within a construction. No mutable universal
Context or generic proof constructor replaces operation-specific validation.
Public boundaries that accept independently built handles reject foreign
combinations with typed errors. Internal sharing does not replace ownership
checks with CID comparisons or assertion failures.

Each preparation contributes incremental usage to the construction's remaining
budget. Callers and collectors must not independently reconstruct cumulative
shared prefixes. Compilation-wide proof conversion reuses an already converted
node only for its exact checked owner and Unit binding. Repeated operand edges,
proof uses and publication candidates remain present even when the immutable
converted object is shared. Actual lookups and reference retention are charged;
hashing and construction are charged when performed. Failed attempt state is
not reusable by a later construction.

## Limits and diagnostics

Public compile limits describe document size and structure, traversal work,
generated or retained artifacts, and canonicalization/identity preparation.
They do not expose package preparation order. Existing metering scopes remain
distinct: payload bytes are not interchangeable with metadata/hash bytes,
additive work is not a depth maximum, and source size alone does not bound
generated aliases, combinations or proof graphs.

Compile effort, Program guards and selected capacity contracts, and Host/backend
physical limits are separate configurations. Changing a compile limit cannot
change a selected runtime contract. Removing unnecessary computation may reduce
charged work; it does not waive work actually performed or change the meaning
of a meter.

Diagnostics retain a stable classification and typed details, applicable target,
origin domain, path, source span, decoded-expression range and related causes
or locations. Origin domains distinguish Program, environment, supplied values,
evidence and check configuration. A decoded-expression range is not a raw
document byte range. Missing location information stays explicitly absent; it
is not fabricated as the Program root. Normative failure order is preserved,
without requiring clients to unpack a preparation-phase wrapper tree.

## Consumers and responsibility boundaries

The standard path owns visit expansion, evidence applicability and preparation
order for every supported formal-check route. A parallel legacy Program
construction path is not a compatibility requirement. Independently useful
parsing, value admission and expression checking APIs can remain public; APIs
whose only purpose is assembling Program preparation phases need not be public.

Lowering reads retained input edges, effective values, order strategies, limits,
policy, identities and runtime obligations. It does not reconstruct checker
ownership or decide semantics again. Capability matching, candidate comparison,
placement, reservation, retention and recovery belong to the execution layer.
The fixed-input engine's completion, ownership and budget interfaces are shared
contracts; concrete Connector behavior stays in its Connector.

Acceptance includes public document/parsed equivalence; Local and values,
multiple stages, repeated Result imports and SourceView paths; evidence and
diagnostic ownership failures; budget boundaries and atomic later-stage failure;
and consumers that read decisions without inference. Shared-graph construction
counts and independent usage checks accompany identity, capacity and obligation
invariance. Operation expansion, new inference, general execution admission,
Workers support and durable capture are not implied by this checking boundary.
