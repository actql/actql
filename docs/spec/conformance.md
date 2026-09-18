---
spec_id: actql.conformance
status: adopted
version: actql/0.1
normative_dependencies: [actql.language, actql.execution, actql.protocol.contracts, actql.protocol.artifacts, actql.protocol.run, actql.protocol.discovery, actql.protocol.collection, actql.protocol.http, actql.protocol.run-graph]
---

# ActQL conformance

[Specification index](README.md)

<!-- normative-import: actql.language actql/0.1 -->
<!-- normative-import: actql.execution actql/0.1 -->
<!-- normative-import: actql.protocol.contracts actql/0.1 -->
<!-- normative-import: actql.protocol.artifacts actql/0.1 -->
<!-- normative-import: actql.protocol.run actql/0.1 -->
<!-- normative-import: actql.protocol.discovery actql/0.1 -->
<!-- normative-import: actql.protocol.collection actql/0.1 -->
<!-- normative-import: actql.protocol.http actql/0.1 -->
<!-- normative-import: actql.protocol.run-graph actql/0.1 -->

This document owns claims, profile-dependencies, corpora, evidence, release-combinations. It does not define other owners' wire protocols or a particular Host implementation. Cross-owner links outside the declared dependencies are informative navigation to protocol bindings or conformance evidence; they do not import those documents' requirements. Narrow machine contracts remain authoritative for their explicitly referenced values and envelopes.

<!-- page-contents:start -->
## On this page

- [Conformance profiles](#conformance-profiles)
- [Conformance and versioning](#conformance-and-versioning)
- [Product boundary acceptance](#product-decision-acceptance)
- [Conformance claims](#conformance-claims)
- [Module closure workloads](#module-workloads)
- [Conformance tests and reports](#conformance-tests)
- [Additional Operations conformance](#operations-conformance)
- [Versioning](#versioning)
- [Artifact and companion contract index (normative)](#contract-index)
<!-- page-contents:end -->

<a id="conformance-profiles"></a>

### Conformance profiles

ActQL 0.1 defines a required language Core, a required RelA module, three
optional algebra modules, and the optional profiles listed below.
Each claim covers the complete profile, not a selection of its operations:

```text
actql-core/0.1   sources, contracts, diagnostics, Results, delivery, receipts, checked effects
actql-rela/0.1   relation algebra
actql-sga/0.1    graph algebra
actql-veca/0.1   vector algebra
actql-tea/0.1    event algebra
actql-infer/0.1  bounded structured model acquisition
actql-text-time/0.1 composable pure text, UTC time, and regular expressions
actql-lookup/0.1 bounded acquisition for a keyed external join
actql-artifact/0.1 bounded Artifact serialization
actql-text-rank/0.1 pure lexical ranking over a finite corpus
actql-search/0.1 bounded external ranked candidate acquisition
actql-calendar/0.1 explicit-zone Gregorian buckets and series
```

The Core/RelA combination includes the expression 0.1 contract pinned by
Language. Parsing alone does not establish typed lowering, demanded bounds,
or execution conformance to that contract.

Expression conformance includes boolean-null preservation in values and condition
consumption, all-branch static checks versus demanded conversion failures,
aggregate-filter-before-argument evaluation, cast/structured identity, typed-null
and empty-array inference, nullable parents, invalid versus out-of-range indices,
join qualification, decimal negation, string boundary cases, and unchanged
Effect selector restrictions. Optimized and reference execution are compared for
required failure and logical limits as well as values, under the exact pinned
value laws.

<!-- requirement-block: conformance-profiles.an-implementation-must-accept-every-valid-program-and-reject-every conformance-profiles.a-generally-usable-actql-0-1-implementation-must-claim-core-and conformance-profiles.an-implementation-must-publish-complete-module-claims-separately-from-partial conformance-profiles.an-implementation-must-publish-complete-module-claims-separately-from-partial.second -->
An implementation MUST accept every valid program and reject every invalid
program within every module it claims. A generally usable ActQL 0.1
implementation MUST claim Core and RelA together. SGA, VecA, TEA, infer,
text-time, lookup, artifact, text-rank, search and calendar are optional
claims, but each is indivisible. Text-rank additionally requires the pinned
Unicode normalization/case-fold laws, not a claim to every text-time function.
Calendar requires TEA and its pinned timezone/transition contract. Search
requires Core/RelA acquisition contracts, not VecA: vector requests additionally
require their declared vector value contracts, while pure nearest remains VecA.
Implementing one or two named operators is partial support, not module
conformance. An implementation MUST
publish complete module claims separately from partial operation support and
MUST reject an unimplemented operation during check rather than changing its
meaning.

<!-- requirement-block: conformance-profiles.within-their-supported-profile-sets-conforming-checkers-must-produce-the -->
Within their supported profile sets, conforming checkers MUST produce the same
canonical AoA Fragments, Executable Plan, and semantic identities for the same
source, bound values, and Check Environment under the contracts in [Canonical identities](language.md#canonical-identities) and [AoA fragments and algebra lowering](language.md#algebra-lowering).
This equality concerns the canonical checked envelope, not identical physical
execution strategies ([Typed barriers and Plan Documents](language.md#plan-documents)).

<!-- requirement-block: conformance-profiles.an-unclaimed-profile-must-be-rejected-with-actql-e-profile-unsupported-before-computation conformance-profiles.known-profile-vocabulary-must-not-be-reported-as-unknown-or -->
An unclaimed checker profile MUST be rejected with `ACTQL_E_PROFILE_UNSUPPORTED`
before computation, provider access, byte publication, or Effect dispatch.
Rejection does not require complete type checking, lowering, or Plan identity
assignment for that profile. Known profile vocabulary MUST NOT be reported as
unknown or silently lowered to weaker semantics.

<!-- requirement-block: conformance-profiles.any-published-plan-must-satisfy-the-same-canonical-contracts-as product-decision-acceptance.product-079ca9c4bcb9 -->
A checker MAY publish a fully validated Plan with `unsupported`
when only execution is unsupported. Any published Plan MUST satisfy the same
canonical contracts as a supported Plan.

Profile workloads, conformance evidence, and versioning are specified in [Conformance and versioning](#conformance-and-versioning).

<a id="conformance-and-versioning"></a>

## Conformance and versioning



<a id="product-decision-acceptance"></a>

## Product boundary acceptance

The adopted stage, authorization, recovery, Catalog, infer, numeric observation,
input normalization, parameter and projection rules are adopted
semantics. A full claim MUST include positive/negative, crash, replay, scope,
canonical artifact and independent cross-target evidence for those rules.
Schema validation or unrelated passing tests do not establish
their execution conformance. Alpha/beta distribution policy is a separate gate:
it may disclose partial support and known gaps, but cannot claim full compliance
or silently execute unsupported syntax with different semantics.

The non-normative [acceptance mappings](../../spec/product-decisions/traceability.json)
connect design requirements to independent acceptance cases, Program fixtures
and Host assumptions. These definitions do not constitute execution evidence.
Compatible Connector-lock automatic renewal and
cross-Run model cache remain deferred, not implied by stale renewal or replay.
Existing pinned contracts remain available to retained Runs; secret rotation
does not alone invalidate static Catalog identity.

<a id="authoring-evaluation-gate"></a>

#### Authoring and execution verification

The adopted source syntax uses explicit stages, map/ordered-array derive, and
select. Authoring evaluation measures intent preservation, successful checking,
diagnostic repair, field leakage, shadowed-value confusion, coverage and cost.
Evaluation does not introduce alternative source spellings. Independent curators
seal task variants, contract pins, seeds and oracles before isolated sessions;
answers stay out of author context and failed attempts remain in the results.
Examples and acceptance cases are not execution evidence by themselves.

<!-- requirement-block: authoring-evaluation-gate.final-freeze-evaluation -->
Before freezing the source syntax for a Final release, authoring evaluation
MUST measure first-check validity, intent agreement and one-repair convergence
on isolated holdout tasks. The adopted syntax remains the implementation target;
an evaluation that has not run is reported as unexecuted, not as passing evidence.

Runtime evidence compares direct stages and extracted graph Programs
for local approval noninterference, membership, shared budget, normal/exceptional
cursor commit, fault/replay and recovery eligibility. Schema tests alone are not
these execution tests.

<a id="conformance-claims"></a>

### Conformance claims

An implementation is conforming only if it publishes one exact content-
addressed ConformanceClaim and:

1. accepts every valid program within its claimed profile set and rejects
   unclaimed profiles as specified in [Conformance profiles](#conformance-profiles);
2. rejects every program that violates a closed vocabulary or required
   semantic choice;
3. produces byte-identical canonical AoA IR for every algebraic fragment and
   byte-identical canonical Executable Plans and semantic identities under the
   same bound values, Check Environment, and semantic contracts ([Conformance profiles](#conformance-profiles));
4. records every authoring normalization and deterministic completion;
5. does not resolve a semantic ambiguity by guessing; and
6. preserves the determinism and ordering requirements in this specification.

<a id="module-workloads"></a>

### Module closure workloads

Operation count is not a completeness criterion. A module claim is valid only
when independent conformance programs can express and execute its closure
workload without Python post-processing, hidden carrier manipulation, or a
provider-specific semantic escape hatch:

<!-- requirement-block: module-workloads.module-required-closure-workload-core -->
| Module | Required closure workload |
| --- | --- |
| Core | typed source and Contracts -> checked Plan and checked Effect declarations -> named Result Artifacts and Result Manifest -> authorized canonical delivery and receipts; Effect application is a separate capability |
| RelA | typed semi-structured rows -> unnest/normalize/derive -> checked join or full reconciliation -> aggregate/dedupe/global or partitioned rank -> relation/effect |
| SGA | typed rows -> property-bearing graph -> node/edge match -> typed bounded traversal/path or component analysis -> stable relation projection |
| VecA | RelA-filtered corpus/query -> vector conversion/pooling -> exact score/search -> threshold/merge/dedupe/per-query rank -> metadata relation |
| TEA | typed rows -> event stream -> fixed/sliding/session assignment -> late policy/dedupe -> as-of or bounded sequence correlation -> relation aggregate/output |
| Infer | typed relation -> bounded structured model acquisition -> captured evidence -> explicit relation join/effect |
| Text/time | typed relation -> bounded Unicode/UTC/closed-regex transforms -> relation/effect |
| Lookup | bounded left Relation -> keyed external join -> deduplicated/batched/paged SourceView acquisition -> checked joined Relation |
| Artifact | totally ordered relation -> bounded canonical CSV/JSONL capture -> ArtifactRef relation -> typed command |

The normative operation and law inventory for these flows is published by
`ACTQL_MODULES`.

<a id="conformance-tests"></a>

### Conformance tests and reports

The [nest canonical corpus](../../portability/corpus/actql-nest-canonical-v0.1.json)
is generated by the [independent Python lowering](../../portability/python/nest_graph.py),
not by the production compiler. It covers the declared fixture subset, including
reference aliases, existing-order reuse, item/byte binding proofs and typed empty
arrays. Its exact-graph checks supplement, rather than replace, the separate
value/order oracle and runtime failure tests. The corpus includes explicit
staged inputs, stage and Program identity envelopes, and canonical AoA identities.

<!-- requirement-block: conformance-tests.a-conforming-implementation-must-publish-and-pass -->
A conforming implementation MUST publish and pass:

1. parser rejection cases for YAML features outside the JSON data model;
2. valid and invalid examples for every operation;
3. canonical-vocabulary negative tests proving undocumented spellings cannot execute;
4. deterministic-completion idempotence tests;
5. ambiguity-preservation tests with stable candidate order;
6. AoA Carrier-sort, arity, field, identity, bridge, and ordering negative tests;
7. independent oracle cross-checks for Core/effect semantics, the required
   RelA closure workload, and every optional algebra module claimed;
8. empty-Result schema and manifest tests;
9. Run Receipt, Result Manifest, Result Artifact, delivery-receipt, and delivered-byte tamper tests;
10. five-run reproducibility tests over fixed inputs;
11. canonical diagnostic ordering, replacement/candidate exclusivity, stable
    candidate ordering, and diagnostic-CID reproducibility tests;
12. row-effect tests covering AoA `EFFECT.plan` lowering, per-row values,
    complete resolved mapping contract identity, exact permission derivation,
    duplicate identity, missing target, target type mismatch,
    differently named output/target upsert keys, explicit write fields,
    `max_items`, normative row idempotency, host-approval monotonicity, single-
    effect/failure-policy semantics, and preview-CID reproducibility;
13. typed-input, `unnest`, complete closed expression, representative-dedupe,
    composite/full join cardinality/null/output-bound, global/partitioned rank,
    order-sensitive operation, and append schema/nullability tests;
14. for each claimed algebra, an end-to-end closure-workload test from [Module closure workloads](#module-workloads),
    including negative vectors for every semantic choice and exclusion;
15. SGA path-order/identity oracle tests, VecA quantization/pool/ranking-merge
    oracle tests, and TEA boundary/session/dedupe/as-of/sequence oracle tests
    whenever those modules are claimed;
16. pinned diagnostic-catalog and AoA-contract CID tests;
17. for each claimed acquisition or Artifact profile, bound-overflow,
    duplicate/correlation, atomic-publication, captured-replay, data-egress,
    and no-implicit-join-back negative vectors;
18. for a claimed Run Graph or HTTP companion profile, independent portable
    contract/CID validation plus adversarial retry, SSRF, receipt, lock, and
    failure-transition vectors;
19. independent validation of every JSON Schema keyword used by the public
    Plan Document, Plan Result, and Run State protocols, including their
    conditional unions, nested closed objects, canonical identities, and
    cross-artifact bindings;
20. independent acquisition and restoration of a fixed reference identity set,
    verifying consistent equality, join, distinct, grouping, uniqueness, and
    canonical identity ordering. Vectors cover reference-only and mixed candidate
    keys with unorderable payloads, reordered and empty inputs, primitive ranking
    with reference tie completion, admitted reference partition/correlation keys,
    and source-print/recheck preservation without authored reference orders.
    Negative vectors cover explicit reference orders and tie-breaks, ordered
    comparisons including BETWEEN/NOT BETWEEN, and min/max including pivot;
    text/tree predicates agree, deferred order-domain checks reject references
    before ordering, and opaque-field access remains rejected;
21. SourceView resolution and observation vectors: sole-view completion with
    journal evidence; zero-view rejection; multiple-view rejection with
    candidates; exact selector matching even with a pinned contract CID;
    rejection of unregistered extraction contracts and contracts requiring
    implicit model invocation before provider access; and Catalog, Plan, and
    acquisition-review presentation of classification and contract identities; and
22. expression-text vectors for every spelling, signature, precedence level,
    and exclusion in [Expression text](language.md#expression-text): independent decoding to the same structured trees;
    equal Program identities across text/tree forms; canonical printer
    round trips including structured fallback; Unicode diagnostic spans;
    unchanged literal/metadata/request strings; and rejection of computations
    in restricted Effect positions. Vectors include decimal/binary64
    separation, literal-NULL comparison rejection, and grammar/lock drift;
23. source-decoding vectors for scalar resolution, normalized-key collisions,
    Unicode and line endings, numeric limits, and source versus artifact admission;
24. type/evidence vectors for recursive compatibility, nullable parent paths,
    and canonical key selection independent of proof enumeration order; and
25. lifecycle vectors for preparation versus Run Checkpoints, typed dispatch
    outcomes, strength-specific review rows, and acyclic receipt dependencies;
26. `nest` vectors: empty inputs and typed empties versus all-null children;
    duplicate parent correlations and legal child multiplicity; reference-key
    completion and authored-order rejection; independent sibling arrays;
    guard/byte/depth/overflow failure before consumers; preserved upstream
    failures, completeness and policy; and independent lowering/value/CID checks;
27. Discovery vectors: fixed snapshot pagination, scope and cursor isolation,
    exact versus projected identity, closure/issuer admission, partial-list
    ambiguity, current disclosure authority, and no provider observation; and
28. read collection vectors: exact slot/Result evidence, required/all-source
    failure, closed permitted classes, retained attempt costs, coverage admission,
    canonical ordering, no fabricated artifacts, and replay without dispatch.

<a id="operations-conformance"></a>

### Additional Operations conformance

The expanded RelA claim includes values, set multiplicities, bounded cross
join, analytics, added aggregates, offset and outer unnest. SGA includes
subgraph, equality, typed Delta application, means and extended paths; VecA
includes row-local vector expressions and RRF; TEA includes carrier-preserving
session, finite series and interval joins. Separate lexical, external-search
and calendar claims cover their complete Language definitions.

<!-- requirement-block: operations-conformance.independent-vectors -->
Each claimed operation MUST have independent source/checked-type/canonical-node
and success/rejection/failure vectors, including empty inputs and resource
breaches. Golden values are derived from the normative law rather than copied
from one runtime. Comparison covers complete output contracts, semantic IDs,
ordered outputs, root/demand and limit bindings, policy and completeness,
not merely matching row payloads. Existing kernel tests, parser acceptance,
aggregate test counts and rehashed-fragment self-CIDs do not substitute
for these vectors.

Required cases are:

- RelA: typed empty values; literal data resembling expression tags; set NULL
  equality and ALL multiplicities; input permutations and row order; zero/
  singleton/general cross products and overflow; analytic peers versus identity
  tie-break; empty/truncated ROWS frames; own aggregate filters and different
  orders; conditional argument failures; offset past end; outer synthetic rows
  versus actual null elements; statistical insufficient samples and rounding.
- SGA: empty and edge-filtered induced graphs; exact equality versus identity
  relabeling; invalid graph rejection; diff/apply roundtrip; wrong base, missing
  targets and dangling edges; mean support boundaries, zero weights, absent
  entities versus null properties, unequal sampling and non-associative means;
  source/target selection modes, zero-cost ties and hop-constrained paths.
- VecA/search: composed vector functions, null demand and dimension overflow;
  RRF rank-window versus output-k, input duplicates, score-scale independence
  and canonical numerical folds; lexical tokenizer/normalization fixtures,
  empty corpora, df/document-length changes and correctly rounded ln;
  search zero-hit coverage, partial/exact orthogonality, replay without new
  requests, request egress rejection and failure without fabricated zero rows.
- TEA/calendar: preserved event identity after session labeling; explicit
  session partition use; finite empty grids without absence claims; touching
  intervals, invalid endpoints and multiplicity limits; DST gaps/folds, skipped
  dates, leap years, week/year boundaries and pinned TZDB changes.

No complete expanded-profile claim exists until its machine registry, schema,
law and runtime evidence agree. Partial implementation remains reportable
without changing the adopted source semantics or rewriting old attestations.

<!-- requirement-block: conformance-tests.conformance-reports-must-state-core-support-the-required-rela-claim conformance-tests.all-conforming-core-compilers-must-check-all-six-effect-declarations conformance-tests.reports-must-also-include-actql-diagnostic-semantic-profile-cid-and-actql-aoa-contract-cid -->
Conformance reports MUST state Core support, the required RelA claim or its
gaps, every claimed normative optional module, optional connectors, and Effect
application capabilities. Profile claims follow [Conformance profiles](#conformance-profiles); an AoA registry entry
alone is not evidence of support. All conforming Core compilers MUST check all
six Effect declarations; Host application remains a separately declared
capability. Reports MUST also include
`ACTQL_DIAGNOSTIC_SEMANTIC_PROFILE_CID` and `ACTQL_AOA_CONTRACT_CID`.
Reports claiming exact diagnostic catalog compatibility additionally include
`ACTQL_DIAGNOSTIC_CATALOG_CID`.

Agent-usability holdouts are not language conformance, but a frozen evaluation
SHOULD separately report first-check validity and one-repair convergence. It
SHOULD record the initial and aggregate diagnostic-code distributions together
with the diagnostic catalog CID, so a repair-rate change cannot be attributed
to an unidentified diagnostic surface.

<a id="versioning"></a>

### Versioning

<!-- requirement-block: versioning.the-grammar-diagnostic-portability-and-protocol-contract-bodies-must-agree versioning.a-release-s-conformance-manifest-must-bind-their-exact-recomputed-identities -->
The grammar, diagnostic, portability, and protocol contract bodies MUST agree
with the normative definitions. A release's conformance manifest MUST bind
their exact recomputed identities. Release evidence is immutable and attests
only the exact artifacts it identifies.

<!-- requirement-block: versioning.each-runtime-and-cli-artifact-protocol-is-separately-versioned-and -->
`actql/0.1` source, Program semantics, ordering, identity, and authority laws
are immutable once released as Final. Each runtime and CLI artifact protocol is
separately versioned and MUST reject unknown versions. The machine-readable
compatibility policy is `actql-version-policy/0.1`, exported as
`ACTQL_VERSION_POLICY_CID`; mutable release pointers live separately in
`release/actql-release-index.json`.

<!-- requirement-block: versioning.the-source-parser-must-reject-an-absent-or-unsupported-version versioning.unknown-document-input-operation-parameter-result-and-effect-fields-must -->
The source parser MUST reject an absent or unsupported `version` before
lowering; [Structural grammar (normative)](language.md#structural-grammar) defines the admitted source version. Unknown document, input, operation, parameter,
result, and effect fields MUST fail closed.
ActQL 0.1 has no extension namespace, deprecated syntax, source aliases, or
alternate compatibility mode. Only the current canonical syntax is accepted.

<!-- requirement-block: versioning.a-patch-must-not-accept-a-new-source-spelling-alias -->
An implementation patch MAY fix execution or rejection of source whose status
was already determined by the frozen specification, reject source that was
invalid under that specification, optimize without changing observable
semantics or identities, and improve non-normative prose. A patch MUST NOT accept a new source spelling,
alias, field, default, or completion; change AoA lowering or observable
semantics of a valid program; or change a frozen grammar, diagnostic, artifact,
module, law, or contract CID in place. A source-language change requires a new
ActQL language version and conformance corpus. An incompatible machine-artifact
or CLI change requires a new artifact protocol version and package major
revision, while preserving all earlier frozen evidence.

<!-- requirement-block: versioning.a-runtime-must-reject-unsupported-actql-aoa-ir-connector-spi versioning.the-installed-skill-must-bind-the-compiler-s-exact-grammar-manifest versioning.aoa-execution-must-bind-the-exact-frozen-aoa-contract-cid -->
A runtime MUST reject unsupported ActQL, AoA IR, Connector SPI, and artifact
versions. Authoring tooling MUST bind the compiler's exact Grammar Manifest
CID, not merely a semver range. AoA execution MUST bind the exact frozen AoA
contract CID.

<!-- requirement-block: versioning.a-migration-must-refuse-a-transformation-whose-target-authority-or versioning.it-must-produce-new-source-and-an-edit-journal-rather -->
Migration is an explicit source transformation, not a parser compatibility
mode. A migration MUST refuse a transformation whose target, authority, or
typed Command Contract requires an unresolved semantic choice. It MUST
produce new source and an edit journal rather than reinterpret a stored
Program in place. Tool-specific migration syntax is outside this specification.

Core, RelA, SGA, VecA, and TEA publish independent module contract CIDs and
maturity status. A distribution may claim only a subset, but a semantic change
inside any Final 0.1 module requires a new module and ActQL language version;
an implementation cannot relabel partial operation coverage as that module.

<a id="contract-index"></a>

## Artifact and companion contract index (normative)

The following documents supply machine-readable definitions by reference.
Their released identities are bound by the conformance manifest ([Versioning](#versioning)).
Exported constant names below identify those contracts; importing a particular
implementation package is not a conformance requirement.

<!-- requirement-block: contract-owner-index -->
| Contract family | Normative document and registry location |
| --- | --- |
| Connector, value, Catalog, and lock schemas | [Protocol schemas](../../spec/contracts/actql-protocol-schemas.json): `schemas`, identified by `schema_cids`. |
| Host Discovery | [Discovery contracts](../../spec/contracts/actql-discovery.json): owner-specific schemas, laws and CID; [Host Discovery protocol](protocols/discovery.md#discovery). |
| Read collection | [Collection contracts](../../spec/contracts/actql-read-collection.json): owner-specific schemas, laws and CID; [Read collection protocol](protocols/collection.md#collection). |
| Plan, Run, Checkpoint, Resolution, and receipt schemas | [Protocol schemas](../../spec/contracts/actql-protocol-schemas.json): `artifact_schemas`, identified by `artifact_schema_cids`. |
| Acquisition, Artifact, text-time, HTTP, and Run Graph schemas | [Production-profile schemas](../../spec/contracts/actql-production-profile-schemas.json): `schemas`, identified by `schema_cids`. |
| Source decoding | `actql-source-decoding/0.1`, [Source representation](language.md#source-representation). Complete decoding/admission evidence is required by [Conformance tests and reports](#conformance-tests). |
| Common expressions, signatures, canonical nodes and printing | [Expression 0.1 grammar](../../spec/grammar/actql-expression-0.1.ebnf), [expression contracts](../../spec/contracts/actql-expressions.json), and [Common expression contract](language.md#common-expression-contract); grammar bytes are pinned by the expression contract. |
| Stage product contracts | [Stage contract registry](../../spec/contracts/actql-stage-contracts.json): closed template, activation, receipt, logical request/ledger, risk/template/renewal, Catalog, input, parameter, model and numeric evidence shapes, with owner-local pins. |
| Lookup acquisition identities | [Lookup identity registry](../../spec/contracts/actql-lookup-identities.json): the five Lookup Evidence CID roles, pre-Invocation Relation, typed keys, batch partition and attempt receipt, with supporting order/scope/request/slot schemas. Specification tests do not attest lookup runtime conformance. |
| Closed regex grammar and AST | [Regex grammar](../../spec/grammar/actql-regex-0.1.ebnf) and [AST schema](../../spec/grammar/actql-regex-ast-0.1.schema.json). |
| Predicate consumer capacity | [Consumer capacity contract](../../spec/contracts/actql-consumer-capacity.json), owned by [Machine contracts](protocols/contracts.md#machine-contracts); consumer bodies and schemas bind its exact canonical CID, not merely its version name. |
| Managed retained execution | [Managed retained execution contract](../../spec/contracts/actql-managed-retained-execution.json), owned by [Managed retained execution](execution.md#managed-retained-execution); explicit alternative completion with unchanged legacy artifact obligations. Contract registration and runtime conformance are separate. |
| Closed timestamp-pattern grammar and AST | [Timestamp grammar](../../spec/grammar/actql-timestamp-pattern-0.1.ebnf) and [AST schema](../../spec/grammar/actql-timestamp-pattern-ast-0.1.schema.json). |

Normative prose and machine contracts describe the same design.
A disagreement is a specification defect, not permission
for an implementation to choose whichever definition it prefers ([Versioning](#versioning)).

Core publishes versioned canonical schemas and individual schema CIDs for:

```text
actql-parameter-values/0.1
actql-bound-invocation-template/0.1
actql-source-evidence/0.1
actql-normalization-journal/0.1
actql-result-artifact/0.1
actql-effect-preview/0.1
actql-review-projection/0.1
actql-authoring-context/0.1
actql-approval-attestation/0.1
actql-effect-apply-receipt/0.1
actql-effect-set-apply-receipt/0.1
actql-effect-reconciliation-receipt/0.1
actql-result-manifest/0.1
actql-result-delivery-receipt/0.1
actql-result-definition/0.1
actql-run-invocation/0.1
actql-result-retention-policy/0.1
actql-durable-result-binding/0.1
actql-publication-request/0.1
actql-publication-attempt/0.1
actql-publication-record/0.1
actql-manifest-read-grant/0.1
actql-result-read-grant/0.1
actql-delivery-attempt/0.1
actql-delivery-record/0.1
actql-public-index-entry/0.1
actql-run-receipt/0.1
actql-plan-result/0.1
actql-plan-document/0.1
actql-run-state/0.1
actql-run-definition/0.1
actql-prepared-invocation/0.1
actql-run-policy/0.1
actql-run-authorization/0.1
actql-execution-checkpoint/0.1
actql-checkpoint-resolution/0.1
actql-runtime-error/0.1
```

The normative envelopes are published as `ACTQL_ARTIFACT_SCHEMAS` and
`ACTQL_ARTIFACT_SCHEMA_CIDS`. The Connector/opaque-value protocol envelopes are
published as `ACTQL_PROTOCOL_SCHEMAS` and `ACTQL_PROTOCOL_SCHEMA_CIDS`, and the
aggregate schema identity is `ACTQL_PROTOCOL_SCHEMA_CID`.
