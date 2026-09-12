---
spec_id: actql.language
status: adopted
version: actql/0.1
normative_dependencies: []
---

# ActQL language

[Specification index](README.md)

This document owns source, types, expressions, operations, nest, effect-intents, canonical-semantics, observable-boundaries. It does not define other owners' wire protocols or a particular Host implementation. Cross-owner links outside the declared dependencies are informative navigation to protocol bindings or conformance evidence; they do not import those documents' requirements. Narrow machine contracts remain authoritative for their explicitly referenced values and envelopes.

<!-- page-contents:start -->
## On this page

- [Scope and conventions](#scope)
- [Source and Program structure](#source-and-program)
  - [Linear stages](#stages)
- [Carriers, values, and types](#values-and-types)
- [Inputs and external contracts](#inputs)
- [Expressions and predicates](#expressions)
- [Operations](#operations)
  - [Operation inventory](#operation-inventory)
  - [Relation operations](#relation-operations)
  - [Event operations (TEA)](#event-operations)
  - [Graph operations (SGA)](#graph-operations)
  - [Vector operations (VecA)](#vector-operations)
  - [Pure lexical ranking: `text_rank`](#text-rank)
  - [External ranked acquisition: `search_candidates`](#candidate-search)
- [Named Results and Effect declarations](#results-and-delivery)
- [Checking and canonical planning](#checking-and-planning)
- [Structural grammar (normative)](#structural-grammar)
- [Complete example (informative)](#complete-example)
- [Machine contracts](#machine-contracts)
<!-- page-contents:end -->

<a id="scope"></a>

## Scope and conventions

An ActQL Program defines a bounded computation over typed observations, with
named Results and optional Effect intents in finite linear stages. The same Program can be executed
repeatedly; each execution is managed as a Run. For one Invocation, pure
computation yields the same logical Result CIDs. This guarantee does not extend
to fresh acquisitions or Effect outcomes
([Capture, execution, and replay](execution.md#capture-and-replay)).

The language covers relations, graphs, vectors, event streams, addressable
Resources, captured Artifact bytes, bounded external acquisition, and typed
provider commands. Arbitrary scripts and raw HTTP are outside the language.

AoA supplies the common algebra and canonical fragment representation.
Compilation combines validated AoA Fragments and typed boundary barriers into
an Executable Plan ([AoA fragments and algebra lowering](#algebra-lowering)).

ActQL fixes a Program's observable semantics and leaves physical execution to
the Host. Checking establishes static validity and proof obligations under a
Check Environment. After binding, planning derives the closed execution envelope,
including limits not written in source. A Host MAY fuse, reorder, push down to a
Connector, or place computation elsewhere only when the chosen strategy
preserves the specified results and ordering, failure and atomicity behavior,
observation and data-egress scope, evidence, permission boundaries, and
Checkpoints. Sealed Plan identity and approval preservation are specified in
[Typed barriers and Plan Documents](#plan-documents); runtime admission is specified in [Checkpoints and Resolutions](execution.md#checkpoints).

The Program declares semantic choices and any independent author guards.
Contracts supply external-system meaning; checking derives execution facts;
the Host supplies current policy and execution ceilings. Concrete observations
and continuation state belong to the Run, not to Program source.

<a id="normative-conventions"></a>

### Normative conventions

<!-- requirement-block: normative-conventions.the-key-words-must-must-not-required-shall-shall-not normative-conventions.the-key-words-must-must-not-required-shall-shall-not.second normative-conventions.the-key-words-must-must-not-required-shall-shall-not.third normative-conventions.the-key-words-must-must-not-required-shall-shall-not.fourth normative-conventions.the-key-words-must-must-not-required-shall-shall-not.fifth -->
The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**,
**SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **NOT RECOMMENDED**, **MAY**, and
**OPTIONAL** in this document are to be interpreted as described by RFC 2119
and RFC 8174 when, and only when, they appear in all capitals.

Except for examples and text explicitly marked informative, this document is
normative. YAML examples, including [Complete example (informative)](#complete-example), illustrate the rules rather
than define them. Formal grammars, contract definitions, and semantic tables
are normative regardless of their code-block formatting.

**Checking** determines whether a Program satisfies the static language rules
under a Check Environment. **Binding** supplies declared invocation values.
**Planning** produces the canonical bound Executable Plan. These are semantic
phases, not command names or requirements on an implementation's internal
pass structure. Their results and permitted external access are specified in
[Checking and canonical planning](#checking-and-planning); execution is specified in [Run execution](execution.md#effects-and-execution).

Planning fixes an execution contract, not an immutable physical strategy.
Strategy selection and scheduling may continue during preparation and execution
under that contract ([Typed barriers and Plan Documents](#plan-documents)).

<!-- requirement-block: normative-conventions.phase-supplied-inputs-result-external-work -->
| Phase | Supplied inputs | Result | External work permitted by this phase |
| --- | --- | --- | --- |
| Checking | Program, Check Environment | Rejection for language violations or the checker's claim boundary, or a valid template with binding/proof obligations | None; evidence is supplied, not fetched |
| Binding | Declared parameter and opaque values | Exact typed values, or missing/invalid bindings | No provider observation or Effect |
| Planning | Checked Program, all bindings, Check Environment | Canonical bound Plan and execution-support status | None |
| Execution | Bound Plan, current authorization, initial captured inputs | Captured observations, Results, receipts, or a recorded failure/pause | Only the admitted Plan boundaries |

Initial input capture occurs during each activated stage's preparation, subject
to authorization and Checkpoints. Program-wide checking cannot prefetch a later
stage's business data ([Run admission and identity](execution.md#run-admission)).

Host Discovery ([Host Discovery protocol](protocols/discovery.md#discovery)) explicitly supplies published contracts before
checking; optional read collection ([Read collection protocol](protocols/collection.md#collection)) coordinates separate Runs.
Neither adds implicit I/O or failure recovery to compilation or pure operations.

Checking validity, binding completeness, and Host execution support are distinct
judgments. Rejection at a checker's profile-claim boundary does not assert that
the Program violates the language, and does not establish its validity.
A valid template without bindings is not runnable. A fully checked bound Plan
whose execution the Host does not support is `unsupported`, not runnable;
neither state grants access to external data. The public status mapping is
defined in [Plan Documents and public planning results](protocols/contracts.md#planning-wire).

<a id="terms"></a>

### Terms

The following terms distinguish source, checked meaning, captured computation,
and Host lifecycle. Requirements governing their identities and transitions
are specified in [Canonical identities](#canonical-identities), [AoA fragments and algebra lowering](#algebra-lowering), [Capture, execution, and replay](execution.md#capture-and-replay), and [Run admission and identity](execution.md#run-admission).

- **Generator** — an operation that establishes its output without consuming
  implicit current; any named additional inputs are still explicit dependencies.
- **Delta** — typed graph-value change data bound to exact base, target and
  structural contract identities; it is neither a capability nor a mutation.
- **Coverage** — evidence about the scope and completeness of a captured
  observation, not a percentage or proof of absence beyond that scope.

- **Program** — an `actql/0.1` document describing a bounded computation,
  published Results, and optional Effect intents. Its semantic content is
  distinguished from presentation-only Authoring Context.
- **Bounded** — each runnable capacity limit has a checked Resolved limit,
  witnesses, and a defined enforcement boundary; exceeding the ceiling fails
  the protected work. The applicable limits are specified by the operations
  and [resolved-limit rules](#resolved-limits). Exact row counts, cost, or
  duration need not be known before execution; this does not remove their
  applicable ceilings.
- **Resource** — a provider-addressable thing whose identity, kind, authority
  scope, lifecycle, and version survive any one tabular representation.
- **SourceView** — a Connector-owned, versioned typed observation contract over
  a Resource or resource extent.
- **Carrier** — a logical typed value on which the algebra computes: a relation,
  graph, vector set, or event stream ([Carriers](#carriers)).
- **ModelTask** — a versioned contract for bounded structured model acquisition
  ([Model acquisition: `infer`](#infer)).
- **Effect** — explicit intent to change external state.
- **Effect Set** — the unordered finite set of Effects declared by one stage and
  materialized from its Stage Invocation. Set and member semantics are defined in
  [Effect declarations](#effects).
- **Stage Definition** — a stable local stage ID and canonical local semantics,
  included in the Program's ordered stage descriptors without hashing its parent.
- **Unit Definition** — the common Run Graph local definition of an extracted
  stage: its stable Program-ID/node-ID namespace, Stage Definition, used parameter
  declarations and incoming producer/import/freshness/gate declarations. It never
  includes the enclosing Program revision or unrelated stages; see
  [Local approval dependencies](#local-approval).
- **Program checked template** — all stages checked with typed future ports;
  it is not a collection of fabricated concrete Stage Invocations.
- **Stage Invocation** — the semantic identity of one captured stage computation,
  including its adopted numeric and model observations and imported receipts.
- **Program Run** — the common Run Graph execution of a staged Program, retaining
  its logical request, immutable values, pins and recovery history; not a second
  orchestration state machine.
- **Author guard** — an optional author-declared upper limit that fails
  protected work when its measured scope exceeds the limit; it does not select
  the first N items ([Author guards, resolved limits, and Plan facts](#resolved-limits)).
- **Program Definition** — the authority-bearing identity combining the
  Program's authored `id` and canonical semantics, identified by
  `program_definition_cid` ([Canonical identities](#canonical-identities)).
- **Authoring Context** — the nonsemantic metadata sidecar associated with a
  Program Definition and displayed alongside its checked meaning ([Authoring Context](#authoring-context)).
- **Resolved limit** — the checked effective ceiling combining available
  bounds and guards, with their provenance and enforcement boundary ([Author guards, resolved limits, and Plan facts](#resolved-limits)).
- **Executable Plan** — the closed checked envelope of validated AoA Fragments,
  typed barriers, and their execution constraints and evidence ([AoA fragments and algebra lowering](#algebra-lowering)).

<a id="aoa-foundation"></a>

### Common AoA foundation

<!-- requirement-block: aoa-foundation.a-conforming-actql-0-1-compiler-must-report-the-actql-aoa-contract-cid-published aoa-foundation.it-must-not-silently-substitute-a-newer-aoa-contract aoa-foundation.every-frozen-conformance-report-must-include-the-exact-value-it -->
ActQL 0.1 normatively pins the AoA Kernel law-manifest identity, AoA Pipeline
IR version, Pipeline law-manifest identity, the reference executable
operation-registry identity, the complete target-module contract and its
required AoA registry additions, and law
`aoa.pipeline.effect-plan.terminal-boundary.v0.1`. These semantic references
form the machine-readable `actql-aoa-contract/0.1` artifact, identified by
`ACTQL_AOA_CONTRACT_CID`.
A conforming ActQL 0.1 compiler MUST report the `ACTQL_AOA_CONTRACT_CID`
published by its frozen 0.1 conformance manifest. It MUST NOT silently
substitute a newer AoA contract. Every frozen conformance report MUST include
the exact value it executed.

Package names, registry versions, and source commits are informative reference
implementation bindings only. They do not constrain an independent conforming
implementation that supplies the same normative semantic identities.

The semantic contracts imported by this document are explicitly pinned in
[Machine contracts](#machine-contracts). The family-wide
[contract index](conformance.md#contract-index) is informative navigation, not
an import of every listed protocol. An implementation's internal language, data
structures, and compiler pass names do not replace those shared contracts.

<a id="language-boundaries"></a>

### Language boundaries

<!-- requirement-block: language-boundaries.adding-a-contract-cid-around-opaque-code-does-not-make -->
ActQL has no UDF, lambda, custom reducer, user-defined operator registry,
inline JavaScript/Python, arbitrary WASM, runtime macro, or `custom_compute`
escape hatch. Adding a contract CID around opaque code does not make its
purity, bounds, ordering, pushdown, or replay semantics inspectable and MUST
NOT be treated as an ActQL operation.

<!-- requirement-block: language-boundaries.unsupported-semantics-must-fail-during-check-with-a-stable-error language-boundaries.the-compiler-must-not -->
Semantics outside ActQL 0.1 or the checker's claimed profiles MUST fail during
check with a stable error code. The
compiler MUST NOT:

- invent an operation;
- silently drop an input or field;
- change exact computation to approximate computation;
- convert event time to processing time;
- convert one join kind to another;
- return an empty result as a substitute for unsupported behavior.

ActQL 0.1 additionally rejects unbounded watch execution, continuous streams,
interactive/duplex sessions, arbitrary binary algebra, raw SQL or
provider-specific query languages, raw or uncontracted HTTP, ANN as pure VecA,
implicit Carrier conversion, cross-provider transactions, Saga orchestration,
and natural-language interpretation. Effect composition and its
orchestration boundaries are defined in [Effect declarations](#effects). A provider session or long-running
operation may be represented as a Resource, bounded incoming observations as
events, and outgoing work as a typed command, but its
interactive lifecycle remains host application state.

The closed vocabulary does not include PageRank, community detection, random
walks, PCA, general graph clustering or graph isomorphism. Their addition
requires an explicit algorithm, initialization/iteration, numerical and
resource contract; they are not rejected on the premise that all such
algorithms are inherently nondeterministic. Degree distributions compose
degree with group. Arbitrary theta joins, dynamic pivot columns and generic
failure-catching remain excluded; interval_join and explicit acquisition
coverage do not introduce those broader semantics.

Run Graph and HTTP transport are companion contracts, not Program vocabulary
([Artifact and companion contract index (normative)](conformance.md#contract-index)). Proposals for future language extensions follow the separate,
informative [extension policy](../design/extension-policy.md).

<a id="source-and-program"></a>

## Source and Program structure

Source is a closed JSON-model document. [Structural grammar (normative)](#structural-grammar) defines its structural
grammar; this chapter defines representation, naming, and authoring context.

<a id="source-representation"></a>

### Source representation

ActQL source files SHOULD use the `.aql` extension for both YAML and JSON
representations. The extension identifies the language, not the representation.

<!-- requirement-block: source-representation.yaml-input-must-be-restricted-to-the-json-data-model -->
ActQL source MAY be encoded as YAML or JSON. YAML input MUST be restricted to
the JSON data model:

- object with string keys;
- array;
- string;
- finite number;
- boolean;
- null.

<!-- requirement-block: source-representation.yaml-tags-anchors-aliases-merge-keys-executable-types-non-string-mapping -->
YAML tags, anchors, aliases, merge keys, executable types, non-string mapping
keys, non-finite numbers, duplicate keys, and implementation-specific scalar
types MUST be rejected.

<!-- requirement-block: source-representation.source-text-encoding-must-be-utf-8 source-representation.object-key-order-must-not-affect-parsing-lowering-or-logical source-representation.duplicate-object-keys-must-be-rejected-before-validation document-structure.product-c3aeab8b2f74 document-structure.product-2cde8f5dea2e -->
Source text encoding MUST be UTF-8. Object key order MUST NOT affect parsing,
lowering, or logical identity. Array
order is semantic. Duplicate object keys MUST be rejected before validation.

The `actql-source-decoding/0.1` profile uses [YAML 1.2.2 Core
scalar resolution](https://yaml.org/spec/1.2.2/#103-core-schema), restricted as
above, or JSON syntax. Exactly one non-empty object document is required. A
single leading UTF-8 BOM is permitted and is not a value; additional documents
and invalid UTF-8 are rejected. Numeric tokens decode to binary64 using
round-to-nearest, ties-to-even; overflow and negative zero are rejected.
Thus YAML `yes`, `on`, and `2026-09-06` are strings, `01` is number 1, and
`1e3` is number 1000. JSON does not admit `01` as a number token.

Source decoding, including builder-provided JSON-model values, normalizes
strings and keys under the AoA Kernel law: NFC, then CRLF and lone CR to LF.
This includes line breaks inside string values, not just file layout.
Colliding keys after normalization are rejected. Semantic checking consumes
that canonical model; admission of a purportedly canonical machine artifact
rejects noncanonical values rather than repairing its signed or hashed bytes.

<a id="document-structure"></a>

### Document structure

Complete Programs use the stage structure shown below and in the
[stage scenarios](../../spec/product-decisions/SCENARIOS.md).
Unwrapped pipeline snippets in operation sections describe stage-local bodies.

The language version is `actql/0.1`; the pinned Grammar identity identifies
the exact grammar. The checker MUST reject root `inputs`, `from`, `steps` or
`effects` as invalid top-level members. A missing `stages` fails required-member
checking. The compiler MUST NOT invent a stage or execute an implicit repair.

```yaml
version: actql/0.1
id: orders.shipped_recent
stages:
  - id: main
    inputs:
      orders:
        carrier: relation
        schema:
          id:
            type: string
            nullable: false
          status:
            type: string
            nullable: false
          created_at:
            type: timestamp
            nullable: false
        primary_key:
          - id
    from: orders
    steps:
      - filter: status = 'shipped'
      - select:
          - id
          - status
          - created_at
      - sort:
          - created_at: desc
          - id: asc
      - take: 100
        as: recent_shipments
    results:
      main:
        from: recent_shipments
        fields:
          - id
          - status
          - created_at
        order_by:
          - created_at: desc
          - id: asc
results:
  main:
    from:
      stage: main
      result: main
```

[Structural grammar (normative)](#structural-grammar) defines the closed top-level shape. The following table is an
informative summary, not a second grammar:

<!-- informative-table: top-level-summary -->

| Key | Required | Meaning |
| --- | --- | --- |
| `version` | yes | exactly `actql/0.1` |
| `id` | yes | stable author-chosen program identifier |
| `meta` | no | non-executable authoring metadata |
| `params` | no | closed typed runtime value declarations |
| `bindings` | no | host-bound opaque invocation value declarations |
| `stages` | yes | nonempty finite ordered array of stage definitions |
| `results` | yes | explicit exports of closed Stage Results |

<!-- requirement-block: document-structure.unknown-top-level-keys-must-be-rejected document-structure.id-must-be-a-non-empty-string stages.product-ab871e85f75f stages.product-c747718d48e2 stages.product-504c1999559c -->
Unknown top-level keys MUST be rejected. `id` MUST be a non-empty string. It is
an authority-bearing definition namespace, not presentation-only provenance
and not an AoA step reference. Changing `id` intentionally changes Program
Definition, Invocation, Effect Preview, approval, and idempotency identities,
while leaving `program_semantics_cid` unchanged.

`meta` is non-executable Authoring Context. Its syntax, identity, and
review semantics are defined in [Authoring Context](#authoring-context).

<a id="stages"></a>

### Linear stages

Stages are a source and compilation surface, not a second orchestration
runtime. They lower to the common finite Run Graph contract. Every Program,
including a single-stage Program, uses the explicit `stages` array.

A Program has one nonempty finite `stages` array. Each stage has a unique
nonempty `id`, `inputs`, `steps`, nonempty `results`, optional `from`, `effects`
and `meta`. Root `params` and `bindings` are declared once. Dataflow, Result and
Effect names are stage-local. The root `results` map contains only exports
`{from: {stage: StageId, result: ResultName}}`; it performs no computation or
projection. A stage may contain a pure dataflow DAG, but the stage list is linear.

All stages MUST be checked before Program execution, including future receipt
schemas, references, contracts, profiles and bounds. A future producer supplies
a typed unbound port, not a fabricated value or Invocation CID. Missing caller
values yield `needs_bindings`; a checked Stage Plan awaiting its predecessor is
`pending_predecessor`, not missing caller input. Concrete Stage Plans bind every
used import and effective parameter before admission; Stage Invocation identity
is completed only after its required observations have been captured.

Stage inputs additionally accept `{result: {stage, result}}` and
`{receipt: {stage, effect}}`. They import an earlier Stage Result or the typed
success view of an earlier Effect receipt. Self/forward references, temporary
`as` imports, cycles and cross-stage implicit current are rejected. The ordinary
input/`as`/multi-output namespace and sole-materialized-input completion apply
within each stage. Imports never trigger a provider read. Zero-row imports
retain their checked schema. Root exports retain the selected Stage Result's
schema, order and policy; re-projection belongs in a stage.

Stage order MUST be preserved even without data dependencies. Fresh SourceView
reads occur only after that stage activates, never before an earlier Effect.
Static contract resolution is not a business read. Within a stage, Effects are
an unordered `attempt_all` set; member rows default to `halt`. No member consumes
an outcome of its own stage. Later stages may consume explicitly imported
receipts or perform fresh reads. Arbitrary workflow branching, loops, recursion,
dynamic stage creation and implicit compensation are not admitted; pure `if`
and CASE expressions and contract-bounded retry/poll remain distinct.

Only a noninitial stage accepts `after: completed|accepted`; omission normalizes
to `completed`. It refers to the immediate predecessor, not a selected DAG
edge. Activation requires both predecessor success at that level and availability
of every import. `accepted` requires every member applied or validly accepted;
it never permits failure or unknown. `completed` additionally requires terminal
success of the necessary asynchronous operations. A completion-only file Ref
still waits for completion under `after: accepted`. Missing finite completion
capability is unsupported at check, not an implicitly nullable import.

Any failed or partially applied stage MUST prevent normal downstream activation.
An unknown outcome waits for reconciliation. A 99/100 success does not silently
advance 99 items into the next stage. A cancelled checkpoint does not resume.
Successful stages/items are retained, not rolled back or resent on recovery.
Independent per-item progression requires explicitly separate Program Runs;
it is not a transparent optimization of the stage barrier. Cleanup, compensation
and failure notifications are separate explicit recovery Programs.

Every local Stage Result is an execution root. Delivery selection cannot skip a
stage, Result or Effect. Local artifacts can survive later failure for authorized
inspection. A complete graph output index requires every explicit export and
truthful flow evidence; complete export coverage is not flow or business success.

Program, stage and execution identities follow the canonical envelopes below.
Profile support is checked independently of source validity.

<a id="pipeline-references"></a>

### Pipeline names and references

<!-- requirement-block: pipeline-references.each-non-empty-step-object-must-contain-exactly-one-operation-key -->
`steps` is an ordered array and MAY be empty. `steps: []` is the identity
pipeline over the selected input; Result ordering and projection still lower
to AoA steps when declared. Each step object MUST contain exactly one operation
key plus OPTIONAL `from`, `as`, and `meta` keys, subject to the generator and
multi-output exceptions below. An empty step object is invalid.

```yaml
- filter: "status = 'open'"
  from: opportunities
  as: open_opportunities
```

Here and in operation snippets, an input/step/Result name is local to the
enclosing stage. Root Program Results use only the export form in Stages.

For an ordinary consuming step, if `from` is omitted it consumes the current
step result. The first
step consumes the stage-level `from`. If the stage has exactly one input, the
stage-level `from` MAY be omitted and that input is selected deterministically.
For these selection rules, count only materialized inputs, not search-template
bindings classified under Inputs and external contracts. A template name is
not a valid current Carrier, even when it is the only declared input name.

<!-- requirement-block: pipeline-references.if-more-than-one-input-exists-and-top-level-from-is pipeline-references.a-compiler-must-not-select-an-input-by-declaration-order -->
If more than one input exists and stage-level `from` is omitted, an ordinary
consuming step before any explicit current selection MUST be rejected.
A compiler MUST NOT select an input by declaration order.

Generators `values`, `time_series`, `calendar_series` and `mean_graphs` reject
step-level `from`, require `as`, and set the current result to their output.
They consume only the explicitly named additional inputs, if any. Thus an
empty inputs map is legal when every dataflow root is generated. Stage-level
`from` is absent with zero inputs. With multiple inputs, a generator or an
explicit step `from` can establish the current result without a stage-level `from`.
`search_candidates` instead binds the two names in its outputs object,
rejects `as`, and leaves the current result unchanged. References to these
names have the same uniqueness, scope and no-forward-reference rules as as.
An authored dataflow binding is an input name, a single-output step's `as`,
or an explicitly named multi-output port. Search preserves the current value
from before the step, even when its query input uses an explicit `from`.
If current was unset it remains unset. Both output names are registered
together; neither output order nor explicit query selection updates current.

<!-- requirement-block: pipeline-references.input-names-and-as-names-must-be-non-empty-strings pipeline-references.input-names-and-as-names-share-one-dataflow-namespace-and -->
`as` binds a dataflow name for later reuse. All authored dataflow names MUST be
non-empty strings. Inputs, `as` names and explicit multi-output names share
one dataflow namespace and MUST be unique within it. Result names form a
separate publication namespace: `from: name` resolves in the dataflow
namespace, while `from: {result: name}` resolves in the publication namespace.
A Result MAY therefore reuse a dataflow name. Authors SHOULD NOT reuse one,
because a review reader would see the same token denote two objects. Authors
SHOULD use `as` for branches, later reuse, or Result publication; generated names are used for
ordinary linear steps.

Name resolution has the following closed scopes:

<!-- requirement-block: pipeline-references.position-available-names-top-level-from -->
| Position | Available names |
| --- | --- |
| Top-level `from` | Declared materialized inputs only; no search templates |
| Step `from` and additional Carrier inputs | Materialized inputs and preceding authored Carrier bindings; search.source alone accepts a template binding |
| Result `from` | All authored Carrier bindings in the completed pipeline; no templates |
| Effect `from` | `{result: name}` in the publication namespace only |

<!-- requirement-block: pipeline-references.forward-references-self-references-cycles-duplicate-bindings-and-unavailable-names-must -->
Forward references, self-references, cycles, duplicate bindings, and unavailable
names MUST fail during check. Compiler-generated names are not author-visible bindings.

<!-- requirement-block: pipeline-references.an-unavailable-or-carrier-incompatible-name-must-fail-during-check -->
Join and other multi-input operations name their additional inputs inside the
operation. An unavailable or Carrier-incompatible name MUST fail during check.

<a id="field-paths"></a>

### Field names and nested paths

<!-- requirement-block: field-paths.authored-schema-fields-must-not-contain-equal-cid-or field-paths.a-compiler-must-not-reinterpret-a-user-field-as-join -->
An `AuthoredFieldName` is a flat NFC string containing at least one
non-whitespace character. This rule applies to relation/graph/event/vector
fields and recursively to object properties.
Here whitespace is the union of ECMAScript 2025
[WhiteSpace and LineTerminator](https://tc39.es/ecma262/2025/multipage/ecmascript-language-lexical-grammar.html#sec-white-space):
U+0009–U+000D, U+0020, U+00A0, U+1680, U+2000–U+200A, U+2028,
U+2029, U+202F, U+205F, U+3000, and U+FEFF.
Authored schema fields MUST NOT contain `.`, equal `__cid`, or begin with the
reserved `__actql_` prefix. Generated semantic fields such as `edge_id`,
`window_start_ms`, `session_id`, and score/identity restorations are checked
for collision before lowering. A compiler MUST NOT reinterpret a user field as
join provenance or an internal carrier field.

<!-- requirement-block: field-paths.line-breaks-in-field-names -->
Implementations MUST permit line breaks within field names; source NFC/LF normalization and quoted or
escaped representations apply as for other strings.

`GeneratedFieldName` denotes a field introduced by a specified operation;
it is not permission for authors to declare reserved internal fields.
`ProvenanceQualifiedFieldReference` is the explicit `left.name` or `right.name`
reference to a join operand ([join](#join)), not an authored field. Subsequent
property access is a distinct expression node ([Typed access](#typed-access)).
A raw qualified join output requires a flat projection before another join;
recursive join provenance is not inferred from a chain of dots.

A flat field name may hold a closed nested `object` or `array` value. Nested
values do not create dotted field names. Typed expression access is specified
in [Typed access](#typed-access); `json_pick` remains the explicit relational form:

```yaml
- json_pick:
    column: payload
    path: [customer, id]
    output: customer_id
```

> **Note (informative):** `customer.id` selects property `id` of field `customer`;
> it cannot name a flat field containing a dot.

<!-- requirement-block: field-paths.before-actql-checking-a-connector-adapter-must-map-every-provider-specific -->
Before ActQL checking, a Connector adapter MUST map every provider-specific
source-field selector into a declared flat canonical ActQL field name. This
rule governs field names, not value shape: a declared field may still contain
a closed nested value.

<a id="authoring-context"></a>

### Authoring Context

<!-- requirement-block: authoring-context.it-must-not-appear-inside-expressions-predicates-value-contracts-or -->
`meta` provides author-supplied annotations for presentation and review. It
MAY appear on the Program, a Stage, an Input (including a Result/receipt import),
a Parameter or Binding declaration, a Step,
a Result, or an Effect. It MUST NOT appear inside expressions, predicates,
value contracts, or operation bodies. Short-form inputs use their object form
to carry annotations.

<!-- requirement-block: authoring-context.top-level-keys-beginning-with-actql-are-reserved-and-must-be authoring-context.its-complete-content-uses-the-aoa-kernel-canonical-json-contract -->
`Meta` is a non-empty JSON object with service-defined content. Top-level keys
beginning with `actql_` are reserved and MUST be rejected in 0.1. Its complete
content uses the AoA Kernel canonical JSON contract ([Canonical identities](#canonical-identities)); non-finite numbers,
negative zero, and unpaired UTF-16 surrogates MUST be rejected.

<!-- requirement-block: authoring-context.it-must-not-change-computation-authority-egress-bounds-optimization-effect authoring-context.it-must-not-be-copied-into-a-model-request-connector authoring-context.except-for-validating-metadata-itself-hosts-must-not-use-metadata authoring-context.a-host-may-impose-metadata-capacity-or-content-restrictions-but -->
Metadata is nonsemantic authoring context. It MUST NOT change computation,
authority, egress, bounds, optimization, Effect Preview identity, or semantic
Program, Executable Plan, Invocation, or idempotency identity. It MUST NOT be
copied into a model request, Connector request, Effect payload, or provider prompt.
Except for validating metadata itself, Hosts MUST NOT use metadata as a
structured input to execution admission or policy, permissions, approval routing,
Checkpoint requirements, or Resolution validation. A Host MAY impose metadata
capacity or content restrictions, but MUST reject violations at intake with a
stable diagnostic code rather than silently truncating or rewriting metadata.

<!-- requirement-block: authoring-context.an-effect-review-projection-must-bind-both-the-semantic-effect-preview-cid authoring-context.metadata-must-be-identified-as-author-supplied-and-separated-from-verified authoring-context.natural-language-metadata-must-not-satisfy-a-missing-structured-semantic-choice -->
An Effect review projection MUST bind both the semantic `effect_preview_cid`
and the exact `authoring_context_cid` presented to the reviewer. Metadata MUST
be identified as author-supplied and separated from verified authority and
approval status. A projection MAY present a CID reference to the canonical
metadata instead of rendering its contents; the reference remains subject to
the applicable access and redaction policy. Changing only metadata therefore
does not rebuild the Effect Preview, but it does require a
new review projection and approval attestation. Natural-language metadata MUST
NOT satisfy a missing structured semantic choice.

<a id="values-and-types"></a>

## Carriers, values, and types

Carriers describe collections on which the algebra operates. Field contracts
describe the values carried by those collections; they are shared by local
schemas, external Contracts, expressions, and Results.

<a id="carriers"></a>

### Carriers

The graph structural contract has the closed canonical body
`{version: "actql-graph-contract/0.1", node_id_contract, node_properties,
edge_properties, edge_labels, identity_law_cid, value_law_cid}`.
Node_id_contract is the complete checked semantic ID value contract;
node_properties and edge_properties are complete checked property-contract
maps, including nullability and extents. Edge_labels is null when no closed
label domain is proven, otherwise the duplicate-free canonical sorted label
list. Identity_law_cid and value_law_cid resolve the exact graph identity and
typed value equality laws in the admitted AoA contract. Edge identity is the
fixed (source ID, target ID, label) tuple, using node_id_contract for endpoints.
`graph_contract_cid` is the ordinary ActQL CID of exactly this body, without a
self-CID member. Property-map enumeration, source aliases, observations, graph
contents, row counts, policy and provider locators are not contract members.
Diff resolves one common contract using recursive common-type rules over
compatible input domains; both snapshots are admitted under it. Apply verifies
the base against that pinned contract. A different contract is not inferred
from the Delta's payload or from a matching self-CID.

<!-- requirement-block: carriers.graph-law-body -->
For the 0.1 contract, both graph law CID members MUST equal
`sga_identity_law_manifest_cid` in the admitted ActQL AoA contract. That pin
resolves `aoa-sga-identity-laws/0.1`, which contains the semantic identity and
typed value equality laws together. Computing a structural contract CID proves
neither snapshot admission nor base/target content identity.

ActQL source uses four public Carrier names:

```text
relation
graph
vectors
events
```

<!-- requirement-block: carriers.a-compiler-must-not-reinterpret-a-value-as-another-carrier -->
These map directly to the AoA sorts `relation`, `graph`, `vector_set`, and
`event_stream`. Every materialized input and every step result has exactly one
ActQL Carrier. Conversions are legal only through the deterministic semantic
expansions defined in this specification. A compiler MUST NOT reinterpret a
value as another Carrier.

Relations contain ordered rows with string-named fields. Graph, event-stream,
and vector carrier representations are AoA-defined; ActQL restores authored
semantic identity field names when returning to relations, except operations
with fixed result roles such as `nearest`'s `query_id` / `candidate_id` ([Vector operations (VecA)](#vector-operations)).

Physical enumerability, a proven stable total order, and candidate-key evidence
are different properties. A **candidate key** is a non-null field tuple proven
unique; candidate keys form a set of independent witnesses. An **ordering
witness** proves the logical row sequence used by order-sensitive operations.
Provider arrival order alone proves neither. A **complete schema** supplies
every field name and recursive value contract; knowing some names is not completeness.

<a id="value-contracts"></a>

### Closed value contracts

The closed value type names are `string`, `number`, `decimal`, `boolean`, `timestamp`,
`date`, `json`, `object`, `array`, `vector`, `resource_ref`, and `artifact_ref`.
The primitive value domains are:

<!-- requirement-block: value-contracts.type-value-domain-string-unicode -->
| Type | Value domain |
| --- | --- |
| `string` | Unicode strings in the pinned Unicode 16.0 NFC form. |
| `number` | Finite IEEE-754 binary64; negative zero is invalid in canonical source. |
| `boolean` | `true` or `false`. |
| `decimal` | Precision, scale, and exact base-10 coefficient ([Exact decimal values](#decimal-values)). |
| `timestamp` | Canonical UTC `YYYY-MM-DDTHH:mm:ss.sssZ`; offsets and leap-second spellings are invalid. |
| `date` | Canonical `YYYY-MM-DD`; distinct from a timestamp. |

`json` provides no recursive static field evidence. `object` and `array`
carry the recursive contracts described below; `vector` carries fixed
dimensions and the 0.1 f32 element law. Opaque reference values are defined in
[Opaque reference values](#opaque-references). Arithmetic, conversion, and null propagation are specified in [Expressions and predicates](#expressions).

<!-- requirement-block: value-contracts.every-field-contract-including-an-array-element-contract-or-object value-contracts.array-contracts-must-declare-items value-contracts.object-contracts-must-declare-fields value-contracts.for-json-pick-on-a-typed-object-a-referenced-path-must value-contracts.when-schema-is-present-it-is-complete-runtime-rows-must value-contracts.when-schema-is-present-it-is-complete-runtime-rows-must.second -->
`resource_ref` and `artifact_ref` additionally declare `resource_kind` or optional `media_type`
and require issuer evidence as specified in [Opaque reference values](#opaque-references). Every field contract, including
an array element contract or object property contract, MUST declare `nullable`.
`array` contracts MUST declare `items`; `object` contracts MUST declare
`fields`. These members contain recursive field contracts and are legal only
for their respective types. Values without declared internal structure use
`json`. For `json_pick` on a typed object, a referenced path MUST be
present in the complete recursive contract. When `schema` is
present, it is complete: runtime rows MUST have exactly that field set and
every value, nested array element, and declared object property MUST satisfy
the declared type/nullability. `nullable: true` permits a present value to be
`null`; it does not make the field or property optional.

<!-- requirement-block: value-contracts.empty-object-contracts -->
Both authored and checked object contracts MUST permit `fields: {}`. This closed
contract admits only the empty object, plus `null` when `nullable: true`.

An empty array retains its declared item contract; its contents do not infer
`json` or change nullability. `nest` ([nest](#nest)) derives that contract from the
selected child schema, with a non-null array and non-null object items.

The author-facing field contract contains only semantic choices. An authored
object contract omits `additional_properties`; the compiler inserts the sole
0.1 machine meaning `additional_properties: false`. An authored vector
contract declares positive `dimensions` and omits `element_type`; the compiler
inserts the sole 0.1 machine meaning `element_type: f32`. These fixed machine
fields appear in checked Plan and protocol contracts but are not authoring
vocabulary.

The author and checked contracts are separate closed grammars. Every row below
also has `type` and required `nullable`; `?` marks an optional member.

<!-- requirement-block: value-contracts.type-other-author-members-checked-expansion-or -->
| Type | Other author members | Checked expansion or evidence |
| --- | --- | --- |
| `string` | none | optional `min_length`, `max_codepoints`, `max_utf8_bytes` from admitted evidence |
| `number`, `boolean`, `timestamp`, `date`, `json` | none | unchanged |
| `decimal` | `precision`, `scale` | unchanged; [Exact decimal values](#decimal-values) ranges |
| `array` | `items: AuthorValueContract`, `max_items?` | recursive checked `items`; bound unchanged |
| `object` | `fields: {AuthoredFieldName: AuthorValueContract}` | recursive checked fields; `additional_properties: false` |
| `vector` | `dimensions` | `element_type: f32` |
| `resource_ref` | `resource_kind` | unchanged |
| `artifact_ref` | `media_type?` | unchanged |

`AuthorValueContract` is exactly the author column; `CheckedValueContract`
is its recursive expansion plus only the checked members listed above.
Unknown or wrong-type members are rejected. Array `max_items` is a
non-negative safe integer, including zero; it constrains admitted values,
unlike an operation guard over measured work ([Author guards, resolved limits, and Plan facts](#resolved-limits)). Checked string extents
are non-negative safe integers and do not become author syntax.
`min_length` and `max_codepoints` count Unicode scalar values after canonical
string normalization; `max_utf8_bytes` counts the normalized UTF-8 bytes.
Neither counts grapheme clusters or UTF-16 code units.

Type equality and compatibility use the following common relations:

- `TypeEqual(A,B)` compares complete canonical checked contracts recursively,
  including nullability, bounds, decimal precision/scale, vector dimensions,
  reference kind/media type, and object field sets. Object key order is irrelevant.
- `Assignable(A,B)` means every value permitted by A satisfies B. Non-null may
  flow to nullable, but not conversely. Base types match without coercion;
  decimal precision/scale, vector dimensions, and ResourceKind must match.
  Objects have exactly the same field set with recursively assignable values;
  arrays have assignable items. An actual upper bound cannot exceed an expected
  bound, and an actual lower bound cannot be smaller. Missing bounds prove no
  restriction. An unspecified expected Artifact media type admits any media
  type; a specified type requires that exact type to be proven.
- `JoinNullability(A,B)` requires the same recursive base structure and the
  exact decimal/vector/ResourceKind parameters. It takes nullable OR at each
  position and the least restrictive common value bounds. Different Artifact
  media types join to an unspecified media type. Other base-type differences
  have no join. `json` is not an implicit supertype of typed objects or references.

`append`, conditional result branches, `coalesce`, and array construction use
this common join. SourceView request and Command argument checking use
assignability. A literal null acquires a nullable form of the other branch's
known type; all-null expressions alone provide no non-null type evidence.
An explicit cast of null supplies its target type with `nullable: true`.
An immediate fixed signature also supplies a literal NULL's type when its
argument domain is unique: `len(NULL)` uses nullable string, `concat(NULL,NULL)`
uses string arguments, and `NULL IS TRUE` and `CASE WHEN NULL THEN 1 ELSE 2 END`
use a nullable boolean condition. An overloaded argument without a unique
domain supplies no type; two untyped NULL operands of `IS DISTINCT FROM`
still require independent type evidence.

<!-- requirement-block: value-contracts.decimal-output-target-is-not-input-evidence -->
For `quantize` and `decimal_divide`, implementations MUST NOT use the output
precision and scale to supply an input type: the decimal input domain has no
unique precision/scale, and the divisor domain also permits `number`.
Bare literal NULL operands remain
unresolved; an explicit cast such as `CAST(NULL AS DECIMAL(8,2))` supplies
the missing input type. Already-typed nullable operands still propagate null.

An empty array obtains its item type from an explicit `empty_array.items`
contract or the unique common item type of independently typed peers in an
`if`/`case`, `coalesce`, or array constructor. A schema-typed array with
`max_items: 0` and an explicitly typed empty array both supply evidence.
Resolution is recursive, ignores only untyped NULL and untyped `[]` as
type evidence, and fails if no unique type remains.
It never searches arbitrary downstream consumers. The empty array itself is
non-null with `max_items: 0`; peer nullability is not copied to it.
An unresolved field may acquire its type from one explicitly mapped nullable
ModelTask input. Outside these explicit type, local signature and peer rules, no other consumer
context supplies an unresolved null type in 0.1; absence of a unique type fails
with `ACTQL_E_NULL_TYPE_UNRESOLVED`.
An operation may impose stricter preconditions, but not a different coercion.
Expression-specific nullability, such as `coalesce` being non-null when an
argument is proven non-null, is refined by [Expressions and predicates](#expressions) after this structural join.

`KeyComparable(A,B)` compares non-null value domains, not entire contracts.
Nullability and value-size bounds may differ; each input still satisfies its
own contract, and the operation's null policy governs null keys. Base types
must match without coercion. Decimal precision/scale may differ: decimal keys
compare by exact numeric value under [Exact decimal values](#decimal-values).
ResourceKind must match; ArtifactRef media restrictions do not change reference equality.
Scalar and reference domains are comparable under these rules; object, array,
json, and vector keys are not admitted. Join-key compatibility uses this
relation, not `TypeEqual`.

For `json_pick` through a closed object, result nullability is the OR of the
leaf's nullability and every traversed parent's nullability. A null parent
returns null; an absent declared property violates the input contract.
Parameter declarations reuse the recursive value domains with the parameter-specific
default and nullability rules in [Parameters and binding](#parameters).

`date` and `timestamp` use the proleptic Gregorian calendar with years
0000 through 9999 and valid month/day combinations. Timestamps require hours
00–23, minutes/seconds 00–59, and exactly three fractional digits in UTC.
Leap seconds and out-of-range dates fail. These value rules apply without the
optional text-time profile, which only adds transformations over the domain.

<a id="decimal-values"></a>

### Exact decimal values

Decimal follows the AoA RelA exact-decimal contract. The closed type is
`{type: decimal, precision: P, scale: S, nullable: boolean}`,
with integer `1 <= P <= 38` and `0 <= S <= P`. Its exact value is
`coefficient × 10^(-S)`. The machine coefficient is a base-10 integer string
matching `0|-?[1-9][0-9]*`, with at most P digits excluding the sign; leading
zeros, a leading `+`, and negative zero are invalid.

Typed value identity is domain-separated from string identity and includes
the decimal contract version, P, S, and coefficient. Each declared type has
exactly one canonical spelling per value. Thus `19.90` at scale 2 and
`19.900` at scale 3 compare numerically equal but have different types and
typed value identities. Arithmetic and conversion rules are defined in [Decimal expressions](#decimal-expressions).

Decimal comparison, including join-key equality, compares the exact values
`coefficient × 10^(-S)` without binary64 conversion or rounding. Equivalently,
compare integer coefficients aligned to the greater scale; this comparison
introduces no precision-38 intermediate-value restriction. Different precision
or scale does not prevent comparison or an equal-key match. Hash-based joins
use the same numeric equality, not typed value CID equality. This does not
change either operand's type, canonical spelling, or typed value identity;
changing a stored decimal's precision/scale still requires explicit conversion.

Canonical JSON, JSONL, and CSV serialization uses fixed-scale decimal text:
exactly S fractional digits, no exponent or leading `+`, and no redundant
integer leading zeros. When S is zero, the decimal point is omitted. JSON and
JSONL encode this text as a string; declared decimal JSON inputs use that same
canonical spelling. A coefficient outside the declared precision fails rather
than being rounded or truncated.

<a id="opaque-references"></a>

### Opaque reference values

Two opaque scalar types cross carrier boundaries:

- `resource_ref<K>` is a projected Resource identity. It contains a provider
  namespace plus content identities for provider identity, authority scope,
  Resource boundary, and the complete reference. It contains no native provider
  locator, view, connector version, observation time, etag, or schema evidence.
- `artifact_ref<Mime>` identifies captured bytes and carries content CID, media
  type, bounded byte count/range, storage scope, truncation, sensitivity,
  capture authority, and optional source ResourceRef/version evidence.

ResourceRef equality is equality of `identity_cid`, scoped by provider
namespace, ResourceKind, provider identity, authority scope, and boundary.
Connection names and authentication revisions do not determine that identity.
ArtifactRef equality is equality of `artifact_ref_cid`, including store, scope,
retention, and policy; equal `content_cid` values establish byte identity only.
SourceView and serialization output contracts may expose `content_cid` as a
separate field.

<!-- requirement-block: opaque-references.reference-equality-must-be-consistent-across-predicates-joins-grouping-distinct -->
Reference equality MUST be consistent across predicates, joins, grouping,
distinct, and uniqueness checks, independently of acquisition or in-memory
object identity. Within each reference type, `eq`/`neq` use that equality.
References are scalar keys for equality-based operations. For specification-defined
canonical identity ordering and deterministic compiler completion, use AoA code-unit
order of `identity_cid` for ResourceRefs or `artifact_ref_cid` for ArtifactRefs.
This includes canonical group/partition enumeration and request-key ordering
where the operation already admits reference keys; it does not expand any
operation's admitted key or Carrier types. Machine-only means not
author-selectable as a reference value order, not unobservable: the resulting
canonical order remains part of observable semantics. Author-order restrictions
and their validation boundaries are defined in [Lexical and ordering rules](#ordering).

<!-- requirement-block: opaque-references.host-accepted-bindings-and-artifact-or-result-inputs-must-revalidate-issuer opaque-references.references-serialize-as-tagged-canonical-json-objects-but-their-internals -->
Only a Connector host may issue a `resource_ref`. An `artifact_ref` may be
issued only by a Connector capture or an authorized content-addressed Artifact
Store derivation. Both issuers bind typed issuer evidence; the public protocol
exports validators, not an author-accessible issuer. A reference grants no
authority. Host-accepted bindings and Artifact or Result inputs MUST revalidate
issuer evidence and current usage authorization; authored JSON alone cannot
establish a valid reference. References serialize as tagged canonical JSON
objects, but their internals MUST NOT be inspected or modified by expressions
or `json_pick`.

<!-- requirement-block: opaque-references.an-operation-requiring-a-resourceref-must-receive-it-explicitly-hidden opaque-references.an-operation-requiring-a-resourceref-must-receive-it-explicitly-hidden.second -->
An operation requiring a ResourceRef MUST receive it explicitly; hidden
execution lineage MUST NOT restore a projected-away reference or supply an
implicit write target. Mapping-based Effect selectors remain valid ([Effect declarations](#effects)).
Binary bytes and base64 are not embedded into ordinary AoA JSON values, and
image/audio-specific carriers do not exist.

<a id="ordering"></a>

### Lexical and ordering rules

`AuthorOrderable` comprises `string`, `number`, `decimal`, `boolean`,
`timestamp`, and `date`. `CanonicalOrderable` comprises those types plus
`resource_ref` and `artifact_ref`. These are specification classifications,
not source syntax. A portable order is the specified total order over non-null
values of a `CanonicalOrderable` type: numeric order for `number` and `decimal`, `false < true`
for `boolean`, chronological order for `timestamp` and `date`, the string order
below, and reference identity order ([Opaque reference values](#opaque-references)). `object`, `array`, `json`, and
`vector` have no portable order. Null placement follows the operation's rules;
null does not acquire a value order.

<!-- requirement-block: ordering.every-authored-ordering-key-ordered-comparison-operand-and-min-max-input-must -->
Every authored ordering key, ordered-comparison operand, and `min`/`max` input
MUST be `AuthorOrderable`, regardless of operation or field spelling. This
includes ranking and explicit tie-break keys, but not equality-based partition,
grouping, correlation, or uniqueness keys. Reference identity order is available
only for specification-defined canonical identity ordering and deterministic
compiler completion ([Opaque reference values](#opaque-references)).

<!-- requirement-block: ordering.statically-invalid-order-domains-must-be-rejected-during-check ordering.where-an-existing-rule-permits-deferred-type-validation-the-plan ordering.where-an-existing-rule-permits-deferred-type-validation-the-plan.second input-normalization.product-4ae6697ed1a4 -->
Statically invalid order domains MUST be rejected during check. Where an
existing rule permits deferred type validation, the Plan MUST retain the
`AuthorOrderable` obligation and the runtime input boundary MUST validate it
before evaluating the ordering operation. This rule permits no new deferral
and never authorizes reference ordering.

Every lexicographic ordering in this specification uses the AoA canonical NFC-normalized
UTF-16 code-unit order. Locale collation and Unicode code-point order are not
permitted alternatives. Connector references are non-empty UTF-8 strings whose
normalized spelling is identity-bearing. Author-facing Mapping Contract
references use the typed-qualified closed ASCII grammar in [Mapping contracts](protocols/contracts.md#mapping-contracts). They are not
inferred from the surrounding field and do not change spelling during
compilation. A compiler does not perform provider-specific case folding.
Duration tokens have lexical form
`[0-9]+(ms|s|m|h|d)`, are ASCII case-insensitive at authoring, and canonicalize
to positive safe integer milliseconds. Negative zero and non-finite numbers
are invalid before identity computation.

<a id="inputs"></a>

## Inputs and external contracts

An input referenced as `search_candidates.source` declares an acquisition
template, not a captured Relation. Check classifies that binding before input
selection: it resolves the SourceView and static request without dispatch,
and excludes it from initial capture and implicit sole-input selection.
All references to that binding are template references from search steps;
using it as top-level/step `from`, a local operation operand or Result input
fails check, including mixed template/Relation use in one Program. Multiple
search steps may reuse the template. An independent snapshot requires a
separate input binding with its own complete request and capture evidence.
Dynamic request roles are supplied only by each search step; static and dynamic
roles together match the exact request contract. Template resolution does not
grant provider access, create rows, or establish observation completeness.

Parameter and opaque binding values are declared and supplied under [Parameters and binding](#parameters);
they are distinct from the external contracts selected by an input.

The external and computational models are orthogonal:

```text
Resource -> SourceView ---------------------> Carrier
Relation -> ModelTask infer acquisition ----> Relation
Relation -> keyed SourceView join acquisition -> Relation
Relation -> Artifact serialization ---------> Relation<artifact_ref>
Relation<artifact_ref> -> typed external SourceView join -> Relation
Carrier  -> AoA algebra -> Effect Plan -> Receipt
```

Resource, SourceView, Carrier, and Effect are defined in [Terms](#terms).
SourceView, ModelTask, and Artifact serialization contracts are versioned
barrier contracts, not intermediate languages. External inference and the
acquisition selected for an external join
are not AoA operations or business-state mutation Effects. Relation
serialization is an explicit
Artifact barrier rather than a hidden output-side post-processing pass.

<a id="input-normalization"></a>

### Input duplicate normalization

Materialized relation inputs accept `duplicates: reject` or
`duplicates: {first_by_order: {order_by: [OrderKey, ...]}}`;
omission normalizes to `reject`. The array is nonempty and uses declared raw
fields and the ordinary OrderKey grammar. The bare string `first_by_order` is
invalid. First-by-order selects the first complete row
per declared primary-key tuple using an independently admitted total order.
The duplicated key itself, provider arrival order or an invented payload-CID
tie-break is not that proof. Without it checking fails; an unkeyed raw input
followed by explicit `dedupe_rows` is a separate business-selection path.

Admission MUST decode and normalize optional provider fields, then validate all
raw rows' known fields, types, nullability and non-null key components before
selection. A discarded malformed row cannot be hidden. Raw rows/bytes and
normalized rows/bytes have separate limits. Non-null uniqueness is proved only
on the selected output. Evidence binds the raw artifact, policy, order witness,
normalized artifact and excluded count. Raw capture cursor and coverage are
unchanged. An authoritative SourceView uniqueness violation remains a contract
failure, not something an author can repair with `first_by_order` or a local
schema override.

<a id="local-inputs"></a>

### Local typed inputs

A local input MAY use the short form:

```yaml
inputs:
  rows: relation
  graph: graph
  events: events
  embeddings: vectors
```

or the object form:

```yaml
inputs:
  rows:
    carrier: relation
    expected_columns: [id, status]
```

An optional inline `schema` supplies the closed field contracts defined in [Closed value contracts](#value-contracts):

```yaml
inputs:
  orders:
    carrier: relation
    schema:
      id: {type: string, nullable: false}
      amount: {type: number, nullable: true}
      occurred_at: {type: timestamp, nullable: false}
      items:
        type: array
        nullable: false
        items:
          type: object
          nullable: false
          fields:
            sku: {type: string, nullable: false}
            quantity: {type: number, nullable: false}
    primary_key: [id]
```

<!-- requirement-block: local-inputs.when-a-complete-schema-is-available-every-component-must-exist local-inputs.at-the-runtime-input-boundary-every-component-must-be-present local-inputs.at-the-runtime-input-boundary-every-component-must-be-present.second -->
`primary_key`, when present, is a non-empty field list. When a complete schema
is available, every component MUST exist in it, have a scalar or reference
type ([Opaque reference values](#opaque-references)), and declare `nullable: false`. At the runtime input boundary,
every component MUST be present, non-null, and a scalar or reference value,
and, after the explicitly admitted input duplicate normalization, the complete
tuple MUST be unique by canonical-value equality, including
when static type evidence is unavailable. Reference components use the
equality defined in [Opaque reference values](#opaque-references).

<!-- requirement-block: local-inputs.such-evidence-must-satisfy-any-explicit-input-assertions -->
The Host may supply schema evidence under [Check Environment and source evidence](protocols/contracts.md#check-environment) without an authored `schema`.
Such evidence MUST satisfy any explicit input assertions. `schema_ref` is not
an input field; unresolved descriptive labels belong in `meta` ([Authoring Context](#authoring-context)).

<!-- requirement-block: local-inputs.carrier-is-required-for-an-opaque-local-input local-inputs.expected-columns-is-optional-but-when-present-must-be-a-duplicate-free local-inputs.runtime-bindings-must-be-checked-against-it-before-computation local-inputs.a-compiler-must-not-infer-a-complete-field-set-from local-inputs.when-schema-is-also-present-every-expected-column-must-belong -->
`carrier` is REQUIRED for an opaque local input. `expected_columns` is OPTIONAL
but, when present, MUST be a duplicate-free array of non-empty field names.
Runtime bindings MUST be checked against it before computation.
It requires those columns to be present but permits additional columns and
specifies neither column order nor value types. A compiler MUST NOT infer a
complete field set from `expected_columns` alone. When `schema` is also present,
every expected column MUST belong to that schema.

<!-- requirement-block: local-inputs.an-operation-must-fail-only-when-the-proof-it-needs -->
Check reports one of three evidence levels rather than rejecting every
partially described relation: `typed` for a resolved complete schema,
`columns_only` for known column names without a complete typed schema, and `unknown` when
neither is available. Static evidence checking MUST NOT reject an operation
solely because evidence unrelated to its required proofs is absent.

This rule does not exempt language violations, authorization denials, or runtime
failures. A required proof must be established during check unless the operation's
existing rules permit a deferred validation obligation; such an obligation is
retained in the Plan and discharged at its specified runtime boundary. These
evidence levels introduce no additional permission to defer validation.

Known field names, field-set completeness, recursive type evidence,
candidate keys, and ordering witnesses are independent evidence axes.
`columns_only` may describe a subset or a complete set of names; the complete
set must have separate evidence. The three levels above summarize type
knowledge, not all five axes.

<a id="sourceviews"></a>

### Connector SourceViews

A connector input names a Host-published Connector instance (`connector`),
a Resource within it (`resource`), and an observation of that Resource
(`view`). The instance selector identifies a Catalog entry, not a Connector
implementation name or connection revision ([Resource identity contract](#resource-identity-contract)). For example, if the admitted Catalog exposes
only the `records` SourceView for `Opportunity`:

```yaml
inputs:
  opportunities:
    connector: crm/main
    resource: Opportunity
from: opportunities
steps:
  - select: [id, account_id, stage, amount]
  - filter: "stage NOT IN ('ClosedWon', 'ClosedLost')"
```

<!-- requirement-block: sourceviews.when-view-is-omitted-check-must-resolve-it-from-all sourceviews.resolution-must-not-filter-candidates-by-current-execution-permissions-request sourceviews.an-explicitly-selected-sourceview-must-match-the-full-connector-resource -->
`connector` and `resource` are required. When `view` is omitted, Check MUST
resolve it from all SourceViews for that exact pair in the admitted Catalog:
zero views is rejected as unresolved; one is completed under
`actql.source.sole-view-completion`; more than one is rejected with
`ACTQL_E_SOURCE_VIEW_AMBIGUOUS` and the candidate list. Resolution MUST NOT
filter candidates by current execution permissions, request compatibility, or
downstream expressions. An explicitly selected SourceView MUST match the full
`(connector, resource, view)` selector, including when a contract CID is pinned.
Check does not synthesize a SourceView, implicitly select `records`, or fall back
across Resources. Catalog publication is governed by [Connector Catalog and lock](protocols/contracts.md#catalog-and-lock).

<!-- requirement-block: sourceviews.concrete-resource-selector -->
SourceView resolution MUST bind the concrete Resource using its admitted output
data-policy `source_ref`, exactly `"connector://" + connector_id + "/" + resource
+ "#" + view_id`, with nonempty `resource`; `resource_kind` is a type, not that
address. This is literal string construction, not URL parsing: the known
`connector_id` prefix and `view_id` suffix delimit the Resource. Percent escapes,
slashes and fragment characters inside the Resource remain literal. Authored
selectors use their source-normalized strings exactly, with no URI-prefix
removal, slash trimming, percent decoding or case folding. Different Resources
may expose the same kind and view name.

<!-- requirement-block: sourceviews.catalog-selector-uniqueness -->
Before resolving inputs, Check MUST reject every supplied SourceView whose
policy source reference does not have that exact prefix, nonempty Resource and
suffix, and reject duplicate `(connector_id, resource, view_id)` selectors,
even across different kinds or versions and even when unused. This check follows
policy-reference admission; Catalog integrity alone does not establish Resource
selector uniqueness. Ambiguous candidate names are reported in UTF-16 order.

<!-- requirement-block: sourceviews.the-resolved-plan-must-identify-the-sourceview-and-bind-its sourceviews.a-catalog-change-requires-rechecking-against-the-new-catalog-it -->
The resolved Plan MUST identify the SourceView and bind its contract CID. A Catalog
change requires rechecking against the new Catalog; it MUST NOT retarget a
sealed Plan. Completion is recorded in the normalization journal ([Deterministic completion](#completion)), not
required as a rewrite of the authored Program.

<!-- requirement-block: sourceviews.authors-must-not-repeat-the-output-carrier -->
The SourceView contract determines acquisition semantics, read authority,
output Carrier/schema/facts, ResourceRef issuance, read modes,
checkpoint/delivery contract, and pushdown capabilities. Authors MUST NOT
repeat the output Carrier. A relation SourceView lowers directly to an AoA
relation source; SourceView resolution is not another IR.

<!-- requirement-block: sourceviews.catalog-discovery-must-expose-each-sourceview-s-name-request-contract-acquisition sourceviews.human-readable-discovery-must-present-these-facts-rather-than-names-alone sourceviews.acquisition-review-projections-must-include-the-sourceview-classification-and-contract -->
Catalog discovery MUST expose each SourceView's name, request contract, acquisition
kind, authority, observation classification, output Carrier/schema, modes,
and contract CID, including any extraction contract. Human-readable discovery
MUST present these facts rather than names alone. Authors and generators
select SourceViews from this evidence, not by inferring meaning from their names.
Acquisition review projections MUST include the SourceView classification and
contract identities reported by the Plan summary ([Diagnostic documents](protocols/contracts.md#diagnostic-documents)), subject to redaction.

`request` is validated against the resolved SourceView `request_schema`. It may
contain literals, typed scalar parameters, or an explicit `{$binding: name}`.
Opaque invocation bindings are declared separately from scalar parameters:

```yaml
bindings:
  target_file:
    type: resource_ref
    resource_kind: google_drive.file

inputs:
  file:
    connector: google_drive/main
    resource: drive_file
    view: content
    request:
      resource_ref: {$binding: target_file}
      max_bytes: 262144
      require_full: false
```

<!-- requirement-block: sourceviews.static-request-value-slots -->
Each field of an authored static `request` is one whole-value slot. An exact
singleton `{$param: name}` or `{$binding: name}` at that slot denotes the named
declaration; other slot values are literal JSON. Request decoding MUST NOT
descend into literal values to discover or substitute references. In particular,
nested parameter-shaped or binding-shaped business objects are data, and a
`literal` key does not introduce an additional request quotation operator.
The resolved request contract still determines each slot's admissible type and
whether all required static and correlation roles are covered.

<!-- requirement-block: sourceviews.bindings-must-be-used-only-inside-sourceview-requests sourceviews.a-binding-must-not-create-a-resourceref-or-artifactref sourceviews.the-host-invocation-contract-must-expose-each-declaration-name-and sourceviews.authors-must-not-inspect-that-artifact-to-discover-keys-and sourceviews.authors-must-not-inspect-that-artifact-to-discover-keys-and.second -->
The host supplies the opaque binding at invocation. Its declaration and request
position belong to Program identity; the concrete binding belongs to Invocation
identity and `resolved_request_cid` source evidence. Bindings MUST be used only
inside SourceView requests. A binding MUST NOT create a ResourceRef or ArtifactRef.
The host invocation contract MUST expose each declaration name and its
`resource_kind` or media-type constraint separately from the opaque values
artifact. Authors MUST NOT inspect that artifact to discover keys, and authoring tooling
or compiler MUST NOT guess a missing binding name.

<!-- requirement-block: sourceviews.execution-must-use-those-bound-values sourceviews.the-public-planning-result-must-redact-opaque-values-and-resolved -->
Without all declared opaque bindings, checking establishes only a template
proof. An executable Plan requires every binding, validated for presence,
kind, and request compatibility ([Parameters and binding](#parameters)). Execution MUST use those bound values.
The public planning result MUST redact opaque values and resolved requests,
reporting only declaration names, constraints, and binding status.

Ordinary SourceView requests are static: they may use literals, parameters,
and Host bindings. Data-dependent SourceView acquisition uses the checked
external-join lowering in [External SourceView joins](#external-joins), or
[search_candidates](#candidate-search) for ranked candidate retrieval. A
finite left key/query set drives one pinned SourceView access path, with
the distinct completeness requirements of each operation. Programs cannot author a general fetch/follow DAG or
row-driven acquisition loop.

<!-- requirement-block: sourceviews.a-connector-must-bind-every-declared-request-field-to-one -->
Every field declared by a complete request contract is present in the resolved
request object. `nullable: true` permits the value `null`; it does not permit
the field to be absent. A Connector MUST bind every declared request field to
one typed planning/execution consumer. Declaring a field and then ignoring it
is a contract error.

Every resolved SourceView is a canonical `actql.source_view/0.1` contract with:

```text
connector_id, connector_version, resource_kind, view_id, view_version,
acquisition {kind, authority, request_schema, modes, default_mode,
             optional correlation {request_fields, response_fields, identity, cardinality},
             optional batching},
observation {kind, optional transform},
output {carrier, schema, facts}, optional resource_identity,
pushdown {contract, operations}, contract_cid
```

For a keyed access path, `acquisition.correlation.cardinality` declares the
**response cardinality** (`zero_or_one | zero_or_many | one | one_or_many`) per
requested key. It is not an `output.facts` field or an authored join assertion.
The correlation contract also names request fields, response fields, and
response identity; [External SourceView joins](#external-joins) defines their use in external joins. Join cardinality
assertions use the distinct vocabulary and meaning in [join](#join).

<!-- requirement-block: sourceviews.request-correlation-types -->
Each SourceView's request contract MUST be a complete non-null checked object
contract, including for views without correlation. Its fields may themselves
be nullable; a nullable field still requires a value. A declared correlation
uses a `search`, `fetch` or `follow` acquisition and refers to record fields of
a Relation, Events or Vectors output. This field-based correlation grammar does
not flatten a Graph's nodes or edges into a response record. Request and response
field lists are nonempty, duplicate-free and have equal length. Positions pair
in supplied order, and every pair resolves existing fields with compatible
KeyComparable contracts. Their nullability, string extents and decimal
precision/scale need not be identical; declaration compatibility does not bypass
actual request-value constraints or the selected null-request policy.

<!-- requirement-block: sourceviews.correlation-identity-types -->
The declared response identity MUST be a nonempty ordered list of distinct
existing response fields with non-null KeyComparable contracts. It may overlap
the response key fields and need not equal an Events or Vectors intrinsic
identity role. It is an acquisition response identity, not a replacement for
that Carrier's semantic identity. Validation retains all supplied tuple orders
and exact contract ownership without coercion. Non-null types alone do not prove
identity uniqueness, response cardinality, completeness, ordering or successful
request execution. The existing acquisition obligations still enforce those
claims on actual responses. Native batching's transport contract and value
validation are separate from these single-request correlation declarations.

<!-- requirement-block: sourceviews.search-may-be-ranked-and-incomplete-it-must-not-be sourceviews.a-reference-to-such-a-field-must-not-trigger-an -->
`acquisition.kind` is exactly one of `scan`, `search`, `fetch`, or `follow`.
They mean finite collection enumeration, provider candidate search, exact
Resource observation fetch, and provider-declared relationship traversal. Search MAY
be ranked and incomplete; it MUST NOT be promoted to a complete extent.
Read authority is exactly `read_metadata`, `read_content`, or `read_binary`.
A metadata SourceView cannot expose a content or ArtifactRef field. Referencing
one is a check failure. A reference to such a field MUST NOT trigger an
implicit read-authority upgrade.

<!-- requirement-block: sourceviews.observation-kind-must-be-one-of-the-following-with-the-specified -->
`observation.kind` MUST be one of the following, with the specified meaning.
Observation classification is independent of the output Carrier.

<!-- requirement-block: sourceviews.kind-meaning-projection-a-meaning-preserving -->
| Kind | Meaning |
| --- | --- |
| `projection` | A meaning-preserving mapping of existing structured provider data into a Carrier. The contract fixes field and identity mappings, including graph nodes/edges, vector identity/metric, or event identity/time where applicable; it does not infer new facts. |
| `capture` | Provider-returned bytes retained as an Artifact, without interpreting their content. For export, the contract fixes the target scope and supported formats; the resolved request fixes any format choice. |
| `extraction` | Interpretation of captured content by a deterministic transformation defined by a registered ActQL profile. |

<!-- requirement-block: sourceviews.observation-transform-must-be-a-transformation-contract-reference-for-extraction-and sourceviews.check-must-reject-unregistered-transformation-contracts-under-a-connector-supplied sourceviews.extraction-evidence-must-bind-the-captured-content-cid-resolved-arguments -->
`observation.transform` MUST be a transformation contract reference for
`extraction` and absent otherwise. Check MUST reject unregistered
transformation contracts under [SourceView transformation profiles](protocols/contracts.md#sourceview-transformations); a Connector-supplied CID alone
does not register a transformation. Provider export is capture; parsing its returned bytes is
extraction. Extraction evidence MUST bind the captured content CID, resolved
arguments, and transformation contract CID.

<!-- requirement-block: sourceviews.a-sourceview-must-not-invoke-a-model-as-an-implicit sourceviews.the-host-must-admit-the-concrete-combination-of-acquisition-authority -->
A SourceView MUST NOT invoke a model as an implicit part of observation;
model acquisition uses the ModelTask boundary ([Model acquisition: infer](#infer)). The Host MUST admit the
concrete combination of acquisition, authority, observation, and Carrier
under its supported contracts, and reject unsupported combinations before
provider access. Classification and self-CIDs do not replace conformance or
runtime authority checks. Connector-defined names do not extend these laws.

<!-- requirement-block: sourceviews.check-must-report-that-unsupported-selection-and-the-runtime-must sourceviews.check-must-report-that-unsupported-selection-and-the-runtime-must.second -->
Read modes are `snapshot`, `changes`, and `watch`. Snapshot denotes a finite
observation, not proof of a capacity ceiling or snapshot consistency. Changes
declares a cursor/watermark/history/resource-version/offset/opaque checkpoint
and may execute in 0.1 only when the requested page/range is bounded. Watch is
unbounded: selecting it is statically unsupported, even if a Catalog advertises
it for another profile. Check MUST report that unsupported selection, and the
runtime MUST recheck it before network access. Delivery
facts distinguish ordered/partition-ordered/unordered delivery, possible
duplicates, acknowledgement, lease, reset, and replay policy. Provider receive
order is not event-time order.

<!-- requirement-block: sourceviews.read-mode-contract-coherence -->
A SourceView's advertised read-mode names MUST be unique, and `default_mode`
names exactly one advertised mode. A `snapshot` mode has `bounded: true`, a
`watch` mode has `bounded: false`, and both `changes` and `watch` carry a
checkpoint contract. A snapshot may also declare a checkpoint. A changes mode
may advertise either boundedness; admission of its declaration is distinct from
permission to select it for execution. Advertising watch does not make its
selection supported in ActQL 0.1. Validation preserves supplied mode order and
does not insert a missing default, checkpoint or boundedness declaration.

Snapshot acquisition remains subject to checked ceilings and their enforcement
boundaries ([Author guards, resolved limits, and Plan facts](#resolved-limits)).
Consistency within and across acquisitions depends on the admitted source
evidence, not the mode name ([Runtime source evidence](protocols/run.md#runtime-source-evidence)).

<!-- requirement-block: sourceviews.those-relation-operations-must-not-rewind-erase-or-otherwise-derive -->
The outgoing checkpoint is provider delivery evidence. It is computed from the
provider page/range before user projection, filter, ordering, or limit and is
carried separately from relation rows. Those relation operations MUST NOT
rewind, erase, or otherwise derive the provider checkpoint.

The stable rejection codes are:

```text
ACTQL_E_SOURCE_READ_MODE_UNSUPPORTED
ACTQL_E_UNBOUNDED_EVENTS_UNSUPPORTED
ACTQL_E_SOURCE_CARRIER_UNSUPPORTED
```

<!-- requirement-block: sourceviews.a-runtime-must-reject-missing-support-before-provider-access-it sourceviews.a-runtime-must-reject-missing-support-before-provider-access-it.second -->
Execution of a SourceView requires support for its acquisition and Carrier
contracts. A runtime MUST reject missing support before provider access;
it MUST NOT silently convert graph, vectors, or events to relation.
Pagination, retry, projection pushdown,
filter pushdown, and completeness remain connector capabilities, not ActQL
operations.

<!-- requirement-block: sourceviews.a-compiler-or-runtime-must-report-whether-a-connector-result sourceviews.it-must-not-represent-a-partial-result-as-complete -->
A compiler or runtime MUST report whether a connector result is complete. It
MUST NOT represent a partial result as complete.

<!-- requirement-block: sourceviews.a-connector-may-push-down-those-checked-operations-only-when sourceviews.it-must-not-interpret-an-author-only-scan-predicate-projection-order -->
The closed author-facing `scan` vocabulary contains only `mode`.
`mode` may select only a mode in the resolved SourceView. A concrete change
checkpoint is Invocation/Run state and is invalid in Program source.
Projection, filtering, ordering, limiting, and
deduplication use ordinary `select`, `filter`, `sort`, `take`/`top_k`, and
`dedupe_rows` steps. A Connector MAY push down those checked operations only
when its capability evidence proves the same semantics; otherwise the runtime
MUST apply them locally or reject before provider access. It MUST NOT interpret
an author-only scan predicate, projection, order, limit, or uniqueness dialect.

<!-- requirement-block: sourceviews.connector-inputs-must-not-repeat-local-carrier-expected-columns-schema-or -->
Connector inputs MUST NOT repeat local `carrier`, `expected_columns`, `schema`,
or `primary_key` declarations. The pinned SourceView contract
owns those facts. Such fields are invalid rather than drift assertions that
could disagree with the authority-bearing contract.

<!-- requirement-block: sourceviews.a-sourceview-used-as-the-keyed-right-side-of-an -->
A SourceView used as the keyed right side of an external join MUST NOT author
`scan`, including an empty object. Its keyed access path and bounded default
mode are owned by the pinned SourceView contract. Mode selection is available
only when the SourceView is read directly; a future checkpointed
keyed access path requires its own fully bound contract rather than silent
reuse of scan vocabulary.

<!-- requirement-block: sourceviews.whenever-the-resolved-read-mode-is-changes-whether-explicit-or -->
Whenever the resolved read mode is `changes`, whether explicit or supplied by
the contract's `default_mode`, the compiler MUST produce a content-addressed
`actql-source-state-requirement/0.1` in the checked Plan. The requirement binds
the Program Definition, input name, SourceView Contract, mode, and checkpoint
value contract. A concrete checkpoint is private Run material represented by
an `actql-source-state-binding/0.1`; changing it changes Invocation/Run
identity, not Program Definition identity.

Changes-read state is governed by [Source-state advancement](execution.md#source-state). Local graph, vector, and event inputs
belong to their algebra profiles independently of Connector execution support.

<a id="parameters"></a>

### Parameters and binding

ActQL 0.1 has typed invocation parameters for reusable programs:

```yaml
params:
  cutoff: {type: timestamp}
  threshold: {type: number}
  account_ids:
    type: array
    items: {type: string}

steps:
  - filter: "occurred_at >= $cutoff AND score >= $threshold"
```

<!-- requirement-block: parameters.decimal-declarations-must-specify-literal-precision-and-scale-under -->
Scalar parameter types are `string`, `number`, `decimal`, `boolean`,
`timestamp`, and `date`. Closed typed objects and homogeneous recursive arrays
are also admitted. Arrays declare one item contract under `items`
and MAY declare a positive fixed
`length`, which is required when the value is used as a fixed-dimension query
vector. Decimal declarations MUST specify literal `precision` and `scale`
under [Exact decimal values](#decimal-values); decimal array items declare the same pair once under `items`,
shared by every element. For example:

```yaml
params:
  unit_price: {type: decimal, precision: 18, scale: 2}
  tax_rates:
    type: array
    items: {type: decimal, precision: 5, scale: 4}
```

<!-- requirement-block: parameters.decimal-bindings-must-use-the-fixed-scale-canonical-string-representation-defined parameters.binding-must-reject-noncanonical-text-precision-overflow-and-binary64-numeric parameters.parameter-value-identity-must-use-the-typed-decimal-identity-of -->
Decimal bindings MUST use the fixed-scale canonical string representation
defined in [Exact decimal values](#decimal-values). Binding MUST reject noncanonical text, precision overflow,
and binary64 numeric input without implicit rounding or conversion. Parameter
value identity MUST use the typed decimal identity of [Exact decimal values](#decimal-values), not the identity
of its wire-format string, including for array elements.

<!-- requirement-block: parameters.they-must-not-select-an-operation-input-result-name-field-name -->
Number declarations MAY add `integer: true` and finite inclusive
`minimum`/`maximum`; string declarations MAY add `format: duration`.
These type-specific constraints apply recursively to Parameter object fields and
array items. `integer: false` imposes no integrality restriction; `integer: true`
requires a finite integral binary64 value, not an implicit safe-integer ceiling.
Array `length` is a positive safe integer and fixes the exact element count;
the shared optional `max_items` bound remains a nonnegative safe integer.
These constraints are checked at bind time, before AoA lowering. Parameters may
appear in scalar value positions, including
predicate literals, explicit ID lists, time/duration values, `k`, query vectors,
and numeric author guards, including `max_items`, `max_output_rows`, and
serialization bounds. They MUST NOT select an operation, input/result name, field
name, join kind, metric, direction, contiguity, overlap, connector,
resource, view, mapping, permission, approval, or failure policy.
A sequence `pattern` is structural and cannot be parameterized.

The additional recursive-value positions are exactly a values CellValue
`{$param: name}`, a pivot `fill` CellValue `{$param: name}`, an immediate
EffectValue `{literal: {$param: name}}`, and a
SourceView request value role accepting the same declared object/array contract.
An array parameter may also occupy an IN literal list, explicit ID list or
query-vector value where that consumer admits its element contract and extent.
Only these whole-value holes are substituted, once; nested business JSON is
opaque. An object EffectValue may supply an object-valued mapped field, but this
does not turn raw `create.payload` into a recursive template or parameterize its
field names. Existing consumer type, constructibility, egress and bound rules
still apply. A declared recursive value is not permission to use it at an
otherwise structural position.

Invocation value admission is closed:

<!-- requirement-block: parameters.condition-parameters-opaque-bindings-permitted parameters.product-dd791bbe096c -->
| Condition | Parameters | Opaque bindings |
| --- | --- | --- |
| Permitted types | Scalar, closed typed object, homogeneous recursive array | The closed opaque binding declarations in [Connector SourceViews](#sourceviews) |
| Missing value | Apply a declared literal default once; otherwise `needs_bindings`, including nullable declarations | `needs_bindings` |
| Null or wrong type | Null only with `nullable: true`; wrong type rejects | Reject; a reference also requires issuer/admission evidence |
| Undeclared supplied name or unused declaration | Reject | Reject |
| Structural selector or authority-policy substitution | Reject | Reject |

In Parameter type syntax, `nullable` defaults to false at every recursive type
position, including object fields and array items; this shorthand does not change
the explicit-nullability rule for general value contracts or checked contracts.
`default` and annotation `meta` are admitted only on a named Parameter declaration,
not on its nested type contracts. A business object field named `meta` is ordinary
data. Optional `default` is a complete
typed canonical literal, never an expression, clock, environment lookup or
reference to another parameter. Every object field is required; nullable does
not mean optional. Default substitution is top-level only, without deep merge.
An explicit null is never replaced by the default. Ordinary parameters cannot
fabricate opaque references or secrets. Consumer constraints such as
positive safe-integer guards are checked independently of parameter nullability.

Effective parameter values MUST be resolved once before the Program starts and
remain immutable across all stages, attempts and resume. Explicitly supplying a
default's value and omitting that value have the same typed values CID; origin
evidence is separate. Changing the default declaration changes Program semantics.
Usage is checked over all stages; extra supplied names and unused declarations
remain invalid. Public explain exposes type, bound state and default presence,
not private values.

For a direct SourceView, the authored request supplies its entire closed request
schema. For a keyed SourceView join ([External SourceView joins](#external-joins)), those fields are the disjoint union
of authored static request fields and Contract-defined correlation fields;
missing fields, overlap, and extra fields are rejected.

<!-- requirement-block: sourceviews.acquisition-request-classification -->
Check MUST classify a correlated SourceView input using both its authored
request fields and its actual consumers. Supplying every correlation request
field selects direct acquisition, including when that resulting Relation is a
join operand; a join reference does not remove supplied values or turn that
request into a key-driven template. Supplying none selects keyed acquisition
only when the input has at least one logical join-right consumer and no other
direct operation or Result consumer. Supplying only some correlation fields,
using an incomplete template directly, or leaving such a template without a
join-right consumer fails Check. A SourceView without correlation uses direct
request admission. Every non-correlated request field remains required in
either form. Classification does not prove boundedness, response completeness,
mode support, policy admission or the remaining join requirements, and does
not authorize deleting an unused declaration or an authored operation.

Within EffectValue, `{literal: {$param: name}}` is an immediate parameter
hole; other literal payloads are opaque JSON, not recursively substituted.
An explicit `create.payload` is likewise data, including `$param`-shaped objects.

<!-- requirement-block: parameters.a-parameterized-author-guard-must-resolve-to-a-positive-safe -->
A parameterized author guard MUST resolve to a positive safe integer before
executable planning. It retains the fail-closed semantics of a literal guard
([Author guards, resolved limits, and Plan facts](#resolved-limits)), and does not override Contract or Host ceilings or grant authority.

<!-- requirement-block: parameters.every-declaration-must-be-referenced-and-every-runtime-invocation-must parameters.every-declaration-must-be-referenced-and-every-runtime-invocation-must.second parameters.an-approval-must-not-carry-across-a-parameter-change -->
Every declaration MUST be referenced and every runtime invocation MUST resolve
all references by explicit binding or a missing-only default to a value of the
exact declared type. Binding does not
rewrite the Program CID. A change to canonical bound values changes
`parameter_values_cid`, compiled-plan identity, Invocation CID, and any
resulting Effect Preview CID, even if the lowered AoA computation is unchanged
([Canonical identities](#canonical-identities)). An approval MUST NOT carry across a parameter change.

Parameter binding precedes bound AoA lowering. The semantic phases ([Normative conventions](#normative-conventions))
have the following obligations; they do not prescribe compiler pass names:

```text
checking   template + Check Environment proof
binding    canonical values + range/length/duration proof
planning   substitute bound values before AoA Fragment and barrier planning
execution  capture source evidence before establishing Invocation identity
```

<!-- requirement-block: parameters.the-compiler-may-use-type-valid-witness-values-solely-to-prove parameters.effect-preview-accepts-a-captured-run-and-must-not-perform parameters.an-executable-plan-must-bind-the-exact-parameter-values-used parameters.an-executable-plan-must-bind-the-exact-parameter-values-used.second -->
`actql-bound-invocation-template/0.1` binds Program Definition CID,
Parameter Values CID, Check Environment CID, and the fact that runtime source
evidence remains unbound. The compiler MAY use type-valid witness values solely to
prove the template; it MUST NOT publish a compiled-plan or invocation identity
for those witnesses. Planning without every referenced value reports
`needs_bindings` and does not publish a runnable Plan Document. Emitting a Plan
Document and starting execution require every referenced value. Effect preview
accepts a Captured Run and MUST NOT perform parameter binding again.
An executable Plan MUST bind the exact parameter values used to resolve its
operations and limits; execution MUST NOT substitute different values.

<!-- requirement-block: parameters.a-host-that-derives-parameters-from-clocks-schedules-or-other parameters.same-run-retry-or-resume-must-not-recompute-these-values -->
Callers supply concrete values. A Host that derives parameters from clocks,
schedules, or other invocation settings MUST resolve them before executable
planning and retain them for the Run. Same-Run retry or resume MUST NOT
recompute these values. Schedule registration is not authorization of future
executions; each occurrence is subject to Run admission ([Run admission and identity](execution.md#run-admission)).

> **Note (informative):** A scheduler may store a Program and parameter-generation
> settings, then bind values and plan each occurrence. Timezone and whether a
> date is derived from the scheduled or actual start time are Host settings,
> not implicit ActQL expressions.

<a id="resource-identity-contract"></a>

### Resource identity contract

A SourceView `resource_identity` contract contains only the static provider
namespace, ResourceKind, provider-ID field, output field, and required boundary
topology. Connection revision, concrete authority scope, and boundary CID are
resolved connection evidence recorded by the plan/source evidence and hydration
receipt; host connection-secret rotation does not churn the static Connector Catalog or
lock. The SourceView issues the same `resource_ref<K>` for the same provider
namespace, resolved authority scope/boundary, ResourceKind, and provider
identity across all its views. View/version/etag/observation facts do not alter
Resource identity.
Runtime hydration, Artifact issuance, and availability leases are specified in [Reference admission and availability](protocols/artifacts.md#reference-admission).

<a id="expressions"></a>

## Expressions and predicates

Expression text and structured trees share one typed expression model.
`Expression<T>` produces a value of T; `Predicate` names a condition position
requiring a boolean Expression, optionally nullable, not a separate value
domain. Comparisons and boolean operations produce true, false, or null
(the three-valued unknown). Storing the result preserves null. No string or
number truthiness is admitted. A boolean field or function is directly usable
as a condition. `if(p, TRUE, FALSE)` deliberately maps null to false; it is not
the general representation of a boolean expression's value.

<!-- requirement-block: expressions.condition-consumption -->
| Position | true | false | null |
| --- | --- | --- | --- |
| Value position, including `derive` | store true | store false | store null |
| `filter`, aggregate filter | admit row | exclude row | exclude row |
| `if`, `case` condition | select branch | do not select branch | do not select branch |
| `assert_rows.where` | row satisfies assertion | assertion fails | assertion fails |
| `count_if` | count | do not count | do not count |

`count` counts non-null argument values, including false; `count_if` counts
only true. Each consumer uses these rules without inserting a Program-level
cast or changing the boolean expression's identity.

The following table closes expression placement and lowering in 0.1:

<!-- requirement-block: expressions.position-admitted-tree-and-context-evaluation-lowering -->
| Position | Admitted tree and context | Evaluation/lowering |
| --- | --- | --- |
| `derive` value | Common Expression over the input row, including pure profile calls | Canonical typed expression; conditional demand and per-expression envelopes preserved |
| `filter`, `assert_rows.where` | Boolean Expression over the input row | Common evaluation followed by the condition-consumption rule |
| Aggregate `expr` | Common row-local Expression | Each aggregate's filter first, expression only for its admitted rows, then null exclusion, distinct, and fold ([group](#group)) |
| Graph/sequence conditions | Boolean Expression in the operation's property/event context | Same expression laws and profiles; Carrier scope remains operation-specific |
| Effect `where` element | EffectPredicate over target fields ([Predicates](#predicates)) | Common decode followed by restricted selector validation; no scalar computation |

<!-- requirement-block: expressions.an-inadmissible-profile-position-must-fail-during-check-in-either expressions.moving-a-subexpression-to-a-separate-step-is-valid-only -->
An inadmissible expression or selector node MUST fail during check in either notation.
Moving a subexpression to a separate step is valid only if its evaluation
conditions, failure behavior, and resource bounds remain unchanged; a compiler
MUST NOT evaluate an unselected branch by hoisting it before its conditional.
Profile admission applies to every branch, but a pure profile does not require
an author-visible intermediate step. Effect selector and invocation-value
restrictions are not widened by expression composition.

Source notation and precedence are in [Expression text](#expression-text); canonical representation,
printing, and diagnostics in [Decoding, identity, and printing](#expression-decoding). Value families and their evaluation rules
are in [Scalar expressions](#scalar-expressions) and [Decimal expressions](#decimal-expressions)–[Text, time, and regular expressions](#text-time); predicate structure and evaluation are in [Predicates](#predicates).

<a id="scalar-expressions"></a>

### Scalar expressions

An expression or predicate position accepts expression text ([Expression text](#expression-text)) or the
structured tree form. In the tree form, field references, literals, and
parameters use `{field: ...}`, `{literal: ...}`, and `{$param: name}`.
Text is decoded to the same tree before identity computation ([Decoding, identity, and printing](#expression-decoding)).
Strings in non-expression positions, including inside `literal`, `meta`,
requests, and template bodies, retain their declared meaning and are not
recursively parsed as expressions. The Core scalar grammar contains:

- arithmetic `add`, `subtract`, `multiply`, `divide`, and `modulo`;
- boolean/comparison expressions, `case`, three-argument `if`, `coalesce`, and `nullif`;
- `len`, `contains`, `concat`, `safe_div`, `sqrt`, and `floor`;
- the authoring-only string `template` form;
- `lower`, `upper`, `trim`, and literal `replace`;
- `date_trunc`, `date_add`, and `date_diff`; and
- explicit `to_number`, `to_string`, `to_boolean`, and `to_timestamp`;
- `to_decimal`, `try_decimal`, `quantize`, and `decimal_divide`; and
- closed `object`, homogeneous `array` and typed empty-array construction;
- typed property/subscript access and type-preserving numeric `negate`.

`coalesce` is a lazy expression, not a macro that evaluates a child twice.
`template` is a deterministic authoring macro for ordinary messages and labels:

```yaml
- derive:
    message: {template: "{name} is at risk — active users: {active_users_30d}"}
```

<!-- requirement-block: scalar-expressions.each-field-placeholder-must-name-one-visible-string-number-decimal scalar-expressions.the-compiler-must-lower-placeholders-to-canonical-to-string-followed-by -->
Each `{field}` placeholder MUST name one visible `string`, `number`, `decimal`, `boolean`,
`timestamp`, or `date` field. The compiler MUST lower placeholders to canonical
`to_string` followed by left-to-right strict `concat_strict`. The lowering uses no locale,
host formatting, or expression evaluator. `{{` and `}}` emit literal braces.
Unmatched braces, empty placeholders, unknown fields, and non-scalar fields are
invalid. Null interpolation follows the `to_string` and `concat_strict`
rules and therefore produces null. Parameters and nested expressions are not
template placeholders; authors use the ordinary explicit expression grammar
when those are required.

String normalization is Unicode-preserving and locale-independent. `replace`
is literal substring replacement, not regex. `date_add` and `date_diff`
require an explicit unit from `ms|s|m|h|d`; calendar-month or timezone guesses
are not admitted in 0.1. Their forms are
`{date_add: [{field: timestamp}, {literal: amount}, {literal: unit}]}` and
`{date_diff: [{field: end_timestamp}, {field: start_timestamp}, {literal: unit}]}`. Timestamp
inputs and `date_add` results use canonical UTC ISO-8601 strings; `date_diff`
returns a finite numeric count in the authored fixed unit.
The decoded unit is a `{literal: ms|s|m|h|d}`. Full-word units and
day-specific helper names are not ActQL source vocabulary.
The expression 0.1 contract retains the binary64 arithmetic laws of
`actql-scalar-semantics/0.1`, with the conversion/concatenation rules below.
Every binary64 arithmetic result rounds to
binary64; negative zero is normalized at operation boundaries and remains
invalid in canonical source. Overflow/non-finite results and ordinary division
by zero fail the operation; `safe_div(_, 0)` returns null. Binary64 `sum` and
`avg` use the captured numeric-observation boundary defined below, rather than
requiring a placement-independent reduction bit pattern. Exact decimal arithmetic
uses a separate coefficient/precision/scale value domain ([Exact decimal values](#decimal-values)), not an
implicit binary64 or money coercion.

The conversion/boundary truth table is normative:

<!-- requirement-block: scalar-expressions.function-0-1-result-to-number-string-canonical -->
| Function | Adopted result |
| --- | --- |
| `to_number(string)` | canonical decimal grammar `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`; no trim, hex, NaN, or Infinity; otherwise fail |
| `to_boolean(string)` | exactly case-sensitive `true` or `false`; no trim; otherwise fail |
| `to_string(number)` | AoA canonical number spelling |
| `to_string(string)` | unchanged canonical string |
| `to_string(decimal)` | fixed-scale canonical decimal text |
| `to_string(boolean)` | `true` or `false` |
| `to_string(timestamp)`, `to_string(date)` | unchanged canonical temporal spelling |
| `to_timestamp(string)` | canonical millisecond UTC `Z` spelling only; offsets fail |
| `modulo(a,b)` | truncating remainder with dividend sign; zero divisor fails |
| `sqrt(x)` | negative fails |
| `len(null)` | null |
| `concat(...values)` | string operands; skip nulls, concatenate in order; all null yields the empty string |
| `concat_strict(...values)`, text `a \|\| b` | string operands; null if any operand is null; otherwise concatenate in order |
| `template` | authoring-only macro to canonical `to_string` and `concat_strict`; `{{` / `}}` are literal braces |
| `case` | unknown/null condition is not selected; first true branch wins; absent else is null |
| `if` | selects the true branch only when the condition is true; otherwise selects the false branch |
| `coalesce` | first non-null argument; null if all arguments are null |
| `nullif(a,b)` | evaluate a then b once each; null if equality is true, otherwise return the evaluated a |
| `date_diff` | fixed-unit quotient truncated toward zero |

Strict scalar functions propagate a null input unless the row above states
another rule. Conditional selection follows the table; constructors follow
[Object and array construction](#value-construction) rather than null-propagating their children. This table and the machine-readable
expression 0.1 laws are the human- and machine-readable views of
the same contract.

`if` evaluates its condition and only the selected branch. `case` evaluates
conditions in order until the first true condition, then only that branch;
otherwise it evaluates its else expression. `coalesce` evaluates arguments
in order through the first non-null value. Non-selected expressions do not
produce runtime failures, although all expressions are statically checked.
Static checking validates syntax, names, arity, types, profile admission, and
signature-declared static argument constraints in every branch. Checking a
conversion's input type does not apply its value-conversion law.
Positional arguments, array elements, and n-ary operands evaluate in canonical
array order; object children and one `derive` map evaluate in canonical
field-name order. Conditional demand takes precedence over these orders.
The first evaluated failure is the operation's failure; JSON/YAML object-key
enumeration never chooses it. Strict functions evaluate arguments before their
null rule. `try_*` catches only its own specified conversion failure, not an
argument's failure, a malformed static argument, an engine failure, or a bound breach.

<!-- requirement-block: scalar-expressions.static-versus-evaluation -->
| Expression (with required profiles and valid field types) | Required outcome |
| --- | --- |
| `if(FALSE, to_number('bad'), 1)` | check succeeds; value 1 |
| `if(FALSE, 1 / 0, 1)` | check succeeds; value 1 |
| `if(FALSE, unknown_function(x), 1)` | static rejection |
| `if(FALSE, date_add(ts, 1, 'month'), ts)` | static rejection of the unit |
| `try_number(to_string(1 / 0))` | division failure, not null |

Decode never computes values. Canonical lowering follows the fixed expression
contract, not a compiler-selected constant-folding policy. Physical
optimization may fold/reuse values only while preserving canonical identity,
evaluation demand, failure precedence, and applicable logical limits. A failing
fold can be left unfolded; it is not a new check-time error. Logical size and
cardinality obligations survive optimization; physical CPU, allocation, and
memory use need not match a reference evaluator. Every limit retains its
measured scope and enforcement boundary ([Resolved limits](#resolved-limits)).

The signature arities and positional mapping are defined in [Expression text](#expression-text); their value
contracts are completed by this table. `S` is string, `N` is number, and `T`
is the common type from [Closed value contracts](#value-contracts). Strict functions propagate null; domain failures
are atomic, not null, except where the named function explicitly specifies it.

<!-- requirement-block: scalar-expressions.functions-input-result-null-failure-rule-beyond -->
| Functions | Input → result | Null/failure rule beyond the common rule | Profile |
| --- | --- | --- | --- |
| `len` | S → N | Unicode scalar count | RelA |
| `lower`, `upper`, `trim` | S → S | Pinned mappings/character set | RelA |
| `concat`, `concat_strict`, `replace` | S operands → S | [Scalar expressions](#scalar-expressions) string rules | RelA |
| `contains` | S, S → boolean | Exact matching | RelA |
| `sqrt`, `floor`, `safe_div` | N operands → N | Negative square root fails; safe division by zero returns null | RelA |
| `to_number`, `to_boolean`, `to_timestamp` | S or the exact target type → indicated type | [Explicit casts](#casts) closed conversion table; same-type identity | RelA |
| `to_string` | string, number, decimal, boolean, timestamp, or date → S | Canonical spelling; json/object/array/vector and both reference types are rejected | RelA |
| `date_trunc`, `date_add`, `date_diff` | Date/timestamp and fixed unit/number operands | Same temporal domain; [Scalar expressions](#scalar-expressions) units and result rules | RelA |
| `if`, `case` | Predicate conditions, T branches → T | Selected branch only; absent else is null | RelA |
| `coalesce` | T operands → T | First non-null; nullable only if every operand may be null | RelA |
| `nullif` | KeyComparable A,B → nullable A | eager once-only evaluation; no operand conversion | RelA |
| `negate` | number or decimal(P,S) → same type | negate coefficient for decimal, canonicalize zero; no typed-zero subtraction | RelA |
| Decimal functions | [Decimal expressions](#decimal-expressions) typed operands → decimal(P,S) | [Decimal expressions](#decimal-expressions) overflow, conversion, rounding | RelA |
| Text-time functions | [Text, time, and regular expressions](#text-time) closed argument contracts | [Text, time, and regular expressions](#text-time) resource envelopes and total-parse distinctions | Text-time |
| `vector_score` | two same-dimension vectors and literal metric → number | [Row-local vector expressions](#vector-expressions); null propagates | VecA |
| `vector_concat` | at least two typed vectors → vector of summed dimensions | [Row-local vector expressions](#vector-expressions); null propagates | VecA |

`ms|s|m|h|d` are fixed UTC durations, with a
day exactly 86,400,000ms; these fixed-unit functions perform no DST, month,
or calendar-day arithmetic. Explicit calendar operations use the separate
[calendar profile](#calendar).
Date-only values ([Closed value contracts](#value-contracts)) require explicit conversion before timestamp
comparison, and admit only integer `d` arithmetic. `date_trunc('d', date)` is the
identity, `date_add(date, integer, 'd')` returns a date, and `date_diff` between
two dates is measured only in whole fixed UTC days. A date/timestamp mix or a
sub-day date unit is rejected rather than silently promoting midnight to a
timestamp.

<!-- requirement-block: scalar-expressions.lower-upper-use-unicode-16-0-default-mappings-a-runtime-without-exactly -->
String value and ordering rules are defined in [Carriers, values, and types](#values-and-types). `len`
counts Unicode scalar values; `trim` removes only U+0009..U+000D and U+0020;
`contains` is case-sensitive exact normalized matching; `like` is
case-sensitive with `%`, `_`, and backslash escape; `replace` is
non-overlapping left-to-right and an empty search is a no-op. `lower`/`upper`
use Unicode 16.0 default mappings; a runtime without exactly those tables MUST
reject those functions rather than use host-dependent mappings.

<!-- requirement-block: scalar-expressions.like-pattern-validation -->
Before executable compilation, the compiler MUST resolve each LIKE pattern
literal or Parameter from the selected checked bindings to a non-null string
and validate its escape syntax, including in unselected branches. Backslash
quotes exactly the next Unicode scalar; a final unpaired backslash is invalid.
The empty pattern is valid, `%` matches any scalar sequence, and `_` matches
one scalar, including line separators. Other scalars are literal and no regex
syntax or flags are inferred. Validation preserves the normalized pattern text
without rewriting repeated wildcards or escapes. A null value operand retains
the ordinary nullable predicate semantics; it does not excuse an invalid or
null static pattern. LIKE does not acquire the text-time profile's Host policy
requirements merely because its pattern is checked at the same boundary.

<a id="expression-text"></a>

### Expression text

Expression text borrows SQL-style identifiers, quoting, operators, function
calls, and searched `CASE`, not SQL type conversion or execution semantics.
ActQL is not PostgreSQL-compatible. The following comparison is informative;
the ActQL rules in this chapter remain normative.

<!-- informative-table: postgresql-expression-differences -->
| Expression / name | ActQL | PostgreSQL 18 |
| --- | --- | --- |
| `5 / 2` | `2.5` (binary64) | `2` (integer division) |
| `split_part('a,b', ',', 1)` | `'a'` (one-based) | `'a'` (one-based) |
| `substring('abcd', 1, 1)` | `'a'` (one-based) | `'a'` (one-based) |
| `concat('a', NULL)` | `'a'`; non-null arguments must be strings | `'a'`; also stringifies non-string arguments |
| Bare `Name` | Case preserved | Folded to lowercase |

<!-- requirement-block: expression-text.an-implementation-must-reject-unlisted-syntax-functions-and-wrong-arities -->
PostgreSQL references: [arithmetic](https://www.postgresql.org/docs/18/functions-math.html),
[strings](https://www.postgresql.org/docs/18/functions-string.html), and
[identifiers](https://www.postgresql.org/docs/18/sql-syntax-lexical.html).
PostgreSQL is not an oracle for ActQL expressions; differential tests require
an explicitly identified subset with matching semantics.
The complete syntax is defined by
[ActQL expression EBNF](../../spec/grammar/actql-expression-0.1.ebnf) and the
closed mappings below. An implementation MUST reject unlisted syntax,
functions, and wrong arities, and consume the whole expression string.

```yaml
- derive:
    total: "unit_price * quantity"
- filter: "total >= $threshold"
- derive:
    label: "coalesce(customer_name, 'Name unavailable')"
    category: |
      CASE WHEN total >= 100000 THEN 'Large' ELSE 'Standard' END
```

The following are the complete borrowed spellings and their tree meanings:

<!-- requirement-block: expression-text.text-tree-form-name-quoted-name -->
| Text | Tree form |
| --- | --- |
| `name`, `"quoted name"` | `{field: name}` with the decoded name |
| `'text'`, numeric literal, `TRUE`, `FALSE`, `NULL` | `{literal: value}` |
| `$name` | `{$param: name}`; bare parameter names only, not positional `$1` |
| `(e)` | grouping; no tree node |
| `a + b`, `a - b`, `a * b`, `a / b`, `a % b` | `add`, `subtract`, `multiply`, `divide`, `modulo` |
| `-e` | signed literal only when applied directly to a numeric literal token through grouping alone; otherwise `negate(e)` for number or decimal |
| `a = b`, `a <> b`, `a < b`, `a <= b`, `a > b`, `a >= b` | `eq`, `neq`, `lt`, `lte`, `gt`, `gte` |
| `a AND b`, `a OR b`, `NOT p` | `and`, `or`, `not` |
| `e IS NULL`, `e IS NOT NULL` | `is_null`, `not_null` |
| `e IN (a, b, ...)`, `e NOT IN (a, b, ...)` | `in`, `not_in` with `{literal: [...]}`; each item is a scalar literal or scalar parameter reference |
| `e IN $items` (also `NOT IN`) | membership in an array parameter |
| `e BETWEEN lo AND hi` | `between` |
| `e LIKE pattern` | `like`; pattern is a string literal or string parameter |
| `e NOT BETWEEN lo AND hi`, `e NOT LIKE pattern` | `not` around the corresponding predicate |
| `a \|\| b` | `concat_strict`, never null-skipping `concat` |
| `CASE WHEN p THEN a ... [ELSE b] END` | ordered `case.when` entries and optional `else` |

Function names are exact lowercase names. Their complete signatures are below;
arguments are positional and map to the existing tree operands or named fields
in the order shown. `...` means one or more arguments in total; brackets denote
an optional final argument, not expression syntax.

<!-- requirement-block: expression-text.signatures-mapping-constraints-len-x-sqrt-x -->
| Signatures | Mapping / constraints |
| --- | --- |
| `len(x)`, `sqrt(x)`, `floor(x)`, `lower(x)`, `upper(x)`, `trim(x)` | corresponding unary scalar function |
| `to_number(x)`, `to_string(x)`, `to_boolean(x)`, `to_timestamp(x)` | explicit conversion |
| `contains(value, part)`, `safe_div(left, right)`, `replace(value, search, replacement)` | corresponding scalar function |
| `concat(x, ...)`, `concat_strict(x, ...)`, `coalesce(x, ...)`, `if(condition, then_value, else_value)` | corresponding scalar function or conditional tree |
| `vector_score(a, b, 'cosine'|'dot'|'l2')` | `{vector_score: {left: a, right: b, metric: decoded-literal}}` |
| `vector_concat(a, b, ...)` | `{vector_concat: [a,b,...]}`; at least two operands |
| `nullif(a, b)`, `negate(x)` | once-only null comparison; type-preserving negation |
| `date_trunc(unit, value)`, `date_add(value, amount, unit)`, `date_diff(end_value, start_value, unit)` | `unit` is a string literal in `ms`, `s`, `m`, `h`, `d` |
| `to_decimal(value, precision, scale)`, `try_decimal(value, precision, scale)` | [Decimal expressions](#decimal-expressions) fields; precision/scale are integer literals |
| `quantize(value, precision, scale, rounding)` | [Decimal expressions](#decimal-expressions) fields; precision/scale are integer literals and rounding is a string literal naming an admitted mode |
| `decimal_divide(left, right, precision, scale, rounding)` | same literal constraints as `quantize` |
| `split_part(value, delimiter, index)`, `substring(value, start, length)`, `utf8_truncate(value, max_bytes)` | [Text, time, and regular expressions](#text-time) fields and argument restrictions |
| `try_number(value)`, `nfkc(value)`, `case_fold(value)` | [Text, time, and regular expressions](#text-time) unary expressions |
| `parse_timestamp(value, pattern)`, `try_timestamp(value, pattern)`, `format_timestamp(value, pattern)` | [Text, time, and regular expressions](#text-time) fields |
| `regex_match(value, pattern [, flags])`, `regex_extract(value, pattern, capture [, flags])`, `regex_replace(value, pattern, replacement [, flags])` | [Text, time, and regular expressions](#text-time) fields; flags, when present, are a string literal |

<!-- requirement-block: expression-text.the-decoded-tree-must-satisfy-the-position-s-existing-value-or -->
Pure text-time calls require their profile and per-expression envelopes.
`object`, `template`, and opaque JSON literals retain their structured
forms; array literals and typed access are defined below. Aggregate and window operations,
subqueries, named arguments, `::`, `COLLATE`, simple `CASE`, SQL comments, and user-defined functions are
not expression syntax. Text is admitted only at Expression and Predicate
positions, not at restricted EffectValue or request-binding positions.
The decoded tree MUST satisfy the position's type and allowed-node contract.
Each element of the Effect `where` conjunction array is a restricted condition
position accepting text, with fields referring to the target Resource.

`IN (x)` is a one-element list, not grouping. Parameter references inside its
literal-list template are resolved before checking the bound literal array;
parentheses around a literal or parameter are permitted, including
`x IN ((1))` and `x LIKE ('a%')`. Validation examines the decoded node, so
`x LIKE ('a' || '%')` remains invalid. Other literal payloads are opaque data,
not locations for recursive parameter substitution.
Row-dependent membership lists are not supported. Unary `-` on a nonliteral
numeric expression decodes to `negate`, preserving number or decimal type.

The EBNF fixes precedence, highest first:

<!-- requirement-block: expression-text.precedence-associativity-grouping-function-call-searched -->
| Precedence | Associativity |
| --- | --- |
| grouping, function call, searched `CASE`, `CAST`, array constructor | explicit nesting |
| property selection, subscript | left; postfix |
| unary `-` | right |
| `*`, `/`, `%` | left |
| `+`, `-` | left |
| `\|\|` | left |
| `[NOT] IN`, `[NOT] BETWEEN`, `[NOT] LIKE` | non-associative |
| `=`, `<>`, `<`, `<=`, `>`, `>=` | non-associative |
| `IS [NOT] NULL/TRUE/FALSE/UNKNOWN`, `IS [NOT] DISTINCT FROM` | non-associative |
| `NOT` | right |
| `AND` | left |
| `OR` | left |

Bare names match `[A-Za-z_][A-Za-z0-9_]*` and retain case. Other names use
double quotes with doubled `""` for a quote; all decoded names still obey
their field or parameter naming contracts. The closed, ASCII-case-insensitive
reserved words are `AND OR NOT IS NULL TRUE FALSE IN BETWEEN LIKE CASE WHEN
THEN ELSE END CAST AS UNKNOWN DISTINCT FROM`; reserved field names require quotes. Function names are contextual:
`len` is a field and `len(x)` is a call. Parameter names after `$` retain their
declared spelling, including names matching keywords. String literals use single
quotes and doubled `''`, with no adjacent-string concatenation, `E'...'`, or
dollar quoting. Backslash has no lexical escape meaning here; a LIKE, regex,
or other pattern consumer interprets the resulting string under its own law.

<!-- requirement-block: expression-text.a-comparison-with-a-literal-null-operand-must-be-rejected -->
Unadorned numeric literals denote finite binary64 `number`, including those
with a fractional part or exponent. Negative zero is invalid. Decimal values
use explicit `to_decimal`/`try_decimal` conversion, decimal parameters, or
decimal fields; no decimal/binary64 promotion is inferred. `/` is number
division even for integral operands; decimal division uses `decimal_divide`.
An ordinary `=`, `<>`, `<`, `<=`, `>`, or `>=` comparison with a literal `NULL`
operand MUST be rejected; `IS [NOT] DISTINCT FROM` follows its explicit
null-safe rule. Nullable fields otherwise retain [Predicates](#predicates)
three-valued semantics. SQL implicit conversions and
host-specific arithmetic or evaluation behavior do not apply.

> **Note (informative):** JSON/YAML decoding happens first. Quote the entire
> expression or use a YAML `|` block; a SQL string literal is still quoted
> inside it. A block avoids YAML double-quote processing of pattern backslashes.
> YAML comments outside the expression are not expression comments.

<a id="expression-decoding"></a>

### Decoding, identity, and printing

`values` cells are outside expression printing. Their literal wrappers use
CellValue quoting, not expression decoding, template expansion or the mixed
expression printer. Printing never interprets a cell payload as expression
children, even when its keys resemble expression tags or parameter holes.

<!-- requirement-block: expression-decoding.text-decoding-must-finish-before-parameter-reference-discovery-semantic-checking-and -->
Text decoding MUST finish before parameter-reference discovery, semantic
checking, and Program CID computation. Structured and text expressions may
be mixed; both use the same tree validation and lowering. The canonical
local_body referenced by `program_template` contains decoded expression trees, never expression-text
nodes; string literal payloads remain string values. Decoding does not evaluate
expressions, reassociate arithmetic, or infer semantic choices, and is not a
Normalization Journal entry. Existing semantic completion and macro rules
still apply to the decoded tree ([Deterministic completion](#completion)).

<!-- requirement-block: expression-decoding.text-and-structured-forms-decoding-to-the-same-tree-must -->
Text and structured forms decoding to the same tree MUST have the same Program
identity. Whitespace outside tokens, keyword case, and equivalent field quoting
do not change that tree. Parentheses wrapping an existing subtree preserve its
identity only when they do not change operator grouping or arity. An unparenthesized chain of
`AND`, `OR`, or `||` decodes to one n-ary node (`and`, `or`, or `concat_strict`), in operand order; explicit grouping
retains nesting. Arithmetic remains binary and is not reassociated.
For example, `a = 1 AND b = 2 AND c = 3` and
`(a = 1 AND b = 2) AND c = 3` have different trees and Program identities.
`coalesce` remains a dedicated node in both the canonical Program and the
expression 0.1 canonical fragment. CASE expansion is not canonical lowering.
An executor may implement equivalent control flow, but reuses each evaluated
operand rather than duplicating its evaluation.

<!-- requirement-block: expression-decoding.a-canonical-expression-printer-must-preserve-the-tree-operand-order -->
A canonical expression printer MUST preserve the tree, operand order, and
literal values. It uses uppercase keywords, lowercase function names,
unquoted non-reserved ASCII names where permitted, doubled quote escaping,
AoA canonical number spelling, one space around infix operators, and comma
followed by one space between arguments. It parenthesizes each operator
application, prints conditionals as searched `CASE` or `if` according to their
tree kind, and emits no trailing whitespace. It does not resugar arithmetic
subtraction into unary minus. `negate` prints as unary minus with its operand
parenthesized, or `negate(...)` when a signed-literal decode would change the
tree; strict concatenation prints as `concat_strict(...)`, never
`concat(...)`. Casts print as `CAST(value AS TYPE)`; other functions use their
named call spelling. Binary arithmetic and boolean expressions use
the operator spellings in [Expression text](#expression-text); n-ary `and`/`or` print as a parenthesized chain.
Membership prints a literal array as an `IN` list, or a parameter as its right
operand. `not` prints
as `NOT (p)` rather than rewriting the child predicate.

<!-- requirement-block: expression-decoding.for-each-text-representable-canonical-tree-t-decoding-its-canonical-printed expression-decoding.a-printer-must-not-stringify-a-structured-constructor-or-change -->
For each text-representable canonical tree `t`, decoding its canonical printed
text MUST yield `t`. Arrays print as `[a, ...]`; an explicitly typed empty array
retains its structured form. Trees without a text spelling, including object
constructors, opaque JSON literals, and unary `and`/`or` nodes, retain their structured envelope with
recursively printed expression children; literal payloads are never traversed.
Reviews may use this mixed printed form, bound to the exact underlying tree
identity. A printer MUST NOT stringify a structured constructor or change it
to an allegedly equivalent literal. The expression grammar, reserved words,
signatures, decoding rules, and printer rules belong to Grammar Manifest
identity, not a separately selectable execution engine.

<!-- requirement-block: expression-decoding.expression-diagnostics-must-distinguish-syntax-errors-unknown-functions-unknown-field-parameter -->
Expression diagnostics MUST distinguish syntax errors, unknown functions,
unknown field/parameter references, and type/arity errors (including a non-boolean
condition or an inadmissible selector node). They identify the
enclosing JSON path and a zero-based half-open Unicode-scalar offset range in
the decoded expression string; EOF is a zero-width range. Public diagnostics
remain subject to [Diagnostic documents](protocols/contracts.md#diagnostic-documents) redaction. The versioned diagnostic catalog assigns
their codes; this syntax does not authorize uncataloged codes.

<a id="predicates"></a>

### Predicates

The structured predicate grammar is below; expression text in [Expression text](#expression-text) decodes
to this same vocabulary. Predicate operands may be scalar expressions:

<!-- requirement-block: predicates.operand -->
<!-- normative-code: grammar -->
```text
Operand := Expression
SelectorOperand := {field: TargetField} | {literal: JsonValue} | ParamRef
ComputationPredicate := Expression checked as boolean (nullable permitted)
EffectPredicate := SelectorPredicate<SelectorOperand>

BooleanNode<Operand> :=
    {eq|neq|lt|lte|gt|gte|in|not_in|like|contains: [Operand, Operand]}
  | {between: [Operand, Operand, Operand]}
  | {is_null|not_null: Operand}
  | {and|or: [Expression, ...]}
  | {not: Expression}
  | {is_true|is_false|is_unknown: Expression}
  | {is_distinct_from: [Expression, Expression]}

SelectorPredicate<Operand> :=
    {eq|neq|lt|lte|gt|gte|in|not_in|like|contains: [Operand, Operand]}
  | {between: [Operand, Operand, Operand]}
  | {is_null|not_null: Operand}
  | {and|or: [SelectorPredicate<Operand>, ...]}
  | {not: SelectorPredicate<Operand>}
```

Bare `Predicate` denotes ComputationPredicate. Boolean nodes are also value
expressions. Effect selectors use their closed structural subset;
boolean fields and new calls are not implicitly added to that subset. IN-list and LIKE restrictions
apply in both variants. Common decoding does not widen Effect operands.
The `lt`, `lte`, `gt`, `gte`, and `between` operands require `AuthorOrderable`
([Lexical and ordering rules](#ordering)), including under `not` or inside a conditional; reference operands
remain inadmissible in either notation.

<!-- requirement-block: predicates.pushdown-and-other-optimizations-must-preserve-these-evaluation-and-failure -->
AoA RelA boolean predicates evaluate operands left to right, eagerly, before
combining their three-valued results. `AND` does not skip later operands after
false, nor `OR` after true; the first evaluated failure aborts the operation.
For example, `x <> 0 AND 10 / x > 1` fails at x = 0. Use a lazy conditional
to guard a failure-prone value expression. Pushdown and other optimizations
MUST preserve these evaluation and failure rules, not only the truth table.

Boolean structure uses:

```yaml
filter: "status = 'open' AND (region = 'jp' OR region = 'us') AND NOT (deleted = TRUE)"
```

The same predicate has this structured form:

```yaml
filter:
  and:
    - {eq: [{field: status}, {literal: open}]}
    - {or: [{eq: [{field: region}, {literal: jp}]}, {eq: [{field: region}, {literal: us}]}]}
    - {not: {eq: [{field: deleted}, {literal: true}]}}
```

The following AoA predicate vocabulary applies only to the restricted
Effect selector lowering, not to expression 0.1 computation roots:

- column reference: `{type: col, path: [field, ...]}`;
- scalar literal: `{type: lit, value: ...}`;
- comparison: `{type: cmp, op, left, right}`;
- membership: `{type: in, op: in|nin, left, right}`;
- interval: `{type: between, expr, low, high}`;
- deterministic pattern: `{type: like, left, pattern}`;
- string containment as the admitted two-argument `contains` scalar function
  compared with `true`;
- null check: `{type: isnull, expr}`;
- boolean `and`, `or`, and `not`.

<!-- requirement-block: predicates.null-equality-must-not-be-inferred-from-an-equality-comparison -->
Null equality MUST NOT be inferred from ordinary `eq`/`neq`; authors use
null tests or explicit `is_distinct_from`. Reference equality and ordering follow [Opaque reference values](#opaque-references).
Missing and null behavior follows AoA relation semantics. The
scalar expression vocabulary is the closed set in [Scalar expressions](#scalar-expressions).
`like` uses deterministic AoA pattern semantics; ActQL does not expose a host
regex engine. The arbitrary-code boundary is defined in [Language boundaries](#language-boundaries).

<!-- requirement-block: predicates.a-connector-may-advertise-only-a-subset-for-pushdown-but predicates.a-connector-may-advertise-only-a-subset-for-pushdown-but.second -->
Relation filters and their Connector pushdowns use the common boolean expression;
Effect selectors admit only the restricted selector subset above. A connector MAY advertise only a
subset for pushdown, but the runtime MUST apply the remaining predicate with
the same canonical predicate semantics or reject it; it MUST NOT reinterpret it.
In an Effect `where` selector, field operands address the target Resource as
specified in [Effect declarations](#effects), not a computation Result.

<a id="common-expression-contract"></a>

### Common expression contract

The adopted contract is `actql-expression-contract/0.1`. It extends the pinned
AoA foundation with the closed expression schema and laws linked in
[Machine contracts](#machine-contracts). It is not a UDF registry or a Host
callback interface. `actql/0.1` uses this contract for all general computation
positions; there is no source revision selector or compatibility mode. The
Program semantics envelope pins `expression_contract_cid`.

<!-- requirement-block: common-expression-contract.canonical-nodes -->
| Source | Decoded canonical node |
| --- | --- |
| comparison, boolean operation, `contains` | the same expression node in value and condition positions |
| `p IS TRUE/FALSE/UNKNOWN` | `{is_true: p}`, `{is_false: p}`, `{is_unknown: p}` |
| `p IS NOT TRUE/FALSE/UNKNOWN` | `{not: corresponding_test}` |
| `a IS DISTINCT FROM b` | `{is_distinct_from: [a,b]}` |
| `a IS NOT DISTINCT FROM b` | `{not: {is_distinct_from: [a,b]}}` |
| `nullif(a,b)` | `{nullif: [a,b]}`; not a duplicating case macro |
| `-e` (not a signed numeric literal token), `negate(e)` | `{negate: e}` |
| `CAST(e AS TYPE)`, corresponding `to_*` call | `{cast: {value: e, target: CastType}}` |
| `receiver.name` | `{property: {value: receiver, name}}` |
| `receiver[index]` | `{subscript: {value: receiver, index}}` |
| unquoted initial `left.name` / `right.name` | `{join_field: {side: left\|right, name}}` |
| qualified `{field: "left.a.b"}` (likewise `right`) | `{property: {value: {join_field: {side: "left", name: "a"}}, name: "b"}}`; each subsequent segment adds property access in order, as in expression text |
| `[a,b,...]`, `[]` | `{array: [a,b,...]}`, `{array: []}` |
| explicit typed empty array | `{empty_array: {items: AuthorValueContract}}` (structured only) |
| `a \|\| b`, `concat_strict(a,b)` | `{concat_strict: [a,b]}` |
| `concat(a,b)` | `{concat: [a,b]}` |

All named expression bodies are closed; no sibling tags or unknown fields are
accepted. Text and structured spellings undergo the same normalization, including
`to_*` to `cast` and qualified `{field: "left.name"}` to `join_field`.
Bare field spelling and explicit quotation retain the same field node, except
that quotation prevents lexical recognition of a leading join qualifier, not
subsequent whole-field alias normalization. Cast targets
contain `type` and, only for decimal, `precision` and `scale`, not `nullable`.
An explicit cast of null remains a cast node in Program identity; it supplies
the typed null in checking. A same-type cast also remains a node, even though its
value law is identity. No constant evaluation occurs during this normalization.

`IS TRUE`, `IS FALSE`, and `IS UNKNOWN` require boolean input and produce
non-null boolean. `IS UNKNOWN` tests boolean null; `IS NULL` is the general
typed null test. `IS DISTINCT FROM` requires KeyComparable operands (a literal
null receives its peer's type); both null gives false, exactly one null gives
true, otherwise it uses non-null inequality. Two untyped null operands still
require explicit type evidence. `nullif` requires KeyComparable inputs,
returns the first operand's type made nullable, and evaluates both arguments
once even if the first is null. It returns null only when ordinary equality
is true, otherwise the already evaluated first value.

<!-- requirement-block: common-expression-contract.boolean-tests -->
| p | NOT p | p IS TRUE | p IS FALSE | p IS UNKNOWN | p IS NOT TRUE |
| --- | --- | --- | --- | --- | --- |
| true | false | true | false | false | false |
| false | true | false | true | false | true |
| null | null | false | false | true | true |

Ordinary equality and ordered comparison propagate null; `is_null`/`not_null`
are non-null boolean. AND/OR use three-valued conjunction/disjunction, eagerly:
false dominates AND, true dominates OR, otherwise a null operand yields null.
No truthiness or reference inspection is introduced.

The canonical extension node is `{op: tag, body: payload}` under
`actql-expression-node/0.1`. Lowering recursively preserves each normalized tag
and its closed payload shape from the machine expression schema, replacing
expression children with extension nodes; structural arguments and opaque
literal data are copied. Non-null parameter nodes become literals from bound values.
The author-only template is first expanded to its ordered literal segments
and cast-to-string placeholders under one `concat_strict`; a template with no
segments yields an empty-string literal. It is not an executable template node.
Empty array constructors become `empty_array` with the canonical checked item
contract; explicit empty arrays lower to the same node. Every typed NULL,
including a null parameter and a missing CASE ELSE, uses
`{op: typed_null, body: {contract: CheckedValueContract}}`, with `nullable: true`.
Explicit casts retain their cast node around that typed child. There is no
primitive-versus-structural alternative for implicit ELSE completion.
This machine-only form is not an author conversion to object or array.

Canonical fragments bind the extension contract CID, roots at their semantic
expression positions, and profile envelopes sorted by canonical expression
pointer. The existing AoA relational operations consume those typed roots;
conversion to a scalar node with different meaning is forbidden.
Placement requires support for this extension, including boolean value roots,
typed empty arrays and per-expression demand. A profile operation is still a
pure expression, not an acquisition or arbitrary callback. This defines the
canonical lowering under the pinned AoA and expression contracts.

The Relation binding is `actql-expression-fragment/0.1`, whose closed machine
schema is in [Machine contracts](#machine-contracts). Its `request` fixes the
canonical source pipeline, checked source schemas, typed parameter values,
`max_rows` and `max_value_bytes`. The latter ceiling applies per input value,
evaluated root value and published output value, not to physical allocations.
`graph` contains inline expression 0.1 nodes with unambiguous typed contracts.
`expression_contract_cid` pins the exact expression contract. `fragment_cid`
hashes the whole fragment excluding only itself. The containing executable
artifact pins this fragment CID; its inner graph is not a standalone
AoA execution artifact.
The request is private execution material, not a public diagnostic projection.

In the containing AoA composition, `ACTQL.expression_fragment/0.1` has one
Relation input and output. Its `params` contains exactly `fragment`; the
fragment request names its single local source `input`. Admission rechecks the
sealed fragment before evaluating the composition. A carrier-validation
projection is not a semantic graph, a hash input, or an execution replacement.

Optional `request.open_sources` maps each incompletely described source to its
sorted required column set. Checked field contracts remain in `source_schemas`;
unknown fields gain no inferred type. Pass-through operations preserve those
fields, while every expression still requires its own type evidence. Derive
rejects collisions with required or actual input fields; group closes its
output. `output_open` and `output_schema` are regenerated at admission. Runtime
validates required columns, known contracts and all actual value ceilings.

`request.null_contexts` optionally maps derive step IDs and output names to
nullable checked contracts for literal NULL roots. The source remains NULL;
the lowered node is `typed_null`. Program checking derives these contexts only
from the append-peer or explicitly mapped nullable ModelTask rules in
[Closed value contracts](#value-contracts), through field projection, rename
and row-preserving steps. Conflicting contexts or missing evidence fail;
arbitrary later computations and Effects supply no type evidence.

For text-time calls, `request.text_time_policy` contains the closed
`actql-text-time-host-policy/0.1` value; its CID is the envelope's
`host_policy_profile_cid`. `evaluations` lists every profile occurrence once,
sorted by `envelope.expression_pointer`, or is empty when none occur.
Each entry's `node_pointer` addresses `/roots/<index>/node`; its envelope
addresses the corresponding `/roots/<index>/source` occurrence and binds that
root's `step_id` and regenerated demand path, including its aggregate filter.
Admission regenerates the envelopes, pointers, argument CIDs and bounds.
Known literal or checked source extents prove input bounds; otherwise a
demanded expression performs input preflight against the selected Host ceiling.
Successful results satisfy the output ceiling. These checks introduce no I/O.

The group binding admits the complete [group aggregate vocabulary](#group),
with an `expr` root and optional own `filter`. `count_if` requires
a boolean argument and counts only true values; it does not admit `distinct`.
Distinct is admitted only by each aggregate's declared signature, preserving
first occurrence before the pinned fold. `avg` accepts number, not decimal. Decimal `sum` has precision
38 and preserves scale; `array_agg` retains order and its positive guard.

The `limits` list contains a Resolved limit for each request ceiling and each
aggregate `max_items` or `max_bytes`, ordered by its RFC6901 `request_pointer`. Each limit
has that pointer as `subject_ref`, a `contract_ceiling` witness binding the
canonical request CID and pointer, law `actql.expression-fragment.capacity`,
source derivation and that request CID as its sole dependency. Enforcement is
`engine_atomic`, breach is `fail`; units are `rows`, `bytes`, and `array_items`
respectively. These are declared ceilings, not estimated or proven row counts.
Admission regenerates these witnesses and limits alongside the graph.
The capacity law is registered by the expression 0.1 contract for this
fragment's admission. Admission uses that pinned law and its witness contract.

<!-- requirement-block: common-expression-contract.composition-registration common-expression-contract.composition-dependencies common-expression-contract.composition-capability -->
The selected pipeline registry MUST register `ACTQL.expression_fragment/0.1`
with its one-Relation-input/output signature and the execution contract at
`spec/contracts/actql-aoa.json#/execution_contracts/ACTQL.expression_fragment~10.1`.
That contract pins both the expression contract and its existing fragment schema;
schema references MUST resolve against those pinned bodies, not a network lookup.
A consumer MUST reject a missing registration, mismatched contract or dependency
CID, or unsupported execution capability. Registration is not whole-Program
completion or execution authorization; sealed-fragment re-admission and all
required runtime checks remain mandatory.

<!-- requirement-block: common-expression-contract.relation-root-slots -->
| AoA consumer | Root pointer relative to `params` |
| --- | --- |
| `REL.derive` | `/exprs/<escaped-output-name>` |
| `REL.derive` ordered row-kernel alternative | `/bindings/<index>/expr` |
| `REL.where`, `REL.assert_all` | `/expr` |
| `REL.groupBy`, `REL.window.project` | `/aggs/<escaped-output-name>/expr` |
| Either aggregate consumer's filter | `/aggs/<escaped-output-name>/filter`, when present |

Names use RFC6901 escaping. The `roots` array follows canonical graph step
order, then code-unit order of the parameter pointer within each step. Each
entry binds `step_id`, `parameter_pointer`, canonical `source`, lowered `node`,
checked `contract` and `demand_paths`. The inline graph node equals that root's
node. Semantic pointers address `/roots/<index>/source`, not the differently
shaped lowered node. An aggregate argument prepends its own filter root's
`true` test to every inherited path. The filter has no self-demand.

<!-- requirement-block: common-expression-contract.fragment-readmission common-expression-contract.fragment-capability -->
Fragment admission MUST recheck the bound request and require exact equality
of the canonical graph, root set and ordering, types and demand paths. A valid
self-CID or schema alone is insufficient. An implementation MUST reject a
consumer or expression revision outside its declared binding capability;
this Relation binding does not implicitly assign root positions to graph,
temporal, vector or Effect consumers.

Graph and temporal conditions use `actql-predicate-consumer/0.1`, carried by
`ACTQL.predicate_consumer/0.1` with exactly `{consumer}` as params and the
underlying operation's carrier signature. Its request fixes the operation,
closed parameters, context schemas and expression ceilings. Roots are ordered
by RFC6901 pointer code-unit order, relative to `request.params`:

<!-- requirement-block: common-expression-contract.graph-temporal-root-slots -->
| Consumer | Condition pointer | Typed context |
| --- | --- | --- |
| `SGA.match_nodes` | `/where` | nodes |
| `SGA.match_edges` | `/where` | edges |
| `SGA.traverse` | `/hops/i/edge_where`, `/hops/i/node_where`; homogeneous `/edge_where`, `/node_where` | edges, nodes |
| `TEA.sequence.match` | `/pattern/i/where` | events |

Each root is a single `REL.where` fragment with source `input` and step
`condition`; its open-source requirements are the sorted context schema keys.
The consumer CID excludes only `consumer_cid`. Admission regenerates the whole
consumer and validates the pinned operation's structural constraints. Condition
evaluation follows that operation's traversal or matching demand, not a
prepass over unreachable graph elements. VEC has no scalar expression slot;
its filtered Relation input uses the Relation binding. Effect selectors remain
separate and restricted.

Aggregate evaluation follows canonical group order, aggregate output-name
order, and logical input-row order within each group. Each aggregate evaluates
its own filter before its argument; it does not share an unconditional
precomputed argument column with another aggregate. Value failure publishes no
partial operation output. Input admission remains independent of row demand.

An envelope pointer addresses the normalized semantic expression tree with
JSON Pointer escaping. Every child inherits the outer demand path; the following
tests are appended in the listed logical order.

<!-- requirement-block: common-expression-contract.demand-derivation -->
| Child | Additional tests |
| --- | --- |
| `if` condition | none |
| `if` then | condition `true` |
| `if` else | condition `not_true` |
| CASE condition i | each earlier condition `not_true` |
| CASE branch i | each earlier condition `not_true`, then condition i `true` |
| CASE ELSE | every condition `not_true` |
| coalesce operand i | each earlier operand `null` |
| aggregate argument | its own filter `true`, if present |
| other eager child; aggregate filter | none |

<!-- requirement-block: common-expression-contract.demand-validation -->
Admission MUST rederive demand paths from the expression tree and consumer
position and require exact equality, not merely valid pointers or self-CIDs.
Tests reference values already evaluated in the same row and evaluation frame;
demand testing never reevaluates a condition or operand.

Within one expression frame, failure priority follows its prescribed child
evaluation order. For a derive operation it is logical input-row order, then
canonical output-field-name order, then expression evaluation order. Parallel
completion order does not choose the representative value failure. Failed
operations publish no partial output; this is not a Run-wide or cross-Effect
transaction guarantee.

Text and structured input pass through the same alias normalization and closed
node validation. `left.id`, `"left.id"`, and qualified `{field: "left.id"}` all
normalize to a join-field node; `"left".id` remains property access on the
ordinary field `left`. Quoting suppresses the lexical qualifier, not subsequent
whole-field alias normalization. Normalization is idempotent, including
after mixed printing. Intake byte, token, node and actual AST-depth limits are
distinct from evaluation budgets; exceeding a declared intake limit produces
a stable diagnostic, never truncation or a partial tree. Structured input has
the same tree limits; opaque literal payloads are counted but not parsed as code.

<a id="casts"></a>

### Explicit casts

<!-- requirement-block: casts.closed-conversions -->
| Cast target | Admitted non-null input | Value law / corresponding source function |
| --- | --- | --- |
| NUMBER | string or number | `to_number`; number to number is identity |
| STRING | string, number, decimal, boolean, timestamp, date | `to_string` canonical spelling |
| BOOLEAN | string or boolean | `to_boolean`; boolean to boolean is identity |
| TIMESTAMP | string or timestamp | `to_timestamp`; timestamp to timestamp is identity |
| DECIMAL(P,S) | string, safe-integer number, decimal | `to_decimal`; exact same P/S is identity; otherwise exact conversion without rounding |

Target names are ASCII case-insensitive and normalize to lowercase type names.
Decimal P/S are integer literal type arguments under [Exact decimal values](#decimal-values).
`CAST(NULL AS target)` supplies that nullable target without evaluating a
conversion. Other null operands propagate after input-type checking. No
reference, object, array, json, or vector cast is supplied by this table.
Same-type acceptance also applies to corresponding `to_*` calls, so equivalent
spellings have the same tree. `DATE`, `::`, and arbitrary SQL type names are
not cast targets in this revision. Decimal/binary64 fractional mixing remains
invalid; `CAST('0.1' AS DECIMAL(2,1))` is exact, while casting binary64 `0.1`
fails if evaluated. `quantize` remains the explicit rounding operation.

Conversion diagnostics distinguish static source/target incompatibility from
evaluation-time domain failure. Repair candidates may suggest an explicit cast
or parameter, but never automatically choose decimal P/S, rounding, or replace
a binary64 value with text claiming the author's original exact decimal intent.

<a id="typed-access"></a>

### Typed access

Property and subscript access apply to any typed expression, including
`items[0].sku` and `coalesce(primary_address, backup_address).city`. They are
pure row-local value operations, not provider navigation or Relation expansion.
Property names are static AuthoredFieldNames; receivers must have a complete
object type. Subscripts require an array receiver and a number expression;
the index is checked at evaluation as a non-negative safe integer without
rounding. Arrays are zero-based, independently of SQL-named string functions.
Receiver then index are evaluated once, eagerly; invalid/null indexes fail
even if the receiver is null. Negative or fractional literal indexes are
evaluation-time domain failures, not static signature constraints.

<!-- requirement-block: typed-access.outcomes -->
| Condition | Outcome |
| --- | --- |
| null object receiver with a statically declared property | null |
| property absent from closed schema | static rejection |
| declared property absent from admitted data | input contract violation |
| null array and valid index | null |
| non-negative safe integer index outside array length | null |
| negative, fractional, unsafe, or null index | evaluation failure |
| untyped json or opaque-reference receiver | static rejection |

Property nullability is the OR of receiver and property nullability.
Subscript results are conservatively nullable, retain the item contract, and
do not infer a minimum length from `max_items`. An explicit empty-array node
therefore remains typed and always yields null for a valid subscript.

An unquoted leading `left.` or `right.` is always a join qualifier, never a
schema-dependent guess. It requires that join scope and selects its following
field; later dots are object properties. `left.customer.city` therefore means
property city of the join-left customer field. `"left".city` means property
city of the ordinary field left. Missing join scope is an error, not a fallback.
Property names after a receiver do not create another qualifier. The printer
quotes an ordinary receiver field named left/right when followed by access.

<a id="decimal-expressions"></a>

### Decimal expressions

<!-- requirement-block: decimal-expressions.implementations-must-validate-decimal-precision-scale-coefficient-explicit-rounding-and -->
Implementations MUST validate decimal precision, scale, coefficient, explicit
rounding, and the prohibition on implicit binary64 mixing before publishing results.

The four expressions have these text forms (shown as `derive` entries):

```yaml
amount: "to_decimal(amount_text, 18, 2)"
maybe_amount: "try_decimal(amount_text, 18, 2)"
tax: "quantize(raw_tax, 18, 2, 'half_up')"
daily: "decimal_divide(total, 31, 18, 2, 'half_even')"
```

For example, the structured form of `tax` is:

```yaml
tax:
  quantize:
    value: {field: raw_tax}
    precision: 18
    scale: 2
    rounding: half_up
```

Conversion accepts decimal values, safe integers, or text matching
`-?(0|[1-9][0-9]*)(\.[0-9]+)?`. Exponents, leading `+`, grouping, currencies,
negative zero, excess fractional digits, and overflow are rejected without
rounding. `try_decimal` makes only invalid/unrepresentable conversion input
null. Null inputs propagate. Only `quantize` and `decimal_divide` round, using
`half_even|half_up|toward_zero|floor|ceiling`. Division by zero fails.

`decimal_divide` requires a decimal left operand and a decimal or safe-integer
`number` right operand. A number divisor is interpreted exactly as an integer;
fractional or unsafe-integer numbers are rejected. This is an explicit function
contract, not an implicit decimal/binary64 conversion for other operators.

`add`, `subtract`, `multiply`, and comparison accept two decimals without
binary64 mixing. Addition/subtraction use scale `max(S1,S2)` and precision
`min(38,max(P1-S1,P2-S2)+scale+1)`; multiplication uses scale `S1+S2` and
precision `min(38,P1+P2)`. An unrepresentable scale or coefficient fails.
`sum` returns precision 38 at the input scale; `min`/`max` retain the type.
Decimal `avg` is rejected: use `sum`, `count`, and explicit `decimal_divide`.
Branches and array elements require one compatible closed decimal type;
explicit `quantize` resolves different precision/scale choices.

<a id="value-construction"></a>

### Object and array construction

<!-- requirement-block: value-construction.implementations-must-preserve-closed-object-array-types-and-reject-unknown-constructor -->
Implementations MUST preserve closed object/array types and reject unknown
constructor fields, heterogeneous elements, and hidden capability references.

`{object: {static_name: Expression, ...}}` builds a closed, non-empty product;
all named properties are present, including nullable properties. Field names
use the same closed schema rules as relation fields. Computed keys, spread,
merge, omission, opaque JSON, and hidden ResourceRef/ArtifactRef values are
not admitted. Key order is canonical for identity, not an author-selected
semantic order. Classification/provenance includes every child dependency.

`{array: [Expression, ...]}` builds a finite sequence with one
homogeneous recursively compatible value contract; its source length proves
the item bound. Dynamic collections use `array_agg` or `nest` ([nest](#nest)), expansion uses `unnest`,
and `json_pick` derives types from closed object paths. Size proofs use child
contracts or the checked Host envelope when child sizes are unresolved.
Effects remain field/literal consumers of named Results; nested payload
construction happens in preceding computation, not inside an Effect.
The empty form is legal only with the unique type evidence defined in
[Closed value contracts](#value-contracts), or explicit `empty_array.items`.
Aggregation and `nest` retain their operation-defined typed empty cases;
no empty array is guessed to be json or left dynamically untyped.

<a id="text-time"></a>

### Text, time, and regular expressions

The optional `actql-text-time/0.1` pure scalar profile adds exactly
`split_part`, `substring`, `utf8_truncate`, `try_number`, `parse_timestamp`,
`format_timestamp`, `regex_match`, `regex_extract`, `regex_replace`, `nfkc`,
`case_fold`, and `try_timestamp`.
Profile admission follows [Conformance profiles](conformance.md#conformance-profiles).

<!-- requirement-block: text-time.implementations-must-use-those-pinned-definitions-as-the-semantic-authority text-time.host-library-icu-and-locale-defaults-must-not-define-normalization -->
This profile pins its Unicode tables, timestamp grammar, and regex grammar.
Implementations MUST use those pinned definitions as the semantic authority.
Host library, ICU, and locale defaults MUST NOT define normalization, folding,
or pattern syntax.

> **Note (informative):** A library can implement the pinned definitions; using
> a library is not itself a fallback. Its environment-dependent defaults do
> not determine ActQL semantics.

```yaml
- derive:
    region_code: "split_part(external_key, '-', 1)"
    short_name: "substring(display_name, 1, 40)"
    export_name: "utf8_truncate(display_name, 120)"
```

<!-- requirement-block: text-time.it-must-not-split-a-unicode-scalar -->
`split_part` and `substring` use the one-based Unicode-scalar positions defined
below; array subscripts remain zero-based. String position/length arguments
are number expressions checked at evaluation as safe integers without rounding.
`utf8_truncate` requires a non-negative safe integer byte limit and returns the
greatest prefix whose UTF-8 encoding is within `max_bytes`. It MUST NOT split a
Unicode scalar.

<!-- requirement-block: text-time.sql-string-boundaries -->
| Function / condition | Value rule |
| --- | --- |
| `split_part(s,d,i)` | literal or parameter string delimiter; split by non-overlapping literal matches preserving empty parts; i > 0 counts from 1, i < 0 counts backward from the final part |
| `split_part`: i = 0 or non-integer/unsafe i | evaluation failure |
| `split_part`: part outside range | empty string, not null |
| `split_part`: empty delimiter | one part containing the whole string |
| `split_part`: empty input | one empty part |
| `substring(s,start,length)` | retain scalar positions j with 1 <= j <= len(s) and start <= j < start + length; interval arithmetic is exact |
| `substring`: length = 0 or no retained positions | empty string |
| `substring`: start <= 0 | same interval intersection; e.g. substring('abcd',0,2) = 'a' |
| `substring`: negative length, non-integer/unsafe start or length | evaluation failure |
| either function: any null operand | null, after eager operand evaluation |

All returned strings undergo canonical normalization. No locale, collation,
provider, or Host compatibility mode changes these rules. The admitted
overload is the displayed fixed arity; SQL regex-substring overloads are not added.

```yaml
- derive:
    parsed_at: "parse_timestamp(local_datetime, 'yyyy-MM-dd HH:mm:ss')"
    maybe_amount: "try_number(amount_text)"
- derive:
    export_at: "format_timestamp(parsed_at, 'yyyyMMddHHmmss')"
```

<!-- requirement-block: text-time.missing-time-components-must-resolve-to-actql-defined-zero-values-not -->
The profile uses the finite grammar artifact
`spec/grammar/actql-timestamp-pattern-0.1.ebnf` and its closed canonical AST.
Fixed-duration and text-time operations have a fixed UTC timezone and no
timezone author field, TZDB, or locale dependency. Only the explicit calendar
profile uses its admitted timezone and pinned TZDB; those settings never flow
into ordinary timestamp conversion or date arithmetic. `parse_timestamp` requires
`yyyy`, `MM`, and `dd` exactly once; `HH` and `mm` occur together, `ss`
requires both, `SSS` requires `ss`, duplicate semantic tokens are forbidden,
the whole input is consumed, and an invalid calendar value fails.
Missing time components MUST resolve to ActQL-defined zero values, not host defaults:
absent `HH`/`mm` means `00:00`, absent `ss` means `00`, and absent `SSS`
means `000`. Parsing uses the proleptic Gregorian calendar, UTC, and the
closed year range `0000..9999`.
`format_timestamp` is locale-independent. `try_number` uses the same canonical
number grammar as `to_number`, but returns null instead of failing for a
non-null unparsable string.

<!-- requirement-block: text-time.timestamp-pattern-modes -->
Timestamp patterns MUST be nonempty sequences of the admitted components;
both parse and format modes reject duplicate semantic tokens and apply the
`HH`/`mm`, `ss`, and `SSS` dependencies above. Only parse mode requires `yyyy`,
`MM`, and `dd`. Format mode admits a pattern consisting solely of the admitted
literals, producing that literal text for a non-null timestamp. Literal
components retain their individual occurrences in the canonical AST, without
coalescing or reordering. An empty pattern is not a literal-only pattern.

<!-- requirement-block: text-time.every-text-time-barrier-also-binds-a-versioned-host-ceiling-the text-time.if-a-finite-admitted-envelope-cannot-be-established-the-unit -->
Text, pattern, replacement, and output resource bounds are not expression
arguments. The compiler derives the strongest envelope available from the
field contract and resolved literal or parameter values. Every text/time
expression also binds a versioned Host ceiling; the derived input codepoint and
UTF-8 extents MUST fit that ceiling, including literal and contract-bounded
inputs. Runtime-bound input is rechecked against the same ceiling when the
expression is demanded, before evaluation. If a finite admitted envelope cannot be established, the unit is
rejected before evaluation; a runtime MUST NOT silently substitute unbounded
host string, time, or regex behavior.

<!-- requirement-block: text-time.hosts-must-implement-that-law-rather-than-a-local-estimate text-time.without-that-ceiling-check-must-not-issue-a-checked-plan -->
Every checked expression binds one machine-only
`actql-text-time-evaluation-envelope/0.1` containing the semantic step, canonical
expression pointer, demand path, and
operation, input codepoint and UTF-8 extents with an evidence CID, parsed
pattern-AST CID and byte extent where applicable, canonical replacement-AST
CID, literal byte total, capture-reference count and maximum capture index,
replacement-count and output-byte ceilings, verification phase, current Host
policy-profile CID, and a self CID. Each canonical AoA Fragment binds these
envelopes in expression-pointer order, including expressions inside conditions,
constructors and aggregate arguments. No derive-only acquisition barrier is
introduced. The portable bound law is versioned as
`actql-text-time-bound-laws/0.1`; Hosts MUST implement that law rather than a
local estimate. Every text/time expression requires a versioned Host ceiling in
the checked Plan; runtime-bound strings are additionally rechecked at their
demanded evaluation boundary. Without that ceiling, Check MUST NOT issue a checked Plan.

Demand paths preserve selected conditional branches, earlier coalesce null
tests, and the containing aggregate's filter. Moving a pure profile call into
another physical unit preserves that same row mask and first-failure order.
Expression-local enforcement is not performed on undemanded rows. Input
admission, static pattern checks, and whole-unit limits retain their separate
scopes and cannot be bypassed by lazy evaluation. Logical output/size bounds
use the pinned Unicode/regex/time laws with the string rules above;
physical scheduling and resource consumption are not deterministic logical charges.

For substring and split_part, the canonical conservative output-byte ceiling is
the input UTF-8 ceiling. Substring tightens it to `min(input_bytes, 4 * length)`
only for a bound nonnegative safe-integer literal length. `utf8_truncate`
similarly uses `min(input_bytes, max_bytes)` for a bound nonnegative safe-integer
literal limit, otherwise the input ceiling. These calculations use exact
integer arithmetic before comparison with Host limits. Dynamic lengths and
invalid conversion-data literals do not trigger speculative evaluation or a
new static rejection; their domain checks occur only on demanded rows.
Other output-bound formulas retain the pinned base profile's laws. Each parent
consumes its children's checked extents, including nullable outputs, rather than
requiring those children to be named columns. Envelope self-CIDs exclude only
their self-CID field; argument CIDs bind the canonical argument subtrees.

<!-- requirement-block: text-time.input-evidence-preimages -->
Input evidence CIDs MUST hash the following complete canonical JSON preimages.
For `source: value_contract`, the preimage is the complete checked input value
contract. For `source: literal`, it is
`{version: "actql-literal-text-extent/0.1", value: V}`, where V is the resolved
canonical string, timestamp wire string, or known null. Selected Parameter
values use the same rule as literals; declaration metadata and binding origin
do not enter this extent identity. Known null has zero scalar and byte extent.
For `source: runtime_preflight`, the preimage is
`{version: "actql-text-time-runtime-preflight/0.1", contract: C, policy: P}`,
where C is the complete checked input contract and P is the complete selected
`actql-text-time-host-policy/0.1` value, not only its input ceilings.
A derived child output uses `value_contract` with its checked output contract.

<!-- requirement-block: text-time.input-evidence-applicability -->
This CID identifies the extent evidence content, not its applicability: the
owning expression, selected bindings, policy and child producer dependencies
MUST still be verified and retained. Equal contract CIDs do not discharge a
child's demanded runtime checks or authorize evidence from another Program.
These preimages contain no process-local handle or step index and are not
Program, Invocation, expression-argument or envelope identities.

<!-- requirement-block: text-time.check-must-parse-every-literal-or-bound-regex-and-timestamp -->
Regex expressions use `spec/grammar/actql-regex-0.1.ebnf` and the closed
`actql-regex-ast/0.1` schema. Check MUST parse every literal or bound regex and
timestamp pattern into its canonical AST and bind that AST's CID.
The admitted regex grammar contains literals, classes/ranges, captures,
alternation, anchors, dot, and greedy bounded/unbounded quantifiers. Lookaround,
backreferences, named captures, lazy quantifiers, Unicode property escapes,
and implementation-specific escapes are outside the grammar. Patterns are
literal or invocation-parameter values, not fields; recursion and
host-specific flags are forbidden.

<!-- requirement-block: text-time.regex-ast-scalars -->
Regex AST literal nodes MUST use the closed form `{kind: "literal", codepoint: n}`,
where `n` is one Unicode scalar integer (`0..1114111`, excluding `55296..57343`),
not a UTF-16 code unit or string. Assignment in the Unicode version is not
required. Character-class range `start` and `end` use the same scalar integer
domain, with `start <= end` and inclusive membership over the scalar universe.
Decoded `\\n`, `\\r`, and `\\t` therefore carry 10, 13, and 9 respectively.
Source pattern text retains its ordinary NFC/LF admission; decoded AST scalars
are not text-normalized. Literal nodes, class items, branches and captures
retain their prescribed occurrence order.

<!-- requirement-block: text-time.regex-ast-construction -->
Canonical regex AST construction MUST retain each capturing group, number
captures from one in opening-parenthesis order, and omit sequence/alternation
wrappers only when they have exactly one child. Empty patterns, groups and
alternation branches are invalid. A leading or trailing unescaped hyphen inside
a class is a literal; elsewhere inside a class it separates scalar range
endpoints. Outside a class, hyphen is a metacharacter and requires escaping.
Quantifier bounds are exact nonnegative integers with the grammar's canonical
decimal spelling. They are not rounded to fit AST numbers: a finite binary64
integer must represent the complete authored integer exactly, without an
additional safe-integer ceiling. A finite maximum is at least the minimum;
an omitted unbounded maximum is represented by null. Identical class items,
branches and repeated occurrences are not deduplicated.

<!-- requirement-block: text-time.regex-ast-identity -->
The regex AST CID MUST use ordinary canonical JSON of the complete AST body,
excluding only `ast_cid`. Numeric scalar representation preserves CR versus LF
and range endpoints without an exception to global canonical JSON rules.
Schema checking covers scalar domains and closed node shapes; capture numbering,
capture counts, range ordering and quantified-expression rules remain separate
semantic checks.

<!-- requirement-block: text-time.regex-ast-contract-binding -->
The expression contract's pinned `regex_ast_contract` MUST govern regex AST
representation and identity in preference to the inherited text-time profile's
older string-literal AST representation. Matching, source grammar, flags and
demand laws otherwise remain unchanged. Old string-valued literal nodes and
range endpoints are rejected, not silently converted or assigned the new CID.
A backend without this exact AST dependency and expression-contract support
cannot produce an executable Plan for it; the old registry is not relabeled as
supporting the new representation.

<!-- requirement-block: text-time.portable-regex-flags -->
Regex flags MUST be a string containing only `m` (anchors also match
U+000A line boundaries) and `s` (dot also matches U+000A), each at most once,
in either order. Omitted flags and the empty string both select neither flag.

<!-- requirement-block: text-time.regex-static-capture text-time.regex-static-replacement -->
The `regex_extract` capture argument MUST be a nonnegative integer literal or
an invocation parameter of number type. The `regex_replace` replacement argument
MUST be a string literal or an invocation parameter of string type. Neither
argument admits a row field or a computed expression, including a constant
expression. Check validates the resolved non-null parameter value and its
capture/replacement consistency with the admitted pattern before evaluation;
declaration-only type checking does not discharge that obligation.

The profile requires positive limits for input codepoints, pattern bytes, output bytes,
and replacements. `regex_extract` requires an explicit capture index and
returns null for no match; `regex_replace` applies a bounded left-to-right
global replacement. Its closed replacement grammar uses `$$` for a literal
dollar and `$1..$99` for captures; references to absent captures are rejected
at Check, while an unmatched admitted capture expands to the empty string. The
portable output ceiling accounts for every literal and repeated capture
expansion. A limit breach fails atomically.

<!-- requirement-block: text-time.replacement-tokenization -->
Regex replacement tokenization MUST consume `$$` as one literal dollar, or a
dollar followed by one ASCII digit `1..9` and, when present, one further ASCII
digit `0..9` as a capture reference. Further digits are literal text: `$100`
denotes capture 10 followed by literal `0`, not capture 100. Other dollar
forms, including `$0`, `$01`, a bare dollar and `${1}`, are invalid. Backslash
has no special replacement meaning. The canonical replacement AST coalesces
adjacent literal text, including decoded `$$`, into one nonempty literal part;
capture parts retain their order and repetition. An empty replacement has an
empty parts array. Its literal UTF-8 byte total, capture reference count and
maximum capture index (zero with no references) describe these parts, not the
source spelling or a deduplicated set of captures.

The operation/input matrix is closed: `split_part`, `substring`,
`utf8_truncate`, `try_number`, `parse_timestamp`, `regex_match`,
`regex_extract`, `regex_replace`, `nfkc`, `case_fold`, and `try_timestamp`
consume strings; `format_timestamp` consumes a timestamp. `parse_timestamp`
preserves input nullability. `try_number` and `try_timestamp` have nullable
output because input parse failure produces null.

<!-- requirement-block: text-time.it-must-return-null-for-invalid-calendar-input-text text-time.an-invalid-pattern-bound-breach-or-engine-failure-must-fail -->
`nfkc` uses Unicode 16.0.0 compatibility normalization; `case_fold` uses full
default C/F mappings, not locale-specific T mappings. Both return NFC. The
profile pins the vendored Unicode table CID and derives expansion ceilings
from those tables (18 decomposed scalars for NFKC, 4 for full folding/NFC per
input scalar). `try_timestamp` uses the same UTC grammar as `parse_timestamp`.
It MUST return null for invalid calendar/input text. An invalid pattern, bound
breach, or engine failure MUST fail the operation rather than produce null.
Null input propagates after the pattern has been checked.

<!-- requirement-block: text-time.a-quantified-subexpression-must-consume-at-least-one-unicode-scalar -->
A quantified subexpression MUST consume at least one Unicode scalar on every
successful match. Check rejects quantified anchors and any quantified capture,
sequence, alternation, or repeat whose canonical AST is nullable; this keeps
the grammar and the finite matcher state space identical across runtimes.

<!-- requirement-block: text-time.implementations-must-use-the-exact-actql-regex-sets-and-boundaries text-time.all-actql-strings-and-object-keys-must-reject-unpaired-utf-16 -->
Implementations MUST use the exact ActQL regex sets and boundaries below.
Regex shorthand classes are exact ASCII sets: `\\d` is `0..9`, `\\w` is
`A..Z`, `a..z`, `0..9`, and `_`, and `\\s` is TAB, LF, VT, FF, CR, and SPACE.
Their uppercase forms are complements over the Unicode scalar universe. Dot
excludes only LF unless `s` is set. With `m`, anchors use document or LF
boundaries; CR remains an ordinary scalar, including in CRLF. An unmatched
capture is null and expands to the empty string in `$1..$99` replacement.
All ActQL strings and object keys MUST reject unpaired UTF-16 surrogates.

<a id="operations"></a>

## Operations

Each operation specifies its accepted Carrier, parameters, result, ordering,
and failure conditions. Shared expressions are defined in [Expressions and predicates](#expressions); author guards
and proof-derived execution limits are defined in [Author guards, resolved limits, and Plan facts](#resolved-limits).

Operation definitions use the following common contracts rather than repeating
them for each spelling:

<!-- requirement-block: operations.concern-normative-home-authoring-shape-and -->
| Concern | Normative home |
| --- | --- |
| Authoring shape and name scope | [Structural grammar (normative)](#structural-grammar), [Pipeline names and references](#pipeline-references), and the operation's definition |
| Required evidence and recursive result types | [Closed value contracts](#value-contracts), [Local typed inputs](#local-inputs), and operation-specific preconditions |
| Identity, ordering, and completeness propagation | [Evidence propagation](#evidence-propagation); canonical key selection in [Deterministic completion](#completion) |
| Bounds and enforcement boundary | [Author guards, resolved limits, and Plan facts](#resolved-limits) and the operation's measured scope |
| Failure and atomic publication | Operation-specific failures and [Capture, execution, and replay](execution.md#capture-and-replay) |
| Canonical lowering | [AoA fragments and algebra lowering](#algebra-lowering) and the pinned AoA contract ([Common AoA foundation](#aoa-foundation)) |

<a id="operation-inventory"></a>

### Operation inventory

Family is an author-visible functional grouping, not an AoA opcode namespace
or a profile identifier. Search/text_rank belongs to actql-text-rank/0.1 and
lowers to REL.text_rank; Calendar belongs to actql-calendar/0.1 and lowers to
the specified TEA calendar opcodes. Acquisition/search_candidates is a typed
barrier, not an algebra opcode. Profile claims and registry admission are
checked independently of this display classification.

ActQL has exactly one source spelling for each operation. The complete
canonical vocabulary is:

<!-- requirement-block: operation-inventory.family-operation-input-output -->
| Family | Operation | Input -> output |
| --- | --- | --- |
| RelA | [`filter`](#filter) | relation -> relation |
| RelA | [`select`](#select) | relation -> relation |
| RelA | [`rename`](#select) | relation -> relation |
| RelA | [`drop`](#select) | relation -> relation |
| RelA | [`derive`](#derive) (snapshot map or ordered array) | relation -> relation |
| RelA | [`sort`](#sort) | relation -> relation |
| RelA | [`take`](#take) | relation -> relation |
| RelA | [`top_k`](#top-k) | relation -> relation |
| RelA | [`top_k_by`](#top-k) | relation -> relation |
| RelA | [`row_window`](#event-windows) | relation -> relation |
| RelA | [`window_group`](#relational-temporal) | relation -> relation |
| RelA | [`lag`](#relational-temporal) | relation -> relation |
| RelA | [`watermark_rows`](#relational-temporal) | relation -> relation |
| RelA | [`pivot`](#reshaping) | relation -> relation |
| RelA | [`unpivot`](#reshaping) | relation -> relation |
| RelA | [`json_pick`](#reshaping) | relation -> relation |
| RelA | [`unnest`](#reshaping) | relation -> relation |
| RelA | [`join`](#join) | relation x relation -> relation |
| RelA | [`nest`](#nest) | relation x relation -> relation |
| RelA | [`group`](#group) | relation -> relation |
| RelA | [`distinct`](#distinct-and-dedupe) | relation -> relation |
| RelA | [`dedupe_rows`](#distinct-and-dedupe) | relation -> relation |
| RelA | [`assert_rows`](#assert-rows) | relation -> relation |
| RelA | [`append`](#append) | relation x relation -> relation |
| RelA | [`values`](#values) | none -> relation |
| RelA | [`except`](#row-set-operations), [`intersect`](#row-set-operations) | relation x relation -> relation |
| RelA | [`cross_join`](#cross-join) | relation x relation -> relation |
| RelA | [`analytic`](#analytic) | relation -> relation |
| SGA | [`normalize_graph`](#structural-graphs) | graph -> graph |
| SGA | [`match_nodes`](#graph-property-match) | graph -> relation |
| SGA | [`match_edges`](#graph-property-match) | graph -> relation |
| SGA | [`traverse`](#traverse) | graph x optional selector relation -> relation |
| SGA | [`shortest_path`](#shortest-path-and-components) | graph x up to two selector relations -> relation |
| SGA | [`components`](#shortest-path-and-components) | graph -> relation |
| SGA | [`reach`](#reach) | graph -> relation |
| SGA | [`graph_bounds`](#structural-graphs) | graph -> relation |
| SGA | [`degree`](#degree) | graph -> relation |
| SGA | [`graph_diff`](#structural-graphs) | graph x graph -> relation |
| SGA | [`graft_graph`](#structural-graphs) | graph x graph -> graph |
| SGA | [`union_graphs`](#structural-graphs) | graph x nonempty finite graph list -> graph |
| SGA | [`subtract_graphs`](#structural-graphs) | graph x graph -> graph |
| SGA | [`subgraph`](#subgraph) | graph x optional relation -> graph |
| SGA | [`graphs_equal`](#graph-equality-and-delta) | graph x graph -> relation |
| SGA | [`apply_graph_delta`](#graph-equality-and-delta) | graph x relation -> graph |
| SGA | [`mean_graphs`](#graph-mean) | finite graph list -> graph |
| TEA | [`window_events`](#event-windows) | events -> events |
| TEA | [`watermark_events`](#event-bridges) | events -> events |
| TEA | [`session`](#session) | relation -> relation; events -> events |
| TEA | [`time_series`](#time-series) | none -> relation |
| TEA | [`interval_join`](#interval-join) | relation x relation -> relation |
| Calendar | [`calendar_bucket`](#calendar), [`calendar_series`](#calendar) | relation -> relation; none -> relation |
| TEA | [`dedupe_events`](#dedupe-events) | events -> events |
| TEA | [`asof_join`](#asof-join) | relation/events x relation -> relation |
| TEA | [`sequence`](#sequence) | relation/events -> relation |
| VecA | [`normalize_vectors`](#vector-bridges) | vectors -> vectors |
| VecA | [`score_vectors`](#vector-bridges) | vectors -> vectors |
| VecA | [`nearest`](#nearest) | relation/vectors x relation/vectors -> relation |
| VecA | [`pool_vectors`](#pool-vectors) | relation/vectors -> vectors |
| VecA | [`merge_rankings`](#merge-rankings) | relation x relation (RRF: nonempty finite relation list) -> relation |
| Bridge | [`graph`](#graph-construction) | relation x relation -> graph |
| Bridge | [`node_rows`](#graph-rows) | graph -> relation |
| Bridge | [`edge_rows`](#graph-rows) | graph -> relation |
| Bridge | [`to_events`](#event-bridges) | relation -> events |
| Bridge | [`events`](#event-bridges) | events -> relation |
| Bridge | [`to_vectors`](#vector-bridges) | relation -> vectors |
| Bridge | [`vectors`](#vector-bridges) | vectors -> relation |
| Acquisition | [`infer`](#infer) | relation -> relation |
| Acquisition | [`search_candidates`](#candidate-search) | relation -> candidates and coverage relations |
| Search | [`text_rank`](#text-rank) | relation x relation -> relation |
| Artifact | [`serialize`](#serialize) | relation -> relation containing `artifact_ref` |

<!-- requirement-block: operation-inventory.implementations-must-not-execute-an-unknown-spelling-through-fuzzy-matching -->
Reserved operation, argument-key, scalar-function, predicate, Effect-kind, and
binding-form spellings are exact lowercase. Author-defined identifiers retain
case under [Pipeline names and references](#pipeline-references) and [Parameters and binding](#parameters). Case folding and conversion of spaces, dots, or
hyphens to underscores are not part of ActQL. Implementations MUST NOT execute
an unknown spelling through fuzzy matching or an undocumented synonym.

<!-- requirement-block: operation-inventory.a-compiler-must-reject-them-as-unknown-operations-authors-choose operation-inventory.the-compiler-must-not-turn-an-unknown-word-into-an -->
Bare `search` and bare `dedupe` are not ActQL vocabulary. A compiler MUST reject
them as unknown operations; authors choose the exact operation whose semantics
they require. The compiler MUST NOT turn an unknown word into an ambiguity
resolver or operation-discovery side channel.

`row_window` is the relation-in/relation-out window operation and
`window_events` is the event-stream-preserving operation; both require explicit
`kind`. `graph`, `nearest`, `row_window`, and the other declared semantic macros
may insert typed carrier bridges, but their computation remains AoA IR.
`infer` is an explicit typed external acquisition operation; `serialize` is an
explicit Artifact barrier. An ordinary `join` whose right side is a keyed
SourceView may lower to an `actql-lookup/0.1` acquisition barrier. These
barriers are not AoA algebra operations, hidden Connector callbacks, Effects,
or control-flow constructs.

The Grammar Manifest `operations` inventory is the complete author-visible
operation vocabulary. `ACTQL_INTEGRATION_PROFILE_CONTRACT` identifies the
corresponding optional production-profile contracts. Profile conformance and
unsupported-profile rejection follow [Conformance profiles](conformance.md#conformance-profiles). No operation outside these closed
contracts may execute as ActQL 0.1.

<a id="relation-operations"></a>

### Relation operations



<a id="filter"></a>

#### `filter`

`filter` accepts the one explicit predicate grammar in [Predicates](#predicates):

```yaml
- filter:
    and:
      - {eq: [{field: status}, {literal: open}]}
      - {gte: [{field: amount}, {literal: 100000}]}
```

Field-to-field and field-to-literal comparisons use the same binary form:

```yaml
- filter:
    lt:
      - {field: score}
      - {field: required_score}

- filter:
    lt:
      - {field: score}
      - {literal: required_score}
```

These are structured-form examples. Predicates also accept expression text
([Expression text](#expression-text)): `score < required_score` compares fields, while
`score < 'required_score'` compares a field with a string literal. Operand
expressions follow [Expressions and predicates](#expressions); names and literals are distinguished by syntax, not
inferred from their values.

`filter` lowers to `REL.where`.

<a id="select"></a>

#### `select`

Simple projection:

```yaml
- select: [id, status, amount]
```

Projection with deterministic renaming:

```yaml
- select:
    - opportunity_id: id
    - account_id
```

The map form means `{output_name: input_field}`. Projection order is semantic.
`select` lowers to `REL.select`.

<!-- requirement-block: select.duplicate-output-names-unknown-fields-or-dropping-every-field-must -->
`rename: {existing_name: new_name}` and `drop: [field, ...]` are convenience
forms that retain the remaining complete input shape and lower directly to
`REL.select`. They require a complete statically known field set. Duplicate
output names, unknown fields, or dropping every field MUST fail during check.

<!-- requirement-block: select.empty-rename-and-drop-are-identity-projections -->
Given a complete input schema, check MUST accept `rename: {}` and `drop: []`
as identity projections retaining every input field, including when the input
schema itself has no fields. The prohibition on dropping every field applies
to removing all fields from a nonempty input, not to preserving an already
empty input. This does not admit `select: []`. Accepting an identity projection
does not authorize deleting the authored operation or equating its semantic
identity with omission of the operation; ordinary lowering and identity rules
continue to apply. Repeated names in `drop` denote the same removal, not
duplicate output fields.

<a id="sort"></a>

#### `sort`

```yaml
- sort:
    - {score: desc}
    - {id: asc}
```

<!-- requirement-block: sort.each-key-must-follow-orderkey-in-and-specify-asc-or sort.nulls-is-required-in-that-form -->
Each key MUST follow `OrderKey` in [Structural grammar (normative)](#structural-grammar) and specify `asc` or `desc`. The
single-field map uses `last` for null placement where the AoA contract defines
that completion as exact. The explicit `{field, dir, nulls}` form selects
`first` or `last`; `nulls` is REQUIRED in that form. Null placement is
independent of ascending or descending direction. `sort` lowers to
`REL.orderByStable` for a nonempty authored key list.

<!-- requirement-block: sort.empty-sort-identity sort.empty-sort-no-completion sort.empty-sort-retained -->
Check MUST accept `sort: []` as an identity operation preserving row values,
multiplicity, schema, current order and existing evidence, including for empty
input. An empty sort MUST NOT perform candidate-key sorting or establish new
order evidence; it is an exception to the completion rule below. Acceptance
MUST NOT authorize deleting the authored operation or equating its semantic
identity with omission. Later consumers still apply their own order requirements,
including any candidate-key completion permitted for `take`.

<!-- requirement-block: sort.ordering-ties-that-can-affect-a-published-result-or-an sort.when-the-current-relation-retains-a-candidate-key-whose-fields sort.without-a-retained-candidate-key-the-compiler-must-not-invent -->
Ordering ties that can affect a published Result or an order-sensitive
operation MUST be resolved. For a nonempty authored sort, when the
current relation retains a candidate key whose fields all have a portable
order, the compiler MUST append missing key fields in ascending order as a
deterministic identity tie-break and journal
the completion. This does not invent a business field: it reuses proven
identity evidence. Without a retained candidate key, the compiler MUST NOT
invent a tie-break.

<!-- requirement-block: sort.primitive-stable-ties sort.compiler-completed-keys sort.stability-not-order-proof -->
`REL.orderByStable` MUST compare the supplied keys in their declared priority
and preserve input-relative order for rows equal on all keys, without adding
`valueCID` or any other implicit tie-break. The compiler MUST pass completed
explicit keys and their completion record to lowering; the primitive does not
perform candidate-key inference. An existing admitted total-order witness can
justify stable tie resolution where the consuming operation's rules permit it;
this is distinct from appending candidate-key fields. Stability alone MUST NOT
promote physical input enumeration into deterministic total-order evidence.
The empty-sort identity and evidence rules above remain unchanged.

<!-- requirement-block: sort.resolution-priority sort.retained-witness-ties sort.retained-witness-origin sort.unresolved-boundary sort.lowering-strategy -->
For nonempty `sort`, the compiler MUST prefer eligible candidate-key completion.
If no eligible candidate key exists but an applicable admitted total input-order
witness exists, it MUST resolve equal explicit-key tuples using only the relative
order established by that witness. The sorted output MUST identify this sort as
its order producer and retain the prior witness as a tie-resolution dependency,
not copy the prior order as if the complete input sequence were unchanged.
Projection hiding prior order fields does not itself invalidate a retained
occurrence-order witness. With neither strategy available, the compiler MUST
retain the order as unresolved and reject it at a boundary requiring total order.
The checked strategy, authored keys, completion record or exact owned prior
witness MUST be exposed to lowering without requiring order re-inference.
This fallback is specific to `sort`; it does not relax the separate candidate-key
requirements of `top_k` or `top_k_by`.

<a id="take"></a>

#### `take`

```yaml
- take: 20
```

The object form is `take: {count: 20, offset: 40}`; its count member is named
`count`, not `limit`.

<!-- requirement-block: take.the-value-must-be-a-positive-safe-integer take.the-input-must-already-have-a-proven-stable-order-from take.provider-return-order-alone-is-not-evidence-and-must-not -->
The count MUST be a positive safe integer. `take: n` and
`take: {count: n, offset: 0}` normalize to the same closed object;
`offset` defaults to zero and otherwise is a nonnegative safe integer.
Skip that many rows, then retain at most count rows; an offset beyond the
input yields empty output. `take` lowers to `REL.limit` with both values.
The input MUST already have a proven stable order from `sort`, `top_k`, an
ordered deterministic operation, admitted connector order evidence, or a
retained candidate key that the compiler can order by and journal.
Provider return order alone is not evidence and MUST NOT make `take` valid.

<a id="distinct-and-dedupe"></a>

#### `distinct`

```yaml
- distinct: true
```

removes duplicate complete rows. A key projection MAY be written as:

```yaml
- distinct: [customer_id]
```

<!-- requirement-block: distinct-and-dedupe.a-compiler-must-not-choose-a-representative-row-for-unspecified -->
Keyed distinct projects the declared keys before applying `REL.distinct`; it
does not retain unspecified fields. A compiler MUST NOT choose a representative
row for unspecified fields.

<!-- requirement-block: distinct-and-dedupe.distinct-occurrence-order -->
Distinct MUST retain the first occurrence of each equal complete row in existing
input order; keyed distinct applies this rule after the declared projection.
It does not sort surviving rows or select values for fields omitted by that
projection. Existing logical order is preserved, but provider arrival order
without evidence does not become a stable-order proof through deduplication.
This rule is independent of candidate-key propagation and does not introduce
a non-null scalar identity for arbitrary complete rows.

<!-- requirement-block: distinct-and-dedupe.nonempty-distinct-projection distinct-and-dedupe.distinct-no-empty-reinterpretation -->
A keyed `distinct` list MUST be nonempty and contain no repeated field
references, because it defines a projection with distinct output names.
Check MUST reject `distinct: []` rather than reinterpret it as `distinct: true`.
The list retains its authored projection order; these rules do not reject
empty runtime input or impose a scalar-only schema on whole-row distinct.

<!-- requirement-block: distinct-and-dedupe.equality-key-domains -->
Fields selected by keyed `distinct` and fields in `dedupe_rows.by` MUST belong
to the scalar or reference domains admitted by `KeyComparable`; nullable keys
are permitted. Object, array, json and vector fields are not admitted as these
explicit equality keys. This restriction does not apply to complete-row
`distinct: true`. Authored ordering keys separately follow `AuthorOrderable`.

Representative-row selection is a separate operation:

```yaml
- dedupe_rows:
    by: [customer_id]
    order_by:
      - {updated_at: desc}
      - {source_id: asc}
```

<!-- requirement-block: distinct-and-dedupe.by-and-non-empty-order-by-are-required distinct-and-dedupe.if-two-candidate-rows-for-one-key-tie-on-every distinct-and-dedupe.if-two-candidate-rows-for-one-key-tie-on-every.second -->
`by` and non-empty `order_by` are REQUIRED. The operation keeps the
first row in that order and fails an unresolved top tie; those are language
invariants rather than authoring fields and are recorded in the Plan.
The compiler lowers this to `REL.dedupeRows`. If two candidate rows for one
key tie on every authored order key, execution MUST fail; implementation row
order or CID MUST NOT silently choose the representative.

<!-- requirement-block: distinct-and-dedupe.global-dedupe distinct-and-dedupe.repeated-dedupe-keys distinct-and-dedupe.retain-dedupe-keys -->
Check MUST accept `dedupe_rows` with `by: []`, treating all input rows as one
global partition. Its required nonempty `order_by` selects the first existing
row; empty input yields zero rows, and a tie between top candidates fails under
the same rule as any other partition. No representative row is synthesized.
This differs from a global aggregate and from sort followed by take-one.
Check MUST accept repeated `by` references while checking each reference's
existence and applicable type requirements. The checked representation MUST
retain their authored order and repetitions without preimage deduplication;
repetition neither adds output columns nor proves uniqueness or resolves ties.

<a id="group"></a>

#### `group`

<!-- requirement-block: group.closed-calls group.empty-and-repeated -->
Aggregate calls MUST use the closed function-specific grammar below: `field`
and `expr` are mutually exclusive, and only row-count `count` may omit both.
String shorthand, `op`, function-name keys and `count_if.where` are not aliases.
Check MUST accept an empty `aggregates` map and repeated `by` references while
checking every input contract, reference and budget. An empty aggregate map
produces only the grouping fields, once each in first-occurrence order; repeated
conditions do not duplicate rows or strengthen uniqueness. With `by: []`, it
produces one empty object even on empty input. Authored repetitions and the
operation remain in the semantic source; no preimage deduplication, operation
deletion or identity equivalence with another operation is implied.

The `distinct` member accepts either boolean for `count(expr)`, `sum`, `avg`,
`array_agg` and `string_agg`; only `false` for row-count `count`, `min` and `max`;
and neither boolean for all other aggregate functions. No implicit cast is
performed. A unique fixed immediate input domain supplies literal NULL with
type evidence (for example number for `avg`, boolean for `count_if`, string for
`string_agg`), but overloaded input domains and unresolved child computations
receive no inferred type from the aggregate's result.

`array_agg` constructs a non-null array of non-null root items, retaining nested
nullability. Its item contract follows recursive value-construction rules:
opaque `json` and reference types, including those hidden in arrays or objects,
are not constructible here. In contrast, `first` and `last` select existing
typed values and may retain structured, opaque JSON and reference contracts;
their ordering keys independently satisfy AuthorOrderable. Aggregate capacity,
order completion and numeric observation obligations are not discharged by
static type checking alone.

```yaml
- group:
    by: [customer_id]
    aggregates:
      event_count: {fn: count}
      total_amount: {fn: sum, field: amount}
```

<!-- requirement-block: group.every-aggregate-must-have-an-output-name group.every-function-except-row-count-count-must-name-an-input-expression group.every-array-agg-must-declare-the-same-non-empty-order-by-the-compiler -->
Supported aggregate functions are `count`, `count_if`, `sum`, `avg`, `min`,
`max`, `array_agg`, and the [ordered and statistical aggregates](#additional-aggregates).
Every aggregate MUST have an output name. Every
function except row-count `count` MUST name an input expression or field.
`distinct: true` is admitted only for `count(expr)`, `sum`, `avg`, and
`array_agg` and the explicitly admitted additional aggregates; it is invalid
for row-count `count`, `count_if`, `min`, and `max`.
The fixed evaluation order is each aggregate's filter, its argument expression
on true rows only, null exclusion, canonical-value CID distinct, then stable
fold. Argument expressions are not hoisted before their filters. Separate
aggregates evaluate in canonical output-name order; each consumes rows in its
specified input order. Every `array_agg` MUST declare its own non-empty
`order_by`; these orders may differ between aggregates. The compiler applies
each after its own filter, without imposing one aggregate's order or demand
on another. Group
results are canonically ordered by the group keys in ascending AoA order,
including reference identity order ([Opaque reference values](#opaque-references)).
`group` lowers to `REL.groupBy` followed by that canonical group order.

<!-- requirement-block: group.its-order-must-retain-a-candidate-key-so-equal-authored group.a-breach-must-fail-the-aggregate-operation-without-publishing-a numeric-aggregates.product-88840cf32f93 numeric-aggregates.product-1f5f9b0e54d1 -->
Null group keys of the same declared type form one group. `by: []` is the
global aggregate and emits one group even for empty input. `count` counts rows;
`count` with an expression counts non-null expression values; `count_if`
counts only true and excludes false/null. `sum`, `avg`, `min`, and `max` ignore
null and return null when no non-null value exists. `min`/`max` require one
`AuthorOrderable` type ([Lexical and ordering rules](#ordering)). `array_agg` excludes null, applies `distinct`
equality by canonical value CID while retaining the first occurrence in the
authored stable order. `array_agg.max_items` is an author guard as defined in
[Author guards, resolved limits, and Plan facts](#resolved-limits), counting elements in each aggregate array after null exclusion and any
distinct step. Its resolved limit uses input proof, Host policy, and any
authored guard. Its order MUST retain a candidate key so equal authored keys
cannot choose a row by provider enumeration. A breach MUST fail the aggregate
operation without publishing a partial Relation or truncated array.

For groups containing binary64 sum/avg, lowering preserves the same checked
grouping and result contract but inserts typed numeric observation slots for
those aggregate values. Exact aggregates remain AoA computation; replay uses
the captured slot values. Describing group as `REL.groupBy` does not authorize
recomputing an observed floating reduction on replay.

<a id="numeric-aggregates"></a>

### Captured floating-point aggregates

Binary64 `sum` and `avg`, including their group, window_group, pivot and analytic
forms, use a compiler-inserted numeric observation boundary. Both local and
remote reductions MUST capture the admitted result before any downstream
filter, ordering, Result or Preview consumes it. Replay reuses that value,
never a newly computed approximation. Determinism is over the ObservationSet
including numeric observations, not merely over the original input rows.

Placement may choose a Contract-admitted reduction algorithm with its declared
rounding and error law; it cannot choose arbitrary opaque code. A numeric
contract fixes contributors, input type, filter demand, NULL/distinct semantics,
group/window identity, count, finite output, overflow and algorithm/error law.
Wrong groups, counts, domains or demand are not numerical tolerance. The closed
boundary does not authorize unrelated provider computation or additional egress.
No universal epsilon is inferred. Cancellation in `[1e16, 1, -1e16]` can produce
0 or 1 under different reductions; differences are not necessarily one last bit.

Numeric observations MUST bind the semantic aggregate slot, logical input
artifact, post-filter contributor evidence, group/window key, NULL/distinct
law, input type/count, adopted finite value, provider/kernel law and policy/cost
evidence. Slot identity precedes response capture and excludes future Stage
Invocation/Result CIDs. The logical Plan binds the aggregate and slot contract,
not future physical parallelism or response bytes. Different fresh placements
may change ObservationSet, Invocation and Result identities without changing
Program identity; same-observation replay cannot.

`count`, `count_if`, exact decimal sum, and a separately proved integer sum
retain exact semantics and final public-domain checks. Integer evidence requires
an admitted integer/range contract, not values that happen to look integral.
Integer sums use exact accumulation; an admitted integer average requires an
explicit result/rounding law. Decimal average is not introduced implicitly.
Decimal scale zero remains an explicit exact route. Min/max, ordered strings,
variance/percentile laws, VecA scores and graph means retain their own laws.
Scalar binary64 arithmetic is unchanged. Money and exact decisions should use
the explicit exact value domains, not assume approximate reduction invariance.

<a id="join"></a>

#### `join`

```yaml
- join:
    with: contracts
    kind: left
    on:
      - {left: organization_id, right: organization_id}
      - {left: account_id, right: crm_account_id}
    cardinality: many_to_one
    select:
      opportunity_id: left.id
      renewal_at: right.renewal_at
```

<!-- requirement-block: join.kind-is-required-and-must-be-one-of-inner-left join.kind-is-required-and-must-be-one-of-inner-left.second join.on-must-state-one-equality-key-or-a-non-empty-array -->
`with` names the right relation. `left` MAY explicitly replace the current
relation. `kind` is REQUIRED and MUST be one of `inner`, `left`, `full`, `semi`, or
`anti`. `on` MUST state one equality key or a non-empty array of equality keys;
same-name field shorthand is permitted. Arbitrary non-equality conditions are not part of this join;
bounded Cartesian products and temporal overlap use the separately specified
`cross_join` and `interval_join` operations.

<!-- requirement-block: join.explicit-selector-precedence join.validate-overridden-selector -->
Check MUST permit step-level `from` together with `join.left`: step `from`
selects the main input first, then `join.left` replaces it as the actual left
operand. Without step `from`, `join.left` replaces current and can establish
the left operand when current is unset. Both explicit selectors MUST resolve
to available Relation bindings under the ordinary name-scope rules; an invalid
`from` is not ignored merely because `join.left` overrides its selection.
The checked join's left input edge identifies the final selected operand,
not the overridden binding. The join output becomes current as usual.

<!-- requirement-block: join.repeated-equality-keys join.retain-equality-key-order -->
Check MUST accept repeated equality pairs and repeated use of one side's field
with different fields on the other side. Every pair is checked independently;
the checked representation MUST retain the authored pair order and repetitions.
Acceptance does not authorize deduplication of the operation's semantic preimage.

<!-- requirement-block: join.a-violated-uniqueness-assertion-must-fail-before-a-result-is -->
`cardinality` is an OPTIONAL validation assertion, not output semantics. It is
one of `one_to_one`, `many_to_one`, or `one_to_many`; it asserts uniqueness of
both sides, the right side, or the left side respectively. A violated uniqueness assertion MUST fail before a
result is accepted. This failure behavior is a language invariant, not an
authoring policy.

<!-- requirement-block: join.when-cardinality-is-omitted-the-compiler-must-derive-it-only join.when-neither-side-is-proven-unique-cardinality-remains-unproven-the -->
When `cardinality` is omitted, the compiler MUST derive it only when candidate
key evidence proves the join-key tuple unique on the left, the right, or both.
Uniqueness on both sides proves `one_to_one`; uniqueness only on the right
proves `many_to_one`; uniqueness only on the left proves `one_to_many`. When
neither side is proven unique, cardinality remains unproven; the compiler MUST
NOT infer `many_to_many`. A derived cardinality and its candidate-key proof,
including any SourceView Contract CID on which it depends, belong to the
Compiled Plan and are not source normalization. An authored cardinality is
recorded as an author assertion and requires the same fail-on-violation runtime
check.

Static uniqueness evidence and the authored assertion are combined per side.
A proven unique right side together with an asserted unique left side yields
`one_to_one`; the Plan retains both sources of evidence. The assertion does
not discard a stronger static proof.

<!-- requirement-block: join.a-breach-must-fail-the-join-before-publishing-its-output join.join-key-types-must-satisfy-keycomparable-under-the-resolved-schemas -->
Omitted `null_key` has the fixed SQL-style `no_match` language law and creates
no normalization entry. Explicit `null_key: no_match` is legal and normalizes
to the same canonical form as omission;
`null_key: fail` is the sole authored override and rejects a null key component
on either input. `max_output_rows` is an author guard as defined in [Author guards, resolved limits, and Plan facts](#resolved-limits),
counting joined output rows. Its resolved limit uses safe join-cardinality
transfer over both inputs, current Host policy, and any authored guard. A
breach MUST fail the join before publishing its output Relation. Join-key
types MUST satisfy `KeyComparable` ([Closed value contracts](#value-contracts)) under the resolved schemas; implicit coercion is
forbidden.

<!-- requirement-block: join.unqualified-field-access-on-a-raw-join-result-must-fail join.both-complete-typed-schemas-and-stable-identities-for-both-sides join.both-complete-typed-schemas-and-stable-identities-for-both-sides.second -->
Without `select`, join fields retain explicit `left.` and `right.` provenance.
These compiler-generated names are the sole exception to the authored flat
field rule in [Field names and nested paths](#field-paths); an author cannot declare a source field with either prefix.
Unqualified field access on a raw join result MUST fail as ambiguous. `semi`
and `anti` joins expose only left fields. `full` is the reconciliation join:
unmatched rows from either side are preserved, absent-side fields are null,
and output ordering follows the row-order contract below. Both complete typed
schemas and stable identities for both
sides are REQUIRED for `full`; the compiler MUST NOT synthesize them.

<!-- requirement-block: join.a-compiler-must-not-select-a-same-named-field-from-one -->
With `select`, every output field maps to a provenance-qualified source field,
and subsequent steps use the flat output names. A compiler MUST NOT select a
same-named field from one side by precedence.

<!-- requirement-block: join.nonempty-projection join.empty-projection-rejected join.multiple-projection-aliases join.retain-projection-aliases -->
An explicitly authored join `select` MUST be a nonempty map; `{}` MUST fail
during check. Omission retains the qualified output and is not an empty
projection. Check MUST permit distinct output names to select the same source
field, preserving its exact type and nullability in each output. Duplicate
output names remain invalid. Projection mappings MUST retain every alias;
accepting aliases does not itself prove candidate-key preservation.

Because object key order is not semantic, join `select` output names are
lowered in AoA canonical UTF-16 code-unit order. Authors control final column
order with the selected named result's `fields`.

<!-- requirement-block: join.null-keys-must-not-match-under-no-match -->
All join kinds have a fixed row-order contract. `inner` and `left` enumerate
left rows in their stable input order and matching right rows in stable right
input order; unmatched left rows remain in place for `left`. `semi` emits each
matching left row once and `anti` emits each unmatched left row, both in stable
left order. `full` uses the `left` order first and then unmatched right rows in
stable right order. Null keys MUST NOT match under `no_match`; `fail` aborts before
publishing output. Projection may hide key fields but does not erase the
runtime ordering evidence attached to the relation result.

Candidate-key preservation is separate from row ordering and follows this
closed table:

<!-- requirement-block: join.join-kind-cardinality-candidate-keys-preserved-before derive.product-84665ce46b6b -->
| Join kind | Cardinality | Candidate keys preserved before `select` |
| --- | --- | --- |
| `semi` / `anti` | any | left |
| `inner` | `many_to_one` | left |
| `inner` | `one_to_many` | right |
| `inner` | `one_to_one` | left and right, as separate keys |
| `inner` | neither side proven unique | left + right composite only |
| `left` | `many_to_one` / `one_to_one` | left |
| `left` | other | none inferred |
| `full` | any | none inferred |

Each input may have more than one candidate key. A `select` or rename retains
each key for which every field maps to one distinct output field. It may drop
one key while preserving another. Outer-join null extension is not evidence
for right-side uniqueness.

<a id="derive"></a>

#### `derive`

Computations and replacements belong to derive; closing the field set belongs
to [select](#select). Derive preserves input fields, row order and multiplicity.

| Body | RHS scope | Input-name collision | Binding order |
| --- | --- | --- | --- |
| map | operation-start input snapshot only | rejected | canonical UTF-16 output-name order |
| nonempty array of singleton maps | prior slot, otherwise input | allowed once per name | authored array order |

<!-- requirement-block: derive.empty-map-is-no-op -->
An empty derive map MUST be accepted, including with an empty input schema,
and preserves input values, schema, row order and row count. Input-contract and
budget checks still apply. No-op admission does not authorize operation deletion
or CID equivalence with an omitted operation. This rule does not require a
complete input schema for derive in general; the ordinary input contract applies.
The array form remains nonempty, with exactly one entry in every slot map.

<!-- requirement-block: derive.product-bbab978e258b derive.product-7852090b86a2 derive.product-8abbc7816d26 derive.product-74d1432fc5b5 derive.product-7a7bed99441f -->
All map expressions read the input, never siblings. Map keys are canonically sorted
before lowering to the existing `REL.derive`. An output name MUST NOT collide
with a visible input field in map form.

```yaml
- derive:
    - original_amount: "amount"
    - amount: "amount * $multiplier"
    - tax: "amount * $tax_rate"
    - total: "amount + tax"
- select: [id, original_amount, amount, tax, total]
  as: calculated
```

Array slots MUST be nonempty singleton maps with static flat field names and
common Expression RHSs. Output names are unique after NFC normalization.
Shadowing an input once is distinct from declaring the same slot name twice.
Reserved-name and prototype-safe field handling remains unchanged; lawful
`__proto__` and numeric-looking names are data, not dictionary instructions.
No spread, wildcard, dynamic LHS, slot metadata or sequential flag is added.
No `project` operation is registered by this revision.

For each row start with E0=input. Evaluate slot i against E(i-1), then bind
its name to that value to obtain Ei; publish En. Its own binding is not in
scope during its RHS. A previous slot wins over input; otherwise an existing
input wins even when a future slot uses that name. A name found only in a
future slot, or a self-definition without an input value, fails check.
Save an old value under a different name before shadowing to use it later;
there is no new `input.` namespace or implicit original-value accessor.

Checking MUST record each reference as the exact input field or earlier
value-version slot. A shadow takes its checked RHS type without coercion or
joining it to the old type. No type inference flows backwards from future
slots. Required input admission precedes shadowing, including a value that
will be overwritten. An otherwise admitted open input need not gain a
complete schema: retain unknown fields under its existing contract and require
the ordinary type evidence for every field actually read. Map collision
requirements are not relaxed by this rule.

Array output retains every input field unless shadowed, replacing a shadowed
field's value and type. Unmentioned fields remain. Object-key enumeration is
not a column-order identity law; final publication order is ResultDefinition.fields.
The authored slot sequence is semantic for evaluation and dependency identity,
not an implicit reordering of published columns.
For amount=10, multiplier=2, tax_rate=0.5 the example yields original_amount=10,
amount=20, tax=10, total=30; only the final select removes other input columns.
Selecting only final columns before derive may drop required raw fields or
refer to fields not yet created. Optional early projection must preserve all
input dependencies and admission, failure, bounds and policy obligations.
Result.fields may close publication shape without a final select, but does
not close the intermediate Relation.

Both forms MUST preserve row-major failure: logical row, canonical map name
or authored array slot, then common expression child order. Each demanded RHS
is evaluated once in one shared row frame; lazy unselected children remain
undemanded. Every authored slot retains its evaluation obligation even if a
later select drops it. A discarded division by zero still fails the operation.
Whole-Relation derive steps are not an equivalent expansion when they change
the representative failing row/slot. No partial row or slot is published.

Candidate keys whose values are unchanged remain. Computed replacement of a
key loses its proof even under the same name; an exact copy of the complete
non-null tuple to retained distinct aliases can preserve it. Row-position
witnesses may survive shadowing, but old sort-key proofs do not describe new
values. Field policy follows resolved value versions; replacement by a less
sensitive value does not erase required observation provenance or Relation
policy. Effects use the actual published target fields, not hidden old values.

Source normalization and printing MUST preserve map versus array shape,
normalizing only RHS expressions. Literal payloads and structural arguments
remain opaque. Map permutation is not array permutation. The common checked
row-binding contract records source shape, ordered `{name, expr}` slots,
input/prior-slot references, types, demand, retained input field contracts,
proofs and one failure scope. Array roots use `/bindings/i/expr`; input
references are `{input_field: name}`, earlier slots `{prior_slot: i}`.
The ordinary current Relation is the sole graph input. The map
AoA node shape remains unchanged. Ordered bindings require the pinned shared
row-kernel extension, not an unregistered opcode or Host row rewrite.

Input, root, output, live-value and total-work ceilings retain their existing
measurement scopes; slots do not reset budgets. Fusion with select must
preserve derive's logical retained-output limits.

<!-- requirement-block: derive.ordered-execution-registration -->
Ordered derive MUST use the `REL.derive` registration's `ordered_bindings`
execution extension, pinned at
`actql-aoa.json#/execution_contracts/REL.derive.ordered`. The closed params are
`{row_kernel_contract_cid, bindings, references}`. The CID selects that exact
extension, not a new opcode; `bindings` is a nonempty authored-order array of
closed `{name, expr}` entries using the existing machine expression nodes.
The legacy snapshot-map `exprs` representation is unchanged. An adapter lacking
this extension cannot interpret the alternative as legacy params.

<!-- requirement-block: derive.ordered-reference-table -->
The reference table MUST contain exactly one closed `{at, target}` entry for
every field-node occurrence, in binding order then semantic expression preorder.
The RFC6901 `at` pointer is relative to params and starts at `/bindings/i/expr`;
it never traverses literal payloads. Target is exactly `{input_field: name}` or
`{prior_slot: j}`. The field spelling and checked type agree with the target.
For binding i, the latest earlier slot of that name takes precedence; otherwise
the original input is selected. Missing, duplicate, reordered, extraneous,
self or future references are invalid, even when hashes match.

<!-- requirement-block: derive.ordered-fragment-source -->
In `fragment.request.pipeline`, an ordered `REL.derive` step MUST have exactly
`{id, in, op, params}`, with `params` exactly `{bindings: [{name, expr}, ...]}`.
The nonempty bindings retain authored order and unique canonical names; each
`expr` is the canonical normalized source Expression, not a machine expression
node. Parameter references remain source syntax, with checked bindings retained
in `request.parameters`; literal payloads remain opaque. Source params contain
no reference table, extension pin, contexts, limits or derive evidence. The
legacy map alternative remains exactly `{exprs: {name: Expression, ...}}`.
Request and graph preserve the same canonical step IDs, input edges and binding
names/order. Regeneration lowers the RHSs, adds the selected registry extension
CID and derives the machine reference table, rather than trusting those as
source assertions. Each root's `source` equals its corresponding source RHS.

<!-- requirement-block: derive.ordered-evidence-closure -->
A fragment with ordered nodes MUST carry `row_kernel_evidence` containing
`bindings`, `contexts`, `limits` and `shapes`: each referenced body once, in
self-CID order, with no unreferenced bodies. There is one existing
`actql-derive-binding/0.1` record per ordered node. Its node, input/output,
binding names and types, expression roots, contexts and limits are regenerated
from the same checked request. With no ordered nodes this member is absent.
Root-list serialization still follows graph order then pointer UTF-16 order;
it does not change authored binding evaluation order.

<!-- requirement-block: derive.ordered-evidence-preimages -->
For this extension, `checked_expression_cid` MUST hash the complete corresponding
fragment root, including its step ID, parameter pointer, source, node, checked
contract and demand paths. `context_contract_cid` resolves an
`actql-derive-row-context/0.1` body binding the same input contract and the exact
prefix of prior `{name, contract}` slots. Input/output contract CIDs resolve
`actql-derive-row-shape/0.1` bodies with known `fields`, sorted unique
`required_fields` and boolean `additional_fields`; known fields are a subset
of required fields. Unknown field types stay unknown. Context, shape and limit
self-CIDs omit only `self_cid`; no diagnostic spans enter these preimages.
Node identity includes its extension pin, never the evidence that names it.

<!-- requirement-block: derive.ordered-node-preimage -->
For ordered derive, `derive_binding.aoa_node_cid` MUST be the canonical JSON CID
of the complete corresponding `fragment.graph.steps[i]` object, exactly
`{id, in, op, params}`, without a wrapper, domain field or omitted member.
`op` is `REL.derive`, `in` is the one-element ordered input-edge array, and
`params` is the complete machine alternative defined above, including
`row_kernel_contract_cid`, ordered lowered bindings and the full reference table.
This is not the source request step, params alone, a scalar expression node,
the whole pipeline, a sort-validation projection or a resolved step augmented
with `input_sorts`/`output_sort`. The actual canonical fragment graph names are
included; process-local handles are not substitutes. The derive evidence,
contexts, shapes, limits and their self-CIDs remain outside the step. Changing
the step ID, input edge, extension pin, bindings or references changes this
preimage; changing only external evidence does not. Fragment identity still
binds the complete evidence. Node identity proves neither type correctness nor
ownership; admission regenerates the same-request graph and evidence together.

<!-- requirement-block: derive.ordered-resource-context -->
`request.row_kernel_limits` MUST map exactly the ordered step IDs to their
`actql-derive-row-limits/0.1` bodies. Each has nonnegative safe-integer
`max_input_rows`, `max_value_bytes`, `max_live_value_bytes`, `max_work` and a
self-CID. Evidence `limits_cid` resolves the exact same-step request body;
the row/value ceilings do not exceed the enclosing request's corresponding
ceilings and selected Host constraints remain applicable. These limits are
declared enforcement bounds, not inferred capacity proofs. A fragment without
ordered nodes omits this request member.

<!-- requirement-block: derive.ordered-resource-measures -->
Enforcement MUST count all input row occurrences, and measure each admitted
input value, demanded root value and complete retained output row as canonical
JSON UTF-8 bytes of its typed wire value. Live-value bytes sum live input,
slot, temporary and pending-output roots; aliases count as separate logical
roots even with shared physical storage. Release follows last use. A transfer
of ownership does not create a second root. These are logical measures, not a
process heap ceiling; additional backend resource limits remain separate.

<!-- requirement-block: derive.ordered-work-measure -->
Work MUST accumulate one unit per row, binding and demanded expression entry,
plus value weight for input admission, each consumed operand, each produced
value and the retained output. Value weight is one per scalar/container plus
raw UTF-8 octets of string values and object keys, counting every logical
occurrence. Caching and short-circuit scalar comparisons do not discount this
weight; unselected lazy expressions incur no evaluation work. Logical work is
not an instruction count. Charges precede traversal/construction, check
arithmetic overflow, accept exact caps and never reset per row or slot.
All required input validation precedes shadowing; failure exposes no partial
operation output. Later projection cannot waive retained-output charges.

Saved plans are rechecked under their exact admitted law; map/array conversion,
early select or expression deletion is not an automatic meaning-preserving
repair. Ordered derive retains the input shape; explicit select closes the
output shape. These are distinct operations with their own measured bounds.

<a id="top-k"></a>

#### `top_k`

```yaml
- top_k:
    k: 20
    by: [{score: desc}, {id: asc}]
```

<!-- requirement-block: top-k.k-must-be-a-positive-safe-integer-and-by-must top-k.k-must-be-a-positive-safe-integer-and-by-must.second -->
`k` MUST be a positive safe integer and `by` MUST contain at least one
explicit stable order key. Selection requires a total order. When retained
candidate-key evidence exists, the completion algorithm in [Deterministic completion](#completion) selects and
appends missing key fields and journals the change; without it, a possibly
tied order is rejected. `top_k` lowers
directly to `REL.topk`.

Partitioned ranking is a distinct operation:

```yaml
- top_k_by:
    partition_by: [customer_id]
    k: 3
    by:
      - {score: desc}
      - {candidate_id: asc}
```

<!-- requirement-block: top-k.partition-by-positive-k-and-a-stable-non-empty-by-order-are -->
`partition_by`, positive `k`, and a stable non-empty `by` order are REQUIRED.
The same total-order and retained-candidate-key rule applies inside every
partition.
The result preserves no input order across partitions: partitions are ordered
by their keys in canonical ascending order, and rows within each partition use
the authored order. It lowers to an AoA partitioned-top-k operation; repeated
global `top_k` or host-side grouping is not a conforming substitute.

<!-- requirement-block: top-k.closed-bodies top-k.empty-partitions -->
Check MUST use the closed `{k, by}` body for `top_k` and
`{partition_by, k, by}` for `top_k_by`. The count is a positive-safe-integer
literal or whole Parameter reference, not an arbitrary expression; bound
values satisfy the same range before execution. The operations retain the
input field contracts without fabricating row-count or total-order evidence.

Check MUST accept empty and repeated `top_k_by.partition_by` references while
validating each equality-key field. Empty partition keys mean one global
partition of existing rows, with no row synthesized on empty input. Repetitions
and authored order remain in the checked representation; they add neither rows
nor uniqueness evidence. Repeated authored order keys are also retained and
cannot establish a missing tie-breaker. Neither empty partition keys nor
repetition authorizes operation deletion, preimage deduplication, or identity
equivalence with `top_k`.

<a id="relational-temporal"></a>

#### Relational temporal operators

`row_window` assigns fixed or sliding window columns without changing sort:

```yaml
- row_window:
    kind: sliding
    time: occurred_at
    size: 1h
    step: 15m
```

<!-- requirement-block: relational-temporal.kind-time-and-positive-size-are-required-sliding-windows-also -->
`kind`, `time`, and positive `size` are REQUIRED; sliding windows also require
positive `step`. It lowers to `REL.window.fixed` or `REL.window.sliding`.
Window membership and emitted boundary values are defined in [Canonical fixed and sliding windows](#event-windows).

<!-- requirement-block: relational-temporal.its-input-must-carry-statically-known-window-start-and-window-end-fields relational-temporal.its-input-must-carry-statically-known-window-start-and-window-end-fields.second -->
`window_group` lowers to `REL.window.project` and uses the same named aggregate
grammar and type rules as `group` ([group](#group)). Its input MUST carry statically known `window_start` and
`window_end` fields produced by `row_window` or declared by an already-windowed
relation contract; it MUST NOT interpret an ordinary relation as windowed.
`lag` lowers to `REL.window.lag` and requires
`partition_by`, non-empty `order_by`, `field`, and an output name. An authored
`offset` is a positive safe integer; omission and explicit `offset: 1`
normalize to the same one-row lag. Its partition order must retain a candidate key so lag selection has
no unresolved tie. The output name is written as `output`. `watermark_rows` lowers to
`REL.watermark` and requires `time`, an
explicit `late_policy` of `drop` or `mark`, and either a finite `watermark_ms`
or positive `max_skew`.

<!-- requirement-block: relational-temporal.watermark-source-and-output -->
`watermark_rows` MUST specify exactly one of `watermark_ms` and `max_skew`;
neither omission of both nor precedence between two supplied sources is admitted.
It adds fresh non-null fields `watermark_ms: number`, `watermark_late: boolean`
and `watermark_decision: string`. Any collision with an input field fails check.
For `max_skew`, the threshold at input occurrence i is the maximum time over
occurrences 0 through i inclusive, minus the resolved skew. This is an
unpartitioned prefix in the proven logical input order, not a maximum over
the complete Relation or a provider-arrival-order completion. Such order
evidence is required for the prefix path. A row is late exactly when its time
is strictly less than its threshold; equality is not late. `mark` preserves
every row, using decision `mark` for late rows and `keep` otherwise. `drop`
removes late rows and emits `keep` for retained rows. Empty input has the same
output contract and no threshold observation. Non-finite threshold arithmetic
fails before publication; invalid time rows cannot be silently discarded or
emitted with missing generated fields.

<!-- requirement-block: relational-temporal.window-role-evidence -->
`window_group` MUST have checked window-boundary role evidence, introduced by
`row_window` or an admitted already-windowed input contract. Coincidentally
named fields are insufficient. The evidence identifies the two boundary
fields and their interval law separately from ordinary field-type knowledge.
Value-preserving filters and whole-row distinct retain it. A name-changing
projection transfers each role to every alias in its explicit, value-preserving
field mapping; keyed distinct follows its projection. Removing or overwriting
an alias removes only that alias's evidence. The window evidence becomes invalid
when either boundary has no surviving alias. Window grouping retains only
aliases that remain actual grouping keys, not same-named aggregate outputs.
Required evidence must resolve
before window-group checking is complete; this rule grants no new runtime
deferral. Window keys are prepended exactly once to the ordinary group keys;
the shared empty-group and repeated-key laws remain unchanged.

<a id="reshaping"></a>

#### Reshaping and nested data

```yaml
- pivot:
    index: [customer_id]
    column: status
    values: [open, won, lost]
    value: amount
    aggregate: sum
    fill: 0
- unpivot:
    columns: [jan, feb]
    name_column: month
    value_column: amount
    keep: [customer_id]
- json_pick:
    column: payload
    path: [customer, id]
    output: customer_id
- unnest:
    column: items
    as: item
    with_index: item_index
```

<!-- requirement-block: reshaping.json-pick-accepts-a-non-empty-path-of-object-keys-and-must -->
`pivot` uses `index` for its key fields and supports the aggregates `sum`,
`avg`, `count`, `min`, `max`, and `first`; `min`/`max` require `AuthorOrderable`
inputs ([Lexical and ordering rules](#ordering)). `unpivot` requires explicit source
columns plus the canonical `name_column` and `value_column` fields. `json_pick`
accepts a non-empty path of object keys and MUST NOT evaluate JSONPath code.
`unnest` requires an array-typed field, preserves the source row, emits one row
per array element, and optionally emits a zero-based index named by
`with_index`; `with_index: true` names it `<as>_index`. They lower to
`REL.pivot`, `REL.unpivot`, `REL.json.pick`, and `REL.unnest`.

<!-- requirement-block: reshaping.all-unpivot-columns-must-have-exactly-the-same-statically-proven-type reshaping.json-pick-accepts-an-object-or-object-valued-json-it-must-not reshaping.for-statically-typed-objects-every-path-segment-must-exist-in -->
All `unpivot.columns` MUST have exactly the same statically proven type and
nullability. ActQL 0.1 has no implicit common-supertype conversion; authors
derive explicit casts before unpivoting heterogeneous fields. `object` means a
parsed JSON object only, while `json` means any canonical JSON value.
`json_pick` accepts an object or object-valued `json`; it MUST NOT parse a JSON
string implicitly or inspect an opaque reference ([Opaque reference values](#opaque-references)). For statically typed
objects, every path segment MUST exist
in the recursive `fields` contract and retains the leaf type with nullability
composed through the parent path under [Closed value contracts](#value-contracts). An opaque `json` value may be checked only with host-provided
shape evidence; absence of that evidence is not permission to guess a result
type.

<!-- requirement-block: reshaping.unpivot-columns-nonempty reshaping.unpivot-output-collisions reshaping.unpivot-order-and-multiplicity -->
`unpivot.columns` MUST be nonempty; an empty list cannot establish the value
column's type. A typed input containing zero rows is valid. Repeated source
columns are retained. Omitted `keep` means `[]`; overlapping `keep` and `columns`
is permitted. The output consists of the kept fields followed by `name_column`
and `value_column`. Generated names MUST be authored field names and the actual
output names must be distinct, including repeated `keep` entries. Names of input
fields that are not kept do not cause collisions. The name column is non-null
string; the value column retains the exact selected contract, including nested
structure and nullability. Each input row MUST produce one row per authored
column occurrence, in input-row then column order, retaining null values. Expansion
bounds count repeated columns; repeating a source column does not establish
uniqueness of the input candidate key combined with the name column.

<!-- requirement-block: reshaping.json-pick-output-is-an-authored-field-name reshaping.json-pick-output-must-not-collide -->
`json_pick` preserves every existing field and adds `output`; its output name
MUST be an authored field name and MUST NOT collide with an existing field.
Each path segment denotes one exact object key, not a dot-separated path or an
array index. A selected leaf may have type `json`; shape evidence is needed
only when traversing an opaque `json`, not when retaining it as a leaf.

<!-- requirement-block: reshaping.unnest-output-names-are-authored reshaping.unnest-index-options-are-closed -->
For `unnest`, `as` and a string `with_index` MUST be authored field names.
Omitting `with_index` emits no index field; its only explicit forms are `true`
or a field-name string. `false` and null MUST fail during check. The source
array field remains in the output. Without `outer: true`, the element contract
retains exactly the array's item contract: a nullable array container does not
make its elements nullable. `outer` accepts only booleans when present.

<!-- requirement-block: reshaping.pivot-values-are-required-nfc-unique-output-field-names -->
`pivot aggregate: first` is order-sensitive and requires a previously proven
stable input order. Pivot values are REQUIRED, NFC-unique output field names.
Dynamic data-derived output columns are not part of ActQL 0.1. Null pivot
values do not match a declared string value; the string `"null"` is ordinary
text. A generated column that collides with an index field, another generated
field after NFC normalization, or the reserved namespace fails during check.
Pivot aggregates ignore null input values. `count` returns the non-null count;
`sum`, `avg`, `min`, `max`, and `first` return null for an empty non-null
bucket, after which an authored `fill` is applied. Binary64 sum/avg use the same
captured numeric boundary as `group`; exact aggregates keep their own laws.
Only `first` observes the
already-proven stable input order.

<!-- requirement-block: reshaping.pivot-empty-axes reshaping.pivot-column-domain reshaping.pivot-fill-contract -->
Check MUST accept `pivot.index: []` and `pivot.values: []` while retaining all
input-contract, name, type and budget checks. Empty index means one global
group, including empty input; empty values emits only index fields, once in
first-occurrence order. Both empty emits one empty object. Repeated index
references are retained without adding output columns or uniqueness evidence.
The operation and authored value order remain identity-relevant; empty axes
do not authorize operation deletion or CID equivalence with another operation.

The pivot `column` MUST have string or nullable string type, without implicit
conversion. A null or undeclared string contributes to no generated bucket but
still establishes its index group. Generated columns follow canonical UTF-16
string order, independently of authored `values` order; index fields precede
them. Empty buckets produce zero for count and null for the other five functions,
then apply fill only to null, never to count's zero.

Pivot `fill` MUST use the whole-value CellValue alternatives and satisfy the
aggregate result contract without implicit coercion or deep merge. Bare
unreserved wire values and `{literal: WireValue}` are literals, with the latter's
payload opaque. Only an exact singleton `{$param: name}` is a Parameter hole;
malformed reserved roots fail, and nested holes are not traversed. Recursive
object/array Parameters are admitted at this whole-value position. Bound
Parameter values receive the same value validation before execution. Decimal
literal fills use the exact canonical fixed-scale wire string and are validated
in the aggregate's precision/scale context. A compatible non-null fill makes
an otherwise nullable result non-null; nullable fills do not. Fill is validated
even for count and empty generated-column lists. Reference values still require
their own evidence: a raw JSON object is not reference proof. Literal NULL
requires only a nullable result and constructs no reference value.

<!-- requirement-block: reshaping.as-with-index-and-existing-fields-must-not-collide -->
For `unnest`, optional `outer: true` retains a parent with an empty or null
array as exactly one row whose element and exposed index are null. Omitted
or explicit `outer: false` normalizes to false and emits zero rows in those
cases. Nonempty arrays retain ordinary element multiplicity, including null
elements; their indices are non-null. Outer output therefore has nullable
element and index contracts. A missing or non-array value is a runtime type
failure. `as`, `with_index`, and
existing fields MUST NOT collide. The internal row identity is source primary
identity plus zero-based element index. It remains provable when the source
identity is known during the operation. Because the index is otherwise not an
author-visible field, ordinary non-outer unnest retains a candidate key only
when `with_index` is emitted and retained alongside the source key. This rule
does not infer a non-null candidate key from the nullable outer index.

The synthetic outer row has an internal missing-element identity distinct
from every nonnegative element index. Exposed nullable index is not a
non-null primary key. Outer output has conservative per-parent bound
`max(1, array_max_items)`, with the normal nested byte and output-row limits.
An independently proven at-most-one expansion per parent preserves the parent
key. Otherwise outer unnest retains internal occurrence/order evidence only;
later non-null refinement and uniqueness assertions may establish new keys.

<a id="append"></a>

#### `append`

```yaml
- append: {with: archived_rows}
```

<!-- requirement-block: append.both-inputs-must-have-complete-schemas-with-the-same-field append.missing-or-extra-fields-and-incompatible-types-must-fail -->
`append` requires two available relations and has no author-selectable schema
mode. Both inputs MUST have complete schemas with the same field names and
compatible recursive contracts under [Closed value contracts](#value-contracts). Field order may differ; the compiler deterministically aligns the
right relation by name before lowering to `REL.unionAll`. Missing or extra
fields and incompatible types MUST fail. The common contract is
`JoinNullability` ([Closed value contracts](#value-contracts)); no implicit base-type coercion occurs.

<!-- requirement-block: append.typed-field-provenance-is-preserved -->
Field-set comparison MUST include typed qualification: an unqualified `id` is not
`left.id` or `right.id`. Compatible qualified schemas MAY be appended without
flattening, and their qualification is preserved. Two empty schemas are
compatible; appending their zero-column rows still adds their multiplicities.
The closed body is `{with: InputOrStepName}`. Its left operand is the current
relation selected by the normal step `from` rule; there is no `append.left`
selector. Both operands may name the same available relation, in which case
both occurrences are retained, without deduplication or no-op elimination.

<!-- requirement-block: append.the-compiler-must-not-add-a-missing-field-the-author -->
Contextual null typing follows [Closed value contracts](#value-contracts).
The compiler MUST NOT add a missing field; the author writes the explicit
null-producing `derive` when a branch lacks it.

Append does not deduplicate; authors add `distinct` explicitly when required.
It is not an identity assertion. When both inputs retain the same local
candidate key and a retained field has statically known, disjoint literal
domains, the compiler proves the composite candidate key consisting of that
discriminator followed by the local key. For example, local key `[source_id]`
plus `source = crm` on one branch and `source = support` on the other proves
`[source, source_id]`. Without such a proof, append does not invent a global
identity and `infer` reports `ACTQL_E_APPEND_IDENTITY_UNPROVEN` when one is
required.

Append order is every left row followed by every right row. Completeness is
`complete` only when both inputs are complete; source provenance remains
evidence even when not projected.

Complete-row `distinct` compares canonical AoA value CIDs. Object key order is
therefore irrelevant, array order is relevant, strings/timestamps use their
canonical spellings, and null differs from a missing field (the latter is
normally excluded by a complete typed schema).

<a id="assert-rows"></a>

#### `assert_rows`

```yaml
- assert_rows:
    where: {not_null: {field: customer_id}}
- assert_rows:
    unique_by: [account_id, external_id]
```

Exactly one of `where` and `unique_by` is present. `where` requires strict
true on every row; false and three-valued unknown fail. `unique_by` is a
non-empty, duplicate-free list of visible fields and rejects null or
missing components and duplicate canonical tuples. Both variants preserve row
bytes, shape, order, and identity on success. The `unique_by` variant additionally
proves non-null uniqueness for the declared tuple. The physical assertion
precedes every consumer of that proof.
Any violation fails before publishing the assertion output. Unconsumed
assertion branches fail planning rather than silently disappearing. No
`on_failure`, skip, warning, catch, or custom-message form is admitted.

<!-- requirement-block: assert-rows.equality-key-domains assert-rows.nullable-key-contracts -->
Fields in `assert_rows.unique_by` MUST belong to the scalar or reference
domains admitted by `KeyComparable` ([Closed value contracts](#value-contracts)),
including ResourceRef and ArtifactRef. Object, array, json and vector fields
are not admitted. Nullable field contracts MUST be accepted during type
checking; the physical assertion rejects null or missing component values.
Type checking alone neither narrows those contracts nor establishes a
non-null uniqueness proof.

<!-- requirement-block: assert-rows.implementations-must-execute-an-atomic-row-assertion-before-any-consumer -->
Implementations MUST execute an atomic row assertion before any consumer of
its candidate-key proof and preserve the successful input relation unchanged.
`where` lowers to `REL.assert_all`; `unique_by` lowers to `REL.assert_unique`.

<a id="nest"></a>

#### `nest`

`nest` is a pure Relation operation.
It attaches an ordered child-object array to each parent row. Example fragment:

```yaml
- from: customers
  nest:
    with: orders
    on: [{left: customer_id, right: customer_id}]
    into: orders
    fields: [order_id, amount, created_at]
    order_by: [{created_at: desc}, {order_id: asc}]
  as: customer_tree
```

The closed body contains required `with`, `on`, `into`, `fields`, and optional
`order_by`, `max_items`. `with` follows dataflow scope; `on` is a nonempty list
of explicit equality-key pairs checked with `KeyComparable`. `fields` reuses
`select` projection/rename syntax; calculations belong in preceding `derive`.
`into` must be a fresh parent field. No implicit relationship lookup, recursive
query, overwrite mode, or error handler is added. Both operands are Relations
from the checked graph; keyed-only acquisition must be explicit upstream work.

<!-- requirement-block: nest.qualified-payload-projection nest.repeated-correlation-pairs -->
Parent and child schemas may carry qualified fields. `fields` MUST use only
field strings or singleton `{output_name: input_field}` maps, with distinct flat
authored output names. A qualified child field requires an explicit flat alias;
the legacy `{from: ..., to: ...}` object is not authored projection syntax.
Parent fields retain their qualification. Repeated `on` pairs MUST retain their
authored sequence and do not multiply matching child rows or prove uniqueness.
This does not alter the canonical lowering's first-occurrence deduplication of
right correlation fields for the internal group key.

##### Values, types, and order

Output preserves every parent row, its fields, order, and candidate keys.
Each parent receives all matching children; null correlation components never
match. Duplicate parent correlation keys remain separate rows. Legal child
multiplicity is preserved; duplicate identities still violate input contracts.
Zero matches produce `[]`; an existing all-null child produces an object with
null fields, not an empty array. Acquisition failure never produces `[]`.

The new field is a non-null array of non-null closed objects. Selected field
contracts, including nullability, are preserved even for empty inputs. Required
field/type evidence is static. Constructibility follows [Object and array construction](#value-construction): nesting does not
permit hidden references or infer safe structure from opaque JSON. Reference
correlation/tie-break keys need not appear in the child payload.

<!-- requirement-block: nest.projection-sequence -->
Before child projection, resolve order using [Named Results and Effect declarations](#results-and-delivery)'s precedence: explicit order,
existing total witness, canonical candidate key, eligible full projected row,
otherwise rejection. Authored order requires `AuthorOrderable`; canonical
completion uses `CanonicalOrderable` and [Deterministic completion](#completion)'s key selection. Internal reference
order remains in Plan/evidence, not authored source. Array order is observable
and identity-bearing. Projection does not discard ordering evidence.
With explicit `order_by`, ties require an eligible candidate key or an
existing total witness preserved by stable sorting; otherwise checking fails.
Full-projection fallback applies only when `order_by` is omitted. Its comparison
priority MUST follow the declared projection sequence, not object property
enumeration or canonical object-key serialization.

##### Lowering and limits

The canonical Program retains a `nest` node. Its value-level expansion is:

```text
child semijoin against original parents (null keys never match)
→ effective child order → closed child objects
→ array_agg by correlation key → many-to-one left join to original parents
→ typed empty array for missing groups only → parent fields plus into
```

The canonical node sequence is fixed below; equivalent physical rewrites do
not replace it. Generated IDs follow the ordinary AoA operation-base allocator
in insertion order; only the final projection may use the authored `as`.
Reference key aliases are `__actql_nest_ref_i`, where `i` is the field's index
in the lexically sorted complete input schema. Derive aliases on parent first,
then child, only if that side contains reference fields; their values are the
reference identity components defined in [Opaque reference values](#opaque-references). All correlation and completed
order terms use these aliases. Original equality-pair order is retained.

<!-- requirement-block: nest.canonical-lowering -->
| Node | Canonical parameters and wiring |
| --- | --- |
| matched children | `REL.join(child, parent)`, semi, reversed equality pairs, `null_key: no_match`; no distinct-parent node |
| child provenance | `REL.select` removes `left.` from the complete child schema, followed by reference aliases |
| child order | `REL.orderByStable` with resolved order; omitted only when the existing witness is reused unchanged |
| child arrays | `REL.groupBy`, distinct right correlation fields in first-occurrence order; `__actql_nest_items = array_agg(object(projected fields))` with the resolved item limit |
| empty relation | `REL.where` over the original child with literal `0 = 1` |
| empty constant | global `REL.groupBy`, the same typed object aggregation as `__actql_nest_empty`, item limit 1 |
| attach groups | many-to-one left join of original parent (with reference aliases) and child arrays; duplicate groups fail; null keys never match |
| retain parents | select parent fields in their retained field sequence, then `__actql_nest_items` |
| attach empty | left join the retained parent rows to the singleton empty constant on literal `1 = 1` |
| flat values | select parent fields, items, empty constant, removing provenance qualifiers |
| fill missing | derive `into = case(is_null(items), empty, items)`; an existing all-null child object is not missing |
| result | select original parent fields then `into` |

The child schema projection uses canonical schema-key order; this is separate
from the authored payload projection sequence. Item-limit bindings target each
group node's `params.aggs.<internal-field>.max_items`. Byte bindings target the
child-array group and final projection as specified below. Empty-array evidence
uses the fixed upper bound 1, not a guessed element type or a Host replacement.

Generated aggregation consumes verified effective order; it does not relax
authored `array_agg` rules. Required upstream failures cannot be optimized away.
Unmatched child groups do not incur nest-specific per-array guards. Independent
collections aggregate separately, avoiding sibling Cartesian products. Deeper
nesting uses finite bottom-up dataflow steps, not recursive acquisition.

`max_items`, when supplied, is a positive-safe-integer guard or an admitted
parameter bound before planning. It caps each emitted child array, never
truncates it; use preceding `top_k_by` for selection. With parent bound P and
per-parent bound M, total nested elements are bounded by P×M. A child-total bound
can tighten this only when parent correlation keys themselves are proven unique.
Other parent primary keys do not prove that fact. Sibling bytes add; deep values
compose recursive byte/depth bounds, checked for overflow. Resolved ceilings and
enforcement boundaries follow [Author guards, resolved limits, and Plan facts](#resolved-limits); violations fail publication atomically.
Statistics and shared physical storage do not reduce logical expansion bounds.

The Host capacity contract supplies `max_nested_value_bytes` and
`max_nested_value_depth`. Depth counts array/object containers in the child
payload and is checked from its recursive type before execution. Byte usage
is the sum of UTF-8 AoA canonical JSON encodings of the emitted array values,
including each repeated parent copy. The Plan binds byte ceilings both after
child aggregation and after parent attachment as `aoa_output` limit targets
(`step_id`, canonical sorted `fields`, `measure: bytes`). Attachment measures
all retained top-level object/array fields together, so sibling collections
share the ceiling; nested containers are counted within their enclosing value.
Core admission checks these outputs
before any consumer, even if a later step would discard them. This envelope
validates values; it performs no construction or acquisition.

Policy and completeness propagate through payload, membership, correlation,
ordering, and count dependencies. Partial child observations do not become a
complete parent history. `[]` proves absence only in the supplied Relation.
Results remain Relations; delivery only serializes their materialized values.

The typed empty constant lowers to `REL.where(false)` on the child input and
global `REL.groupBy([], array_agg(object(...)))`. Attach this singleton and use
`case` only for missing groups. Host JSON postprocessing is forbidden; no
untyped empty author constructor is introduced. Hand
expansion need not have the same Program Definition CID as a `nest` Program.

<a id="values"></a>

### Finite relation construction: `values`

`values: {schema, rows}` is an input-free generator; `schema` is a nonempty
closed author field-contract map and `rows` is a finite list of complete objects
with exactly those fields. An empty list has the declared schema. Each cell is
a CellValue as defined below and in Structural grammar; nested literal data
is opaque to binding resolution. Decimal cells use fixed-scale
wire strings decoded under the declared type. No row expressions, provider
access, implicit casts, or opaque-reference fabrication occur here. Constructor
admissibility follows [Object and array construction](#value-construction).
Rows retain list order and multiplicity. An internal occurrence ordinal proves
order, not uniqueness of projected field values. Generated Relations have local
definition provenance, not external-observation completeness evidence.

At a cell root, an exact singleton `{$param: name}` is a parameter hole and
an exact singleton `{literal: WireValue}` quotes literal data. A malformed
parameter name in the singleton hole fails; schema compatibility or parameter
existence never chooses its interpretation. Every other wire value is literal.
The quoted payload is opaque, including nested parameter or literal shapes.
For example `{literal: {$param: business_value}}` stores the business object;
`{literal: {literal: 1}}` stores the object `{literal: 1}`. Both plain `1` and
`{literal: 1}` normalize to the same canonical cell `{literal: 1}`. Canonical
cells are exclusively `{literal: WireValue}` or `{$param: name}`; the printer
quotes every literal whose root collides with either reserved singleton shape.
This cell grammar admits no expression evaluation and changes no value-domain
or constructor eligibility rule.

<!-- requirement-block: values.admission -->
Checking MUST validate the complete schema, bindings and every literal row;
resolved row, byte and recursive-value limits apply before publication. A
`values`, `time_series`, `calendar_series`, or `mean_graphs` generator requires
`as`, does not consume the current Carrier, and rejects a step-level `from`.
`inputs: {}` is legal when all dataflow roots are generators; top-level `from`
is then absent. Current-input selection follows [Pipeline names and references](#pipeline-references).

<a id="row-set-operations"></a>

### Row set operations: `except` and `intersect`

Both bodies are `{with, duplicates}`, where `with` names a Relation and
`duplicates` is required `distinct|all`. Fields are matched by exact name,
never position; the field sets and recursive value domains agree, with
nullability and extents joined under the common type rules. No implicit cast
or field inference is performed. Equality compares the complete typed row:
NULL equals NULL here, references use semantic reference identity, arrays are
ordered, objects compare exact field sets recursively, and opaque JSON compares
canonical JSON values. Decimal equality uses the common decimal equality law,
not wire spelling or a different precision-tag hash. Hashing is an implementation
of this equivalence, not an alternative definition.

<!-- requirement-block: row-set-operations.multiplicity -->
For an equivalence class with left multiplicity m and right multiplicity n,
`except all` MUST emit max(m-n,0) left occurrences; `intersect all` emits min(m,n).
The ALL variants retain the earliest required number of left occurrences.
`distinct` emits the first left occurrence exactly when m>0 and respectively
n=0 or n>0. Surviving occurrences retain left input order. Absence here is
absence from the right captured Relation, not proof of absence outside its
observation scope. Output bounds never exceed the left bound; comparison,
hash-table and byte resources remain separately limited.

<a id="cross-join"></a>

### `cross_join`

The closed body is `{with, select?, right_rows?, max_output_rows?}`.
`right_rows`, when present, is exactly `one`: a checked assertion of one right
row, not a request to select one row. Both operands are Relations. Provenance,
projection and collisions follow ordinary join rules. Without the assertion,
an empty operand yields no rows; with it, zero or multiple right rows fail.
Output enumerates left occurrences then right occurrences in their logical
input order. The product of retained operand identities proves output identity.

<!-- requirement-block: cross-join.bounds -->
The compiler MUST derive the product bound with checked arithmetic and combine
it with Host ceilings and any positive author guard. A singleton assertion is
discharged statically or enforced before any consumer uses it; a failed
assertion publishes no rows. No input is silently truncated or null-extended.
This operator introduces no acquisition or permission. In particular, a
singleton aggregate can be broadcast without a fabricated equality field.

<a id="analytic"></a>

### Row-preserving analytics: `analytic`

<!-- requirement-block: analytic.partition-repetitions analytic.bound-numeric-options -->
Check MUST retain repeated `partition_by` references and their authored order
while validating every key. Repetition adds no rows, output fields or key
evidence. An empty partition list denotes one global partition of existing rows;
empty input remains empty. Names in `functions` are checked against the input
snapshot, not earlier sibling outputs. Neither identity rewriting nor a new
publication order follows from these acceptance rules.

Navigation `offset` and numeric `preceding`/`following` boundaries MUST be a
literal or whole Parameter reference, not an arbitrary expression. Offset is
a nonnegative safe integer; preceding/following distance is positive. Invalid static
literals and structurally reversed boundary classes fail during checking;
unbound values and unresolved within-class boundary comparisons are validated
before execution. A Parameter cannot select frame kind, boundary direction or
function name. Selecting existing structured or reference values with navigation
or first_value/last_value does not construct new reference evidence; their
argument contracts are retained with nullable root output.

The body contains required `partition_by`, `order_by`, `functions`, and optional
`frame`. `partition_by` is a possibly empty list of equality-key fields;
`order_by` is a nonempty authored OrderKey list. `functions` is a nonempty map
of fresh output names to closed calls. Partition NULLs group together. Results
retain original input-row order, fields, multiplicity and candidate keys;
window ordering determines calculations, not a new publication order. Ranking
functions return non-null safe-integer numbers; navigation/value functions
retain their argument domain and bounds with nullable output. Frame aggregates
have their ordinary result contracts and empty-input behavior.

Calls are `{fn: row_number|rank|dense_rank}`, `{fn: lag|lead, expr, offset?}`,
`{fn: first_value|last_value, expr}`, or a [group aggregate](#group) call without
an aggregate-local `order_by`. Offsets are nonnegative safe integers, default 1;
out-of-partition navigation yields typed NULL and does not fabricate a row.
`first_value` and `last_value` respect NULL elements. Rank/navigation calls
reject `filter` and `distinct`. Aggregate calls retain their own filter/null/
distinct laws. Result types follow the function, including nullable navigation.
First_value and last_value are frame functions, not navigation functions;
they require frame and reject filter/distinct. Only lag/lead are navigation
calls. Aggregate frame functions retain their explicitly admitted modifiers.

`frame` is `{start, end}`. A boundary is `unbounded_preceding`, `current_row`,
`unbounded_following`, `{preceding: n}`, or `{following: n}`, with n a positive
safe integer. It is a ROWS frame; RANGE, GROUPS and exclusion clauses are not
admitted. Start cannot be unbounded_following, end cannot be
unbounded_preceding, and start cannot follow end in logical offset order.
Intersect the logical inclusive interval with the partition; do not clamp an
out-of-partition start to an existing row. Empty frames use aggregate empty-set
laws and yield NULL for first/last value. Frame is required for frame functions,
absent for calls consisting solely of ranking/navigation. It does not affect
lag, lead or ranking. A bounded partition may use unbounded frame boundaries.

<!-- requirement-block: analytic.peers -->
Checking MUST separate authored peer order from physical position completion.
`rank` is one plus the number of preceding rows with different authored order
values; `dense_rank` is one plus the preceding distinct peer-group count.
`row_number` starts at 1 in completed order. Missing candidate-key fields or a
retained total witness complete position order without splitting peer groups.
Reference keys are eligible for internal completion, not authored value order.
Without an adequate position witness, position-sensitive functions fail check.
Position completion is journaled under Deterministic completion, recording the
authored peer order, the added identity terms or reused total witness, and the
supporting evidence. It does not change peer groups or publication order.

<!-- requirement-block: analytic.evaluation -->
Each call's filter and argument MUST be evaluated once per demanded source row
in its partition, then reused by every output frame that consumes it. Filter
false/null excludes the argument from demand. A navigation or first/last call
demands only referenced rows. A row used by several calls has separate call
frames; no callback or hidden source retrieval is permitted. Representative
value failure order is canonical partition-key order, source position, canonical
output name, then child-expression order, independent of parallel completion.
Binary64 frame sum/avg are numeric observation slots per output frame under
[Numeric aggregate observations](#numeric-aggregates); exact aggregates keep
their own laws. Frame position selects members and binds the observation demand,
not a bit-fixed floating-point summation order. Bounds include input
and output bytes, partition storage, and total frame memberships; optimized
prefix sums are legal only when they preserve specified values and failures.

<a id="additional-aggregates"></a>

### Ordered and statistical aggregates

The aggregate vocabulary additionally contains `string_agg`, `first`, `last`,
`percentile_disc`, `percentile_cont`, `var_pop`, `var_samp`, `stddev_pop`, and
`stddev_samp`. They use existing `{fn, expr, filter?}` calls. First/last and
string_agg require an aggregate-local total `order_by` outside analytic frames;
different aggregates may use different orders. `first` and `last` exclude NULL
like other group aggregates; this differs intentionally from analytic
first_value/last_value. `string_agg` accepts strings, requires a literal string
`delimiter`, ignores NULL, returns NULL on no values, and admits `distinct`.
It has optional positive `max_bytes`, enforced on UTF-8 output without truncation.
Ordered aggregates evaluate their own filter before arguments and sorting.
For string_agg, the logical sequence is filter, demanded argument evaluation,
NULL exclusion, stable ordering by the aggregate's total order_by, distinct by
canonical value CID retaining the first occurrence in that order, then joining
with the delimiter. In analytic frames, the completed frame position order
supplies that order. Argument failures follow the shared aggregate evaluation law;
sorting or deduplication cannot remove a demanded argument failure.

Percentile calls require `fraction` in [0,1], a bound finite number; they reject
distinct and explicit order_by. Values sort ascending in their value domain.
`percentile_disc` accepts AuthorOrderable and returns item max(1,ceil(p*n)) in
1-based order. `percentile_cont` accepts number and for n>0 computes
h=(n-1)*p, i=floor(h), f=h-i, then x[i] if f=0, otherwise
x[i]+f*(x[i+1]-x[i]), with binary64 rounding after each arithmetic operation.
No rows returns typed NULL; no implicit decimal-to-number conversion occurs.

<!-- requirement-block: additional-aggregates.numeric-laws -->
Variance and standard deviation MUST use number inputs, NULL exclusion, and
canonical value-CID input order. First compute the binary64 left-fold sum and
mean; then left-fold (x-mean)*(x-mean), rounding after each subtraction,
multiplication and addition. Divide by n for population and n-1 for sample;
insufficient n (0 or <2 respectively) returns NULL. Standard deviation uses
correctly rounded binary64 square root. Non-finite intermediates fail, even
if a different algebraic formula could avoid overflow. These definitions and
percentile interpolation admit no reassociation or approximate sketch silently.
Statistical/first/last calls reject distinct; all input, sort and output bounds
remain enforced. Physical memory/CPU savings need not simulate discarded
allocations, but do not erase logical membership or output limits.

The mean inside variance/stddev is part of that operation's own strict fold,
not an observed avg slot and not required to equal a separately captured avg.
These statistical operations retain the stated deterministic numerical law;
the sum/avg observation boundary does not implicitly relax them.

<a id="event-operations"></a>

### Event operations (TEA)

<!-- requirement-block: event-operations.fixed-sliding-support-alone-is-partial-tea-support-and-must-not -->
`actql-tea/0.1` is the authoring-complete deterministic event-time module. A
module claim covers fixed, sliding, and session assignment; explicit late
policy; stable event deduplication; bounded as-of correlation; bounded event
sequence matching; and relation projection. The module also covers finite time_series and interval_join;
calendar operations require the separate calendar claim. Fixed/sliding support alone is
partial TEA support and MUST NOT be reported as module conformance.

Processing-time substitution, unbounded state, implicit reordering, implicit
gap fill, and interval relations beyond [interval_join](#interval-join) are outside 0.1. An
implementation MAY support them only under a separately versioned profile.

<a id="event-windows"></a>

#### Canonical fixed and sliding windows

```yaml
- row_window:
    kind: fixed
    time: occurred_at
    size: 1h
```

<!-- requirement-block: event-windows.kind-is-required-and-must-be-fixed-or-sliding event-windows.kind-is-required-and-must-be-fixed-or-sliding.second event-windows.size-is-required-and-accepts-a-positive-integer-millisecond-value -->
Relation input uses `row_window`; event-stream input uses `window_events`.
There is no generic `window` spelling in ActQL 0.1. This keeps carrier choice
explicit without adding an alias or another authoring layer. `kind` is
REQUIRED and MUST be `fixed` or `sliding`. `size` is REQUIRED and accepts a
positive integer millisecond value or a duration string using `ms`, `s`, `m`,
`h`, or `d`. Sliding windows additionally require `step`.

<!-- requirement-block: event-windows.fixed-step-retention -->
Fixed windows MUST admit an explicit `step`, validate it under the same positive
integer millisecond constraints as a sliding step, and retain its authored and
identity representation. It does not participate in boundary, membership or
cardinality-bound calculations, which continue to use `size` and `offset`.
Omission does not insert a step. An explicit Parameter step retains its binding
and value-validation obligations even though it does not affect these calculations.

<!-- requirement-block: event-windows.offset-grid -->
Both `row_window` and `window_events` MUST admit `offset`. It is a
signed safe-integer millisecond value, a positive duration token under the
common lexical rule, or a whole Parameter reference to a compatible number
or duration declaration. Numeric values and bound numeric Parameters must be
safe integers. Omission inserts numeric zero; explicit zero is valid.
Fixed-window starts are `offset + n * size`, and sliding-window starts are
`offset + n * step`, for integer n. A window contains t exactly when
`start <= t < start + size`; emitted memberships are in ascending start order.
Checked arithmetic must not saturate or wrap. `offset` is not reduced modulo
size or step for canonical identity. In particular, a supplied sliding offset
must not be ignored by a lowerer or evaluator.

<!-- requirement-block: event-windows.occurrence-order -->
Window output MUST enumerate input occurrences in their existing logical order,
then each occurrence's memberships in ascending window-start order, for both
Relation and Events inputs. This is not a global sort by window start. Fixed
windows retain one occurrence; sliding windows retain each matching membership.
The operation does not establish input order when no such evidence exists.
Removing boundary columns can lose window-role evidence without changing the
retained occurrence sequence. Membership expansion alone does not prove ID
uniqueness, completeness or successful discharge of resource obligations.

`row_window` preserves relation fields and adds `window_start` and
`window_end`. It lowers directly:

```text
relation
-> REL.window.fixed or REL.window.sliding
-> relation
```

<!-- requirement-block: event-windows.session-has-a-distinct-shape-in-and-must-not-be -->
`window_events` preserves the event-stream carrier, adds `window_start_ms` and
`window_end_ms`, and lowers to `TEA.window.fixed_label` or
`TEA.window.sliding_assign`. Event windows use closed-open intervals;
the boundary is a language invariant recorded in the Plan. Fixed windows
preserve the event-count upper bound. Sliding windows derive an event-membership
upper bound of `input_events * ceil(size / step)` using checked multiplication;
overflow fails planning rather than saturating. `session` has
a distinct shape in [session](#session) and MUST NOT be inferred from either operation.

<a id="event-bridges"></a>

#### Event-stream-preserving operations and explicit bridges

When a later TEA operation must consume the carrier, authors use the explicit
event-stream form:

```yaml
- to_events: {id: event_id, time: occurred_at}
  as: events
- window_events: {kind: sliding, size: 1h, step: 15m}
- watermark_events: {watermark_ms: 0, policy: mark}
- events: true
```

`to_events` and `events` lower to `BRIDGE.rows.to_events` and
`BRIDGE.events.to_rows`. `window_events` uses the same fixed closed-open
boundary and lowers to
`TEA.window.fixed_label` or `TEA.window.sliding_assign` and preserves
`events`. `watermark_events` requires a finite `watermark_ms` and an
explicit `drop` or `mark` policy, lowers to `TEA.watermark.label`, and also
preserves `events`.

<!-- requirement-block: event-bridges.clock-source -->
The `to_events` body MUST contain exactly `id` and `time` field references on
its Relation input, with the time source having a non-null number or UTC timestamp
contract. Other field types may remain unknown, and the retained payload field
set may be open. A timestamp source is converted to the internal numeric UTC-millisecond
clock without replacing its authored payload value or inserting a public
`event_time_ms` alias. The Event carrier retains the source role and its clock
encoding separately; clock-consuming operations validate values and perform the
required conversion before temporal arithmetic. An explicitly authored clock
field on an existing Event carrier remains subject to that operation's own
field-domain rules, including sequence's numeric-only rule.

<!-- requirement-block: event-bridges.watermark-labels -->
`watermark_events` MUST have a closed body containing `watermark_ms` and
`policy`. Both policies add fresh non-null fields `watermark_ms: number`,
`late: boolean` and `watermark_decision: string` to every retained event.
Existing fields with any of these names are collisions; unknown field-set
completeness does not establish their absence. The event is late exactly when
its numeric millisecond time is less than the threshold; equality is not late.
`mark` retains every event, with decision `mark` for late events and `keep`
otherwise. `drop` removes late events and labels all survivors `keep`. Both
preserve retained events' semantic identity, time, payload and relative order;
they do not establish uniqueness or a new ordering proof. The threshold is a
finite number literal, not a Parameter, and may be negative or fractional.

<!-- requirement-block: event-bridges.semantic-identity-domain event-bridges.identity-uniqueness event-bridges.preserve-identity-order event-bridges.reject-unsupported-identity-lowering -->
`to_events.id` MUST have a complete, non-null `KeyComparable` value contract.
The semantic identity retains that contract and its values; it is not limited
to strings. Type comparability does not prove uniqueness: duplicate event
identities MUST be rejected separately before identity-dependent operations.
Session and sequence order equal-time events by the existing type-specific
scalar order, or by the existing internal identity order for reference values.
This does not admit references as authored `OrderKey` fields. Lowering MUST
preserve typed equality and ordering, and MUST reject unsupported identity
domains before claiming executable support rather than implicitly converting
identities to strings or replacing them with CIDs.

<!-- requirement-block: event-bridges.every-relation-form-tea-time-field-must-have-complete-typed-evidence event-bridges.unknown-nullable-date-only-string-or-other-time-evidence-is-rejected -->
Every relation-form TEA time field MUST have complete typed evidence as either
a non-null `timestamp` or a non-null `number` containing UTC epoch
milliseconds. For a typed `timestamp`, the compiler inserts a reserved,
collision-checked `REL.derive` using `date_diff(authored_time,
1970-01-01T00:00:00.000Z, ms)` before the event bridge, records
the fixed UTC epoch-millisecond carrier law in the checked Plan, and preserves the authored
timestamp in public relation results. A numeric field passes through
unchanged. Unknown, nullable, date-only, string, or other time evidence is
rejected; an explicit not-null filter may refine nullable evidence, but the
compiler MUST NOT guess a parse, timezone, or null policy.

<a id="session"></a>

#### `session`

```yaml
- session:
    id: event_id
    time: occurred_at
    by: [customer_id]
    gap: 30m
```

<!-- requirement-block: session.by-and-positive-gap-are-required -->
`by` and positive `gap` are REQUIRED. Sessions use the closed-open
boundary recorded in the Plan. Relation input
also requires `id` and `time`; event-stream input already carries those roles.
Within each key, events are ordered by event time ascending then event identity
ascending. An event belongs to the preceding session only when its time is
strictly less than the preceding event time plus `gap`; an event exactly on the
gap boundary begins a new session. The result preserves the input Carrier and includes the key fields,
event fields, `session_start_ms`, `session_end_ms`, and a stable `session_id`
derived from the key tuple, session start, and first event identity.
`session_end_ms` is the last event time plus `gap` and is exclusive.
Events retain their original event identity and time; session labels do not
change event order or identity. Relation results retain the specified event
ordering. Later sequence/dedupe operations use `session_id` explicitly in their
partition keys to prevent crossing sessions; Carrier preservation alone does
not provide that guarantee.

<!-- requirement-block: session.closed-body -->
The closed session body MUST contain `by` and `gap`, plus exactly `id` and
`time` on Relation input; Events input uses its intrinsic roles and does not
admit role overrides. `by` contains known KeyComparable fields, preserves
repeated references and admits an empty global partition. Empty input remains
empty. `gap` uses the same positive safe-integer millisecond, positive fixed
duration token or whole non-null number/duration Parameter forms as window
size; a Parameter retains validation obligations even if its default is known.
The three generated session fields are fresh and non-null: start/end have
number type and `session_id` has string type. Unrelated payload contracts may
remain unknown, but generated-field absence requires field-set evidence.

<a id="time-series"></a>

#### `time_series`

The generator body is `{start, end, step}`: start/end are bound non-null UTC
timestamp values, and step is a positive fixed duration. Start<=end is required.
It emits `{time: timestamp}` at start+i*step while time<end, in ascending time
order; start=end emits an empty typed Relation. Time is its candidate key.
No end sentinel or extrapolated row is emitted. Timestamp domain or safe
integer overflow fails before publication. Its row bound is the checked ceiling
of duration/step. No timezone or calendar arithmetic is implicit.

<!-- requirement-block: time-series.source-arguments -->
The closed `time_series` body MUST contain exactly `start`, `end` and `step`.
Each endpoint is a canonical UTC millisecond timestamp string or a whole
Parameter reference with a non-null timestamp declaration. Step uses the shared
positive safe-integer millisecond literal, fixed duration token or whole non-null
number/duration Parameter forms. Literal endpoint validity and reversed ranges
are checked statically; Parameter defaults are not substituted during declaration
checking, and bound ranges and positive steps are validated before generation.

<!-- requirement-block: time-series.coverage -->
A generated time grid MUST NOT attest observed absence. Joining it to counts
and replacing missing counts with zero is explicit computation; describing a
zero as confirmed absence additionally requires complete source coverage of
that interval. Neither an empty grid nor a synthetic row replaces failed
acquisition. Grid, partition cross-product and final output have separate
resolved bounds.

<a id="interval-join"></a>

#### `interval_join`

Full is deliberately not admitted here: 0.1 temporal correlation covers
left-driven matching and absence within captured scope, not symmetric temporal
reconciliation. A full variant is possible, but would additionally need a
closed unmatched-right ordering, identity transfer and coverage contract.
This restriction is not a claim that full temporal joins are inherently unsafe.

<!-- requirement-block: interval-join.source-shape -->
The closed body is `{with, kind, mode, on, left, right, select?, max_output_rows?}`.
`kind` is `inner|left|semi|anti`; `mode` is `point_in_interval|overlap`; `on` is
a possibly empty equality-key-pair list. `left` is `{time}` for point mode or
`{start,end}` for overlap; `right` is `{start,end}`. These names refer to fields
of two Relations, not dataflow sources. Each temporal field has the same
non-null timestamp domain or all use safe-integer UTC milliseconds; explicit
casts precede mixed-domain joins. Every interval requires start<end, even when
its equality key matches no row. Null equality keys do not match.
Each `on` item MUST be exactly `{left: Field, right: Field}`; the list preserves
authored pair order and repeated pairs without multiplying matches. Empty `on`
applies temporal matching across the two captured Relations without equality
partitioning. Ordinary join's single-name or standalone-pair shorthand is not
part of this body's list grammar. Step `from` selects the left Relation;
body `left` specifies its temporal fields and does not replace that selection.

Point mode matches r.start<=l.time<r.end. Overlap matches
l.start<r.end and r.start<l.end. Endpoints are closed-open, so touching intervals
do not overlap. All matching pairs are retained; kind, null extension,
projection, provenance and left-major/right-minor order follow ordinary join.
Semi/anti emit a left occurrence at most once. Input endpoint validation is
atomic before matching. Candidate-key transfer follows retained pair identity.

<!-- requirement-block: interval-join.bounds -->
An interval join MUST resolve output and search-work ceilings separately,
using the checked operand product bound where no stronger proof exists.
Output overflow fails, never truncates. Membership or nonmembership refers to
the captured right Relation; an external absence assertion requires sufficient
per-key and interval coverage. This operation is local computation, not a
complete external-join acquisition path or permission to run arbitrary theta joins.

<a id="calendar"></a>

#### Calendar profile

`actql-calendar/0.1` adds `calendar_bucket` and `calendar_series`; it does not
change fixed-duration arithmetic or the text-time UTC functions. Calendar
calculations use the proleptic Gregorian calendar in years 0001..9999.
The closed shared parameters are `unit: day|week|month|quarter|year`, `timezone`,
and, for week only, required `week_start: monday|sunday`. Timezone is `UTC` or
an exact IANA name in the profile's pinned TZDB artifact; Host locale/timezone
and ambient OS databases are irrelevant. No optional gap/fold interpretation
switch is admitted. Unknown zones or out-of-domain boundaries fail.

<!-- requirement-block: calendar.source-admission -->
`unit`, `timezone`, and `week_start` MUST be literal strings, not expressions or
Parameters. `week_start` is required exactly for `unit: week` and forbidden for
other units, including explicit null. Series `start` and `end` are canonical UTC
timestamp literals or whole non-null timestamp Parameters; bound values retain
calendar-year and interval validation obligations. Literal endpoints use years
0001..9999, reject reversed ranges, and admit equal endpoints as an empty range.
Bucket `time` is a field reference and `into` an ordinary authored output name.
Source-option admission alone is not recognition of a timezone: a checked
Calendar operation requires membership in the selected fixed semantic artifact.

`calendar_bucket: {time, unit, timezone, week_start?, into}` is row-preserving.
`time` names a non-null timestamp field; `into` is a fresh object field with
non-null timestamp `start` and `end`. Local calendar boundaries start at
midnight, day 1 for month, Jan/Apr/Jul/Oct 1 for quarter, Jan 1 for year.
Week boundaries use the selected weekday. An ambiguous boundary uses its
earliest UTC occurrence; a nonexistent boundary advances to the first valid
instant at or after that local boundary. Coincident UTC boundaries collapse;
a skipped civil day produces no zero-duration bucket. Bucket is the unique
adjacent-boundary interval containing time; boundaries are closed-open.

`calendar_series: {start,end,unit,timezone,week_start?}` generates the distinct
full `{start,end}` bucket intervals intersecting the nonempty UTC range
[start,end), in ascending UTC start order; start=end emits none, start>end
fails. It does not clip buckets to the requested range. Bucket start is the
candidate key. The planner derives a conservative finite calendar-count bound
from the admitted year range and input interval, then enforces actual row/byte
ceilings. TZDB transition tables are checked local semantic artifacts, not
implicit provider acquisition.

<!-- requirement-block: calendar.identity -->
Calendar Plans MUST pin the TZDB version, canonical transition-table bytes
and conversion-law identity in Check Environment and semantic dependencies.
Missing artifacts prevent a runnable Plan; data cannot select a different zone
or database during execution. DST buckets need not be 24 hours. Generated
calendar rows carry no external absence evidence. Independent vectors cover
leap years, quarter/year boundaries, both weekly origins, folds, gaps, skipped
days, coincident boundaries and version-sensitive historical transitions.

<!-- requirement-block: calendar.transition-artifact -->
The selected transition artifact MUST be exact canonical JSON with closed shape
`{version: "actql-tzdb-table/0.1", tzdb_version, conversion_law:
"actql-calendar-boundaries/0.1", coverage_start_ms: -62135596800000,
coverage_end_ms: 253402300800000, zones}`. Coverage is UTC year 0001 inclusive
through year 10000 exclusive; lookup outside it fails without extrapolation.
`tzdb_version` is the nonempty external release identifier selected by Check
Environment, not an ActQL-owned version. `zones` maps exact nonempty names to
closed `{initial_offset_seconds, transitions}` objects; each transition is closed
`{at_ms, offset_seconds}`. Times are exact safe-integer UTC milliseconds,
strictly increasing and interior to coverage. Offsets are signed 32-bit integer
seconds excluding -2147483648. Initial offset holds at coverage start; each
transition changes the offset at its instant. Repeated offsets are omitted from
this offset-only representation, regardless of abbreviation or DST-label changes.
The map includes `UTC` with zero initial offset and no transitions. Other selected
names, including aliases, retain exact spellings and complete offset tables.

<!-- requirement-block: calendar.artifact-admission -->
Artifact admission MUST compare the original bytes' SHA-256 CID and external
release identifier against the independently selected Check Environment pins,
reject noncanonical bytes without repair, and validate table structure within
explicit byte, node, depth, zone and cumulative transition ceilings before
exposing a profile. The conversion-law domain identifies the Calendar boundary
rules above, including earliest fold resolution, gap advancement and coincident
boundary collapse; it is not a Host-selectable interpretation. A matching CID
proves selected-byte integrity, not independent IANA authenticity. Establishing
release provenance belongs to selection of the trusted semantic artifact.
Synthetic tables test admission but do not establish historical TZDB or Calendar
conformance. Exact-name lookup has no locale, case-folding, alias inference or
ambient database fallback.

<a id="dedupe-events"></a>

#### `dedupe_events`

```yaml
- dedupe_events:
    by: [event_id]
    order_by:
      - {occurred_at: asc}
      - {source_sequence: asc}
```

<!-- requirement-block: dedupe-events.by-and-a-stable-non-empty-order-by-are-required dedupe-events.it-preserves-an-event-stream-and-must-fail-when-the dedupe-events.arrival-order-must-not-serve-as-an-implicit-tie-break -->
The shape matches `dedupe_rows`. `by` and a stable non-empty
`order_by` are REQUIRED. It keeps the first event in that order and
fails an unresolved top tie. It preserves an
event stream and MUST fail when the authored order cannot choose one record.
Arrival order MUST NOT serve as an implicit tie-break.

<!-- requirement-block: dedupe-events.partition-shape -->
The closed body MUST contain only `by` and `order_by`, using the same partition
and OrderKey rules as `dedupe_rows`: empty `by` selects one global partition,
repeated partition references remain in authored order, and `order_by` is
nonempty. An empty input yields no event, including for the global partition.
Partition fields require known KeyComparable contracts; order fields require
known AuthorOrderable contracts. Unrelated payload contracts and field-set
completeness may remain unknown. The operation retains the chosen events'
identity, clock encoding, payload, and window boundary values, but a repeated
key does not prove uniqueness or resolve a top tie. Existing duplicate event
IDs are not repaired by business-key deduplication.

<a id="asof-join"></a>

#### `asof_join`

```yaml
- asof_join:
    with: account_history
    kind: left
    by:
      - {left: account_id, right: account_id}
    left_id: event_id
    left_time: occurred_at
    right_time: valid_from
    direction: backward
    tolerance: 90d
    select:
      event_id: left.event_id
      owner_id: right.owner_id
```

<!-- requirement-block: asof-join.source-contract -->
The body MUST contain exactly `with`, `kind`, `by`, `left_time`, `right_time`,
`direction`, `tolerance`, `select`, and optionally `left_id` and
`right_tie_break`. `by` is a possibly empty array of exactly
`{left: Field, right: Field}` pairs. Empty `by` correlates across the entire
captured right Relation; repeated pairs retain authored order but neither
multiply candidates nor prove uniqueness. Each pair has compatible
KeyComparable types. `select` is a nonempty ordinary join alias map; repeated
source fields under different output aliases are allowed. `null_key` is not
an authored option. Explicit null is not omission for any optional member.

<!-- requirement-block: asof-join.temporal-domains -->
Both time fields MUST have complete non-null number or timestamp contracts.
Number values are safe-integer UTC milliseconds; timestamp values use canonical
UTC millisecond precision and are mechanically converted to that clock for
matching without changing their authored values or contracts. The two fields
may use different representations of this same clock. `tolerance` uses
`MillisecondValue`: a positive safe-integer millisecond number, a positive fixed
duration token, or a whole non-null number/duration Parameter. Parameter binding
does not bypass the positive safe-integer constraint. All time values and checked
distance arithmetic are validated before output is exposed, including rows with
no key match. The explicit `left_time` selects the comparison clock on either
Relation or Events input; it does not rewrite an Events carrier's intrinsic role.

<!-- requirement-block: asof-join.identity-evidence -->
Left identity MUST be complete, non-null and KeyComparable, with uniqueness
validated independently of its type. Relation `left_id` selects a single field;
when omitted, retained candidate-key evidence supplies the entire ordered key
tuple, never just its first field. Without that evidence omission fails during
Check. Events use their retained semantic identity; an explicit `left_id`, if
present, names that same role rather than replacing it. Internal ascending
identity order is the existing type-specific order, including internal Ref
identity order; this does not make Ref fields authored order keys. No implicit
stringification or hidden row CID replaces semantic identity.

<!-- requirement-block: asof-join.kind-left-inner-direction-backward-forward-nearest-and-positive-tolerance-are-required -->
`kind: left|inner`, `direction: backward|forward|nearest`, and positive
`tolerance` are REQUIRED. Relation input additionally requires `left_id` unless
a retained candidate key supplies it. Null join keys mean no match; this
is a TEA 0.1 law rather than an author field. An unresolved time tie
fails. The chosen right row must share the complete key
and be within tolerance. Backward chooses the greatest right time not after
the left time; forward chooses the least right time not before it; nearest
chooses minimum absolute distance. Equal candidates fail unless a complete
right candidate key supplies a compiler-journaled stable tie-break. Provenance
and `select` follow ordinary join rules. `left` preserves unmatched left rows
with null right fields; `inner` drops them. Results use stable ascending left
`(time, identity)` order.

<!-- requirement-block: asof-join.descending-business-priority-requires-an-explicit-preceding-derive-that-produces -->
`right_tie_break` is an ordered list of field names in ascending order.
Descending business priority requires an explicit preceding `derive` that
produces an ascending surrogate; a compiler MUST NOT infer direction from a
field name or input order.

<!-- requirement-block: asof-join.tie-evidence -->
Each authored `right_tie_break` field MUST be AuthorOrderable; ascending null
placement is last. An empty list supplies no authored tie evidence. Repeated
fields and their order are retained, without strengthening uniqueness. A valid
complete right candidate key can complete either an omitted or an insufficient
authored tie-break, with that completion recorded in the compiler journal.
Absent such evidence, equal first-place candidates fail rather than selecting
input order or a hidden identifier. Merely naming fields is not proof that their
tuple is unique. A nearest tie can involve different right timestamps at equal
distance, not only two rows at the same timestamp.

The output has at most one row per left occurrence and therefore inherits the
checked left row-count upper bound. Search-work and allocation ceilings remain
separate requirements; a small output bound does not authorize an unbounded
right scan. Empty input and no-match results refer only to the captured operands,
not to unobserved external coverage. None of these static contracts authorizes
execution before the remaining value, identity, tie and resource obligations are
discharged.

<a id="sequence"></a>

#### `sequence`

```yaml
- sequence:
    by: [customer_id]
    time: occurred_at
    id: event_id
    pattern:
      - {as: opened, where: {eq: [{field: event_type}, {literal: opened}]}}
      - {as: purchased, where: {eq: [{field: event_type}, {literal: purchased}]}}
    within: 30m
    overlap: disallow
    contiguity: subsequence
```

<!-- requirement-block: sequence.source-contract -->
The closed body MUST contain `by`, `id`, `time`, `pattern`, `within`, `overlap`
and `contiguity`, with only `max_matches_per_key` and `max_output_rows` optional.
`by` is a possibly empty list of KeyComparable fields: empty denotes one global
partition. Repeated grouping fields retain their source occurrences but do not
duplicate output columns or strengthen uniqueness. Each pattern element is
exactly `{as: label, where: predicate}`; the predicate has Boolean result type,
possibly nullable, and only true matches. It sees the original input fields and
Parameters, not fields captured by earlier pattern labels. Generated column names
obey the ordinary output-field name rules in addition to collision checks.
`id` is non-null and KeyComparable; on Events it names the retained semantic
identity, not a replacement identity. `within` uses `MillisecondValue`, and the
optional guards use `PositiveIntegerValue`; supplied Parameters retain binding
and value-validation obligations. Omitted guards insert no fixed language
default and still require resolved execution limits from current Host policy.

<!-- requirement-block: sequence.the-key-event-time-event-identity-at-least-two-pattern sequence.pattern-as-labels-must-be-non-empty-and-unique -->
The key, event time, event identity, at least two pattern elements, positive
`within`, explicit `overlap: allow|disallow`, and explicit
`contiguity: adjacent|subsequence` are REQUIRED. `adjacent` permits no
non-matching event between pattern elements; `subsequence` may skip them but
all selected events remain ordered and within the bound. Each pattern
predicate uses the closed RelA predicate grammar. Pattern `as` labels MUST be
non-empty and unique. Selected event indices are strictly increasing
(`i1 < i2 < ... < in`), so one event record cannot satisfy two positions.
The inclusive temporal bound is
`last.event_time_ms - first.event_time_ms <= within`. Matching is in ascending
`(time,id)` order. `disallow` chooses the lexicographically earliest complete
match, emits it, and advances the per-key cursor to the event immediately
after that match's final selected event; skipped events before that final event
are consumed with the interval. `allow` emits every complete bounded match.
Output is a stable relation containing the key, match start/end, and the
authored label's `{label}_id` and `{label}_time_ms` for each pattern element.
It does not copy arbitrary event payload fields into the match relation. No
unbounded automaton or processing-time interpretation is permitted.

<!-- requirement-block: sequence.generated-output-contract -->
The match boundary fields MUST be exactly `match_start_ms` and `match_end_ms`,
both non-null numbers in UTC milliseconds. Each `{label}_id` retains the
complete non-null semantic event-identity contract, and each
`{label}_time_ms` is a non-null numeric millisecond value. Group fields retain
their contracts and appear once for each distinct authored grouping field.
All generated names must be distinct from one another and the retained group
fields. Collisions fail check, not overwrite or implicit renaming. Empty
results retain this complete contract.
<!-- requirement-block: sequence.a-breach-of-either-limit-must-fail-the-whole-operation -->
`max_matches_per_key` and `max_output_rows` are author guards as defined in
[Author guards, resolved limits, and Plan facts](#resolved-limits). They count matches for one key and total output matches respectively.
Both limits use current Host policy and any authored guards; this specification
does not define a static sequence match-count proof. A breach of either limit
MUST fail the whole operation without publishing partial matches.

<!-- requirement-block: sequence.the-authored-sequence-clock-must-satisfy-this-closed-carrier-contract -->
The authored sequence clock MUST satisfy this closed carrier contract: a
relation accepts a typed non-null UTC timestamp or numeric UTC-millisecond
field and inserts timestamp conversion when needed; an existing
`events` accepts only a typed non-null numeric millisecond field such as
`event_time_ms`; every other type is rejected during planning rather than
failing at runtime.

For `overlap: disallow`, cursor advancement and unique event-carrier identity
prove each emitted `{label}_id` to be a candidate key. For `overlap: allow`, no
individual label ID is inferred as a candidate key because an event may appear
in more than one match.

<!-- requirement-block: sequence.session-generated-session-start-ms-session-end-ms-and-session-id-must-not-collide-with-source -->
Event carrier record identity is the unique `to_events.id` value. Duplicate
record identity is invalid before session, dedupe, as-of, or sequence
semantics. Business duplicate keys belong in `dedupe_events.by`; they are not
carrier identity. Session-generated `session_start_ms`, `session_end_ms`, and
`session_id` MUST NOT collide with source fields. The complete event schema is
preserved alongside those generated fields.

<a id="graph-operations"></a>

### Graph operations (SGA)

`actql-sga/0.1` is the authoring-complete deterministic graph-value module. A
module claim covers graph construction, node/edge property matching, typed and
directed bounded traversal, stable node/path projection, shortest path,
connected components, degree/bounds, and pure structural graph changes.
Construction plus simple reachability alone is partial SGA support.

Unbounded traversal and a general graph-pattern language are outside 0.1. The
closed `traverse` shape below is sufficient for bounded repeated-edge and
authored hop-by-hop patterns without importing Cypher or arbitrary predicates.

<a id="master-data-boundary"></a>

#### Master-data graph boundary

The SGA module does **not** define canonical-entity or persistent-MDM
semantics. A graph node identifier is only an authored semantic identity. It
is not proof of any of the following distinct concepts:

- canonical entity identity;
- source-record binding;
- entity type;
- merge or split lineage; or
- entity-resolution evidence.

<!-- requirement-block: master-data-boundary.an-implementation-must-not-infer-those-concepts-from-an-ordinary master-data-boundary.it-must-reject-authoring-terms-such-as-canonical-entity-bind-source-record-merge-entity -->
An implementation MUST NOT infer those concepts from an ordinary node, edge,
label, property, or vector score. It MUST reject authoring terms such as
`canonical_entity`, `bind_source_record`, `merge_entity`, or `split_entity` as
unsupported unless a future separately versioned MDM module is explicitly
claimed.

<!-- requirement-block: master-data-boundary.ordinary-graft-graph-union-graphs-and-subtract-graphs-are-pure-graph-value-computation-and -->
The 0.1 SGA module is a computation carrier rather than an authority-bearing
persistent master graph. ActQL 0.1 does not define persistent graph source
versions, graph-delta proposals, compare-and-swap base versions, merge/split
preview, approval, apply, or graph-mutation receipts. Ordinary
`graft_graph`, `union_graphs`, and `subtract_graphs` are pure graph-value
computation and MUST NOT be presented as persistent entity mutation or
authorization. `apply_graph_delta` is pure computation over captured graph
values, not persistent MDM identity change, provider mutation, approval or
application to an external graph store.

MDM completeness remains a separate future profile. Property match and typed
traversal/path query are part of SGA 0.1 and do not imply MDM authority.

<a id="graph-construction"></a>

#### `graph`

```yaml
- graph:
    nodes:
      from: customers
      id: customer_id
      fields: [name, segment]
    edges:
      from: interactions
      source: customer_id
      target: product_id
      label: relation
      fields: [occurred_at]
  as: customer_graph
```

<!-- requirement-block: graph-construction.node-and-edge-branches-must-name-relation-inputs graph-construction.id-source-and-target-are-semantic-identity-fields-and-must -->
Node and edge branches MUST name relation inputs. The compiler deterministically
inserts branch filters and projections before
`BRIDGE.rows.to_graph`. `id`, `source`, and `target` are semantic identity
fields and MUST be explicit. ActQL 0.1 supports directed graphs only.
Direction is therefore a language invariant recorded in the Plan, not an
authoring field.

<!-- requirement-block: graph-construction.source-forms -->
Construction MUST use either both named `nodes` and `edges` branches, or the
concise `{source, target, label?}` current-Relation form, never a mixture. The
explicit form has no implicit current operand, requires step `as`, and rejects
step `from`. Branch names are independently resolved, retaining both occurrences
when they name the same Relation. Branch bodies are closed: nodes has `from`,
`id`, optional `fields`; edges has `from`, `source`, `target`, optional `label`
and `fields`. Input filtering, if authored, is an upstream operation.

<!-- requirement-block: graph-construction.identity-domains -->
Node IDs and both endpoint fields MUST have known non-null KeyComparable types
with compatible domains under recursive common-type rules. They retain that
common identity type, not an implicit string encoding. Endpoint-derived nodes
use the semantic name `node_id` and have no properties. Type compatibility does
not establish uniqueness, payload agreement or observed endpoint membership.

<!-- requirement-block: graph-construction.property-projection -->
An explicit `fields` list MUST have distinct existing field references; an empty
or omitted branch list selects no properties. Already selected identity/label
roles are not duplicated as properties if listed. Other selected property names
must be flat authored names; qualified inputs require upstream aliasing.
The concise form retains all non-role edge properties and their known field/type
evidence. Unknown remaining properties are not replaced by a closed empty map.

<!-- requirement-block: graph-construction.label-completion -->
Explicit label roles MUST have a known string type, with nullable strings
allowed for absent labels. Only the concise form completes an omitted label
from a statically known `edge_type` field, otherwise a known `rel` field, in
that priority order; an explicit label overrides completion. Completion is
journaled. A field retained only in explicit `edges.fields` never establishes
a semantic label role. Known role type and a proven closed label-value domain
are separate evidence; construction does not invent a closed value domain.

<!-- requirement-block: graph-construction.before-graph-construction-the-compiler-must-close-both-edge-endpoints -->
When an explicit `nodes` branch is present, it defines the complete graph node
universe. Before graph construction the compiler MUST close both edge
endpoints against that node identity using deterministic equality joins;
edges whose source or target is absent are excluded. This is induced-graph
construction, not implicit entity creation, and is journaled as
`actql.graph.endpoint-closure-completion`. Duplicate or conflicting node
identity remains an error under the rules below.

SGA 0.1 is a directed simple property graph. Node identity is the declared
node ID. Edge identity is the canonical tuple `(source_id, target_id,
edge_type)`, where absent edge type is canonical null. Parallel edges with the
same tuple are not admitted. Duplicate node or edge declarations collapse only
when their complete canonical payloads are equal; an identity-equal payload
conflict fails graph construction. Equal duplicate payloads collapse by this
fixed identity law; authors do not request a separate branch-level distinct
operation.

<!-- requirement-block: graph-construction.for-the-concise-relation-form-a-statically-known-field-named graph-construction.any-typed-traversal-or-shortest-path-constraint-over-edge-types-must-fail graph-construction.the-compiler-must-not-reinterpret-an-arbitrary-retained-property-as -->
The authored `edges.label` field is semantic graph type evidence; listing a
field only under `edges.fields` preserves a property but does not turn it into
the traversal label. For the concise relation form, a statically known field
named exactly `edge_type` or `rel` is the sole deterministic completion for
`edges.label` and MUST be journaled. Any typed traversal or shortest-path
constraint over `edge_types` MUST fail check when the graph has no semantic
edge-label evidence. The compiler MUST NOT reinterpret an arbitrary retained
property as an edge label.

<!-- requirement-block: graph-construction.external-opaque-graphs-without-that-evidence-may-be-normalized-or -->
Every typed graph carrier binds a complete node-property schema, edge-property
schema, node identity, edge identity rule, and optional closed label/type
evidence. External opaque graphs without that evidence may be normalized or
projected, but property predicates MUST fail check because their fields cannot
be proven. Normalization preserves the opaque evidence level. Projection
retains only the field and type evidence actually known, including unknown or
columns-only Relation evidence where appropriate; it does not replace unknown
properties with an empty closed schema or invented `json` contracts. Later
consumers and Result publication retain their ordinary proof requirements.

For a plain edge-list relation, the shorter form is deterministic:

```yaml
- graph:
    source: caller_service
    target: callee_service
```

The compiler derives the node relation as the distinct union of both endpoint
columns and retains no undeclared node metadata. No undirected authoring form
exists in ActQL 0.1.

<a id="graph-rows"></a>

#### `node_rows` and `edge_rows`

These operations convert a graph to relation rows using the corresponding AoA
bridge. Bare `to_rows` is not accepted for a graph because node rows and edge
rows are distinct meanings.

<!-- requirement-block: graph-rows.fields-and-aliases -->
Graph row projection MUST retain the admitted identity types and property
evidence. Node rows expose `id` and declared node properties; edge rows expose
`src`, `dst`, nullable-string `rel` and declared edge properties. Absent edge
labels are explicit null. No undeclared node display-label column is invented.
Known authored identity/endpoint/label names are additional aliases of their
corresponding bridge roles; an alias identical to its own role adds no column.
Aliases retain their field provenance, not nested-property interpretation.
These source-role names are not members of `graph_contract_cid`. Diff retains
the base's names for its common contract metadata; Apply restores the base's
names over the pinned output value contract.

<!-- requirement-block: graph-rows.collisions-and-unknown-evidence -->
Projection MUST reject collisions between distinct output roles, aliases and
properties rather than silently overwrite a value. Unknown property sets remain
open, and unknown identity/property types remain unknown rather than becoming
string or json. Runtime graph admission rejects collisions that cannot be ruled
out from partial evidence. Projection alone does not prove row order, unique
keys, successful data admission or bounded execution.

<a id="degree"></a>

#### `degree`

```yaml
- from: customer_graph
  degree:
    direction: out
```

<!-- requirement-block: degree.direction-is-required-and-must-be-in-out-or-both degree.direction-is-required-and-must-be-in-out-or-both.second -->
`direction` is REQUIRED and MUST be `in`, `out`, or `both`. The result is a
relation containing exactly `node` and `degree`. Join `node` back to a source
relation explicitly when source metadata or a different public field name is
required.

<a id="reach"></a>

#### `reach`

```yaml
- from: customer_graph
  reach:
    start: customer_42
    direction: out
    max_depth: 2
```

<!-- requirement-block: reach.start-explicit-direction-in-out-both-and-positive-integer-max-depth-are-required reach.when-the-graph-was-authored-with-a-semantic-node-id reach.it-must-not-require-the-author-to-route-through-carrier-only -->
`start`, explicit `direction: in|out|both`, and positive integer `max_depth`
are REQUIRED. The operation lowers to
`SGA.reachable`. When the graph was authored with a semantic node ID other than
the AoA carrier name `id`, the compiler MUST restore that semantic name in the
relation result. It MUST NOT require the author to route through carrier-only
identity spellings.

`reach` is the concise form of `traverse` with one start identity, no property
filter, homogeneous edges, `min_hops: 0`, `emit: nodes`, and the authored
direction and `max_depth`. The compiler journals this expansion. There is no
outgoing-direction default.

<!-- requirement-block: reach.typed-result-and-semantic-alias -->
The closed `reach` body admits only `start`, `direction` and `max_depth`.
`start` is one explicit value admitted under the semantic node-ID contract;
authored JSON cannot issue an opaque Ref. `max_depth` is a positive finite
integer-valued number, not a resolved Host ceiling. The result follows the
node-emitting traversal shape: `start_id` and `node_id` retain the semantic ID
type, and `depth` is a non-null number holding the minimum hop count. The start
node is included at depth zero. A declared semantic node name other than
`node_id` is an additional alias of the reached `node_id`, not a renamed
`start_id`; collisions with distinct fixed output columns MUST fail during
check. No other node properties are implicitly projected. This output-shape
clarification does not create uniqueness, order or resource proofs at check.

<a id="graph-property-match"></a>

#### Property match

```yaml
- from: customer_graph
  match_nodes:
    where:
      and:
        - {eq: [{field: entity_type}, {literal: company}]}
        - {in: [{field: country}, {literal: [JP, US]}]}
    fields: [node_id, name, domain]
```

```yaml
- from: customer_graph
  match_edges:
    types: [owns, subsidiary_of]
    where: {eq: [{field: active}, {literal: true}]}
    fields: [edge_id, source_id, target_id, edge_type]
```

<!-- requirement-block: graph-property-match.fields-is-required-the-compiler-must-not-expose-undeclared-carrier graph-property-match.fields-is-required-the-compiler-must-not-expose-undeclared-carrier.second graph-property-match.a-graph-lacking-a-requested-property-or-identity-must-fail -->
Both operations use the closed RelA predicate grammar over statically known
node or edge properties. `fields` is REQUIRED; the compiler MUST NOT expose
undeclared carrier fields. Node results are ordered by semantic node identity.
Edge results are ordered by semantic source identity, target identity, edge
type, then edge identity. A graph lacking a requested property or identity
MUST fail during check.

<!-- requirement-block: graph-property-match.closed-selectors-and-projections -->
`match_nodes` admits only `ids`, `where` and `fields`, with exactly one of `ids`
and `where`. `ids` is a nonempty array of explicit values admitted under the
semantic node-ID contract, without string conversion or implicit Parameter
substitution. Authored JSON alone cannot establish an opaque Ref as specified
in [Opaque reference values](#opaque-references). Repeated IDs remain in the
authored representation; membership selection deduplicates them and requires
every selected identity to exist before publication. `match_edges` admits only
`types`, `where` and `fields`; both filters are optional and, when present, are
conjoined. `types` contains nonempty normalized strings. An empty type list
selects no edges, while absence does not filter types. Repeated types do not
repeat output rows and remain in the authored representation.

Both `fields` lists MUST be nonempty and free of repeated references. Their
order is the output projection order. Predicates admit nullable boolean and
retain only rows for which the result is true. Only referenced fields require
static type evidence; unrelated unknown property types do not invalidate a
match. Visible identity and label names come from declared semantic roles, not
implicit carrier aliases. Matching does not create a missing edge identity.

<a id="traverse"></a>

#### `traverse`

Homogeneous bounded traversal uses:

```yaml
- from: customer_graph
  traverse:
    start: {ids: [company:A]}
    edge_types: [owns]
    direction: out
    min_hops: 1
    max_hops: 3
    emit: paths
```

An authored typed pattern uses `hops` instead of `edge_types`, `direction`,
`min_hops`, and `max_hops`:

```yaml
- from: customer_graph
  traverse:
    start: {where: {eq: [{field: entity_type}, {literal: customer}]}}
    hops:
      - {edge_types: [purchased], direction: out}
      - {edge_types: [belongs_to], direction: out,
         node_where: {eq: [{field: entity_type}, {literal: category}]}}
    emit: nodes
```

All graph node selectors in traverse.start, reach.start, subgraph.nodes and
shortest_path.source/target share membership admission: explicit IDs and IDs
read from a selector Relation are deduplicated and every selected ID must
exist in the admitted graph. Missing IDs fail before traversal, not an empty
path result. An empty Relation or predicate selection remains a valid empty
selection. Membership admission does not demand traversal edge/node predicates;
a selector's own where predicate still selects from its declared node scope.

`start` is exactly one of non-empty `ids`, a named relation plus `id` field, or
a node `where` predicate. Direction is `in`, `out`, or `both`. Homogeneous
traversal requires non-negative `min_hops`, positive `max_hops`, and
`min_hops <= max_hops`. `hops` is a non-empty finite list; each hop requires
direction and may constrain edge types, edge properties, and the reached node.
No implementation may widen the authored maximum.

<!-- requirement-block: traverse.closed-modes-and-filters -->
The closed body MUST admit only `start`, `emit`, optional `max_output_rows`, and exactly
one traversal mode. Homogeneous mode requires literal finite integer-valued
`min_hops` and `max_hops` in the stated ranges and explicit `direction`, with
optional `edge_types`. Pattern mode instead requires a nonempty `hops` array
and rejects all four homogeneous members. Each hop admits only `direction`,
optional `edge_types`, `edge_where`, and `node_where`. A pattern follows its
entire ordered hop list. Predicates require nullable or non-null boolean and
retain only true. Edge-type lists contain nonempty normalized strings; absence
does not filter types, empty lists admit no matching edge, and repetition does
not repeat paths. Any authored list, including an empty one, requires semantic
edge-label evidence. An empty selection does not bypass static checks.

`emit: nodes` returns `start_id`, `node_id`, and minimum `depth`, ordered by
those fields. `emit: paths` additionally requires semantic edge identity and
returns `start_id`, `end_id`, `hop_count`, `node_ids`, and `edge_ids`. Paths are
simple (a node cannot repeat) and are ordered by start identity, hop count,
node-identity sequence, then edge-identity sequence using AoA canonical value
order. Duplicate paths are removed by exact identity.

<!-- requirement-block: traverse.typed-edge-identity-records -->
In traversal and shortest-path output, each `edge_ids` element MUST be the
closed record `{src, dst, rel}` representing the pinned SGA edge-identity tuple.
`src` and `dst` retain the semantic node-ID type; `rel` is the semantic label
or explicit null. These are the edge's original directed endpoints, even when
the path traverses that edge in the incoming direction. Ordering compares the
semantic tuple `(src, dst, rel)`, not JSON field order or serialized text.
No provider edge locator, string conversion, property named `edge_id`, or
newly computed CID substitutes for this identity. This fixes the output
representation of the existing edge-identity law; it does not issue new IDs.

<a id="shortest-path-and-components"></a>

#### `shortest_path` and `components`

```yaml
- from: customer_graph
  shortest_path:
    source: company:A
    target: company:B
    edge_types: [owns, subsidiary_of]
    direction: out
    max_hops: 8
```

<!-- requirement-block: shortest-path-and-components.closed-body -->
The closed body MUST admit only source, target, selection, direction, max_hops,
weight, edge_types and max_output_rows. Source, target and direction are explicit;
direction is in, out or both, and max_hops is a positive finite integer-valued
number. Optional edge_types follows the homogeneous traverse filter rules,
including semantic label evidence, empty filters and retained repetitions.
No max_paths option or implicit output ceiling is added.

<!-- requirement-block: shortest-path-and-components.max-hops-is-required -->
`max_hops` is REQUIRED. Without `weight`, paths have unit edge cost; optional
`weight` names a non-null number edge field. Every admitted edge cost is finite
and nonnegative; invalid costs fail input admission, not merely a visited path.
Costs fold in path-edge order with binary64 rounding after each addition;
overflow enters an internal overrange state, ordered after every finite cost.
Overrange is absorbing for subsequent nonnegative additions and is not a
public number or Infinity. Nonselected overrange candidates do not fail the
operation. If any selected path is overrange, the whole operation fails before
publication, never returning an empty result in place of that path. Overrange
candidates tie on cost and use the ordinary hop/identity tie-breaks. These
rules are independent of exploration and early termination strategy; negative
or non-finite input edges still fail admission even when unvisited.
For each_pair, one selected overrange path fails every pair atomically; other
finite pairs are not published. Authors may explicitly validate admissible
weights upstream; there is no weight-ceiling author guard in this vocabulary.
Paths are simple and satisfy the hop bound. Compare by total
cost, then hop count, then lexicographic node/edge identity sequence, using the
same identity order as `traverse`. No path produces an empty relation.

`source` and `target` accept a single ID or the same closed IDs/Relation/where
selector as `traverse.start`. A set selector requires explicit
`selection: nearest_per_source|each_pair|nearest_pair`; two single IDs omit it
and mean each_pair. Deduplicate selected identities and require membership in
the graph; an empty selected Relation or predicate result yields no paths.
Nearest_per_source selects one path from each source to the target set;
each_pair selects at most one per pair; nearest_pair selects at most one
overall. Cross-pair ties add source then target identity after cost and hops,
before path sequence. Source=target admits the zero-hop zero-cost path.
Output has source_id, target_id, total_cost, hop_count, node_ids, edge_ids and
is ordered by source then target identity. `max_output_rows` is an optional
guard; search-work and output ceilings are separate. Weighted search with a
hop cap preserves the cap during optimization, not by filtering the result of
an unconstrained shortest-path algorithm.

```yaml
- from: customer_graph
  components:
    kind: weak
```

`kind` is `weak` or `strong`. The result schema is exactly `node_id`,
`component_id`, and `component_size`. `node_id` is the semantic graph node
identity, `component_id` is the canonically least semantic node identity in
the component, and `component_size` is its positive member count. Results are
ordered by component identity then node identity.

<a id="structural-graphs"></a>

#### Structural graph operations

<!-- requirement-block: structural-graphs.delta-application-is-not-an-actql-0-1-source-operation-the -->
`normalize_graph` lowers to `SGA.normalize`. `graph_bounds` requires at least
one non-negative `max_nodes`, `max_edges`, or `max_degree` and lowers to
`SGA.bounds_check`. Delta application uses only [apply_graph_delta](#graph-equality-and-delta);
the compiler MUST NOT synthesize an application from prose or untyped data.

<!-- requirement-block: structural-graphs.bounds-report -->
`graph_bounds` MUST return a Relation with exactly `kind: string`,
`node_id: nullable semantic graph ID`, `actual: number`, and `max: number`.
The body admits only `max_nodes`, `max_edges` and `max_degree`, at least one
present, each a nonnegative safe-integer literal or a whole non-null number
Parameter subject to that range at binding. A violated node/edge count emits
`kind: nodes`/`edges` and `node_id: null`; a violated total degree emits
`kind: degree` and the original semantic node ID. Total degree counts both
incoming and outgoing incidences, including two for a self-loop. Only strict
excess (`actual > max`) emits a row; satisfied bounds, including empty input
under zero bounds, emit no rows. Emit the node-count violation, then edge-count
violation, then degree violations in canonical semantic node-identity order.
These thresholds select diagnostic rows, not execution-resource ceilings:
violations do not truncate or mutate the graph or themselves fail the operation.
Data admission and resource failures retain their ordinary failure boundaries.
The adapter supplies explicit nulls instead of the AoA representation's absent
`node_id` member for whole-graph violations.

Binary graph operations name the second graph with `with`:

```yaml
- graph_diff: {with: previous_graph}
- graft_graph: {with: additions}
- union_graphs: {with: peer_graph}
- subtract_graphs: {with: removals}
```

Property-bearing structural union/subtraction uses the closed form:

```yaml
- union_graphs:
    with: peer_graph
    merge:
      node_properties:
        tags: set_union
        score: number_max
      edge_properties:
        observed_at: number_max
```

An unspecified property conflict fails; this is a graph law rather than
an author field. Field strategies are
`exact_equal`, `set_union`, `set_difference`, `number_sum`, `number_mean`,
`number_max`, and `number_min`. Set strategies require arrays interpreted as
canonical-value sets; numeric strategies require finite numbers. Missing and
null are values, not absence-compatible defaults: unless the named strategy
explicitly admits both operands, a one-sided or type-conflicting property
fails. The compiler lowers node and edge maps separately to AoA structural
field laws. Associativity/commutativity claims apply only to strategies whose
published AoA law says so; `set_difference` is directional.

They lower respectively to `SGA.diff`, `SGA.graft`, `SGA.union_structural`,
and `SGA.diff_structural`. `graph_diff` returns a relation; the other three
return a graph. Graph outputs must be consumed by a later graph operation or
converted with `node_rows`/`edge_rows`, because ActQL 0.1 artifacts are
relation outputs.

`graft_graph` is add-only: identity-equal complete payload is idempotent and a
different payload fails. In `union_graphs` and `subtract_graphs`, every
property without an authored strategy fails on conflict as a fixed language
law; this is not a source completion and creates no normalization entry. An
authored structural merge policy must name every non-failing property
strategy; no last-write or provider-order precedence exists.
Subtraction is identity-based and conflicting payload evidence fails unless the
authored merge contract explicitly admits the structural difference.

<!-- requirement-block: structural-graphs.property-contracts-and-strategies -->
Graft, structural union and subtraction MUST require the same node-property and edge-property
field sets respectively, with compatible recursive value domains. The common
type rules join nullability and extents; missing properties are not filled with
null. A present record must contain every declared property even when nullable.
Empty graphs retain those contracts and do not bypass compatibility checking.
An entity present only on one side is distinct from a missing property in a
present entity: union keeps its complete record without applying a binary
property strategy, while subtraction keeps only left-only entities.

On a shared identity, an explicitly named strategy applies even when its two
values are equal. `exact_equal` requires typed value equality and returns that
value; a property without a strategy has the same equality requirement.
`number_sum`, `number_mean`, `number_min` and `number_max` require two finite
number values and compute addition, binary pairwise average, minimum and maximum
respectively. `set_union` and `set_difference` require arrays with compatible
item domains and compute canonical typed-value set union and left difference.
Nullable property contracts may reach these strategies, but an actual null
numeric or array operand fails before result publication: null is never zero
or an empty array. Null array elements are ordinary members when their item
contract admits null. Set results contain one representative per typed equality
class in canonical typed-value order. Output contracts must cover both shared
identity results and untouched one-sided records; no non-null or size proof
may be inferred from the strategy alone for those untouched records.

<!-- requirement-block: structural-graphs.subtraction-entity-and-property-laws -->
Subtraction MUST treat the node and edge strategy maps independently. For a shared
identity with no nonempty strategy map for its entity kind, equal complete
payloads remove the entity and a payload conflict fails. With a nonempty map,
apply its property strategies and the equality requirement for unlisted
properties, then retain the transformed entity. An explicit `exact_equal`
entry is a strategy, not an entity-removal instruction. A zero, empty array,
or unchanged transformed payload never implicitly deletes its entity.
Strategy names keep their meaning in both operations: `number_sum` remains
addition in subtraction, not a context-dependent spelling for subtraction.
After node subtraction, remove every remaining edge whose endpoint is absent
from the retained node set. This induced endpoint closure never resurrects a
deleted node. It is specific to subtraction and does not change the exact
endpoint/admission rules of `apply_graph_delta`.

Thus union is not unconditionally idempotent under explicit non-idempotent
strategies, and subtraction is not unconditionally self-annihilating under
explicit transformation maps. In particular a shared value 2 under
`number_sum` becomes 4, including when subtracting a graph from itself with
that strategy. Unconditional versions of those algebra laws cannot justify
an optimization or be retained as the admitted law for these operations.

`graph_diff` returns exactly one relation row with field `delta`. That result
has the checked Delta contract defined in [Graph equality and Delta](#graph-equality-and-delta),
and can be inspected, retained or applied as pure computation.

`union_graphs.with` additionally accepts a nonempty finite graph-reference list.
The current graph is first, followed by that list in declaration order;
left-fold the specified binary operation. This list order is semantic.
Reassociation or permutation is legal only if every admitted field law and
its failure behavior proves the transformation. In particular, pairwise
number_mean is not a global mean; use [mean_graphs](#graph-mean).

<!-- requirement-block: structural-graphs.a-breach-must-fail-the-whole-operation-without-publishing-a -->
Traversal path exploration receives a resolved Host ceiling in the machine
Plan; `max_paths` is not authoring vocabulary. `traverse.max_output_rows` and
`components.max_output_rows` are author guards as defined in [Author guards, resolved limits, and Plan facts](#resolved-limits), counting
the emitted traversal rows or component membership rows respectively.
`shortest_path` has bound 0..1 for single IDs or nearest_pair, at most source
count for nearest_per_source, and at most the source/target count product for
each_pair; component output
is bounded by the graph node proof and Host policy. A breach MUST fail the
whole operation without publishing a partial graph/path Relation.

<a id="subgraph"></a>

#### `subgraph`

`subgraph: {nodes, edges?}` consumes a graph and returns a graph. `nodes`
uses the same closed IDs/Relation/where selector as `traverse.start`.
Selected IDs are deduplicated; explicit IDs absent from the graph fail.
An empty selected Relation or predicate result selects no nodes. Retain
selected nodes and exactly those original edges whose two endpoints are
selected. Optional `edges` is a boolean expression in the `match_edges`
scope, applied after this induction; only true retains an edge. Removing an
edge does not remove either endpoint. Ego extraction composes bounded
`reach`/`traverse` with this selection; it does not require another traversal
syntax inside `subgraph`.

<!-- requirement-block: subgraph.preservation -->
Selection MUST preserve retained semantic identities, labels, property
contracts and values, canonical graph order, policy and observation scope;
it neither invents edges nor upgrades completeness or authority. Output
node/edge counts are bounded by input counts; selector evaluation and graph
materialization have separately resolved work and byte ceilings. No partial
graph is published on failure.

<a id="graph-equality-and-delta"></a>

#### Graph equality and Delta

`graphs_equal: {with: graph_name}` returns exactly one row with non-null
boolean `equal`. Compare canonical admitted graphs by semantic node and edge
identities, labels and typed property values, independently of input array
enumeration or acquisition identity. Both graphs require the same structural
identity law and compatible closed property domains. This is not graph
isomorphism or approximate similarity. Invalid input fails admission rather
than returning false. Use ordinary `assert_rows` on this result for an
execution assertion; equality of arbitrary future inputs is not a static
type-checking guarantee.

`graph_diff: {with: target}` computes a Delta from the current base graph to
the target. Its one-row `delta` field is a non-null closed object with
`version: "actql-graph-delta/0.1"`, `base_graph_cid`, `target_graph_cid`,
`graph_contract_cid`, `nodes` and `edges`. The three CID fields are canonical
string identities, not capability references. Each of `nodes` and `edges`
is a non-null closed object with non-null arrays `add`, `remove`, `update`.
Add/remove elements are complete after/before records respectively; update
elements are closed `{before, after}` objects of complete records with the
same semantic identity. Their checked item types come from the graph contract,
including for empty arrays. Arrays are sorted by the graph identity order.
Unchanged records are absent; an identity occurs in at most one action array
per entity kind. A changed identity is a removal and addition, not an update.
The graph contract fixes all record fields and equality laws; no patch paths,
arbitrary JSON instructions or implicit property merge exist.

<!-- requirement-block: graph-equality-and-delta.complete-records -->
Delta node records MUST use the closed shape `{id, props}` and edge records
the closed shape `{src, dst, rel, props}`. IDs retain the common contract's
semantic node-ID type without string conversion; `rel` is the semantic edge
label as nullable string, with explicit null for absent type. Each non-null
`props` object contains exactly its complete node/edge property field set;
an empty property map is `{}`, not an omitted member. These wrappers prevent
business properties named `id`, `src`, `rel` or `props` from shadowing identity
members. A node display label, if retained by a source mapping, is an ordinary
declared property, not an undeclared extra Delta member. The adapter does not
copy AoA's optional or partial update records into this complete-record format.
Before and after snapshots are admitted under the one common graph contract;
closed edge-label evidence is the union of both known domains, or unknown when
either domain is unknown. Empty graphs do not weaken these contract requirements.

`apply_graph_delta: {with: relation_name, field: delta_field}` consumes the
base graph and exactly one Delta row; zero or multiple rows fail. Delta is
ordinary typed data with this additional semantic admission, not a new
Carrier or an authority-bearing token. Reading it grants no provider access.

<!-- requirement-block: graph-equality-and-delta.admission -->
Application MUST verify the closed shape, canonical ordering, graph contract,
base identity, unique action identities and exact before records before any
result publication. Add requires an absent identity; remove/update require
an existing exact before record. Apply the node and edge changes together,
then validate endpoint existence, complete result contracts and target CID.
No missing update is skipped and no incident edge is silently deleted.
`apply(A, diff(A, B))` yields the same canonical graph as B for admitted
compatible A and B. Wrong-base, malformed or inconsistent Delta fails;
rehashing its container does not bypass these checks. Diff/apply preserve
policy dependencies and have resolved graph/action/byte/work limits. They
perform pure computation only; external persistence remains an explicit
Effect. A Delta binds its exact base snapshot; applying it to a different
snapshot fails, even if the changed records happen to match. Rebase, Delta
composition and inversion are outside this vocabulary.

<a id="graph-mean"></a>

#### `mean_graphs`

<!-- requirement-block: graph-mean.closed-source -->
The body MUST contain exactly with, weights, support and properties. Weights
and support thresholds are literal numbers, not Parameter references. Both
property-strategy maps are required; an empty map is valid exactly when the
corresponding complete property domain is empty. Compatible property extents
and nullability are joined using the common typed-domain alignment rules.
Semantic row-role aliases survive only when all samples declare the same roles;
no sample-order winner supplies aliases for the generated graph.

`mean_graphs: {with, weights, support, properties}` is a generator over a
nonempty finite list of graph names. `weights` has one finite nonnegative
number per graph and positive total weight. `support` is a closed object
with `nodes` and `edges`, each a number in `(0, 1]`. `properties` has separate
`nodes` and `edges` maps naming every non-identity property and its strategy.
All graphs have the same identity law and closed property domains. List
positions are samples, so repeated graph names contribute their weight again;
zero-weight samples are validated but make no support or property contribution.
This is a statically finite graph list, not a dynamic Graph-valued Relation.

For each identity, support is the weight of samples containing it divided
by total weight. Retain nodes meeting node support, then edges meeting edge
support whose endpoints are retained. Compare support using exact rational
values of the bound binary64 weights and threshold, not a rounded quotient.
Labels for an identity must agree among positive-weight samples containing
it. Different entity IDs are not inferred to represent corresponding roles;
cross-company or cross-version alignment is an explicit upstream operation.

Property strategy is `exact_equal` or the closed object
`{mean: {missing: exclude|zero, nulls: exclude|zero|fail}}`. Exact_equal
requires equal typed values among positive-weight present records. Mean
requires number properties. Missing means the entire node/edge is absent
from a sample, not a declared property missing from an admitted record.
Exclude removes that sample's weight from the property denominator; zero
retains its weight with zero numerator; null fail rejects an observed null
on a retained identity. A zero denominator yields null, so the checked mean
property is nullable. Identity and labels are never averaged.

<!-- requirement-block: graph-mean.numeric-law -->
For example, three samples with weights 1, 2, 3 contain respectively value 6,
an observed null, and no record. With both policies exclude the mean is 6;
missing=exclude/nulls=zero gives 6/3=2;
missing=zero/nulls=exclude gives 6/4=1.5; both zero gives 6/6=1.
A present record missing a required property is invalid input, not either case.

Weighted property means MUST sum exact rational products of admitted
binary64 values and weights, divide by the exact contributing weight, and
round once to finite binary64, nearest ties-to-even; non-finite conversion
fails. No input-order winner, binary pairwise mean, or host-native reduction
substitutes for this rule. Canonical output order uses graph identity order.
Node/edge bounds are at most the respective input-count sums; sample work,
exact arithmetic and materialization have resolved ceilings. Mean preserves
observation scope and policy and grants no master-data authority. Structural
subtraction from this output is not automatically a statistical deviation.

<a id="vector-operations"></a>

### Vector operations (VecA)

`actql-veca/0.1` is the authoring-complete deterministic exact-vector module.
A module claim covers finite vector preparation, exact scoring/search, grouped
pooling, thresholding through RelA, stable ranking-list merge/dedupe,
per-query top-k, semantic identity restoration, and relation projection.
Row-local vector_score/vector_concat and reciprocal-rank fusion are included.
Normalization plus KNN alone is partial VecA support.

<!-- requirement-block: vector-operations.future-ann-access-must-be-a-separately-named-search-index-like-source vector-operations.future-ann-access-must-be-a-separately-named-search-index-like-source.second -->
Metadata filtering occurs in RelA before vector conversion and metadata is
rejoined in RelA after ranking; ActQL inserts only the typed carrier bridges.
Embedding generation and ANN are external reads. ANN access MUST use
[search_candidates](#candidate-search) with a SourceView binding explicit
index, model, filter and exactness identities; it MUST NOT weaken pure exact
`nearest`. There is no separate search_index operation.

<a id="vector-expressions"></a>

#### Row-local vector expressions

`vector_score(a, b, metric)` and `vector_concat(a, b, ...)` are common pure
expressions, not acquisition operations. Score's structured body is
`{left: a, right: b, metric: cosine|dot|l2}`; left/right are expression children
evaluated in that order and metric is structural. Concat's body is an ordered
expression array with at least two children. They compose at all ordinary expression positions, including
conditional branches and filtered aggregate arguments, under the common
demand and first-failure rules. Effect selectors retain their closed subset.

Score requires two vectors with identical positive dimensions and returns
a number. It shares nearest's f32 admission, dimension-order numerical fold,
zero-vector behavior, negative-L2 score orientation and pinned metric law.
It does not compare model identities or infer that two embedding spaces are
semantically interchangeable from dimensions alone. Such an application
constraint is checked by the source/model contracts used by the Program.

Concat requires at least two typed vectors. It preserves argument/component
order, yields dimensions equal to the checked sum, and performs no scaling,
averaging or L2 normalization. Its result components use the same f32 value
contract. Positional arguments evaluate eagerly and once; either function
returns null when any vector operand is null, after argument evaluation.

<!-- requirement-block: vector-expressions.bounds -->
The compiler MUST bind checked dimensions, metric law and component/work
ceilings to the expression root and preserve its demand conditions during
lowering. Overflow in dimension addition, incompatible types, unsupported
metric or unavailable profile is a check failure; invalid values and exceeded
evaluation limits fail only at their specified admission/evaluation boundary.
The same expression tree is used in derive, filter and aggregate consumers;
host callbacks or implicit carrier conversion are not alternative meanings.

<a id="nearest"></a>

#### `nearest`

```yaml
- from: candidates
  nearest:
    queries: queries
    candidate_id: product_id
    candidate_vector: embedding
    query_id: request_id
    query_vector: embedding
    metric: cosine
    k: 20
```

<!-- requirement-block: nearest.the-corpus-must-be-the-operation-s-step-input-the-immediately nearest.queries-positive-integer-k-and-metric-are-required nearest.metric-must-be-cosine-dot-or-l2 nearest.approximate-nearest-neighbor-execution-is-unsupported-and-must-not-be-silently -->
The corpus MUST be the operation's step input: the immediately preceding
result in a linear pipeline or the explicit step-level `from` result. The
`nearest` parameter object has no second corpus reference. This single wiring
surface prevents a filtered current relation from being silently replaced by
its unfiltered source input. `queries`, positive integer `k`, and `metric` are
REQUIRED.
`metric` MUST be `cosine`, `dot`, or `l2`. ActQL 0.1 nearest-neighbor
execution is exact; exactness is recorded in the Plan rather than
authored in source. Approximate nearest-neighbor execution is unsupported and MUST NOT
be silently substituted.

<!-- requirement-block: nearest.in-an-entity-resolution-workflow-it-may-generate-or-rank-candidate nearest.a-compiler-or-host-must-not-auto-merge-entities-solely-because -->
Vector similarity has no master-data authority. In an entity-resolution
workflow it may generate or rank candidate pairs, but it MUST NOT establish a
canonical entity, source binding, merge, or split. A future MDM workflow may
use VecA candidate generation followed by RelA comparison and explicit
evidence, but only an approved graph-binding delta may become authoritative.
A compiler or host MUST NOT auto-merge entities solely because a vector score
exceeds a threshold.

<!-- requirement-block: nearest.closed-source-and-role-consistency -->
The closed body MUST admit only queries, candidate_id, candidate_vector, query_id,
query_vector, metric and k. The k option is a positive safe-integer literal,
not a Parameter reference. Optional field references on an already-typed Vectors
input may restate its roles but cannot override them; an identity field reference
can restate only a singleton identity tuple. Unknown Vectors role and dimension
information remains an input-validation obligation before scoring and does not
invent a public identity type. A known role conflict fails during Check.

Relation inputs require explicit semantic ID and vector fields. Vector-set
inputs already carry those roles. The compiler inserts `BRIDGE.rows.to_vectors`
where necessary and lowers to `VEC.knn_join`. The ranking Relation exposes
`query_id`, `candidate_id`, `score`, and `rank`: the IDs contain the authored identity
values, not internal bridge record IDs. These two role names are fixed even
when the source identity fields have different names.
<!-- requirement-block: nearest.semantic-id-output -->
A single identity component MUST retain its value and type directly in its
fixed output role. A composite identity is represented by a non-null closed
record whose keys are the zero-based decimal positions `"0"`, `"1"`, and so on
in the Carrier's declared identity tuple. Each slot retains its original value
and type, including decimal or reference contracts. Input field aliases are not
encoded into this record. Identity comparison uses the ordered typed components,
not serialized record text or lexicographic ordering of position keys. This
representation does not make arbitrary objects KeyComparable or authorize a
string/CID replacement. It fixes the previously unspecified public tuple shape
without changing the Carrier's internal semantic identity.

Rank is a non-null positive safe integer: the one-based position in each
query's completed score-descending/candidate-identity order after top-k.
It is contiguous from one, not a dense rank or provider-supplied position.

<!-- requirement-block: nearest.every-such-completion-must-be-journaled-as-actql-vector-typed-field-completion-zero-or nearest.every-such-completion-must-be-journaled-as-actql-vector-typed-field-completion-zero-or.second -->
For relation inputs, the compiler MAY deterministically complete a side's ID
field only from that side's sole non-null string primary-key field, and MAY
complete its vector field only from that side's sole statically known
fixed-dimension vector field. Every such completion MUST be journaled as
`actql.vector.typed-field-completion`; zero or multiple candidates require an
explicit authored field and MUST NOT be guessed. `queries` and the step-level
`from` resolve in the available dataflow namespace ([Pipeline names and references](#pipeline-references)). No sigil stripping
or fuzzy name resolution is permitted.

<!-- requirement-block: nearest.zero-vector-and-non-finite-input-behavior-follows-aoa-veca-semantics-non-finite-input -->
Every finite vector component is quantized to IEEE-754 binary32 using
round-to-nearest, ties-to-even before scoring. Query groups are ordered by
query ID ascending. Within a query, results are ordered by score descending
then candidate ID ascending. Zero-vector and non-finite-input behavior follows
AoA VecA semantics; non-finite input MUST be rejected.

<!-- requirement-block: nearest.every-authored-vector-input-schema-must-declare-positive-dimensions-the -->
Every authored vector input schema MUST declare positive `dimensions`; the
canonical checked contract inserts the fixed 0.1 `element_type: f32` law.
Query/corpus dimension mismatch is a check error when
evidence is available and otherwise a runtime failure before scoring. Query
and candidate identities are globally unique within each carrier; duplicate
identity is invalid rather than an implicit dedupe. Cosine and dot scores use
their usual higher-is-better orientation. The canonical `l2` score is
**negative Euclidean distance**, so zero is best and all three metrics share
descending ranking order.

<a id="vector-arithmetic"></a>

#### Deterministic vector arithmetic

<!-- requirement-block: vector-operations.ordered-numeric-law -->
The pinned [VecA numeric law](../../spec/dependencies/aoa-veca-numeric-laws.json)
fixes the arithmetic shared by row-local vector expressions and Carrier
operations. Let R round each individual operation to binary64, nearest
ties-to-even, and Q round to binary32, nearest ties-to-even, represented
exactly in binary64. Admit finite input components through Q before use and
reject non-finite quantized values. Every arithmetic intermediate and output
must be finite. Neither an arbitrary magnitude ceiling nor Decimal128
arithmetic is implied by the finite binary64 score contract.

| Operation | Arithmetic after component admission |
| --- | --- |
| dot | Starting at +0, fold `R(sum + R(a[i] * b[i]))` in increasing dimension order. |
| cosine | Compute dot and each squared-norm fold separately in dimension order. If either norm-squared is zero, return +0; otherwise return `R(dot / R(R(sqrt(left_squared)) * R(sqrt(right_squared))))`. |
| negative L2 | For each dimension compute `d = R(a[i] - b[i])`; fold `R(sum + R(d*d))` from +0; return `-R(sqrt(sum))`. |
| normalize | Fold squared norm identically, compute `n = R(sqrt(sum))`, reject n=0, then emit each `Q(R(a[i]/n))`. |
| pool sum | For each dimension fold `R(sum + component)` from +0 in ascending semantic member-identity order, then emit Q(sum). |
| pool mean | Use the same sum; divide once by member count with R, then emit Q. No incremental mean. |
| pool max | Take the maximum admitted component among the nonempty group's members. No infinite sentinel is an admitted operand. |
| weighted ranking merge | Substitute +0 for a missing score; compute `R(R(left_weight * left_score) + R(right_weight * right_score))`. |

<!-- requirement-block: vector-operations.rounding-and-zero-boundaries -->
Square roots MUST be correctly rounded binary64 operations. Fused multiply-add,
reassociation, pairwise reduction, intermediate f32 accumulation and score
clamping cannot replace the prescribed tree. In particular rounded cosine
scores are not silently clamped to [-1,1]. All emitted zero scores and vector
components are canonical positive zero; internal arithmetic retains IEEE
signed-zero behavior. A nonzero source vector quantized entirely to zero is
a zero vector for scoring and normalization. Zero vectors are valid results
of pooling, but cannot be L2-normalized. Vector-valued output components use
the final f32 conversion; scores remain binary64. Empty grouped inputs create
no groups and no artificial zero-member pooled vector. These laws and their
independent fixed vectors must be pinned before an executable profile claim.

<a id="vector-bridges"></a>

#### Vector-set-preserving operations and explicit bridges

<!-- requirement-block: vector-bridges.explicit-roles -->
`to_vectors` MUST have a closed body containing `id` and `vector` field
references on its Relation input. The distinct selected roles require a complete
non-null KeyComparable identity contract and a non-null fixed-dimension vector
contract respectively. Other payload contracts and field-set knowledge remain
unchanged; no complete payload schema is required. The bridge retains authored
field names and semantic identity values without inserting physical `id` or
`vector` aliases, stringifying identities or replacing them with CIDs. Actual
identity uniqueness and finite component admission are separate validation
obligations. A backend unable to preserve the selected identity domain rejects
lowering explicitly rather than changing that domain.

```yaml
- to_vectors: {id: product_id, vector: embedding}
- normalize_vectors: true
- score_vectors: {query: [0.1, 0.2], metric: cosine}
- vectors: true
```

`to_vectors` and `vectors` lower to `BRIDGE.rows.to_vectors` and
`BRIDGE.vectors.to_rows`. `normalize_vectors` lowers to `VEC.normalize_l2`.
`score_vectors` requires a non-empty finite query vector and an explicit
`cosine`, `dot`, or `l2` metric, and lowers to `VEC.score_sort`. These forms
preserve the vector carrier until `vectors`; `nearest` remains the
two-input relation-returning exact KNN form.

<!-- requirement-block: vector-bridges.scoring-options -->
The `normalize_vectors` body MUST be exactly `true`; the `score_vectors` body
is closed and requires exactly `query` and `metric`. A query is either the
nonempty finite numeric array above or a whole Parameter reference whose
declaration is a non-null array of non-null numbers. A known exact query
length is checked against the carrier dimensions; otherwise matching dimensions
remain a validation obligation before scoring. Defaults are not type evidence,
and binding does not waive finite-component, nonempty or dimension validation.

<!-- requirement-block: vector-bridges.score-output -->
Scoring MUST preserve semantic identities, vector components and payload fields
and add a fresh non-null number field named `score`. An existing `score` field
is an output collision, and unknown field-set completeness does not prove its
absence. This fresh-field rule prevents silent payload replacement; repeated
scoring requires an explicit transformation that removes the previous score.
Normalization preserves these fields and their contracts except for replacing
the component values with normalized values; it does not recompute an existing
score or establish that score's validity for the changed components. Neither
operation's successful type check proves arithmetic validity, uniqueness,
execution bounds or the score ordering required at execution.

<!-- requirement-block: vector-bridges.occurrence-order -->
The explicit `to_vectors` and `vectors` bridges and `normalize_vectors` MUST
retain input occurrence order; none establishes order on an unordered input.
Normalization after scoring preserves that sequence and stored score, but does
not assert that the score measures the normalized components.

<!-- requirement-block: vector-bridges.score-order -->
`score_vectors` MUST order output by score descending, then semantic vector
identity ascending using the existing internal type-specific identity order.
This matches the single-query ordering of `nearest`; L2 scores remain negative
distances under the numeric law. Identity uniqueness is validated independently;
arrival order, stringification or a synthesized row CID cannot break ties.
Binding, profile, finite-arithmetic and resource validation precede publication.

<a id="pool-vectors"></a>

#### `pool_vectors`

```yaml
- pool_vectors:
    vector: embedding
    by: [customer_id]
    method: mean
```

<!-- requirement-block: pool-vectors.actql-source-does-not-expose-a-separate-relation-pooling-carrier-id pool-vectors.actql-source-does-not-expose-a-separate-relation-pooling-carrier-id.second pool-vectors.all-vectors-in-a-group-must-be-finite-and-have -->
Relation input requires a vector field and a retained candidate key;
vector-set input already carries
identity. ActQL source does not expose a separate relation-pooling carrier
`id`: the compiler MUST derive member identity from that proven relation
identity and MUST reject relation pooling when none is proven. `by` is
non-empty and `method` is `mean`, `sum`, or `max`. A single `by` field becomes
the pooled identity; multiple fields use their canonical tuple and are restored
as separate fields by `vectors`. Optional `output_id` may rename a
single-field identity. All vectors in a group MUST
be finite and have the same non-zero dimension. Groups are ordered by their key
tuple; binary32 quantization occurs before pooling, and each output component
is quantized again after the AoA-defined deterministic fold. Members are
ordered by semantic vector identity ascending before the left fold. Mean and
sum round at the law-defined fold points; max is componentwise after input
quantization. Duplicate vector record identity anywhere in the carrier fails,
even when duplicate records belong to different authored groups.

<!-- requirement-block: pool-vectors.closed-source -->
The body MUST admit only vector, by, method and output_id. The by list is
nonempty, ordered and has no repeated field reference, because its fields are
restored as distinct output columns. Repetition is not silently removed.
Method is explicitly mean, sum or max. The optional output_id is an authored
output field name and is permitted only for a single grouping field; it does
not provide a member-identity override or encode an entire tuple into a name.

<!-- requirement-block: pool-vectors.typed-output -->
Each grouping field MUST have a known non-null KeyComparable contract, because
its value becomes a component of the output Vectors identity, not merely an
arbitrary nullable grouping label. The result retains the grouping fields and
the selected component field's name and dimensions, drops other input payload,
and adds non-null number member_count with the positive safe-integer obligation.
For a single grouping field, a different output_id adds an alias with the same
value and type and makes that alias the identity role; the original grouping
field remains available. An identical output_id adds no duplicate field.
Generated columns and aliases cannot collide with retained output columns;
names of dropped input columns do not cause a collision. A vector option on a
Vectors input can restate, but not override, its existing component role.

<!-- requirement-block: pool-vectors.member-key-selection -->
Relation pooling MUST select its member candidate key using
[Deterministic completion](#completion), after retaining only keys with known
non-null scalar component types eligible for this encoding. A shorter or
lexicographically earlier ineligible key cannot hide an eligible alternative.
The selected tuple's fields, including explicit surviving aliases, are in
canonical code-unit order. Input key declarations and their admission obligations
retain their original names and declaration order; that order does not override
the selected completion tuple. Selection does not establish actual row uniqueness.

A selected singleton non-null string candidate-key field is used directly and journaled as
`actql.vector.candidate-key-identity-completion`. Any other non-null scalar
candidate key, including a singleton non-string key, is encoded into reserved internal field
`__actql_vector_record_id`: for each component in the selected canonical key order the
compiler concatenates its Unicode-scalar length in AoA canonical `to_string`
form, `:`, that canonical form, and `|`. The reserved field is
collision-checked and the completion is journaled as
`actql.vector.composite-candidate-key-identity-completion`. This carrier-only
field is not part of the public pooled relation. `vectors` exposes the
group fields, optional `output_id`, pooled vector, and exact positive
`member_count`.

For this Relation member-identity completion, scalar excludes reference values:
no reference-to-string or reference-to-CID conversion is inferred. Member ordering
uses the completed string identity, including its length prefixes, while output
group ordering continues to use the semantic group tuple. A declared input key
retains its input-admission obligations; its use does not certify that rows have
already passed non-nullness, domain and uniqueness checks.

<a id="merge-rankings"></a>

#### `merge_rankings`

```yaml
- merge_rankings:
    with: lexical_ranking
    by: [query_id]
    candidate: candidate_id
    score: score
    score_policy:
      weighted_sum: {left: 0.6, right: 0.4}
    score_contract:
      domain: normalized-relevance.v1
      range: [0, 1]
      normalization: min_max.v1
    k: 20
```

<!-- requirement-block: merge-rankings.source-options -->
The source body MUST be closed to with, by, candidate, score, rank, score_policy,
score_contract, k and tie_break, with policy-specific required and forbidden
members as specified below. An empty by list denotes one global query group;
repeated by references retain their authored order but create each output field
only once, in first-occurrence order. For max and weighted_sum, with is one input
name. An explicitly empty tie_break adds no business fields and still completes
to candidate identity; repeated business tie-break references are retained and
do not strengthen uniqueness evidence. Omission and an explicit empty list are
not canonical-source substitutions. Score_contract admits exactly domain, range,
normalization and optional higher_is_better: true; domain and normalization are
nonempty strings, range has exactly two finite endpoints in nondecreasing order.
The fixed higher-is-better law applies when the redundant true member is absent
as well. All k, rank_constant and rank_window options are positive safe-integer
literals. Weighted-sum admission compares the binary64 sum of its two weights
with exactly one, without an epsilon tolerance.

<!-- requirement-block: merge-rankings.by-candidate-score-score-policy-max-weighted-sum-left-right-and-positive-k-are-required merge-rankings.weighted-sum-weights-must-be-finite-non-negative-and-sum-exactly-to merge-rankings.an-explicit-identical-score-contract-is-required-for-both-ranking-semantics -->
Both inputs are relation rankings with complete typed schemas. `by`,
`candidate`, `score`, `score_policy: max|{weighted_sum:{left,right}}`, and
positive `k` are REQUIRED. Weighted-sum weights MUST be finite, non-negative,
and sum exactly to one under the numeric contract. A candidate missing from
one input contributes positive zero for that input; weights are not
renormalized over the inputs containing that candidate. Output score bounds
must therefore include one-sided participation and the prescribed rounding;
they are not automatically the declared input score range. For example an
input range [1,2] and equal weights can emit 0.5 for a candidate whose only
score is 1. `max` takes the maximum of present scores only, not the maximum
with an invented zero for an absent side. Raw sum is not an ActQL 0.1 policy.
An explicit identical `score_contract` is REQUIRED for both ranking semantics:
it binds domain, finite range, and normalization identity. Higher scores are
better in ActQL 0.1 and the checked Plan records that fixed law.
Raw BM25 and cosine values, or two differently normalized lists,
cannot be summed merely because both fields are named `score`.
Omitted `tie_break` completes to the semantic candidate identity; an authored
tie-break may add business fields before that final identity. Rows for the same query/candidate are combined by
the declared score policy, then ordered by score descending and the authored
tie-break ascending; only the first `k` per query remain. Query groups are
ordered canonically. This operation lowers to exact VecA ranking composition
plus RelA projection; host-language list merging is not conforming.

<!-- requirement-block: merge-rankings.common-input-uniqueness-and-output -->
Every policy MUST require at most one row per query-key/candidate tuple within
each individual ranking input. Validate complete inputs before fusion or
truncation; duplicate rows fail rather than overwrite, collapse or supply an
implicit within-list score aggregation. Repeated references to the same
ranking in an RRF input list remain separate weighted input occurrences.
For max and weighted_sum, output consists only of the by fields, candidate
field, non-null number `score`, and fresh non-null positive safe-integer `rank`.
Business tie-break fields influence ordering but do not implicitly copy a
representative payload into the output. When the same query/candidate occurs
in both inputs, corresponding business tie-break values must agree under
typed equality; disagreement fails before publication. A candidate present
only on one side uses that side's tie-break values. Hidden row identities,
input order and maximum-score representative selection do not resolve a
tie-break-value conflict. Additional business payload is obtained by an
explicit subsequent join.

The preceding score-contract requirement applies to max and weighted_sum,
not to reciprocal-rank fusion. RRF uses the same current ranking Relation and
`with`, where `with` may be a nonempty finite list. It requires `by`,
`candidate`, `rank`, positive `k` and the closed policy
`{rrf: {rank_constant, weights, rank_window}}`; it rejects `score` and
`score_contract`. Input order is current ranking first, then the declared
list. Weights has exactly that length; each is finite and nonnegative with
positive total weight. Rank_constant is a positive safe integer; rank_window
is a positive safe integer, independent of output k.

Each query/candidate occurs at most once per input. Rank is a non-null positive
safe integer, unique within each input query and contiguous from one; it is
the total position after that input's own ranking tie-break, not dense_rank.
Inputs have matching query-key and candidate value domains; their score
scales need not match. Validate each complete ranking input before applying
rank_window, then only positions at most rank_window contribute. A candidate
absent from one list contributes zero for it. A query absent from every list
has no output row; this is not evidence that a provider returned no candidates.

<!-- requirement-block: merge-rankings.rrf-law -->
For each query/candidate, RRF MUST compute contributions
`weight / (rank_constant + rank)` using binary64 round-to-nearest ties-to-even
at each addition and division, then left-fold contributions in declared input
order with the same rounding. Any non-finite intermediate fails. Emit the
union of participating candidate identities, ordered by fused score descending
and semantic candidate identity ascending, retaining at most k per query.
Authored tie_break is not admitted for this policy: list-dependent payloads
do not silently select a representative. Output contains the by fields,
candidate field, non-null number `score`, and positive safe-integer `rank`,
with collision checks. Query
groups use canonical key order. The input list, weights, rank_window and
law identity belong to the canonical Plan; bounds cover admitted input rows,
fusion work and output separately. Optimization preserves the declared fold.

Every merge_rankings policy emits rank as the one-based position within each
query after final tie-breaking and top-k. The output rank field is fixed and
fresh: by/candidate fields cannot collide with rank or score. RRF consumes the
authored input rank field but emits newly computed contiguous ranks, not the
old positions. Nearest, text_rank and merge_rankings therefore compose directly
with RRF. A later filter may create rank gaps; authors explicitly recompute
row_number in the retained ranking order before using such a list as RRF input.

<!-- requirement-block: merge-rankings.the-compiler-must-not-invent-a-threshold-or-silently-change -->
Score thresholds are ordinary explicit RelA filters after `nearest`,
`score_vectors`/`vectors`, or `merge_rankings`. The compiler MUST NOT invent
a threshold or silently change exact search into approximate retrieval.

<a id="text-rank"></a>

### Pure lexical ranking: `text_rank`

`text_rank` consumes the current Relation as corpus and names a finite query
Relation with `queries`. Its closed body requires `queries`, `query_id`,
`query_text`, `candidate_id`, `candidate_text`, `tokenizer`, `scoring`, and
positive safe integer `k`. Both identity fields are non-null string candidate
keys; text fields are non-null strings. Duplicate identities or malformed
text fail admission, not implicit deduplication. The profile is
`actql-text-rank/0.1`; it is pure computation over the two captured Relations.

Tokenizer is `unicode_words` or `char_bigram`. Both first apply the pinned
Unicode 16.0 NFKC and full default case-fold laws, returning NFC. Unicode_words
emits maximal runs of letters or numbers and following combining marks; a
run cannot start with a mark. Categories L*, N*, M* use the pinned Unicode
tables. Other scalars are delimiters. Char_bigram uses the same runs, emits
each adjacent pair of Unicode scalars without crossing a delimiter, and emits
a singleton token for a one-scalar run. Repeated tokens retain multiplicity.
No host locale, dictionary, stopword list, synonym expansion or stemming is
implicit. Token-size, token-count and normalized-text ceilings are resolved.

Scoring is exactly `{bm25: {k1, b}}`, with finite number k1 > 0 and
0 <= b <= 1. Corpus size N counts every admitted document, including empty
documents. Document length counts its tokens; df(t) counts documents with t.
Average length is total token count divided by N. Query terms are deduplicated
and enumerated in canonical string order. For each term present in a document,
its contribution is:

```text
idf = ln(1 + (N - df + 0.5) / (df + 0.5))
norm = 1 - b + b * (document_length / average_length)
term_score = idf * ((tf * (k1 + 1)) / (tf + k1 * norm))
```

<!-- requirement-block: text-rank.numeric-law -->
Implementations MUST evaluate each displayed operation in its parenthesized
tree order with binary64 nearest-ties-even rounding; ln is correctly rounded
for its binary64 argument, not an unspecified host math function. Fold term
contributions from positive zero in canonical query-term order with rounding
after each addition. Non-finite arithmetic fails. An empty corpus, all-empty
corpus or empty tokenized query yields no ranking rows, without division by
zero. Unmatched terms contribute zero and documents with score zero are not
emitted. Results expose query_id, candidate_id, non-null number score and
non-null positive safe-integer rank;
query groups sort by query identity, candidates by score descending then
candidate identity ascending, retaining at most k. Input-order permutation
does not change corpus statistics, scores or Result identity.
Rank is the contiguous one-based position in the final per-query order after
top-k, matching nearest and merge_rankings, including deterministic score ties.

Corpus statistics are computed only from the operation's actual admitted
input, including its filters and authorization scope. They are not borrowed
from an external index containing hidden documents. Scores are comparable
only under the same profile, corpus and scoring contract; RRF does not require
such score comparability. Output bound is query_count * min(k, corpus_count).
Tokenization, corpus statistics, candidate scoring, work and bytes have
separate resolved ceilings; k alone does not bound scoring work. The profile
pins tokenizer tables, the complete numerical law and conformance vectors.

<!-- requirement-block: text-rank.semantic-artifact text-rank.unicode-input-pins text-rank.artifact-admission -->
The selected lexical profile MUST be exact canonical JSON with closed top-level
shape `{version: "actql-text-rank-profile/0.1", unicode_version: "16.0.0",
unicode_source_sha256, tokenizer_law, numeric_law, tokenizer_vectors_bytes_cid,
numeric_vectors_bytes_cid}`. `unicode_source_sha256` MUST contain exactly
`UnicodeData.txt`, `CompositionExclusions.txt`, `CaseFolding.txt`,
`NormalizationTest.txt` and `LICENSE.txt`, each with a lowercase 64-hex SHA-256
of its original bytes. The two vector CIDs are SHA-256 CIDs of their exact
fixture bytes, not reserialized parsed values. `tokenizer_law` and `numeric_law`
are the complete closed law descriptors illustrated by the
[selected Unicode 16 artifact](../../portability/profiles/text-rank-unicode16.json):
their versions are `actql-text-rank-tokenizers/0.1` and
`actql-bm25-binary64/0.1`, and their fields encode the normalization, tokenization,
statistics, binary64 arithmetic and ranking rules above. A different descriptor
does not select a Host-defined replacement law under the same version.

Check Environment selects the profile's byte CID independently. Admission MUST
compare the original profile bytes to that pin, reject noncanonical bytes
without repair, verify every required source/vector byte pin, and reject
unsupported law descriptors before reporting that profile resolved. Required
artifacts are locally provided within explicit input byte/node/depth ceilings;
no ambient Unicode data or implicit download supplies a missing artifact.
Matching hashes establish selected-byte integrity, not independent provenance
or evaluator conformance. Profile resolution does not discharge tokenization,
scoring, uniqueness, resource or publication obligations. These profile bytes
and dependencies participate in Check Environment identity, not authored
Program syntax; selecting or updating a profile never changes a source body
implicitly.

<a id="candidate-search"></a>

### External ranked acquisition: `search_candidates`

`search_candidates` consumes a finite query Relation. Its closed body requires
`source`, `query_id`, `request`, positive safe integer `k`, `fields`, and
`outputs: {candidates: name, coverage: name}`. Source names a declared
relation-valued search SourceView input used as an acquisition template, not
an additional initial read. Its Connector, Resource and view
resolve statically under ordinary SourceView resolution. The query_id field
is a non-null string candidate key of the query Relation. Request maps the
SourceView's dynamic request roles to common typed expressions over each
query row; remaining roles come from that input's static request. Together
they cover the exact request contract without duplication. Fields reuses
select's projection/rename grammar over the response schema.

The step has no `as`: outputs binds two distinct dataflow names in the ordinary
namespace. It does not change the implicit current Relation; a later consumer
selects an output explicitly with `from`. Both outputs are published together
only when the whole acquisition succeeds. They cannot refer forward or shadow
an input/preceding binding. This is the sole multi-output binding form here,
not a general fetch DAG or row-selected Connector mechanism.

The SourceView contract declares dynamic request roles, response candidate
identity, total ranking evidence, optional score contract, per-query extent,
completion scope, pagination and native batch capability. Exactness is
`exact` or `approximate` relative to that declared search contract, separate
from completeness of the external domain. ANN uses this operation with typed
vector request roles and pinned index/model/search configuration; it is not
an approximate implementation of nearest. k is a requested ranked prefix,
not a claim that the prefix enumerates every matching external entity.

Candidates output contains fixed query_id, candidate_id, rank and score fields
plus the selected response fields. Candidate identity preserves its declared
non-null key type; rank is a positive one-based safe integer; score is a
nullable number, null exactly when the SourceView supplies no score. Projected
names cannot collide with fixed roles. Candidate identities are unique per
query; provider scores/order are validated against the declared contract and
captured rather than recomputed by an unspecified local ranking algorithm.
Canonical output is query identity then rank. Capture records the complete
ordered response evidence needed to replay that prefix.

Coverage output contains exactly one row per input query, including zero-hit
queries: query_id, returned_count (nonnegative safe integer),
observation_completeness (complete|partial), exactness (exact|approximate),
truncated (boolean), and observation_cid (string). Enum values are closed
string contracts. Completeness is relative to the pinned request scope, not
the whole Resource. The evidence binds that scope, requested k, actual
request, pagination termination and response identities; partial prefixes
are never reported as complete domain scans. Zero input queries yields two
typed empty Relations and no provider dispatch.

<!-- requirement-block: candidate-search.acquisition-boundary -->
The Host MUST admit request-value policy and egress before dispatch and bind
row, request, response, attempt, cost, duration and byte ceilings to the Plan.
Request expressions respect the common failure rules. Acquisition, schema,
identity, authorization or envelope failure fails the operation rather than
producing an empty candidate list or successful coverage row. Transport
deduplication/batching preserves each logical query's request, ordering,
coverage and accounting evidence, and follows the SourceView capability.
Replay reuses the captured responses without issuing a fresh search. Checking
and Planning perform no implicit provider search.

Local anti joins over these captured candidates remain ordinary Relation
computations. They prove absence only from that finite captured set, not
from the external domain. A consumer or Effect requiring external absence
needs independent complete evidence; no-hit ranked search alone cannot
satisfy it. This is not a blanket prohibition on subsequent joins or Effects.

<a id="infer"></a>

### Model acquisition: `infer`

The public operation name is `infer`; the module profile is
`actql-infer/0.1`, and the contract schema is `actql.model_task/0.1`.
Model inference is acquisition of an externally generated observation. It is
neither pure algebra nor a business-state mutation Effect.

```yaml
- infer:
    contract: model-task:ticket-triage.v1
    input:
      subject: {field: subject}
      body: {field: body}
  as: ticket_triage
```

<!-- requirement-block: infer.infer-must-consume-a-relation-declare-a-unique-as-result infer.it-must-not-be-inferred-from-equal-field-names -->
`infer` MUST consume a Relation, declare a unique `as` result, and map every
and only the closed ModelTask input fields from type-compatible source fields.
`input` is an explicit model-egress manifest. It MUST NOT be inferred from
equal field names.

`key` is either one field or a duplicate-free field tuple containing at least
two fields:

<!-- requirement-block: infer.inferkey -->
<!-- normative-code: grammar -->
```text
InferKey := FieldName | [FieldName, FieldName, ...]
```

<!-- requirement-block: infer.every-key-field-must-be-non-null-and-scalar-and-the infer.every-key-field-must-be-non-null-and-scalar-and-the.second infer.when-the-input-has-exactly-one-candidate-key-key-may infer.when-zero-or-more-than-one-candidate-key-remains-the -->
Every key field MUST be non-null and scalar, and the complete tuple MUST equal
one compiler-proven candidate key. When the input has exactly one candidate
key, `key` MAY be omitted and the compiler MUST record its unique completion.
When zero or more than one candidate key remains, the author MUST select one
explicitly. Key fields correlate requests and results; they are sent to the
model only when also named by `input`.

The result is a new Relation containing the key fields in authored tuple order,
then `outcome` and `value`. Outcome is `ok` or `failed:` followed by exactly
`rate_limit`, `timeout`, `provider_error`, `refusal`, `schema_invalid`,
`safety_rejected` or `truncated`. Value is the ModelTask's non-null closed output
object on success and null on failure. Successful `{summary: null}` is distinct
from a failed null value. Filtering `outcome = 'ok'` refines value to the original
non-null success contract. Keys cannot collide with these fixed output roles.
There is no implicit source-row copy or join-back.

<!-- requirement-block: infer.the-resolved-modeltask-contract-must-fix-task-and-prompt-identity -->
The resolved ModelTask contract MUST fix task and prompt identity, an authored
model selector, exact closed input and output contracts, generation settings,
accepted data classifications and regions, forbidden training use, and
`tool_policy: none`, `retrieval_policy: none`, and `streaming: false`.

<!-- requirement-block: infer.the-runtime-must-materialize-and-count-the-distinct-key-tuples infer.product-d0477b0c1e56 infer.product-f78f50e77109 -->
`max_items` is an author guard as defined in [Author guards, resolved limits, and Plan facts](#resolved-limits), counting distinct input key
tuples. Its resolved-limit candidates are the Program-proven input bound,
ModelTask Contract ceiling, language ceiling, Host ceiling, and authored guard
when present. The runtime MUST materialize and count the distinct key tuples
before the first provider dispatch. A limit breach therefore causes zero
provider calls.

The compiler derives provider-call, request-byte, token, and duration bounds
from the resolved item limit, the ModelTask contract, Host policy, and checked arithmetic.
Physical bounds belong to the inference barrier. The default result mode is
`outcomes`; source may explicitly select `on_non_success: fail` for strict
publication. Omission normalizes to outcomes. A logical key owns one fixed
model-call slot, with finite Contract/Host retry bounds for classified transient
rate limits, timeouts and provider errors. Refusal, invalid schema, safety
rejection and truncation are not automatically retried. Request, model, prompt,
settings and schema do not change between attempts. No provider-text guessing
or hidden retry is admitted.

Every attempt MUST reserve and account for attempt, token, cost, duration and
wire budgets, including failed or lost responses. Unknown usage retains its
reservation rather than becoming zero. The first valid completion of the
currently active attempt seals the slot; later obsolete responses cannot
replace it and their costs remain evidence. Retry backoff is bounded Host work.
Atomic publication follows capture of all slot outcomes: N failed slots emit
N failure rows, not an empty successful observation; zero keys emit a typed
empty Relation with zero calls. Strict mode publishes no Relation if a slot
fails, while retaining private observations and cost evidence. Unattempted
slots are not fabricated provider failures.

Authorization, egress, invalid request or artifact, duplicate identity, global
capacity, engine failure and cancellation MUST fail the barrier, not become
ordinary provider-failure rows. Local or global context-capacity violations
are admission failures, not retriable model outcomes. Exact replay consumes
the captured outcomes with no model dispatch, retry or wait.

<!-- requirement-block: infer.all-call-slots-mapped-requests-request-bytes-exact-adapter-plans -->
All call slots, mapped requests, request bytes, exact adapter plans, tokenizer
results where text tokenization applies, and closed worst-case media/token
reservations MUST be preflighted before the first provider
dispatch. Total bounds are derived from the resolved item limit and per-item contract or
Host limits using checked safe-integer arithmetic.
The Connector and Host own source classification; an author may only strengthen
it with `minimum_classification`. Unknown classification denies model egress.

<!-- requirement-block: infer.before-provider-access-the-runtime-must-reject-input-whose-effective -->
Before provider access, the runtime MUST reject input whose effective data
classification is not admitted by the ModelTask data-handling contract. The
input Relation is processed in canonical key order, while provider completion
order has no semantic meaning.

<!-- requirement-block: infer.every-successful-call-must-emit-versioned-evidence-binding-the-modeltask -->
Every successful call MUST emit versioned evidence binding the ModelTask,
semantic request, call-slot identity, input-result artifact, input-row identity, authored and
provider-reported model identities, provider request ID, attempt count, raw
structured-response artifact, validated structured output, token usage, finish reason,
and observation time. Exact replay reuses the captured response; a fresh model
call creates new evidence and a new Invocation identity.

<!-- requirement-block: infer.effect-preview-derived-from-an-inference-result-must-bind-the infer.effect-apply-must-not-rerun-inference -->
Effect Preview derived from an inference result MUST bind every actually
depended-on model_slot_capture CID, including failed outcomes. Each capture
binds exact ModelTask, fixed request/input identity, ordered attempts, adopted
outcome, accounting, authority, attachment admission and policy evidence.
An ok slot requires validated typed value, actual response artifact and response
issuer evidence (including the successful model-invocation evidence). A failure
slot requires classification evidence and no typed value; response_artifact_cid
and response_issuer_evidence_cid are null when no response arrived, not fabricated
empty artifacts. If a raw error response exists it is retained privately with
its real issuer evidence. Timeout-no-response may feed a failure-notification
Result/Preview in outcomes mode, retaining the original model policy/provenance.
Strict mode exposes no such Relation. Replay and notification use the original
capture; neither issues a replacement model call. Effect apply MUST NOT
rerun inference. Graph, vectors, or events enter `infer` only after an explicit
row bridge. The profile rejects `resource_ref` model inputs. It admits typed
`artifact_ref` inputs and bounded homogeneous arrays under the ModelTask media
contract: MIME, content identity, complete/truncated status, byte/page/frame
limits, transfer method, classifications, region and egress scope are explicit.
Issuer, current scope, permission, availability and exact content bytes are
verified before dispatch. Content equality does not erase Ref scope identity.
PDF, image, audio and video may be model inputs without an extraction registry;
this does not authorize hidden SourceView extraction. Raw bytes/base64 are not
Program values. Adapter uploads are bounded authorized model transport, not
hidden business mutations. Tool use, hosted search/retrieval, code interpreters,
streaming downstream, dynamic model or prompt selection, embedding generation,
and reranking are outside `actql-infer/0.1`. Cross-Run model cache is deferred;
same-observation replay and same-slot retry do not introduce one.

A model slot identity binds the Program/Stage definitions, effective inputs,
input artifact and key, ModelTask and fixed request. It excludes future response
and Stage Invocation CIDs. Captured attempts and the adopted outcome then enter
the ObservationSet, from which the Stage Invocation is computed.

<a id="external-joins"></a>

### External SourceView joins

`lookup` is not an author-visible operation. Authors declare a keyed
SourceView as an input and use the ordinary RelA `join` operation for both
local and cross-system relations:

```yaml
inputs:
  customers: {connector: crm/main, resource: customer, view: active}
  risks: {connector: risk/main, resource: risk_record, view: by_customer}

from: customers
steps:
  - top_k: {k: 100, by: [{score: desc}, {customer_id: asc}]}
    as: bounded_customers

  - join:
      with: risks
      kind: left
      on: [customer_id]
      null_key: fail
      select:
        customer_id: left.customer_id
        risk: right.risk
    as: customers_with_risk
```

<!-- requirement-block: external-joins.an-actql-program-must-not-contain-a-lookup-step external-joins.when-the-right-input-is-a-keyed-sourceview-check-must external-joins.the-barrier-must-not-copy-source-rows-or-perform-the -->
An ActQL Program MUST NOT contain a `lookup` step. When the right input is a
keyed SourceView, Check MUST lower the logical join to an
`actql-lookup/0.1` acquisition barrier followed by an ordinary RelA join. The
barrier MUST NOT copy source rows or perform the logical join itself. The
logical join kind, equality keys, null behavior, selected fields, the authored
join cardinality assertion, and any optional output guard remain author-visible.
Key deduplication, batching, paging, pushdown, materialization, and local join
strategy are compiler/runtime choices.

<!-- requirement-block: external-joins.the-external-right-input-must-resolve-one-pinned-relation-valued-search external-joins.its-default-read-mode-must-be-a-bounded-snapshot-or external-joins.the-left-relation-must-have-a-compiler-proven-positive-finite-row external-joins.the-authored-equality-keys-must-match-every-and-only-the external-joins.the-sourceview-must-prove-a-complete-response-for-each-requested external-joins.the-effective-data-policy-must-be-admitted-before-dispatch external-joins.the-selected-physical-strategy-must-fit-the-sealed-request-byte -->
The external right input MUST resolve one pinned relation-valued `search`,
`fetch`, or `follow` SourceView. Its default read mode MUST be a bounded
`snapshot` or bounded `changes` mode. The left Relation MUST have a
compiler-proven positive finite row bound. The authored equality keys MUST
match every and only the SourceView's correlation response roles. The
SourceView MUST prove a complete response for each requested key. Its response
cardinality (`zero_or_one | zero_or_many | one | one_or_many`) and capacity
contract determine the possible response extent. `max_output_rows` is an author
guard as defined in [Author guards, resolved limits, and Plan facts](#resolved-limits); the logical join's limit uses the transfer rules in
[join](#join), including any authored join cardinality assertion. The acquisition
response limit is resolved separately as specified below. The effective data
policy MUST be admitted before dispatch. The selected physical strategy MUST
fit the sealed request, byte, attempt, cost, and duration envelope.

<!-- requirement-block: external-joins.check-must-not-require-the-author-to-repeat-a-transport -->
If the left key set is unbounded, Check fails with
`ACTQL_E_UNBOUNDED_EXTERNAL_JOIN`. A truncating `hard_limit_only` response is
not a legal implementation of join semantics and fails with
`ACTQL_E_EXTERNAL_JOIN_COMPLETENESS_UNPROVEN`. Check MUST NOT require the author
to repeat a transport limit as `max_items`.

<!-- requirement-block: external-joins.lookup-capacity-bounds external-joins.lookup-capacity-invalid-components -->
The selected SourceView's `output.facts` Contract Envelope of kind
`carrier_facts` carries an optional `body.lookup_capacity` component. Its
closed schema is `contract_bodies.carrier_facts.properties.lookup_capacity` in
`actql-check-environment.json`. When present, all five members are required:
`version: "actql-lookup-capacity/0.1"`, `completeness`, `max_rows_per_key`,
`max_pages_per_request` and `max_response_bytes_per_page`. The three bounds
MUST be positive safe integers. `completeness` is exactly
`complete_per_requested_key` or `hard_limit_only`; only the former can support
a keyed join's completeness obligation. Missing capacity remains unknown;
null, malformed components and unknown component members MUST be rejected,
including on unused views. Other carrier-facts members are not prohibited by
this component schema and do not gain evidence meaning from passing it.

<!-- requirement-block: external-joins.lookup-capacity-decoded-body-limit external-joins.lookup-capacity-transport-limit -->
`max_rows_per_key` bounds the complete logical response for one distinct
requested correlation tuple across all pages, before the ordinary join.
`max_pages_per_request` bounds successful logical response pages for one
request tuple or one native batch; retries are not additional logical pages.
`max_response_bytes_per_page` bounds response-body octets after content
decoding for each such page, including the response envelope, not canonical
row bytes, headers or compressed transport octets. Host decoded-body limits
MUST accommodate this worst-case logical response. Separate transport and
attempt limits MUST cover retries, redirects and failed responses; this page
bound alone is not evidence for their wire-byte extent. Capacity does not
change response cardinality or permit truncating a complete response.

<!-- requirement-block: external-joins.lookup-capacity-ownership external-joins.lookup-capacity-completeness-scope -->
Capacity admission MUST retain the selected SourceView, its exact facts
reference and the containing Contract Envelope CID. The component has no
independent self-CID and is covered by that envelope's existing preimage.
An equal bound from another source is not interchangeable evidence. Neither
shape validation nor a declaration of completeness proves Catalog authority,
actual response completeness, identity uniqueness or successful enforcement.
A generic root `completeness: "complete"` claim MUST NOT be promoted to
`complete_per_requested_key`. Runtime acquisition retains its required
response validation and atomic failure obligations.

<!-- requirement-block: external-joins.static-request-fields-outside-the-correlation-roles-must-be-supplied external-joins.static-request-fields-outside-the-correlation-roles-must-be-supplied.second external-joins.correlation-request-fields-must-not-be-supplied-there-because-the external-joins.together-the-join-keys-and-static-request-fields-must-consume external-joins.provider-resource-sourceview-request-roles-response-roles-identity-response-cardinality -->
The SourceView owns relation schema, candidate keys, correlation
request/response roles, response identity, per-key completeness, response
cardinality, and admitted access paths. Static request fields outside the
correlation roles MUST be supplied under the SourceView input's `request` and
MUST type-check against the closed request contract. Correlation request fields
MUST NOT be supplied there because the join key owns them. Together, the join
keys and static request fields MUST consume every and only the SourceView
request fields.
Provider, Resource, SourceView, request roles, response roles, identity,
response cardinality, and pagination MUST NOT be selected by row data.

<!-- requirement-block: external-joins.repeated-key-role-binding -->
Check MUST compare the set of authored right-side equality fields with the
correlation response roles, rejecting missing or extra roles without rejecting
repeated equality pairs. Request tuple components follow the Catalog's
correlation request/response pair order. For each response role, its request
value comes from the left field of the first authored equality pair naming
that role. All authored equality pairs, including subsequent uses of that
response role with another left field, remain ordinary join predicates in their
original order. The null-request policy examines every authored left join-key
component, not just the selected request representatives. This mapping does not
coerce values or prove their admission to the request contracts, response
completeness, left bounds or successful acquisition.

<!-- requirement-block: external-joins.check-must-reject-a-full-join-against-a-keyed-only-sourceview -->
`inner`, `left`, `semi`, and `anti` joins may use a complete keyed access path.
An `anti` join may treat no response as absence only because completeness is
proved for each requested key. Check MUST reject a `full` join against a
keyed-only SourceView because it cannot observe right-side rows outside the
left key set. Full-Relation semantics require a bounded complete-scan
SourceView.

<!-- requirement-block: external-joins.with-omitted-null-key-a-row-with-any-null-join-key-component external-joins.for-null-key-fail-discovery-of-such-a-row-must-fail external-joins.unrequested-response-keys-excess-response-cardinality-duplicate-response-identity-and external-joins.the-canonical-lookup-barrier-must-resolve-missing-requested-keys-from -->
The compiler canonical-deduplicates request tuples for transport only and then
joins responses according to the authored RelA semantics. Repeated left keys
therefore retain their authored multiplicity. With omitted `null_key`, a row
with any null join-key component MUST be excluded from the provider request and
remain available to the ordinary RelA join; `left` and `anti` therefore retain
it while `inner` and `semi` do not. For `null_key: fail`, discovery of such a
row MUST fail before provider dispatch. The Lookup Barrier binds this as
`null_request_policy: exclude_from_request|fail`, and its evidence binds both
the exact request-key-set CID and the number of excluded null-key rows.
Unrequested response keys, excess response cardinality, duplicate response
identity, and external non-success MUST fail the acquisition atomically. The
canonical Lookup Barrier MUST resolve missing requested keys from response
cardinality by exactly this rule:
`zero_or_one` and `zero_or_many` emit no acquired row for a missing key; `one`
and `one_or_many` fail on a missing key. These laws are explicit in the Lookup
Barrier and are not source options.

<!-- requirement-block: external-joins.a-native-batch-must-bind-distinct-lookup-request-key-lookup-batch-request-and-lookup-response-key -->
A native batch MUST bind distinct `lookup_request_key`,
`lookup_batch_request`, and `lookup_response_key` contracts, a positive
`max_keys_per_request`, and the claim `preserves_per_key_semantics: true`.

<!-- requirement-block: external-joins.every-positive-acquisition-bound-required-by-the-actql-lookup-barrier-0-1-schema-must external-joins.checked-arithmetic-must-reject-overflow-absent-capacity-evidence-or-a external-joins.the-acquisition-s-max-response-rows-is-derived-independently-of-the-logical-join-s -->
Every positive acquisition bound required by the `actql-lookup-barrier/0.1`
schema MUST be present in the canonical Lookup Barrier. The schema is
`schemas.lookup_barrier` in the
[production-profile schema registry](../../spec/contracts/actql-production-profile-schemas.json);
[Typed barriers and Plan Documents](#plan-documents) defines its Plan binding. The compiler derives these bounds from the left
Relation row bound, SourceView batching and capacity facts, and pinned Host
execution policy.
`max_distinct_keys` is at most the left row bound. If the SourceView omits a
native batch capability, `max_keys_per_batch` is one. Checked arithmetic MUST
reject overflow, absent capacity evidence, or a Host byte cap smaller than the
Connector's worst-case logical response. No request, page, retry, byte, or
deadline arithmetic is Program vocabulary. The acquisition's
`max_response_rows` is derived independently of the logical join's
`max_output_rows`; a final semi/anti/output cap MUST NOT truncate the response
needed to prove per-key completeness.

<!-- requirement-block: external-joins.the-remaining-request-batch-page-attempt-byte-and-duration-limits -->
The remaining request, batch, page, attempt, byte, and duration limits are
physical execution constraints and MUST NOT appear in Program source.

<!-- requirement-block: external-joins.lookup-host-component external-joins.lookup-host-invalid-component -->
The selected Check Environment's `host_policy_profile.lookup_execution`
component MUST follow `policy_components.lookup_execution.schema` in
`actql-check-environment.json`: a closed object with
`version: "actql-lookup-execution-policy/0.1"` and six positive safe-integer
ceilings: `max_network_attempts_per_request`, `max_request_bytes_per_attempt`,
`max_total_request_bytes`, `max_total_response_bytes`,
`max_total_decoded_response_bytes` and `max_total_duration_ms`.
Absence leaves lookup execution unresolved without defaults. A present null or
invalid component MUST fail component admission even when no lookup uses it.
Its identity is the canonical CID of the entire component with no exclusions;
admission retains its exact Check Environment membership.

<!-- requirement-block: external-joins.lookup-host-accounting -->
Lookup execution MUST enforce these ceilings against the existing
[lookup accounting](protocols/artifacts.md#lookup-acquisition-identities) counters: request octets
per attempt and in total, `response_wire_bytes` for `max_total_response_bytes`,
and `response_decoded_bytes` for `max_total_decoded_response_bytes`. Neither
response total substitutes for the other. Redirects, failed attempts, and
conservative reservations for unresolved usage remain charged by that protocol.
The attempt ceiling includes redirect network dispatches as well as initial
dispatch and retries for one logical request. `max_total_duration_ms` limits
the acquisition-wide elapsed deadline, including resumed waiting, not a sum of
parallel attempt durations or a fresh deadline on resume.

<!-- requirement-block: external-joins.lookup-host-static-fit -->
Static capacity resolution MUST check that the SourceView's worst-case complete
logical decoded response fits the selected decoded-response ceiling using
checked arithmetic. This does not prove the wire extent of a compressed
response. Selected transport plans additionally fit their own request, response,
redirect and timeout constraints and the aggregate envelope. In particular, the
existing HTTP network policy retains its separate compressed/decompressed
per-request bounds; this Host component does not replace them. Declaring a
maximum retry count grants no retry capability and does not guarantee that all
retries fit the remaining byte or deadline budgets. Dispatch and unresolved-usage
reservations remain subject to those budgets before further work is admitted.

<!-- requirement-block: external-joins.upstream-candidate-completeness-and-complete-response-for-requested-keys-are-separate external-joins.acquisitions-with-different-input-aliases-response-policies-null-policies-or -->
The capacity proof binds the left row bound, SourceView and carrier-facts CIDs,
Host-policy CID, and every resolved bound. `complete` concerns one successful
logical response for all requested keys. Redirect, retry, and failed-attempt
bodies count toward transport wire-byte and attempt limits, not as logical
result data. Upstream-candidate completeness and complete response for
requested keys are separate evidence axes; one MUST NOT be promoted from the
other. Canonical lowering merges exact identical acquisitions into one barrier,
using the following complete CSE identity; this is not an optional graph rewrite. Its CSE
identity includes the named SourceView input, effective response policy CID,
null-request policy, observed response fields, left Relation, pinned contract,
static request, and acquisition bounds. Different logical
join output caps do not change acquisition identity. Acquisitions with
different input aliases, response policies, null policies, or observed field
sets MUST NOT be fused.

<!-- requirement-block: external-joins.a-keyed-sourceview-input-may-author-only-connector-resource-view external-joins.local-schema-and-scan-fields-must-be-rejected-rather-than external-joins.check-must-resolve-its-response-policy-as-the-maximum-of external-joins.immediately-before-provider-access-runtime-must-recheck-sensitivity-completeness-mime -->
The acquired Relation is ordered by canonical request tuple followed by
response identity. A keyed SourceView input may author only `connector`,
`resource`, `view`, non-correlated static `request`, and
`minimum_classification`, and `meta` ([Authoring Context](#authoring-context)); it MUST NOT author `scan`. Local schema and scan
fields MUST be rejected rather than ignored. Check MUST resolve its response policy as the
maximum of the authoritative SourceView policy and the named input's minimum,
then resolve the barrier output policy from both request-input and acquired
response provenance. The barrier and downstream ResultDefinitions bind all
source policy CIDs. Compile time produces egress requirements, not an admission
claim. Concrete ArtifactRef admission follows [Reference admission and availability](protocols/artifacts.md#reference-admission). Immediately before
provider access, runtime MUST recheck sensitivity, completeness, MIME, bytes,
availability, provider-account boundary, region, and current Host policy
against the bound egress requirements. Failure performs zero provider calls.

<!-- requirement-block: external-joins.when-the-sourceview-contract-admits-response-projection-the-compiler-must -->
When the SourceView contract admits response projection, the compiler MUST bind
the observed response field set as the union of right-side fields published by
`join.select`, correlation fields, and response-identity fields needed for
evidence. The Lookup Barrier binds observed, correlation, and identity field
sets separately; the logical join binds the published right-side set. Fields
outside that union are not requested merely to make acquisition sharing easier.
Without a projection claim, the barrier declares the full SourceView response
schema as observed rather than pretending that provider egress was narrowed.

<!-- requirement-block: external-joins.the-public-plan-summary-must-derive-every-external-join-entry-from -->
The public Plan summary MUST derive every external-join entry from the
structured logical-join-to-acquisition binding, not from source order,
physical node order, or normalization presentation text.

<a id="serialize"></a>

### Artifact serialization: `serialize`

<!-- requirement-block: serialize.it-must-not-upload-the-artifact-implicitly -->
The public operation name is `serialize` and the module profile is
`actql-artifact/0.1`. It converts one explicitly ordered Relation into one
content-addressed Artifact and returns a one-row Relation carrying its
`artifact_ref`; it is distinct from ordinary Result delivery. It MUST NOT upload
the Artifact implicitly.

<!-- requirement-block: serialize.the-artifact-barrier-must-bind-every-input-data-policy-cid-and serialize.artifact-derivation-preserves-policy-exactly-the-barrier-output-policy-emitted -->
The Artifact barrier MUST bind every input data-policy CID and the effective
output data-policy CID. Artifact derivation preserves policy exactly: the
barrier output policy, emitted ArtifactRef metadata policy, issuer-evidence
policy, and derivation-evidence policy MUST be identical. A later Invocation
receiving that ArtifactRef therefore cannot replace its original policy with a
weaker local-input default.

```yaml
- serialize:
    format: csv
    fields: [customer_id, risk, observed_at]
    order_by: [{customer_id: asc}]
    encoding: utf-8
    line_ending: crlf
    csv:
      header: true
      delimiter: ","
      null: ""
    logical_name: risk-export.csv
  as: risk_export
```

<!-- requirement-block: serialize.csv-must-use-u-0022-as-its-quote-character-this-is serialize.fields-must-be-the-exact-emitted-field-sequence-and-order-by serialize.fields-must-be-the-exact-emitted-field-sequence-and-order-by.second serialize.the-machine-barrier-must-contain-both-resolved-limits-using-program -->
`format` is exactly `csv` or `jsonl`; encoding is `utf-8` or `utf-8-bom`, and
line ending is `lf` or `crlf`. CSV delimiter, header, and null spelling are
explicit and closed. CSV MUST use U+0022 as its quote character; this is a
serialization-profile law, not an author field. The null spelling is either
empty unquoted null or `\\N`; empty strings remain quoted
empty cells. `fields` MUST be the exact emitted field sequence and
`order_by` MUST provide a total stable order. `bounds.max_rows` and
`bounds.max_bytes` are author guards as defined in [Author guards, resolved limits, and Plan facts](#resolved-limits), counting input rows
and serialized bytes respectively. The machine barrier MUST contain both
resolved limits, using Program proof, Host policy, and any authored guards.
A downstream Command Contract is checked independently during Effect preflight;
serialization does not infer future consumers by reverse dataflow. A breach
publishes neither a partial
Artifact nor a partial output Relation.

<!-- requirement-block: serialize.before-an-artifact-serialization-barrier-is-admitted-the-input-relation -->
Before an Artifact serialization barrier is admitted, the input Relation MUST
have either a compiler-proven candidate key or a total stable ordering witness
from an algebra contract. When a candidate key closes authored ordering ties,
its omitted fields are appended ascending and journaled. Authored `order_by`
alone cannot prove that ties are impossible.

<!-- requirement-block: serialize.actql-source-must-not-contain-bytes-base64-storage-locators-or -->
The output fields are exactly `artifact_ref`, `media_type`, `size_bytes`,
`logical_name`, and `row_count`. The barrier input CID is derivation evidence,
not business data. Only the host
Artifact Store may issue the `artifact_ref`. ActQL source MUST NOT contain
bytes, base64, storage locators, or an author-supplied content CID. Upload,
attachment, and
resumable transfer remain Connector-owned typed `command` Effects over the
resulting `artifact_ref`.

`serialize` creates an Invocation-scoped immutable Artifact. Workspace
persistence, retention, and later deletion are not serialization semantics;
they require an explicit typed store/upload Effect or Run Graph policy. CSV
serialization is byte-faithful and performs no implicit spreadsheet formula
escaping. Authors apply any business transformation before serialization.

<a id="artifact-acquisition"></a>

### Artifact-backed acquisition

ActQL has no media profile and no `extract_text`, `transcribe`, `ocr`, or
provider-feature operation family. A captured PDF, image, or audio object is an
`artifact_ref`; already extracted information may be read as a typed Relation.
A keyed SourceView accepting an ArtifactRef is subject to exactly the same
observation classification as a direct SourceView ([Connector SourceViews](#sourceviews)). It may read existing
structured results or capture bytes. Newly interpreting a document requires a
registered extraction profile; [SourceView transformation profiles](protocols/contracts.md#sourceview-transformations) currently registers none. Naming a
View `text` or `transcription` does not authorize that work.
Accepted MIME types, full-artifact requirements, byte limits, schema,
completeness, data policy, and egress scope remain explicit Contract terms.

<!-- requirement-block: artifact-acquisition.modality-alone-must-not-select-execution-semantics -->
An asynchronous provider flow that requires submit, wait/poll, and result
fetch is not one hidden acquisition. Submission is a typed Command, waiting and
outcome routing belong to the Run Graph, and the completed bytes or result are
captured by a later SourceView. Model-based extraction uses an explicitly
admitted ModelTask, not a hidden SourceView callback. Local byte transformations
likewise require a registered profile. Modality alone MUST NOT select execution semantics.

<a id="results-and-delivery"></a>

## Named Results and Effect declarations

### Named Results

This subsection defines stage-local `ResultDefinition` values. Program-root
Results instead use the explicit Stage Result export grammar in [Stages](#stages).
They inherit this closed Result contract and cannot reselect its fields.

<!-- requirement-block: results-and-delivery.every-actql-program-must-declare-a-non-empty-map-of-closed -->
Every ActQL Program MUST declare a non-empty map of closed named `results`.
Each member is a logical publication boundary and may be consumed by an Effect
or retrieved independently after the Run has materialized it:

```yaml
steps:
  - top_k:
      k: 20
      by: [{score: desc}, {product_id: asc}]
    as: ranked_candidates

results:
  response:
    from: ranked_candidates
    fields: [customer_id, product_id, score]
    order_by:
      - {customer_id: asc}
      - {score: desc}
      - {product_id: asc}
```

<!-- requirement-block: results-and-delivery.a-resultdefinition-from-is-required-and-must-name-either-a-declared results-and-delivery.a-resultdefinition-from-is-required-and-must-name-either-a-declared.second results-and-delivery.compiler-generated-aoa-step-ids-are-not-actql-source-names-and results-and-delivery.fields-is-required -->
A named Result is a Relation. A `ResultDefinition.from` is REQUIRED and MUST
name an authored dataflow binding: a declared input, an explicit step `as`,
or an explicitly named multi-output port in the completed pipeline.
Compiler-generated AoA step IDs are not ActQL source names and MUST NOT be
accepted there. `fields` is REQUIRED. It
closes the data published by the Result, including delivery and Effect
consumption; the compiler does not widen that boundary when an upstream
Relation gains a field.
Optional `order_by` belongs to the named Result, not to serialization.

<!-- requirement-block: results-and-delivery.preserve-join-provenance results-and-delivery.explicit-flat-projection -->
A Result MAY select a raw join output using exact provenance-qualified names
such as `fields: [left.id, right.id]`; its `order_by` uses the same reference
rules against the source before projection. The Result schema and published
column names MUST retain the selected qualification and provenance without
implicitly stripping prefixes, merging same-named fields, or reinterpreting
them as authored flat names. This does not permit dotted authored source fields
or nested-property selection through `fields`. Result `fields` introduces no
alias syntax. A consumer that requires flat fields MUST be supplied a Result
whose required fields have been explicitly flattened upstream with join
`select`, a select alias, or `rename`; it cannot silently flatten them at the
consumption boundary. All ordinary Result type, order and publication checks
still apply.

<!-- requirement-block: results-and-delivery.the-compiler-must-verify-that-every-ordered-and-projected-field results-and-delivery.it-must-report-the-exact-result-schema-when-statically-known -->
If present, result `order_by` is applied before its field projection and lowers to
`REL.orderByStable`. `fields` lowers to `REL.select`. The compiler MUST verify
that every ordered and projected field exists and reject an authored typed
order key unless its type is `AuthorOrderable` ([Lexical and ordering rules](#ordering)).
It MUST report the exact Result schema when statically known, including
for empty runtime results. Columns-only evidence cannot prove an order-key type; such
inputs retain the deferred `AuthorOrderable` obligation of [Lexical and ordering rules](#ordering), while generated or typed
non-scalar order keys are rejected during planning.

<!-- requirement-block: results-and-delivery.every-named-result-must-have-a-proven-total-deterministic-order -->
Every named Result MUST have a proven total deterministic order at its
publication boundary. This rule applies even when no delivery is requested or
the Result is consumed only by an Effect, because later delivery selection is
not part of the checked Program.
Relation identity is a set of independently proven candidate keys; ordering is
a separate witness. When a candidate key closes authored ties, missing key
fields are appended to the Plan's ordering, not authored source ([Deterministic completion](#completion)).
Result order is resolved in this priority:

1. Apply authored `order_by`, completing ties under [Deterministic completion](#completion).
2. Otherwise preserve an existing total stable ordering witness, including
   after a projection that hides its original order fields.
3. Otherwise order by the eligible candidate key selected by [Deterministic completion](#completion).
4. Otherwise order ascending, nulls last, by all projected fields in declared
   field order, if every field is `CanonicalOrderable` ([Lexical and ordering rules](#ordering)).
5. Otherwise reject the Result.

<!-- requirement-block: results-and-delivery.authored-stable-ties -->
For authored Result order, checking MUST first apply eligible candidate-key completion. If no
eligible key is available, a retained total stable ordering witness MAY resolve
ties by stable sorting: authored terms remain primary and the witness orders
only rows equal on all those terms. This does not replace authored order with
the inherited sequence. Without either witness, reject; projected-field fallback
applies only when authored `order_by` is absent. Retained execution and admission
obligations of the supporting witness still apply.

<!-- requirement-block: results-and-delivery.physical-input-enumeration-order-must-not-break-ties -->
No lower-priority rule overrides a higher-priority one. Physical
input enumeration order MUST NOT break ties.

<!-- requirement-block: results-and-delivery.if-any-effect-consumes-a-result-checking-must-derive-a results-and-delivery.the-effective-data-and-retention-policies-must-satisfy-that-evidence -->
If any Effect consumes a Result, checking MUST derive a machine-only evidence
policy with `sensitivity: private`, retention class `authority-evidence`, and
encryption required. The effective data and retention policies MUST satisfy
that evidence policy and every constraint inherited from the Result's fields
and provenance; where constraints on one dimension are ordered, the more
restrictive value applies. This rule is not an author-visible `visibility` or
retention field.

<a id="effects"></a>

### Effect declarations

<!-- requirement-block: effects.evaluating-the-computational-part-of-an-actql-program-must-not effects.proposal-and-commit-are-separate-runtime-phases-the-host-must -->
Effects are declarative, reviewable intent. Evaluating the computational part
of an ActQL program MUST NOT apply an Effect. Proposal and commit are separate
runtime phases; the Host MUST complete current preflight and any required
Checkpoint Resolution before commit. Effect declarations lower directly to
AoA `EFFECT.plan` as defined in [AoA fragments and algebra lowering](#algebra-lowering).

ActQL 0.1 defines these closed effect kinds:

```text
create update upsert delete command store
```

The full form is:

```yaml
effects:
  mark_for_review:
    update:
      target: connector://crm/main/Opportunity
      mapping: mapping:crm.opportunity.v1
      from: {result: crm_updates}
      match:
        target_field: Id
        result_field: opportunity_id
      set:
        NeedsReview: {literal: true}
        RiskScore: {field: risk_score}
```

The nested effect-kind key is the only ActQL 0.1 spelling. A sibling `kind`
field is rejected rather than treated as an alias.

The kind determines its authority class:

<!-- requirement-block: effects.create-appends-and-must-not-address-existing-rows effects.create-appends-and-must-not-address-existing-rows.second -->
- `create` appends and MUST NOT address existing rows;
- `update` changes only addressed existing rows and MUST NOT create;
- `upsert` may create or update against a declared mapping key;
- `delete` removes only addressed rows and carries no field changes;
- `command` invokes one Connector-owned typed provider operation against
  named-result `resource_ref` values; it is not arbitrary HTTP or generic CRUD;
- `store` persists one declared named result.

<!-- requirement-block: effects.every-data-effect-must-explicitly-declare-target-and-a-typed-qualified effects.every-command-must-explicitly-declare-a-resourceref-result-field-and effects.preview-must-enforce-that-limit-on-the-complete-resolved-scope -->
Every data effect MUST explicitly declare `target` and a typed-qualified
Mapping Contract reference in `mapping`. Every command MUST explicitly declare
a ResourceRef result field and Command Contract.
Effect `max_items` is an author guard as defined in [Author guards, resolved limits, and Plan facts](#resolved-limits), constraining the
kind-specific scope units in [Preview strength, scope, and freshness](execution.md#preview-strength). Its resolved limit uses Result or literal
scope proof, Contract ceiling, Host policy, and any authored guard. Preview
MUST enforce that limit on the complete resolved scope before creating an
Effect Commit Checkpoint or dispatching a mutation. The runtime derives
deterministic apply and row idempotency keys from the exact Effect Preview,
resolved Contract, Effect member identity, target identity, operation, and intended change. The
author does not name an idempotency namespace.

<!-- requirement-block: effects.a-program-must-not-author-an-approval-review-allow-deny effects.on-item-failure-when-present-must-be-continue-omission-is-the-sole effects.the-resolved-failure-semantics-must-appear-in-the-plan-and -->
Permissions are not Program vocabulary. The compiler and preview derive the
exact permission set from the resolved Mapping or Command Contract and expose
it in the checked Plan and review projection.
Approval policy is not Program vocabulary. It is resolved from the immutable
Mapping or Command Contract and current Host policy. A Program MUST NOT author
an `approval`, `review`, `allow`, `deny`, or `checkpoint` key as Effect policy;
such a key is invalid rather than a request to weaken or strengthen authority.
`on_item_failure`, when present, MUST be `continue`; omission is the sole
canonical spelling for the fixed fail-fast behavior. The resolved failure
semantics MUST appear in the Plan and authority summary.

ActQL 0.1 treats the Effects within each stage as one unordered intent set derived
from the same Stage Invocation. Member source order is not execution order;
the enclosing stage array does guarantee success-dependent order. The set provides no
cross-member or cross-Connector atomicity, effect-to-effect order, distributed
transaction, compensation graph, or Saga execution.

Each member consumes at most one named result. A result-correlated member
(`from: {result: name}` with `id`, `match`, or the upsert `key`; `create` and
`store` from a result; every `command`) consumes exactly one. A target-addressed
member (`ids`, `external_id`, `where`, or `create` with `payload`) consumes
none. No member consumes another member's outcome within that same stage.

<!-- requirement-block: effects.a-host-apply-receipt-must-distinguish-every-member-and-every -->
Within one member, `on_item_failure` applies to its stable row sequence: `halt`
stops that member after the first failed row and marks its remaining rows
unattempted; `continue` attempts the remaining rows. Failure of one member does not suppress
another independent member under the set's fixed `attempt_all` apply policy. A
host apply receipt MUST distinguish every member and every applied, accepted,
unknown, failed, or unattempted outcome. `compensate` is invalid in ActQL 0.1
rather than an underspecified promise.

<!-- requirement-block: effects.before-preview-succeeds-the-runtime-must-derive-a-structured-write -->
Before preview succeeds, the runtime MUST derive a structured write footprint
for every member. Exact targets in the same provider boundary and identity
scheme cannot overlap, even when different fields of the same row are written.
A create collection footprint may coexist with updates only with admitted proof
that planned keys are disjoint or that allocation cannot reuse existing keys.
Without such proof collection overlap remains a conflict. An opaque footprint
cannot be combined without a contract proving independence. Different Command
payloads alone are not such a proof; a declared append capability may be.
An identity-scheme mismatch within the same
provider boundary is unprovable and therefore rejected. Authors cannot provide
free-form conflict domains or waive this check.

<!-- requirement-block: effects.update-and-delete-must-use-exactly-one-selector -->
`update` and `delete` MUST use exactly one selector:

```yaml
id: output_id_field
match:
  target_field: Id
  result_field: opportunity_id
ids: [literal_id_1, literal_id_2]
external_id: {field: external_key, value: ACME-1}
where:
  - {eq: [{field: status}, {literal: archived}]}
```

<!-- requirement-block: effects.in-actql-0-1-match-target-field-must-equal-the-connector-mapping-contract-s effects.the-result-key-and-target-key-must-both-be-scalar effects.a-missing-target-duplicate-result-identity-duplicate-target-identity-non-primary effects.literal-ids-external-id-and-where-address-the-target-directly-and effects.the-compiler-must-not-infer-a-selector -->
`id` is the preferred shorthand for reading primary-key IDs from one named
result field and therefore requires `from: {result: name}`; the resolved mapping
contract supplies the target primary-key name. `match` is not an alias for
`id`: it carries an additional auditable assertion naming the target field, so
its authority contract and ActQL CID remain distinct even when both forms emit
the same AoA effect plan. In ActQL 0.1 `match.target_field` MUST equal the
connector mapping contract's single declared primary key. The result key and target key MUST both be scalar,
unique, and non-null. A missing target, duplicate result identity, duplicate
target identity, non-primary target match, or identity-type mismatch MUST fail
before preview succeeds. ActQL performs no implicit string/number coercion for
identity matching; any permitted conversion must be explicit in the resolved
mapping contract.
`where` is a non-empty array of [Predicates](#predicates) predicates combined by conjunction. Its
`{field: name}` operands address fields of the target Resource under the
resolved Mapping Contract; they do not refer to an input Relation or named
Result. Literal and parameter operands follow [Predicates](#predicates). Only a target row for which
the conjunction is strictly true is selected; false and three-valued unknown
do not select it. Arbitrary scalar expressions are not selector operands.
Literal `ids`, `external_id`, and `where` address the target directly and MUST
NOT declare `from`. The compiler MUST NOT infer a selector.

<!-- requirement-block: effects.the-runtime-must-correlate-those-two-fields-must-not-assume effects.the-runtime-must-correlate-those-two-fields-must-not-assume.second effects.the-runtime-must-correlate-those-two-fields-must-not-assume.third -->
`create` and `store` consume `from: {result: name}` unless create uses an explicit
object `payload`. `upsert` requires `from: {result: name}`, an explicit
result-side `key`, and a non-empty `set` map. The mapping contract supplies the
possibly differently named target-side single primary key. The runtime MUST
correlate those two fields, MUST NOT assume they share a name, and MUST NOT copy
the remaining result row into the target implicitly. `update` requires a
non-empty `set` map. `delete` carries no field
changes. A step alias is an internal dataflow node; an Effect may consume it
only after stage-local `results` exposes a closed contract for it.

<!-- requirement-block: effects.its-target-field-must-be-a-value-level-resource-ref-k-whose-kind-equals -->
A command consumes one named result. Its `target.field` MUST be a
value-level `resource_ref<K>` whose kind equals the Command Contract target
kind. Each `input` member is exactly `{literal: ...}` or `{field: ...}` and is
validated against the closed Connector-owned input contract. Unknown, missing,
nullable, vector-dimension, ArtifactRef-media, and ResourceRef-kind mismatches
fail during check or preview. The target field may be projected away only by
making the command invalid; receipt-only lineage cannot restore it.

An `update` or `upsert` change value is either a literal or a field from its
correlated result row:

```yaml
set:
  NeedsReview: {literal: true}
  RiskScore: {field: risk_score}
  Reason: {field: risk_reason}
```

<!-- requirement-block: effects.bare-values-are-rejected-with-a-deterministic-explicit-replacement-and effects.a-bare-effect-value-must-be-rejected-before-lowering effects.its-diagnostic-must-expose-only-explicit-literal-and-schema-valid effects.check-must-not-guess-between-those-meanings effects.check-must-reject-unknown-result-fields effects.preview-must-reject-missing-row-values-target-fields-not-declared effects.it-must-compute-separate-strength-appropriate-state-evidence-and-a-target -->
All literal values use the explicit `{literal: value}` form. Bare values are
rejected with a deterministic explicit replacement and MUST NOT be interpreted
from schema likelihood. A bare Effect value MUST be rejected before lowering.
Its diagnostic MUST expose only explicit `{literal: ...}` and schema-valid
`{field: ...}` repairs. Check MUST NOT guess between those meanings.
`{field: name}` requires
`from: {result: name}` and a result-correlated selector (`id`, `match`, or the
upsert key). Check MUST reject unknown result fields. Preview MUST reject missing row values, target fields not
declared by the resolved mapping contract, incompatible target types, target
primary-key mutation, and duplicate row identity. It MUST compute separate
strength-appropriate state evidence and a target guard for every correlated
row under [Preview strength, scope, and freshness](execution.md#preview-strength).

<a id="checking-and-planning"></a>

## Checking and canonical planning



<a id="validation"></a>

### Validation

<!-- requirement-block: validation.if-one-complete-repair-is-unique-and-semantics-preserving-the-checker validation.if-several-meanings-remain-possible-it-must-return-stable-explicit -->
For a Program containing every required semantic choice, checking SHOULD
succeed without an authoring repair. If one complete repair is unique and
semantics-preserving, the checker MUST return that replacement. If several
meanings remain possible, it MUST return stable explicit candidates rather
than select a meaning. Diagnostic representation is specified in [Diagnostic documents](protocols/contracts.md#diagnostic-documents) and [Diagnostic compatibility profiles](protocols/contracts.md#diagnostic-profiles).

<!-- requirement-block: validation.checking-and-planning-must-not-execute-source-text-import-modules -->
Checking and planning MUST NOT execute source text, import modules, access
the network, or resolve external connection authority. A source builder is
subject to the same validation and canonical lowering contracts as textual
source; it cannot bypass them with callbacks or embedded code.

<!-- requirement-block: validation.for-supported-profiles-planning-must-parse-elaborate-validate-and-lower -->
For supported profiles, planning MUST parse, elaborate, validate, and lower
far enough to detect source, Carrier compatibility, arity, field, identity,
ordering, and effect-scope errors without running the computation.
Unsupported-profile rejection follows [Conformance profiles](conformance.md#conformance-profiles).

<!-- requirement-block: validation.machine-readable-diagnostics-must-include -->
Machine-readable diagnostics MUST include:

```text
code
path
message
```

and SHOULD include, when known:

```text
current_shape
available_results
replacement
candidates
allowed_keys
operation_signature
```

<!-- requirement-block: validation.when-multiple-repairs-are-possible-candidates-must-contain-stable-complete -->
A `replacement` is permitted only when one complete repair is semantically
unique. When multiple repairs are possible, `candidates` MUST contain stable,
complete alternatives and no replacement may be applied automatically.

<a id="completion"></a>

### Deterministic completion

The compiler MAY insert structure only when the result is type-unique and
semantics-preserving. ActQL 0.1 permits:

- previous-result wiring in a linear pipeline;
- sole-input selection when exactly one input exists;
- sole-SourceView selection under [Connector SourceViews](#sourceviews);
- generated AoA step identifiers;
- object-predicate expansion;
- relation/carrier bridges required by `row_window`, `window_events`, `graph`, `reach`, and
  `nearest`;
- graph branch projection and explicit distinct;
- restoration of authored graph/vector identity names;
- Result ordering and projection declared by each ResultDefinition;
- the sole compiler-proven `infer` candidate key when `key` is omitted;
- a retained declared identity as a stable tie-break or carrier identity.

<!-- requirement-block: completion.whenever-ordering-completion-is-required-the-compiler-must-apply-the -->
Whenever a rule permits choosing a candidate key, use this canonical algorithm:
retain only keys whose fields remain available and satisfy the use's type and
nullability requirements; sort each key's fields in canonical code-unit order;
deduplicate identical tuples; then order tuples by field count, followed by
lexicographic field sequence, and select the first. Append missing order fields
ascending with nulls last. This selection applies to Result order, tie-break
completion, eligible carrier identity completion, and preferred-identity
summaries. A rule requiring a *sole* candidate (such as omitted `infer.key`)
still rejects multiple candidates; canonical selection does not waive that rule.
Reference fields are eligible for canonical ordering completion. Whenever
ordering completion is required, the compiler MUST apply the algorithm above without
excluding a key solely because it contains reference fields.

<!-- requirement-block: completion.source-printers-repair-and-migration-must-not-write-it-back -->
Author-order restrictions apply to source before completion. Generated reference
ordering belongs in the Plan and completion evidence, not an authored order
key. Source printers, repair, and migration MUST NOT write it back as an
author-selectable reference order or expose a source flag to bypass the rule.

<!-- requirement-block: completion.the-compiler-must-not-infer -->
The compiler MUST NOT infer:

- join kind or business join key;
- fixed versus sliding versus session windows;
- event-time versus processing-time fields;
- an approximate external search in place of exact VecA;
- vector metric;
- traversal direction;
- a business tie-break;
- effect kind, effect scope, or approval policy;
- one of multiple structurally compatible inputs.

Fields with exactly one admitted meaning are not authoring vocabulary.
Their values are language laws, not choices for the checker to infer.
Optional validation assertions, including join cardinality, remain author
choices even when existing evidence already entails them.

<!-- requirement-block: completion.every-semantic-source-completion-or-macro-expansion-must-appear-in completion.they-must-appear-in-the-canonical-plan-node-and-must completion.they-must-appear-in-the-canonical-plan-node-and-must.second completion.facts-derived-from-type-identity-or-an-external-contract-are completion.facts-derived-from-type-identity-or-an-external-contract-are.second -->
Grammar decoding, including expression text ([Decoding, identity, and printing](#expression-decoding)), precedes these rules
and is not a source completion. Every semantic source completion or macro
expansion MUST appear in a stable
normalization journal with source path, authored form, resulting canonical
form, and rule identifier. Fixed operation semantics—such as SQL-style null
non-match for an ordinary join, fail-fast Effect member execution, directed
graphs, exact nearest-neighbor search, closed-open windows, first-row
deduplication, fail-on-tie behavior, and lexicographic shortest-path ties—are language laws,
not source completions. They MUST appear in the canonical Plan node and MUST
NOT produce normalization entries. Facts derived from type, identity, or an
external Contract are Plan proofs and MUST bind the evidence CID on which they
depend; they likewise MUST NOT appear as source normalization.

<a id="normalization-journal"></a>

### Normalization Journal

<!-- requirement-block: normalization-journal.paths-use-the-declared-rfc-9535-compatible-jsonpath-subset-rule-ids -->
The identity-bearing journal has version `actql-normalization-journal/0.1` and
contains `rule_catalog_cid`, canonical `entries`, and `journal_cid`. Every entry
has exactly `path`, `rule`, `authored`, and `canonical`. Paths use the declared
RFC 9535-compatible JSONPath subset; rule IDs MUST exist in the frozen
`actql-normalization-rule-catalog/0.1`. Entries are ordered by path, rule,
authored bytes, then canonical bytes using the ActQL code-unit order. The
journal CID is computed over `{version, rule_catalog_cid, entries}`.

<!-- requirement-block: normalization-journal.two-implementations-claiming-the-same-normalization-rule-catalog-and-check-evidence -->
Compiler-specific notes or prose may accompany a journal only as non-semantic
presentation and are excluded from its CID. Two implementations claiming the
same normalization-rule catalog and check evidence MUST emit byte-identical
semantic entries and journal CID. An implementation with different internal
pass names maps them to the normative rule IDs rather than exposing those names
as language semantics.

<a id="generated-identifiers"></a>

### Generated identifiers

AoA steps generated from ActQL source receive deterministic identifiers based
on document order and preferred operation names. Generated identifiers are not
part of the ActQL authoring surface. There is no alias-equivalence class in
ActQL source: operation, parameter, expression, and binding names use exactly
their registered spelling.

<a id="algebra-lowering"></a>

### AoA fragments and algebra lowering

ActQL source vocabulary, AoA registry vocabulary, and Executable Plan node
vocabulary are three disjoint namespaces:

```text
ActQL algebra form   --lowers to--> AoA operation in an AoA Fragment
ActQL boundary form --compiles to-> typed barrier node
AoA Fragments + typed barriers ----> ActQL Executable Plan
```

An ActQL operation name describes the author-visible action. An AoA operation
identifier names the canonical computation primitive selected by lowering.
Lexical equality between those names is neither required nor semantic: for
example, ActQL `filter` lowers to AoA `REL.where`. AoA identifiers such as
`REL.where` are not ActQL source spellings and are rejected as unknown ActQL
operations. The normative mapping below is the only connection between the two
namespaces. Source names express author-visible actions rather than IR wiring;
the generated operation inventory exposes their canonical mappings.

<!-- requirement-block: algebra-lowering.every-fragment-must-satisfy-the-pinned-aoa-registry-s-sort-compatibility -->
An ActQL compiler lowers every algebra form into one or more typed AoA
Fragments, including separately identified effect-planning fragments. Every
fragment MUST satisfy the pinned AoA registry's sort compatibility, arity,
cycle, dangling-reference, operation-parameter, and output validation
contracts. A program
without a boundary form executes those validated AoA Fragments directly.

When an acquisition or Artifact boundary form is present, the compiler instead
binds the validated fragments and content-addressed typed barriers into one
`actql-executable-plan/0.1` envelope. The envelope is an ActQL protocol
artifact, not ActQL source, not AoA IR, and not another authorable language. It
has no authorable control flow and does not reinterpret AoA semantics.

The required mapping from ActQL algebra forms to canonical AoA registry
operations is:

<!-- requirement-block: algebra-lowering.actql-surface-form-canonical-aoa-registry-operation -->
| ActQL surface form | Canonical AoA registry operation |
| --- | --- |
| `filter` | `REL.where` |
| `select` | `REL.select` |
| `rename` / `drop` | `REL.select` |
| `derive` | `REL.derive` |
| `sort` | `REL.orderByStable` |
| `take` | `REL.limit` |
| `top_k` | `REL.topk` |
| `top_k_by` | `REL.topk_partitioned` |
| fixed/sliding `row_window` | `REL.window.fixed` / `REL.window.sliding` |
| `window_group` | `REL.window.project` |
| `lag` | `REL.window.lag` |
| `watermark_rows` | `REL.watermark` |
| `pivot` | `REL.pivot` |
| `unpivot` | `REL.unpivot` |
| `json_pick` | `REL.json.pick` |
| `unnest` | `REL.unnest` |
| `distinct` | `REL.distinct` |
| `dedupe_rows` | `REL.dedupeRows` |
| `assert_rows.where` / `assert_rows.unique_by` | `REL.assert_all` / `REL.assert_unique` |
| `group` | `REL.groupBy` |
| `join` | `REL.join` |
| `append` | `REL.unionAll` |
| `values` | `REL.values` |
| `except` / `intersect` | `REL.except_rows` / `REL.intersect_rows` |
| `cross_join` | `REL.cross_join` |
| `analytic` | `REL.analytic` |
| `normalize_graph` | `SGA.normalize` |
| `reach` | `SGA.reachable` |
| `match_nodes` | `SGA.match_nodes` |
| `match_edges` | `SGA.match_edges` |
| `traverse` | `SGA.traverse` |
| `shortest_path` | `SGA.shortest_path` |
| `components` | `SGA.components` |
| `graph_bounds` | `SGA.bounds_check` |
| `degree` | `SGA.degree_metrics` |
| `graph_diff` | `SGA.diff` |
| `graft_graph` | `SGA.graft` |
| `union_graphs` | `SGA.union_structural` |
| `subtract_graphs` | `SGA.diff_structural` |
| `subgraph` | `SGA.subgraph` |
| `graphs_equal` | `SGA.equal` |
| `apply_graph_delta` | `SGA.apply_delta` |
| `mean_graphs` | `SGA.mean_structural` |
| fixed/sliding `window_events` | `TEA.window.fixed_label` / `TEA.window.sliding_assign` |
| `watermark_events` | `TEA.watermark.label` |
| `session` | `TEA.window.session_assign` plus relation bridge when required |
| `dedupe_events` | `TEA.dedupe` |
| `asof_join` | `TEA.join.asof` |
| `sequence` | `TEA.sequence.match` |
| `time_series` | `TEA.time_series` |
| `interval_join` | `TEA.join.interval` |
| `calendar_bucket` / `calendar_series` | `TEA.calendar.bucket` / `TEA.calendar.series` |
| `normalize_vectors` | `VEC.normalize_l2` |
| `score_vectors` | `VEC.score_sort` |
| `nearest` | `VEC.knn_join` |
| `pool_vectors` | `VEC.pool` |
| `merge_rankings` | `VEC.merge_rankings` |
| `text_rank` | `REL.text_rank` |
| `edge_rows` | `BRIDGE.graph.to_edge_rows` |
| `node_rows` | `BRIDGE.graph.to_node_rows` |
| `graph` | `BRIDGE.rows.to_graph` |
| `events` | `BRIDGE.events.to_rows` |
| `to_events` | `BRIDGE.rows.to_events` |
| `vectors` | `BRIDGE.vectors.to_rows` |
| `to_vectors` | `BRIDGE.rows.to_vectors` |

<!-- requirement-block: algebra-lowering.failure-to-lower-completely-is-a-validation-failure-a-compiler -->
`nearest` may emit vector bridges for relation inputs;
`graph` may emit relation branch operations before its graph bridge.
Output-correlated effect declarations emit separately identified AoA pipelines
terminating in `EFFECT.plan`. They do not introduce an
ActQL effect IR or another executable language layer.
No ActQL algebra operation may lower to an unregistered AoA operation. Typed
barriers instead resolve exact versioned task, SourceView, or serialization
contracts plus validated request fragments.
Failure to lower completely is a validation failure; a compiler MUST NOT emit
a partially executable plan.

<a id="operation-binding"></a>

#### Canonical binding of additional operations

The added mappings specify required registry contracts, not permission to
invoke unregistered kernel exports. The admitted registry and expression
extension identities in the Check Environment bind these operations and
their complete parameter, type, numerical and failure laws. An implementation
without those contracts cannot issue a runnable Plan for the operation.
Registration/implementation status is not a different source meaning.

Each added single-output operation lowers to exactly one node with the mapped
operation ID, the usual generated step ID, ordered input references and closed
parameters. `union_graphs` with a list is the exception: emit the binary
union nodes as a left fold, using generated operation-local suffixes 0..n-1;
even laws allowing physical reassociation do not change this canonical fold.
No physical indexes, hash tables, runtime batch partition or evaluator caches
appear in this graph. Existing bridge lowering remains as specified above.

Input references are current input first, then with for binary operations;
mean_graphs uses its declared graph list; RRF uses current then its with list;
text_rank uses corpus then queries; subgraph and shortest_path append named
selector Relations in nodes/source/target slot order when present. Generators
without referenced inputs have an empty input list. Repeated references keep
their list positions. Fixed operands occur only in `graph.in`; their source
reference members are removed from parameters. A Relation selector instead
replaces its `from` member with `input_port`, a zero-based number, retaining
its `id` field. It never retains a separately resolved source name.

Canonical parameters retain the operation body's keys and structural values,
excluding input references, step from/as/meta and publication names. Object
keys use canonical field-name order; semantic lists retain declaration order.
Insert fixed defaults: take offset=0; unnest outer=false; omitted join
null_key=no_match; lag offset=1; single-ID shortest_path selection=each_pair;
unweighted shortest_path weight=null; absent subgraph edges=literal true.
Normalize a single union/RRF with to a one-element list. Values retains an
ordered array of complete rows; it never derives their order from object
keys. Bind parameters using the common parameter contract before lowering;
literal business objects remain data, not expression syntax. For values, the
checked schema and unwrapped bound cells follow the execution contract below
rather than retaining author-type defaults or cell operators. Checked output
contracts supply empty collection item types and nullable outer results.

The following table closes input wiring for added operations only; existing
operations retain their specified lowering contracts. `C` means the selected current input;
names in brackets are ordered `graph.in` entries, including repeated names.
All non-reference body members remain, except the defaults and publication
members specified above. Selector `where` and `ids` variants remain unchanged.

<!-- requirement-block: operation-binding.input-ports -->
| Operation | Source reference slots | Ordered inputs | Reference members in canonical params |
| --- | --- | --- | --- |
| except, intersect, cross_join, graphs_equal, apply_graph_delta, interval_join | with | [C, with] | remove with |
| mean_graphs | with list | declared list | remove with; retain weights/support/properties |
| merge_rankings (RRF) | with list | [C, ...with] | remove with; retain ordered weights in policy |
| text_rank | queries | [C, queries] | remove queries |
| subgraph | nodes.from when present | [C, nodes.from] or [C] | nodes becomes {input_port: 1, id} for Relation selector |
| shortest_path | source.from, target.from when present | C, then source Relation, then target Relation | replace each Relation selector with {input_port: assigned index, id} |
| union_graphs list | with list | binary node i takes previous fold result and with[i] | remove with from each binary node |
| values, time_series, calendar_series | none | [] | retain remaining body |
| analytic, calendar_bucket | none beyond current | [C] | retain body |

Non-RRF ranking merge retains its existing binary lowering. Search is a typed
barrier, not a node in this table: source resolves the static acquisition
template, query_input binds the selected current/query Relation, and outputs
binds publication ports rather than algebra inputs.
Union node IDs are `<operation-base>_union_<i>` with zero-based i; allocate the
operation-base once by the ordinary collision-checked allocator for that step.
Only the final node receives the authored output binding. Two union steps
therefore never restart a shared global suffix namespace. The source list's
singleton and scalar forms have the same one-node expansion.

Expression pointers are relative to the canonical node's params: analytic
`/functions/<escaped-name>/expr` and `/functions/<escaped-name>/filter` use the
input row schema; subgraph `/edges` uses edge schema and `/nodes/where` uses
node schema; shortest_path `/source/where` and `/target/where` use node schema.
Search `/request/<escaped-role>` is relative to the barrier request expression
map's enclosing object and uses the query row schema. No pointer targets a
removed input-reference member. Other added operations above have no expression
roots beyond the shared calls explicitly admitted in their definitions.

Independent wiring and value/proof examples are recorded in
[`operation-integration-vectors.json`](../../spec/operation-integration-vectors.json).
These are expected specification outputs, not execution conformance claims.
Wiring examples omit resolved type/resource envelopes and the ordinary node ID
unless ID allocation is the subject of the example. Defaults inside analytic
lag/lead calls are offset=1; every other optional member remains absent unless
its operation explicitly specifies a normalization default.

<!-- requirement-block: operation-binding.roots -->
Expression roots MUST use the common checked-node lowering and retain their
canonical parameter paths: analytic functions/<output>/expr or filter slots
where admitted; subgraph edges and selector where slots;
search request/<role>; existing aggregate expr/filter slots; and vector
function argument positions. Enumerate roots by canonical JSON Pointer order,
escaping ~ and / as ~0 and ~1. Structural field names, metrics, frames,
literal values rows, graph deltas and profile configuration are not expression
roots. Generated typed NULL/empty nodes use checked contracts, never untyped
machine literals. Common expression admission rederives each root, type,
demand path and envelope against its consumer and bound inputs.

Analytic filters/arguments have the frame/partition demand specified by
analytic, not an unconditional preceding derive. Scalar vector nodes retain
the tags vector_score/vector_concat in the common expression tree and lower
to the corresponding op/body nodes, with metric a structural slot. They
bind the metric profile and component limits through the same root envelope
mechanism as other profiled pure expressions. Aggregate nodes retain their
function tag, filter, order, distinct and extra arguments; added aggregates
do not lower through arithmetic macros that change demand or fold order.

<!-- requirement-block: operation-binding.limits -->
Every added node MUST bind resolved limits by measurement and logical
consumer: input admission, expression evaluation, pair/frame/path exploration,
token/statistic computation and output materialization are distinct scopes.
Enumerate bindings by node ID, consumer JSON Pointer and measurement name;
duplicate keys fail. Numerical/profile contracts bind separately from Host
physical resource ceilings. Optimizations preserve logical cardinalities,
types, values, demand, representative failure and enforced logical limits;
they need not reproduce physical allocation counts or elapsed time. Validators
reconstruct canonical nodes, input positions, roots, types and limit bindings
from the checked request rather than accepting a rehashed graph as evidence.

<!-- requirement-block: algebra-lowering.for-each-result-correlated-update-upsert-or-delete-the-compiler-must -->
For each result-correlated `update`, `upsert`, or `delete`, the compiler MUST
emit a separately identified AoA pipeline terminating in `EFFECT.plan`.
`selector_field` is the declared result identity field and `field_map` contains
only `{field: result_field}` changes; literal changes remain in the authority
contract. The AoA effect-plan logical CID and the authority contract are both
bound by the ActQL CID. Effect-plan execution materializes reviewable intent
rows only and grants no write authority.

<a id="rel-values-execution"></a>

##### REL.values execution parameters

The executable contract is `actql-rel-values-execution/0.1`, owned by
`actql-aoa.json#/execution_contracts/REL.values`; its signature and complete
contract CID are required by `target_registry_requirements["REL.values"]`.
Its `params_schema` is a standalone JSON Schema resource. This is not the
Program authoring `values` schema and is not an in-memory checked-cell enum.

<!-- requirement-block: values.execution-shape -->
REL.values parameters MUST contain exactly `schema` and `rows`, with no optional
or unknown members: `schema` is a nonempty field-name map of complete checked
value contracts, and `rows` is an ordered array of objects. Checked contracts
include explicit `nullable`, object `additional_properties: false` and vector
`element_type: f32`; recursive opaque JSON and reference domains are excluded
by constructor eligibility, even for empty rows. Existing safe-integer limits
on string/array extents apply. No schema inference or author-type defaulting
occurs at this boundary.

<!-- requirement-block: values.execution-binding -->
Before constructing execution parameters, the compiler MUST resolve each
authored cell-root Parameter hole against the selected checked bindings, and
remove exactly one authored singleton `literal` quotation while retaining its
payload unchanged. An ordinary literal cell passes through as data. Resolution
does not descend into literal or supplied business values. There are no holes
or quotation operators in the execution params grammar: every row member is
a typed wire value, including objects whose keys are `$param` or `literal`.
Missing bindings or incompatible declared/bound types fail before lowering;
parameters are not evaluated or substituted by the REL.values executor.

<!-- requirement-block: values.execution-admission -->
The execution boundary MUST verify each row's exact declared field set and
recursive value/type compliance without implicit casts, filling, normalization
repair or rounding, before publishing any output. Nullable permits null, not
omission. Strings and keys are well-formed NFC followed by LF canonical text;
numbers are finite binary64 and not negative zero. Decimal is canonical
fixed-scale JSON string text under its declared precision/scale, not a number,
coefficient object or typed-identity projection. Date and timestamp use their
existing canonical text, arrays are ordered wire arrays, objects are exact
field maps, and vectors retain admitted finite numeric components without an
extra quantization step here. Schema validation covers closed shape and checked
type syntax; schema-to-row agreement, canonical text, numeric domains, calendar
validity, decimal precision/scale spelling and resolved resource limits require
semantic validation. Duplicate JSON keys are rejected before map construction.

<!-- requirement-block: values.execution-observation -->
REL.values MUST preserve the declared schema for zero rows, every row occurrence
in list order, and duplicate rows. Object keys use canonical UTF-16 ordering
for serialization and do not determine row order. Neither deduplication nor
reordering is authorized by canonicalization. The internal occurrence ordinal
is not an extra output field or evidence of unique field values. Full value
validation and resolved row/byte/recursive-value limits precede publication;
validation can be bounded or streamed but cannot expose a partial successful
Relation.

<!-- requirement-block: values.execution-registration -->
A runnable Plan using REL.values MUST bind a registry entry implementing the
signature and pinned execution contract, its checked-type dependency and the
existing canonical JSON, typed-value and failure laws. A matching operation
name or input/output signature alone is insufficient. A backend unable to
preserve typed decimals, empty schema evidence, order, multiplicity or required
validation/limits rejects executable compilation, without casts or alternate
encodings. The selected registry is the complete JSON body at
`pipeline_registry_file` (repository-root-relative) in the AoA contract; its
canonical CID is `pipeline_registry_cid`. The REL.values entry's
`execution_contract.file` is repository-root-relative and its `pointer` resolves
within that file; its `cid` identifies the complete selected subtree, not just
the params schema. Registration resolution verifies the registry body CID,
signature, reference and execution-contract CID against the target requirement.
The selected registry registers this extension; registration does not assert
backend implementation, authorize a Program, or discharge other Program and
runtime obligations. Other target requirements remain separate from actual
registrations and are not implicitly added to this registry.

<a id="plan-documents"></a>

### Typed barriers and Plan Documents

<!-- requirement-block: plan-documents.boundary-forms-must-not-lower-to-aoa-operations -->
Boundary forms MUST NOT lower to AoA operations. They compile to the following
closed Executable Plan nodes:

<!-- requirement-block: plan-documents.actql-boundary-form-executable-plan-node-barrier -->
| ActQL boundary form | Executable Plan node | Barrier contract |
| --- | --- | --- |
| `infer` | `acquisition_barrier` | `actql-inference-barrier/0.1` |
| keyed SourceView `join` acquisition | `acquisition_barrier` followed by RelA `join` | `actql-lookup-barrier/0.1` |
| `search_candidates` | one `acquisition_barrier` with candidates and coverage output ports | `actql-search-barrier/0.1` |
| `serialize` | `artifact_barrier` | `actql-artifact-barrier/0.1` |
| binary64 `sum` / `avg` | compiler-inserted `numeric_observation` | numeric capture contract; exact lanes remain AoA computations |

The barrier contract, profile contract CID, input and output port contracts,
and adjacent AoA Fragment CIDs are all part of Executable Plan identity.
Pure text-time evaluation is a registered expression within AoA Fragments,
with per-expression contracts and envelopes, not an acquisition node.
Profile admission precedes evaluation; unsupported execution stops before
input/provider access ([Text, time, and regular expressions](#text-time)).

A numeric observation node binds the logical aggregate slot, input/contributor
contract, numerical law, limits and typed output. Local reduction and remote
pushdown both return a captured observation to that same boundary. The Plan
does not include the future adopted value. The infer node binds model
execution/retry/media contracts and outcomes versus strict mode.

The Executable Plan fixes the canonical computation and admitted execution
envelope, not a Host's physical execution strategy. Hosts MAY choose different
placement, batching, pushdown, scheduling, or execution algorithms wherever
the checked contracts leave those choices open. Limits, access constraints,
and evidence requirements already bound into the Plan remain binding; calling
a choice physical does not exempt it from those requirements.

<!-- requirement-block: plan-documents.physical-optimization-must-not-change-a-bound-plan-s-semantic-identity -->
Physical optimization MUST NOT change a bound Plan's semantic identity or the
artifact covered by an approval. Choosing a physical strategy within the
checked envelope does not authorize rewriting that envelope under an existing
approval.

<!-- requirement-block: plan-documents.estimates-must-not-substitute-for-proven-bounds-enforced-limits-or -->
A complete Plan closes the permitted computation and external boundaries; it
does not require all observed values or exact row counts to be known before
execution. A Host MAY use separately supplied statistics and historical Run
measurements to estimate scale and select an admitted physical strategy.
Estimates MUST NOT substitute for proven bounds, enforced limits, or concrete
scope evidence required for approval. Planning itself does not acquire new
provider observations.

Physical strategy revisions may change only unexecuted work and must preserve
the canonical computation, failure rules, captured observations, approved
artifacts, and remaining limits. Estimates may guide placement, batching,
parallelism, spill, and equivalent algorithms, but never widen a SourceView,
egress destination, or Effect scope. Unknown statistics are not zero estimates.
The Host may acquire additional statistics only as declared, authorized,
budgeted work; compiler evidence resolution performs no hidden acquisition.
Observed statistics carry their subject, authority scope, method, freshness,
snapshot applicability, and uncertainty. Statistics containing source-derived
values retain the source's data-policy protections.

The Host records adopted strategy revisions and the evidence used to select
them separately from canonical Plan identity. Adaptive optimization and a
particular cost model are not required for conformance. Quota observations are
not reservations; waiting or rescheduling does not waive dispatch-time checks.

<!-- requirement-block: plan-documents.an-independent-implementation-that-does-not-supply-and-validate-one plan-documents.an-independent-implementation-that-does-not-supply-and-validate-one.second -->
The required module mappings are bound by `target_registry_requirements` in
`ACTQL_AOA_CONTRACT`.
An independent implementation that does not supply and validate one of those
operations MUST reject the corresponding source and MUST NOT claim that module.

AoA IR is the canonical identity of each computation fragment. Its logical CID
is computed using the AoA canonical serialization and hash contract. Every
staged program additionally has an Executable Plan CID binding every fragment
and barrier CID. An ActQL source hash MAY be stored as provenance, but it is not
interchangeable with either executable identity.

<!-- requirement-block: plan-documents.planning-must-not-acquire-provider-data-create-run-state-or -->
Planning MUST NOT acquire provider data, create Run state or Checkpoints, or
capture private invocation inputs.

<!-- requirement-block: plan-documents.planning-an-otherwise-valid-program-with-unbound-scalar-parameters-or -->
Planning an otherwise valid Program with unbound scalar parameters or opaque
bindings MUST return `needs_bindings` without issuing a runnable Plan Document.
Writing a runnable Plan requires every declared value to be bound.

<a id="evidence-propagation"></a>

### Evidence propagation

<!-- requirement-block: evidence-propagation.the-actql-operation-semantics-table-inside-that-envelope-and-the-propagation-laws -->
The machine-readable portability envelope containing scalar, external-call,
aggregate, join-order, operation-propagation, and atomicity laws is
`ACTQL_PORTABILITY_CONTRACT`, identified by `ACTQL_PORTABILITY_CONTRACT_CID`.
The `ACTQL_OPERATION_SEMANTICS` table inside that envelope and the propagation
laws in this specification MUST agree. Every
public operation has exact `identity`, `order`, `completeness`, and `schema`
rules. The central propagation laws are:

<!-- requirement-block: evidence-propagation.operation-identity-stable-order-completeness -->
| Operation | Identity | Stable order | Completeness |
| --- | --- | --- | --- |
| `filter` / scalar-preserving `derive` | preserve | preserve | preserve |
| `select` / `rename` / `drop` | retain every fully and uniquely mapped candidate key | preserve | preserve |
| `derive` array | retain unchanged keys or proved complete exact-copy aliases; computed key shadow loses proof | retain row positions and input column positions; append new columns in slot order; old sort-key proof does not apply to shadowed values | value-version policy and input provenance; no completeness upgrade |
| non-outer `unnest` | source key + exposed/retained non-null index | source then index | preserve |
| outer `unnest` | no key from nullable index; parent key only with proven at-most-one expansion | internal source/element occurrence order | preserve |
| `group` | group keys | canonical group-key order | preserve |
| `join` | join-kind × cardinality table in [join](#join), then projection | kind-specific [join](#join) order | complete only if both complete |
| `append` | discriminator + local key only when literal domains prove disjointness | left then right | complete only if both complete |
| `dedupe_rows` | `by` fields | canonical key order | preserve |
| `assert_rows.where` | preserve | preserve | preserve on success; atomic failure otherwise |
| `assert_rows.unique_by` | preserve and add the checked non-null unique tuple | preserve | preserve on success; atomic failure otherwise |
| `pivot` | index fields | canonical index order; empty values with nonempty index uses first-occurrence order under [reshaping](#reshaping); empty index emits one global group | preserve |
| `take` / `top_k` | preserve | requires/provides total stable order | bounded-query completeness |
| SGA query | node/edge keys where exposed; path rows need no synthetic scalar ID | canonical graph/path order | atomic bound failure |
| TEA session/sequence | record/session IDs; `sequence(disallow)` label IDs | canonical event/match order | atomic bound failure |
| VecA nearest/merge | query + candidate | query, score desc, candidate | complete only if all inputs complete |

<!-- requirement-block: evidence-propagation.a-compiler-must-not-report-stronger-evidence-than-these-laws -->
A compiler MUST NOT report stronger evidence than these laws. Internally it
represents candidate keys as a set and ordering as a distinct proof. An empty
field-key list does not stand for operation-defined ordering. Concrete
field schemas and renamed keys are inferred from the checked schema bundle,
but loss or preservation cannot vary by host. Successful check reports the
inferred schema, one preferred identity when proven, stable-order status,
completeness requirements, and generated-field collisions.

<!-- requirement-block: evidence-propagation.an-assertion-must-execute-before-any-operation-that-relies-on -->
An assertion MUST execute before any operation that relies on its proof.

<a id="resolved-limits"></a>

### Author guards, resolved limits, and Plan facts

<!-- requirement-block: resolved-limits.a-compiler-must-retain-an-explicitly-authored-guard-and-its -->
An **author guard** is an OPTIONAL positive safe-integer constraint that fails
protected work when its measured scope exceeds the guard. It expresses an
independent safety choice, not a request to select the first N items. The
operation-specific sections define its scope unit and enforcement boundary.
Source may supply a literal or `{$param: name}` under [Parameters and binding](#parameters); the resolved limit
uses the bound value and retains the author's guard provenance.
A compiler MUST retain an explicitly authored guard and its provenance even
when a Program proof or current Contract/Host ceiling is equally or more
restrictive. The availability of a derived bound does not require its value to
be repeated in source.

<!-- requirement-block: resolved-limits.every-runnable-capacity-limit-must-be-represented-by-a-canonical resolved-limits.candidate-order-is-canonical-and-checked-addition-or-multiplication-must -->
Every runnable capacity limit MUST be represented by a canonical
`actql-resolved-limit/0.1`, built from one or more
`actql-bound-witness/0.1` values. A witness identifies its unit, numeric value,
role, governing law, dependency CIDs, and one of these sources: Program proof,
author guard, pinned Contract, language law, or Host policy. Equal numeric
values with different evidence remain different witnesses. Candidate order is
canonical, and checked addition or multiplication MUST reject safe-integer
overflow rather than saturate.

Every non-source witness carries a closed derivation (`preserve`, `min`, `add`,
`multiply`, `clamp`, or an enforced preflight ceiling). Plan validation resolves
its dependency witnesses and recomputes the numeric value. Role/source pairs,
known law IDs, and dependency closure are checked rather than accepted as
self-described metadata.

<!-- requirement-block: resolved-limits.at-least-one-finite-candidate-is-required-for-a-runnable resolved-limits.every-breach-is-fail-it-must-not-truncate-a-relation -->
The effective maximum is the minimum of every applicable available candidate:
Program-proven upper bound, author guard, Contract ceiling, language ceiling,
and Host ceiling. At least one finite candidate is REQUIRED for a runnable
capacity limit. A proven upper bound is evidence about the data; a ceiling is
a restriction requiring enforcement, not such a proof before its check.
An author guard is `binding` only when it is stricter than all non-author
candidates; otherwise it is preserved as `currently_non_binding`. Every breach is `fail`:
it MUST NOT truncate a Relation, external acquisition, Effect Set, or
Artifact. The resolved limit records whether enforcement is static, unit
preflight, before provider dispatch, before Effect commit, streaming atomic,
or engine atomic. An absent author guard is recorded as `absent`, not as an
inferred source field. Host policy changes affect limit resolution, not whether
an authored guard is legal or redundant source syntax.

<!-- requirement-block: resolved-limits.an-operation-must-either-provide-a-versioned-upper-bound-transfer-law -->
`actql-bound-transfer-laws/0.1` classifies every public operation. An operation
MUST either provide a versioned upper-bound transfer law or explicitly require
a finite Contract/Host/author ceiling. Row-preserving operations retain their
input upper bound; `take` and `top_k` clamp it; append adds; bounded expansion
uses checked multiplication; reductions use their operation-specific bounds; joins,
graphs, vectors, temporal operations, inference, and serialization use their
carrier-specific laws. A public operation absent from this registry cannot
produce a runnable Plan.

<!-- requirement-block: resolved-limits.transfer-classification -->
The pinned transfer registry MUST cover exactly the public operation inventory.
Its classifications describe upper-bound transfer, not exact output counts or
permission to execute. `preserve` permits retention of an applicable input upper
bound even when rows are removed; for `nest`, `except`, and `intersect` that
input is the parent/left operand. `clamp`, `add`, and `multiply` select checked
numeric transfer using the operation's actual limit, operand occurrences or
expansion factor. `reduce` requires the operation-specific reduction law,
including its empty-input behavior; it does not assert that every reduction
emits at most the input count. `carrier_specific` requires the law for the
selected Carrier, output port and quantity, rather than a generic row formula.
`explicitly_unknown_requires_ceiling` supplies no derived finite upper bound:
execution requires an applicable finite ceiling and its enforcement. Registry
coverage alone establishes neither a governing witness-law application nor the
validity of its source evidence. Unknown inputs or unresolved factors are not
zero, and none of these classifications waives validation or enforcement.

<!-- requirement-block: resolved-limits.it-must-not-issue-a-runnable-plan-whose-finite-capacity local-approval.product-54ee89eaf54b local-approval.product-6e21b62c13b1 -->
Resolved limits, fixed language laws, and pinned Contract facts belong to the
content-addressed `actql-plan-fact-manifest/0.1`, not the Normalization Journal.
Changing Host policy leaves Program Definition identity unchanged but changes
the checked Plan whenever a Host witness changes. Adding or changing an author
guard changes Program Definition identity. A checker MAY validate semantics
with incomplete execution-policy evidence. It MUST NOT issue a runnable Plan
whose finite capacity remains unresolved.

Every resolved machine limit is also bound to the exact barrier field, AoA step
field, or input preflight it governs. Validation requires the execution value to
equal the resolved maximum, rejects missing or duplicate bindings, and rejects
resolved limits that are not consumed by executable semantics. Fixed language
laws remain Plan facts and do not masquerade as authoring normalization.

<a id="canonical-identities"></a>

### Canonical identities

ActQL uses distinct identities rather than overloading one CID. Stage body CIDs
bind local IDs and local semantics without the enclosing Program CID. Program
semantics bind their ordered descriptors, parameters, imports and exports;
Program Definition adds the root ID. Node-local semantic identities never
include the enclosing Program revision, transitively or directly. The graph
membership envelope binds both sides separately. No definition hashes its
containing Program or future observations. The following invocation/plan/manifest
identities apply to an extracted single-unit Program; its Program Definition is
the local Unit Definition, not the enclosing multi-node Program revision.
The graph output index aggregates node history without new Invocations:

- `source_text_hash` is non-semantic provenance over authored bytes;
- `program_semantics_cid` is the CID of the canonical unbound ActQL semantic
  envelope, excluding authored `id` and every allowed presentation-only
  `meta` object;
- `program_definition_cid` binds the authored authority-bearing `id` to that
  semantics CID;
- `authoring_context_cid` identifies the separately extracted metadata sidecar
  bound to that Program Definition;
- `check_environment_cid` binds the exact evidence bundle used by check;
- `parameter_values_cid` binds one canonical typed value map using the
  [Parameter value identity projection](protocols/contracts.md#parameter-value-projection);
- `invocation_template_cid` binds Program Definition CID, Parameter Values
  CID, Check Environment CID, and the fact that runtime sources remain unbound;
- `executable_plan_cid` binds the complete graph and execution material ([Typed barriers and Plan Documents](#plan-documents)),
  including fragments, barriers/wiring, Results, effects, governing facts,
  resolved limits, source-state requirements, and semantic contract identities;
- `compiled_plan_cid` identifies the compilation envelope below, including
  `executable_plan_cid`; it is not an alias for the main AoA logical CID;
- `prepared_invocation_cid` binds one bound Invocation Template and Compiled
  Plan to an authenticated execution context, current Host policy decision,
  and expiration without restating their execution details;
- `run_authorization_cid` binds the Host's current allow or approved decision
  for that exact Prepared Invocation;
- `run_definition_cid` binds the immutable definition of one durable Run,
  including its initial captured input artifact set ([Run admission and identity](execution.md#run-admission));
- `invocation_cid` binds Program Definition, parameter-values, and Check
  Environment identities to the exact captured observation evidence ([Capture, execution, and replay](execution.md#capture-and-replay));
- `result_manifest_cid` binds the complete name-to-Result-Artifact map produced
  by one Run without embedding Result rows ([Named Results and Effect declarations](#results-and-delivery));
- `effect_preview_cid` binds the concrete invocation and authority preview; and
- Run/apply receipt CIDs bind the exact published artifacts and outcomes, while
  a Result delivery receipt CID additionally binds one selected canonical byte
  representation ([Result delivery](protocols/artifacts.md#result-delivery)).

<a id="local-approval"></a>

#### Local semantic identity and graph membership

Unit namespace is the typed pair of stable authored Program id and node id.
Unit Definition binds this namespace, the complete local body, used parameter
and binding declarations, producer namespace/definition/export/port/type and
correlation contracts, and incoming success/freshness declarations. It excludes
parent revision CID, sibling bodies, unrelated exports, physical paths and array
position. Renaming a node or changing its incoming dependency changes local
meaning. Canonical extraction reuses a single-unit Program Definition and typed
namespace encoding; ambiguous concatenation and duplicate artifact families are
not permitted.

The compiler MUST derive local parameter, binding, contract and review
projections by the pinned law, including domain, guard, permission, scope and
failure dependencies, not an optimizer's optional slice. Whole values and lock
remain graph admission evidence. Local contract closure contains all interpreted
schema, Mapping, Command, ModelTask, capacity, policy and numeric laws. Catalog
membership, uniqueness of resolution and whole-lock authenticity remain checked;
this is not automatic compatible-lock renewal.

An exact Preview MUST bind Unit Definition, used effective values, local contract
closure, exact admitted inputs/imports and observations, required issuer, order,
completeness, policy/provenance, targets, payloads, guards, management-write recipe
and resolved limits. Type equality alone cannot substitute a different producer
receipt. Full ArtifactRef scope remains material. Global Program/lock/manifest
CIDs, unrelated metadata, physical Run ids and the dispatch key itself are
excluded, including indirect ancestry through Invocation, Result, receipt or
parameter envelopes. Projected evidence has its own CID, never its parent's CID.

The local_manifest_cid and semantic_outcome_cid reference roles resolve only to
the registered semantic projections, not the Run-bound Manifest or full
apply receipt. Their registered reference graph includes Result Artifact and
local Invocation descendants. Required source-audit correspondence, signatures
and membership are verified through separate projection attestations; retaining
the entire Captured Run as evidence does not put its wrapper CID into Preview.

Authenticated membership binds current graph revision/run, namespace, local
definition and local artifacts outside their semantic hash preimages. Admission
checks both local semantics and membership/producer authority. A same-shaped raw
JSON value without evidence does not grant execution rights. Local review binds
annotations actually reviewed for the unit and applicable shared root explanation;
unrelated stage metadata and absolute UI positions are excluded. Browse-only
context is distinct from signed review. Changing relevant explanation requires a
new review; changing only node 3 leaves fixed node 1/2 templates unchanged.
New graph launch still needs composition admission; reuse of earlier successful
work requires an explicit recovery link, not silent replay of an old Resolution.

The normative `actql-program-semantics/0.1` canonical envelope is:

<!-- requirement-block: canonical-identities.actql-program-semantics local-approval.product-5938286d40d5 local-approval.product-c84c84c95871 -->
<!-- normative-code: envelope -->
```json
{
  "version": "actql-program-semantics/0.1",
  "actql_version": "actql/0.1",
  "expression_contract_cid": "sha256:...",
  "parameters": {},
  "parameter_references": [],
  "bindings": {},
  "binding_references": [],
  "program_template": {}
}
```

For the staged grammar, `program_template` is exactly
`{stages: [{id, stage_semantics_cid, after, imports}, ...], exports}`.
Descriptors retain stage order; after is `initial` for the first descriptor and
the completed/accepted normalized law thereafter. Imports is a map from local
input name to its explicit Result/receipt reference; exports is the root results
map. No typed runtime artifacts or full source body are embedded here.

Each stage_semantics_cid hashes the closed envelope
`{version: "actql-stage-semantics/0.1", expression_contract_cid, parameters,
parameter_references, bindings, binding_references, local_body}`. Local_body contains decoded inputs, steps,
results and normalized effects (empty map when omitted), plus from only when
authored; imported inputs remain explicit source references, not captured values.
Parameters contains only declarations used by that stage, and parameter_references
uses the common canonical reference enumeration relative to local_body.
Each reference is exactly `{name, path, type}`, with the annotation-free
declaration as type and an RFC 6901 JSON Pointer as path. Sort by path then name
in canonical UTF-16 order, rejecting duplicate locations. Local paths start at
local_body; root paths start at the decoded source document, not the descriptor
array. Structural reference discovery never descends into opaque literal data.
Bindings and binding_references apply the same used-only projection to opaque
binding declarations, never their concrete runtime values. Empty maps/lists
remain explicit. The registered envelope schemas admit source-body containers;
the pinned structural grammar and semantic admission MUST validate their contents.
References remain unbound. Stage id, after and every allowed annotation are
excluded from local_body. The Stage Definition binds its stable stage ID and
this semantics CID; Unit Definition adds the namespace and incoming contracts
specified in [Local approval dependencies](#local-approval). Neither hashes the
parent Program. Root parameters/references cover the entire Program and use
source stage-relative pointers; they do not enter unrelated Unit Definitions.
The Program template MUST use the stage descriptors defined above, not the
complete source JSON as its template. Parameter declarations in both
envelopes exclude annotations. The authority-bearing definition envelope is:

```json
{
  "version": "actql-program-definition/0.1",
  "id": "crm.update_risk",
  "program_semantics_cid": "sha256:..."
}
```

<!-- requirement-block: canonical-identities.the-run-receipt-must-bind-all-applicable-identities-concrete-input -->
Every self-CID is computed over the same envelope without its own CID field.
Normalization journal and schema/capability/mapping evidence
are not Program members. Evidence-dependent completion (for example expanding
`drop` using a complete checked schema) appears in the journal and AoA plan,
therefore changes Check Environment/Compiled Plan identity without changing
Program identity. The separate AoA logical CID identifies only the main
computation plan; each generated effect plan has its own AoA logical CID.
The Run Receipt MUST bind all applicable identities, concrete input logical
identities and evidence, the Result Manifest CID, and every published Result
Artifact identity and completeness claim. It does not select a Result format or
bind delivered bytes. Result byte hashes belong to the delivery receipt defined
in [Result delivery](protocols/artifacts.md#result-delivery).

ActQL semantic identities use that pinned AoA Kernel canonical JSON contract: Unicode
strings and object keys are normalized at the boundaries specified in [Source representation](#source-representation); object
keys are ordered by canonical code units, finite numbers use the AoA normalized
number spelling, and negative zero is invalid. The ActQL CID is SHA-256 over the
UTF-8 canonical serialization of its semantic envelope. Formatting, source key
order, and comments do not affect this identity. A source-text
hash MAY be retained separately as provenance.

<a id="structural-grammar"></a>

## Structural grammar (normative)

The following JSON-model grammar is normative. `?` marks an optional member,
`*` marks a string-keyed map, and `+` marks a non-empty string-keyed map.
`|` separates alternatives; `&` merges members into one closed object.
Object-form Input, Parameter, and Binding declarations additionally admit
`meta?: Meta` as defined in [Authoring Context](#authoring-context). Their execution fields are defined in [Inputs and external contracts](#inputs);
expressions in [Expressions and predicates](#expressions); operation bodies in [Operations](#operations); and Effect bodies in [Effect declarations](#effects).
Expression and Predicate positions accept either a structured tree or a
string decoded under [Expression text](#expression-text). This alternative does not apply to other string
fields or to the restricted EffectValue grammar below.

Named productions resolve as follows: name classes and `InputOrStepName` in
[Pipeline names and references](#pipeline-references)–[Field names and nested paths](#field-paths); `JsonValue`, `NonEmptyString`, and `PositiveSafeInteger` in
[Source representation](#source-representation) and [Author guards, resolved limits, and Plan facts](#resolved-limits); Input, ParamDeclaration, and BindingDeclaration in [Local typed inputs](#local-inputs)–[Parameters and binding](#parameters);
OperationName and OperationBody in [Operations](#operations); ResultDefinition in [Named Results and Effect declarations](#results-and-delivery);
MappingRef, CommandContractRef, ResultField, TargetPrimaryKey, ScalarId, and
Field in [Effect declarations](#effects). Parameter substitution applies only at the value positions
admitted by [Parameters and binding](#parameters), never at a name or structural production.

`InputOrStepName` denotes any authored dataflow binding, including explicit
multi-output port names, with the position-dependent scope above. `values`
cells use the closed CellValue alternatives defined in [values](#values), not
Expression. Search output registration is simultaneous and rejects collisions
with either output, any input or preceding binding, and self/forward references.

<!-- requirement-block: structural-grammar.grammar -->
<!-- normative-code: grammar -->
```text
ActQLDocument := {
  version: "actql/0.1",
  id: NonEmptyString,
  meta?: Meta,
  params?: { ParamName: ParamDeclaration }+,
  bindings?: { BindingName: BindingDeclaration }+,
  stages: [Stage, ...],
  results: { ResultName: {from: {stage: StageId, result: ResultName}} }+
}

Stage := {
  id: StageId, meta?: Meta, after?: "completed" | "accepted",
  inputs: {InputName: StageInput}*, from?: InputName,
  steps: [Step, ...] | [], results: {ResultName: ResultDefinition}+,
  effects?: {EffectName: EffectDeclaration}*
}
StageId := NonEmptyString unique within this Program
StageResultRef := {stage: StageId, result: ResultName}
StageInput := Input | {result: StageResultRef, meta?: Meta}
  | {receipt: {stage: StageId, effect: EffectName}, meta?: Meta}
StageConstraints := prior-stage imports only; first stage rejects after;
  noninitial omitted after normalizes to completed; no implicit cross-stage current;
  Stage.from references only materialized inputs, never a search template.
InputDuplicatePolicy := "reject" | {first_by_order: {order_by: [OrderKey, ...]}}
MaterializedInputExtension := {duplicates?: InputDuplicatePolicy}
InputConstraints := Input forms defined in Local typed inputs and SourceViews;
  only materialized relation inputs admit MaterializedInputExtension;
  keyed/search acquisition templates and authoritative uniqueness claims are not weakened.
ParameterConstraints := recursive closed scalar/object/array value contract;
  nullable defaults false at every recursive Parameter type position;
  number integer/minimum/maximum, string format: duration, and array length/max_items
  apply at their respective type positions recursively;
  default and annotation meta are named-declaration-only;
  default is a typed literal applied only for missing values.
DeriveBody := DeriveMap | OrderedDeriveSlots
DeriveMap := {OutputFieldName: Expression}*
OrderedDeriveSlots := [DeriveSlot, ...]
DeriveSlot := {OutputFieldName: Expression} # exactly one member
DeriveConstraints := array is nonempty; NFC-unique slot outputs;
  map is input-snapshot/add-only; array is prior-slot/input-preserving shadow;
  shape and array order survive normalization; only RHS is Expression.

Meta := non-empty JSON object subject to Authoring Context (#authoring-context)
EventsBody := true
VectorsBody := true
NormalizeGraphBody := true
ReachBody := {start: WireValue, direction: in | out | both,
  max_depth: positive finite integer-valued number}
MatchNodesBody := {ids: [WireValue, ...], fields: [Field, ...]}
  | {where: Expression, fields: [Field, ...]}
MatchEdgesBody := {types?: [NonemptyString, ...] | [], where?: Expression,
  fields: [Field, ...]}
MatchConstraints := fields are nonempty with no repeated reference;
  ids are nonempty typed identities; repeated IDs/types do not repeat result rows.
GraphNodeSelector := {ids: [WireValue, ...]}
  | {from: InputOrStepName, id: Field} | {where: Expression}
SubgraphBody := {nodes: GraphNodeSelector, edges?: Expression}
GraphSelectorConstraints := exactly one closed selector form; selected identities
  are admitted, deduplicated and required to exist; empty Relation/predicate is valid.
TraverseBody := {start: GraphNodeSelector, emit: nodes | paths,
  direction: in | out | both, min_hops: nonnegative integer-valued number,
  max_hops: positive integer-valued number, edge_types?: [NonemptyString, ...] | [],
  max_output_rows?: PositiveIntegerValue}
  | {start: GraphNodeSelector, emit: nodes | paths, hops: [TraversalHop, ...],
     max_output_rows?: PositiveIntegerValue}
TraversalHop := {direction: in | out | both, edge_types?: [NonemptyString, ...] | [],
  edge_where?: Expression, node_where?: Expression}
ShortestPathBody := {source: PathEndpoint, target: PathEndpoint,
  selection?: each_pair | nearest_per_source | nearest_pair,
  direction: in | out | both, max_hops: positive integer-valued number,
  weight?: Field, edge_types?: [NonemptyString, ...] | [],
  max_output_rows?: PositiveIntegerValue}
PathEndpoint := single typed identity | GraphNodeSelector
ShortestPathConstraints := selection is required with any selector and forbidden
  with two single identities; weight names a known non-null number edge field.
NearestBody := {queries: InputOrStepName, metric: cosine | dot | l2,
  k: positive safe-integer literal, candidate_id?: Field, candidate_vector?: Field,
  query_id?: Field, query_vector?: Field}
PoolVectorsBody := {vector?: Field, by: [Field, ...], method: mean | sum | max,
  output_id?: OutputFieldName}
PoolVectorsConstraints := by is nonempty and duplicate-free; output_id requires
  exactly one grouping field; Relation input requires vector and a scalar candidate
  key, while Vectors input retains its intrinsic member identity.
MergeRankingsBody := {with: InputOrStepName, by: [Field, ...] | [],
  candidate: Field, score: Field, score_policy: max | {weighted_sum: {left: number, right: number}},
  score_contract: ScoreContract, k: positive safe-integer literal, tie_break?: [Field, ...] | []}
  | {with: InputOrStepName | [InputOrStepName, ...], by: [Field, ...] | [],
     candidate: Field, rank: Field, k: positive safe-integer literal,
     score_policy: {rrf: {rank_constant: positive safe-integer literal,
       weights: [nonnegative finite number, ...], rank_window: positive safe-integer literal}}}
ScoreContract := {domain: NonemptyString, range: [finite minimum, finite maximum],
  normalization: NonemptyString, higher_is_better?: true}
MergeRankingsConstraints := minimum <= maximum; weighted_sum weights sum to one;
  RRF weights include the current input and have positive total weight.
TextRankBody := {queries: InputOrStepName, query_id: Field, query_text: Field,
  candidate_id: Field, candidate_text: Field, tokenizer: unicode_words | char_bigram,
  scoring: {bm25: {k1: positive finite number, b: finite number in [0, 1]}},
  k: positive safe-integer literal}
MeanGraphsBody := {with: [InputOrStepName, ...], weights: [nonnegative number, ...],
  support: {nodes: number in (0, 1], edges: number in (0, 1]},
  properties: {nodes: {Field: MeanPropertyStrategy}*, edges: {Field: MeanPropertyStrategy}*}}
MeanPropertyStrategy := exact_equal | {mean: {missing: exclude | zero, nulls: exclude | zero | fail}}
MeanGraphsConstraints := nonempty graph list; weights match list length with positive
  exact total; complete property coverage; generator requires as and rejects step from.
GraphBody := {nodes: GraphNodes, edges: GraphEdges}
  | {source: Field, target: Field, label?: Field}
GraphNodes := {from: InputOrStepName, id: Field, fields?: [Field, ...] | []}
GraphEdges := {from: InputOrStepName, source: Field, target: Field,
  label?: Field, fields?: [Field, ...] | []}
GraphConstraints := directed only; explicit branches require step as and reject
  step from; fields lists have no repeated reference; label completion is concise-only.
DegreeBody := {direction: in | out | both}
ComponentsBody := {kind: weak | strong, max_output_rows?: PositiveIntegerValue}
GraphBoundsBody := {max_nodes?: NonnegativeIntegerValue,
  max_edges?: NonnegativeIntegerValue, max_degree?: NonnegativeIntegerValue}
GraphBoundsConstraints := at least one bound; diagnostic thresholds, not resource ceilings.
GraftGraphBody := {with: InputOrStepName}
StructuralGraphBody := {with: InputOrStepName, merge?: GraphMerge}
UnionGraphBody := {with: InputOrStepName | [InputOrStepName, ...], merge?: GraphMerge}
GraphMerge := {node_properties?: {AuthoredFieldName: GraphFieldStrategy}*,
  edge_properties?: {AuthoredFieldName: GraphFieldStrategy}*}
GraphFieldStrategy := exact_equal | set_union | set_difference | number_sum
  | number_mean | number_min | number_max
StructuralGraphConstraints := union_graphs uses UnionGraphBody with a nonempty list;
  subtract_graphs uses StructuralGraphBody; union folds left in authored reference
  order, retaining repeated references and treating scalar with as a singleton;
  empty maps are retained; strategies refer to existing properties of compatible type.
ParamRef := { $param: ParamName }
PositiveIntegerValue := PositiveSafeInteger | ParamRef
FractionValue := finite number in [0, 1] | ParamRef
GroupBody := {by: [Field, ...] | [], aggregates: {OutputFieldName: AggregateCall}*}
ValuesBody := {schema: {OutputFieldName: ConstructibleValueContract}+,
  rows: [{OutputFieldName: CellValue}*, ...] | []}
ConstructibleValueContract := AuthorValueContract excluding json/resource_ref/artifact_ref
  at every recursive type position
ValuesConstraints := each row has exactly the declared field set;
  cells use CellValue, not expressions; schema is nonempty even for zero rows.
SetBody := {with: InputOrStepName, duplicates: distinct | all}
SetConstraints := body of except/intersect; compatible aligned input contracts required.
CrossJoinBody := {with: InputOrStepName, right_rows?: one,
  max_output_rows?: PositiveIntegerValue,
  select?: {OutputFieldName: QualifiedJoinField}+}
QualifiedJoinField := left.Field | right.Field
IntervalJoinBody := {with: InputOrStepName, kind: inner | left | semi | anti,
  mode: point_in_interval | overlap, on: [{left: Field, right: Field}, ...] | [],
  left: {time: Field} | {start: Field, end: Field},
  right: {start: Field, end: Field},
  select?: {OutputFieldName: QualifiedJoinField}+,
  max_output_rows?: PositiveIntegerValue}
IntervalJoinConstraints := left is exactly {time} in point_in_interval mode,
  exactly {start,end} in overlap mode; all temporal fields have the same non-null
  timestamp or safe-integer UTC-millisecond domain; on pair occurrences are retained.
AsofJoinBody := {with: InputOrStepName, kind: left | inner,
  by: [{left: Field, right: Field}, ...] | [], left_id?: Field,
  left_time: Field, right_time: Field, direction: backward | forward | nearest,
  tolerance: MillisecondValue, right_tie_break?: [Field, ...] | [],
  select: {OutputFieldName: QualifiedJoinField}+}
AsofJoinConstraints := Relation left_id omission requires a complete retained
  candidate key; Events retain their intrinsic identity; comparison time fields
  are non-null UTC timestamps or safe-integer milliseconds; key occurrences and
  ascending tie-break occurrences are retained; null equality keys do not match.
SequenceBody := {by: [Field, ...] | [], id: Field, time: Field,
  pattern: [{as: nonempty string, where: Predicate}, ...],
  within: MillisecondValue, overlap: allow | disallow,
  contiguity: adjacent | subsequence,
  max_matches_per_key?: PositiveIntegerValue, max_output_rows?: PositiveIntegerValue}
SequenceConstraints := at least two uniquely labeled pattern elements; generated
  output names are valid and collision-free; Events id names the intrinsic role;
  the explicit Events clock is numeric milliseconds, not a timestamp.
CalendarUnit := day | week | month | quarter | year
CalendarTimestamp := canonical UTC millisecond timestamp in years 0001..9999 | ParamRef
CalendarBucketBody := {time: Field, into: OutputFieldName, unit: CalendarUnit,
  timezone: nonempty string, week_start?: monday | sunday}
CalendarSeriesBody := {start: CalendarTimestamp, end: CalendarTimestamp,
  unit: CalendarUnit, timezone: nonempty string, week_start?: monday | sunday}
CalendarConstraints := week_start is required for week and forbidden otherwise;
  literal profile selectors only; the selected pinned TZDB determines zone membership.
MillisecondValue := PositiveSafeInteger | PositiveDurationToken | ParamRef
SignedMillisecondValue := integer number in [-9007199254740991, 9007199254740991]
  | PositiveDurationToken | ParamRef
PositiveDurationToken := ASCII digits followed by ms | s | m | h | d,
  ASCII case-insensitive; positive safe-integer milliseconds after multiplication
RowWindowBody := {kind: fixed | sliding, time: Field, size: MillisecondValue,
  step?: MillisecondValue, offset?: SignedMillisecondValue}
WindowEventsBody := {kind: fixed | sliding, size: MillisecondValue,
  step?: MillisecondValue, offset?: SignedMillisecondValue}
WindowConstraints := sliding requires step; offset defaults to numeric zero;
  fixed admits and retains an explicit step without using it in window calculations;
  omitted fixed step is not inserted; supplied step retains validation obligations;
  Parameter declarations are non-null number or duration string;
  bound numbers satisfy the corresponding signed/positive safe-integer domain.
WindowGroupBody := GroupBody
LagBody := {partition_by: [Field, ...] | [], order_by: [OrderKey, ...],
  field: Field, output: OutputFieldName, offset?: PositiveIntegerValue}
LagConstraints := order_by nonempty; offset defaults to one;
  partition-key occurrences retained; output is fresh and nullable.
WatermarkRowsBody := {time: Field, late_policy: drop | mark,
  watermark_ms: FiniteNumberValue} | {time: Field, late_policy: drop | mark,
  max_skew: MillisecondValue}
FiniteNumberValue := finite number | ParamRef
WatermarkRowsConstraints := exactly one threshold source; fixed threshold permits
  fractional and negative values, but not negative zero; number Parameter non-null.
TopKBody := {k: PositiveIntegerValue, by: [OrderKey, ...]}
TopKByBody := {partition_by: [Field, ...] | [], k: PositiveIntegerValue,
  by: [OrderKey, ...]}
TopKConstraints := by nonempty; keys repeated without deduplication;
  partition keys KeyComparable; authored order keys AuthorOrderable;
  total-order completion and selection bounds are separate required evidence;
  no expression-valued k or implicit global/partitioned operation rewrite.
PivotBody := {index: [Field, ...] | [], column: Field,
  values: [OutputFieldName, ...] | [], value: Field,
  aggregate: sum | avg | count | min | max | first, fill?: CellValue}
PivotConstraints := repeated index references retained; values NFC-unique;
  generated columns canonical string order; no generated/index name collisions;
  column string or nullable string; fill whole-value literal or Parameter;
  empty axes preserve the specified global-group and index-only semantics.
AggregateCall := {fn: AggregateFunction, field?: Field, expr?: Expression,
  filter?: Expression, distinct?: Boolean, order_by?: [OrderKey, ...],
  max_items?: PositiveIntegerValue, max_bytes?: PositiveIntegerValue,
  delimiter?: String, fraction?: FractionValue}
AggregateFunction := count | count_if | sum | avg | min | max | array_agg |
  string_agg | first | last | percentile_disc | percentile_cont |
  var_pop | var_samp | stddev_pop | stddev_samp
AnalyticBody := {partition_by: [Field, ...] | [], order_by: [OrderKey, ...],
  functions: {OutputFieldName: AnalyticCall}+, frame?: RowsFrame}
AnalyticCall := {fn: row_number | rank | dense_rank}
  | {fn: lag | lead, expr: Expression, offset?: NonnegativeIntegerValue}
  | {fn: first_value | last_value, expr: Expression} | AggregateCall
RowsFrame := {start: FrameBoundary, end: FrameBoundary}
FrameBoundary := unbounded_preceding | current_row | unbounded_following
  | {preceding: PositiveIntegerValue} | {following: PositiveIntegerValue}
NonnegativeIntegerValue := NonnegativeSafeInteger | ParamRef
AnalyticConstraints := fresh outputs, all expressions use input snapshot;
  aggregate-local order_by forbidden; frame required exactly when any frame call exists;
  rank/navigation/value calls reject filter/distinct; offset only lag/lead;
  start not unbounded_following, end not unbounded_preceding, start <= end;
  no RANGE/GROUPS/exclusion; peer order, position order and publication order separate.
AggregateConstraints := exactly one field/expr except optional row-count argument;
  distinct follows the closed group matrix; no other modifiers are admitted;
  array_agg/string_agg/first/last require nonempty order_by outside analytic;
  analytic supplies their order and rejects aggregate-local order_by;
  max_items only array_agg; max_bytes and required literal delimiter only string_agg;
  required fraction only percentile_disc/percentile_cont;
  numeric guards/fractions admit a literal or whole ParamRef, not Expression;
  bound parameters satisfy the same finite/range constraints before execution.
NonnegativeSafeInteger := integer number in [0, 9007199254740991]
WireValue := canonical JSON data-model value, opaque to expression/binding traversal
UnreservedCell := WireValue excluding singleton objects with key literal or $param
CellValue := UnreservedCell | { literal: WireValue } | ParamRef
CanonicalCellValue := { literal: WireValue } | ParamRef
CellConstraints := singleton $param requires ParamName; literal payload is opaque;
  no schema-dependent dispatch; wrap reserved-shape business data with literal.

Step := {
  from?: InputOrStepName,
  as?: StepName,
  meta?: Meta,
  OperationName: OperationBody
}

StepConstraints :=
  generator => from absent, as required;
  search_candidates => as absent, body.outputs required;
  otherwise => ordinary current-input and optional as rules.

SortBody := [OrderKey, ...] | []
JsonPickBody := {column: Field, path: [String, ...], output: OutputFieldName}
AppendBody := {with: InputOrStepName}
UnpivotBody := {
  columns: [Field, ...], # nonempty; repeated references retained
  keep?: [Field, ...] | [], # omitted means []; no repeated output fields
  name_column: OutputFieldName,
  value_column: OutputFieldName
}
UnnestBody := {
  column: Field,
  as: OutputFieldName,
  with_index?: true | OutputFieldName,
  outer?: Boolean
}
DistinctBody := true | [Field, ...] # nonempty, no repeated references
DedupeRowsBody := {
  by: [Field, ...] | [],
  order_by: [OrderKey, ...] # nonempty
}
DedupeRowsConstraints := repeated by references are retained;
  empty by denotes one global partition; keep first, fail on top tie;
  keep/on_tie are language invariants, not authored members.

Take := PositiveIntegerValue | {
  count: PositiveIntegerValue,
  offset?: NonnegativeSafeInteger | ParamRef
}

Nest := {
  with: InputOrStepName,
  on: [{left: Field, right: Field}, ...],
  into: AuthoredFieldName,
  fields: SelectProjection,
  order_by?: [OrderKey, ...],
  max_items?: PositiveIntegerValue
}
SelectProjection := non-empty select projection defined in select (#select)
RenameBody := {ExistingFieldName: AuthoredFieldName}*
DropBody := [Field, ...] | []
ProjectionConstraints := rename/drop require a complete input schema;
  empty rename/drop retain all input fields; select remains nonempty;
  unknown fields, duplicate output names, and removing all fields
  from a nonempty input fail check.

EffectDeclaration :=
    ({ meta?: Meta } & { create: CreateBody })
  | ({ meta?: Meta } & { update: UpdateBody })
  | ({ meta?: Meta } & { upsert: UpsertBody })
  | ({ meta?: Meta } & { delete: DeleteBody })
  | ({ meta?: Meta } & { command: CommandBody })
  | ({ meta?: Meta } & { store: StoreBody })

EffectKind := "create" | "update" | "upsert" | "delete" | "command" | "store"

DataAuthority := {
  target: ConnectorRef,
  mapping: MappingContractRef,
  max_items?: PositiveIntegerValue,
  on_item_failure?: "continue"
}

MappingContractRef := ASCIIString matching
  ^mapping:[A-Za-z0-9][A-Za-z0-9._/-]*\.v[0-9]+$

ResultDefinition := {
  from: InputOrStepName,
  fields: [ResultField, ...],
  order_by?: [OrderKey, ...],
  meta?: Meta
}
OrderKey :=
    { Field: SortDirection }
  | { field: Field, dir: SortDirection, nulls: "first" | "last" }
SortDirection := "asc" | "desc"
FromResult := { from: { result: ResultName } }

CreateBody   := DataAuthority & (FromResult | { payload: JsonObject })
UpdateBody   := DataAuthority & UpdateSelector & { set: { TargetField: EffectValue }+ }
UpsertBody   := DataAuthority & FromResult & { key: ResultField, set: { TargetField: EffectValue }+ }
DeleteBody   := DataAuthority & DeleteSelector
StoreBody    := DataAuthority & FromResult
CommandBody  := {
  from: { result: ResultName },
  target: { field: ResourceRefResultField },
  contract: CommandContractRef,
  input: { InputField: ({ literal: JsonValue } | { field: ResultField }) }*,
  max_items?: PositiveIntegerValue,
  on_item_failure?: "continue"
}

UpdateSelector | DeleteSelector :=
    (FromResult & { id: ResultField })
  | (FromResult & { match: {
        target_field: TargetPrimaryKey,
        result_field: ResultField
      } })
  | { ids: [ScalarId, ...] }
  | { external_id: { field: Field, value: ScalarId } }
  | { where: [EffectPredicate, ...] }

EffectValue := { literal: JsonValue } | { field: ResultField }
EffectPredicate := SelectorPredicate<SelectorOperand>   (see [Predicates](#predicates); target-field scope in [Effect declarations](#effects))
```

<!-- requirement-block: structural-grammar.every-literal-in-set-must-use-literal-an-object -->
The grammar alternatives are exclusive. `create` accepts exactly one of a
named result or payload; `update` and `delete` accept exactly one selector. A
`command` consumes named-result ResourceRefs and its Connector-owned typed
contract; it has neither a mapping nor an arbitrary URL/method/body escape.
[Predicates](#predicates) defines the shared predicate vocabulary; [Effect declarations](#effects) defines Effect
selector scope.
Every literal in `set` MUST use `{literal: ...}`; an object containing exactly
`field` is a result-row reference. Bare JSON values are invalid.
ActQL does not assign field or literal meaning from the surrounding context.

The map is an unordered Effect Set; see [Effect declarations](#effects).

<a id="complete-example"></a>

## Complete example (informative)

Additional complete Programs are in [SCENARIOS.md](../../spec/product-decisions/SCENARIOS.md).

This example is informative. The preceding normative definitions determine
its meaning. It ranks one candidate per customer/product, using that pair's
latest day of activity. The length-prefixed candidate ID uses Unicode scalar
counts, so `/` or `:` in a source ID cannot collapse different pairs.

```yaml
version: actql/0.1
id: renewal_risk.rank_evidence
stages:
  - id: main
    inputs:
      activities:
        carrier: relation
        schema:
          event_id:
            type: string
            nullable: false
          customer_id:
            type: string
            nullable: false
          product_id:
            type: string
            nullable: false
          occurred_at:
            type: timestamp
            nullable: false
        primary_key:
          - event_id
      customers:
        carrier: relation
        schema:
          customer_id:
            type: string
            nullable: false
          name:
            type: string
            nullable: false
          segment:
            type: string
            nullable: false
        primary_key:
          - customer_id
      product_vectors:
        carrier: relation
        schema:
          product_id:
            type: string
            nullable: false
          embedding:
            type: vector
            nullable: false
            dimensions: 3
        primary_key:
          - product_id
      query_vectors:
        carrier: relation
        schema:
          request_id:
            type: string
            nullable: false
          embedding:
            type: vector
            nullable: false
            dimensions: 3
        primary_key:
          - request_id
    from: activities
    steps:
      - row_window:
          kind: fixed
          time: occurred_at
          size: 1d
      - group:
          by:
            - customer_id
            - product_id
            - window_start
          aggregates:
            activity_count:
              fn: count
        as: activity_counts
      - from: activity_counts
        join:
          with: customers
          kind: inner
          on:
            - left: customer_id
              right: customer_id
          select:
            customer_id: left.customer_id
            product_id: left.product_id
            activity_count: left.activity_count
            window_start: left.window_start
            customer_name: right.name
        as: candidates
      - from: candidates
        join:
          with: product_vectors
          kind: inner
          on:
            - left: product_id
              right: product_id
          select:
            customer_id: left.customer_id
            product_id: left.product_id
            customer_name: left.customer_name
            window_start: left.window_start
            embedding: right.embedding
      - derive:
          candidate_key: to_string(len(customer_id)) || ':' || customer_id || to_string(len(product_id)) || ':' || product_id
      - dedupe_rows:
          by:
            - customer_id
            - product_id
          order_by:
            - window_start: desc
      - assert_rows:
          unique_by:
            - candidate_key
        as: candidate_vectors
      - from: candidate_vectors
        nearest:
          queries: query_vectors
          candidate_id: candidate_key
          candidate_vector: embedding
          query_id: request_id
          query_vector: embedding
          metric: cosine
          k: 20
        as: ranked_candidates
      - from: ranked_candidates
        join:
          with: candidate_vectors
          kind: inner
          on:
            - left: candidate_id
              right: candidate_key
          null_key: fail
          select:
            request_id: left.query_id
            customer_id: right.customer_id
            product_id: right.product_id
            score: left.score
        as: ranked_evidence
    results:
      main:
        from: ranked_evidence
        fields:
          - request_id
          - customer_id
          - product_id
          - score
        order_by:
          - request_id: asc
          - score: desc
          - customer_id: asc
          - product_id: asc
results:
  main:
    from:
      stage: main
      result: main
```

The author writes semantic operations and explicit semantic choices. The
compiler supplies linear wiring, carrier bridges, generated step IDs, and
identity restoration. It lowers algebra forms to validated AoA Fragments and,
when a boundary form is present, binds those fragments and typed barriers into
the closed ActQL Executable Plan.

<a id="machine-contracts"></a>

## Machine contracts

These exact schema/law references are owned here. Their identities do not include this document or another owner's aggregate contract.

The expression 0.1 contract supplies common expression and machine node schemas.
Unicode/regex/time data and bound laws are imported through its explicit
base-profile CID. Value laws and demanded evaluation envelopes are resolved
through the pinned expression contract.

<!-- requirement-block: machine-contracts.exact-artifacts -->
<!-- normative-code: law -->
```text
../../spec/contracts/actql-aoa.json# sha256:806d9374ccaf7b21e7ba6ab6da4a28858cee6802cd23faa98b75e3da81991685
../../spec/contracts/actql-bound-transfer-laws.json# sha256:014682262d00c8435f300731e823e5b267ec66b78f980c765c4fd3772c68c911
../../spec/contracts/actql-protocol-schemas.json#/schemas/resource_ref sha256:f88141c15be5ac040af593008fdca7c85214fcb4ba60ea7110160b8fe8ee25ac
../../spec/contracts/actql-protocol-schemas.json#/schemas/artifact_ref sha256:2143a7c6bd2e0b110822670a3cb146cddaa23bcade9de7c1ab8ed4e1ebf88a55
../../spec/contracts/actql-protocol-schemas.json#/schemas/author_value_contract sha256:ad31b593c607142e6fce65b15ca12531c46d61f3bcf8cc55f34eef1b4dca6b6e
../../spec/contracts/actql-protocol-schemas.json#/schemas/canonical_value_contract sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551
../../spec/contracts/actql-production-profile-schemas.json#/schemas/text_time_expression sha256:a9fd34634569c0da417ca5a8770ab064ad8351bbd253c8fea1dae60c756c61c1
../../spec/contracts/actql-production-profile-schemas.json#/schemas/regex_replacement_ast sha256:92c3fc4fc790cdf8f985b634dfe513f85b6cd5c904bb673de7330d18f577aeed
../../spec/contracts/actql-regex-ast.json# sha256:9c4e0107ad1e6a1eb374e8365c07615c74773416b0b43f9a1e02db5e551efc78
../../spec/contracts/actql-expressions.json# sha256:399d4593f8212a2239a0a3e3ca552653ad711010a180207f967cf546012fc1cb
../../spec/contracts/actql-expressions.json#/schemas/expression sha256:8196cef99c66248917d44d322cb21f69f9873cac768bc5bbda2e3757e8e9d66f
../../spec/contracts/actql-expressions.json#/schemas/expression_node sha256:eea37ee96bf6be954e46db196f7ec8101506ed4a28ecc647e8f929a512194b94
../../spec/contracts/actql-expressions.json#/schemas/evaluation_envelope sha256:629342d58af8fa879da391532a838788338ddc42b5f17db814d0bdf7236c195b
../../spec/contracts/actql-expressions.json#/laws sha256:aed67e22149a672dcff44b7f4f55823ac1b20c300c6962952d9d693c85032ea9
../../spec/contracts/actql-expressions.json#/schemas/fragment sha256:4d42600c1b3d42d660f2eb14a84342988c17646110f8995f80bf4dc4344ce3d4
../../spec/contracts/actql-expressions.json#/schemas/predicate_consumer sha256:36320fcc16612a4bd0a64274fcf07526845ae91ad802afce601f4e391f5ba1de
```

<!-- stage-contract-pins:start -->
```text
../../spec/contracts/actql-stage-contracts.json#/source sha256:b98f2467f609677c7b5bfd256892763e4772dd45fe51a494402e56f3a847cdd8
../../spec/contracts/actql-stage-contracts.json#/schemas/derive_binding sha256:d74bb697d91a2daf2c51e0d6c492f4bb35fdea5e542d606318683b1c9c5f06f9
../../spec/contracts/actql-stage-contracts.json#/schemas/local_dependencies sha256:22a2636742d270464988e350adc168af898987e83f620cba893efb091d9f49e8
../../spec/contracts/actql-stage-contracts.json#/laws/lifecycle sha256:da02951b68ca4255a25ac5b3f60288dbde2a8f7b252f518d73247c9feca09c54
../../spec/contracts/actql-stage-contracts.json#/laws/identity sha256:090d1c81f41bc0cbda07b62ade75d2fbd450d0a333fcf6a23d1c2483b43e213f
../../spec/contracts/actql-stage-contracts.json#/schemas/stage_semantics sha256:c9fdde04da54089003a628cae27f01c118f59e359dff7cacdd09f6eb86c9f2e3
../../spec/contracts/actql-stage-contracts.json#/schemas/program_semantics sha256:89152a5f20ffdf17f321f40cf21d57c691ba5c30772d0aac2545888786a98ba0
```
<!-- stage-contract-pins:end -->
