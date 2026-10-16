# R2: dependency policy and boundary behavior

## Responsibility

The architectural gate uses `productionPackageImports` and
`productionDependencyClosure`, backed by the existing Moon manifest reader.
`scopedPackageImports` exposes the same reader's entries for the engine's
intentional all-scope restriction and the integration package's whitebox-only
composition. It adds no manifest grammar or second dependency authority.

The gate allows additional neutral helpers, reordered imports and aliases.
It rejects concrete/transitive Connector dependencies, production conformance
imports, public representation leaks and retired public authority surfaces.
The existing resolver exposes its complete local source input closure through
`localModuleGraphInputs`, before any adapter ownership filtering. The common
policy checks that closure, including relative reexports into `fixtures/` or
`packages/`; a test module cannot disappear through the packaging projection.
The packaging API `adapterModuleGraph` retains its adapter-only projection and
entry validation. Neutral helpers outside `adapters/` remain allowed, and bare
external dependencies remain external rather than expanding this audit's scope.
Public opaque types and operation signatures remain
contract assertions. Private function names, variable names, call order inferred
from text, complete neutral import lists and positional-call regexes are gone.

`query-boundary-behavior.test.mjs` calls production authorization, strategy and
SQLite functions. Controlled Host/Core peers and the existing Site protocol
fixture test adapter sequencing; they are not a second checker or evidence of
Common semantic execution. SQLite cases use a real in-memory database, including
an actual deferred-foreign-key COMMIT failure. Failed close retains its original
owner through retries; approval refusal never dispatches; callback success does
not publish a Common completion; preflight transfers custody before a fallible
stop; rollback does not turn a failed COMMIT into a known outcome.

The existing CI entry imports the structural and behavioral tests. No product
source, public API, runtime authority, specification, pin or acceptance oracle
is changed. Full Host/Common, SDK and Cloud responsibilities retain their own
behavioral suites below; R2 does not claim those suites ran merely by referencing
them here.

## Source-qualified mutation experiments

`mutation-controls.test.mjs` is an explicit review experiment, not an automatic
architectural CI rule. Its patch locations are tied to the recorded product
input hashes. This distinction prevents experimental patch anchors becoming
another permanent implementation-text gate. Ordinary structural/behavioral
checks never inspect those private implementation strings.

The experiment applies changes only to private module copies and uses the same
unchanged behavioral assertions as the ordinary checks. Successful controls
must show a real assertion failure with the expected boundary message and
`ERR_ASSERTION`; parse, import, patch-target or setup failures are not successful
mutant detection. A harmless private authorization-function extraction/rename
passes. Missing approval, discarded cleanup ownership, a known outcome after
failed COMMIT, bypassed Host authorization and an omitted preflight custody
handoff each fail their intended assertion. Synthetic manifest/API/adapter
mutations remain in the ordinary policy tests because they describe stable
architectural edges rather than implementation patch locations.
The opaque-registration probe checks equal names cannot dispatch. The Common
completion probe checks the first typed refusal: a later output guard still
rejects the mutated case, so it is not evidence that the mutation published.

## Reproduction

Use the repository's pinned Node and ordinary locked test dependencies:

```sh
node reviews/2026-10-16-refactoring/r2/prepared-checks.mjs boundaries
node reviews/2026-10-16-refactoring/r2/prepared-checks.mjs mutations
node reviews/2026-10-16-refactoring/r2/prepared-checks.mjs graph
```

All use the existing non-Heavy guard, 60 seconds / TERM grace 5, and the existing
nonzero focused wrapper with a 30-second child limit. No Moon, Native, packed
producer, Provider or installed campaign is started. Preserve every attempt's
original guard and focused receipts; later success does not replace earlier
failure.

`graph` selects the complete-closure counterexamples, the unchanged packaging
projection/entry contract, the real common adapter closure and the existing
Connector installation generator consumer. It does not rerun the earlier
boundary/SQLite/Host or source-qualified mutation acceptance.

## Original assertion responsibilities

This table accounts for every original top-level test at base
`34da525d76ec00ef8e60a9ddbc49589aadc6ce96`. A structural gate establishes edges
and API opacity; an owner behavior suite establishes semantics. Source spelling
is not substituted for either. Owner suite locators are retained coverage,
**not executed R2 evidence** unless separately recorded in the handoff.

| Original test / responsibility | Structural policy or generated oracle | Behavioral owner retained |
| --- | --- | --- |
| Common captured DAG, no operation templates | Direct aggregate-shape boundary; backend semantic boundary suite | `physical_strategy/captured_dag_wbtest.mbt` |
| Standard installation / bridge, no handwritten provider configuration | Existing connector generator/installation tests; common adapter closure | `host-node/installation.test.mjs` |
| Reference author checked context and common completion | Author ledger boundary; no public TaskExecution/NumericAttempt | `connector_sdk/capability_implementations_wbtest.mbt`; Host Common-completion oracle |
| Connector-owned standard profile / fixed contributions | Common/Connector closure and opaque SDK contracts; ordinary bundle generation | `connector_sdk/capability_implementations_wbtest.mbt` |
| Neutral linear costs / implementation work inventories | Cost closure and opaque RateSchedule | `physical_host/adaptive_quantities_wbtest.mbt`; `physical_strategy/operational_estimates_wbtest.mbt` |
| Connector-free serial driver / exact registration | Actual common adapter graph; generated installation tests | New Host exact-registration, approval and completion oracles; `host-node/strategy.test.mjs` |
| One portable Site lifecycle authority | Product graph rejects test authority; neutral Site dependency boundary | `physical_strategy/{host_task_success,host_cleanup_progress,managed_failure_progress,managed_transfer_progress}_wbtest.mbt`; `host-common/{execution-sites,managed-site-transfer,managed-failure}.test.mjs` |
| One portable runtime signature owner | Common remote_bundle closure and public signature operations | `remote_bundle/bundle_wbtest.mbt`; `site-node/runtime-bundle-store.test.mjs` |
| One portable activation transaction | Common activation/drain/retain/reclaim public operations | Same bundle suites; real restart/reclaim responsibility remains there |
| Connector-owned DuckDB SQL and physical values | Concrete adapter dependency and no common SQL API | Existing DuckDB adapter/driver tests |
| Acquisition independent of Compute composition / Local | Host production closure; opaque NativeHostRun/BroadHostRun | Existing DuckDB acquisition tests |
| Connector-owned transport / no SQL reexport | Transport closure and composition public API | Existing DuckDB Host tests |
| SDK no concrete implementation or public concrete error | SDK closure, public forbidden types and opaque author handles | Existing SDK capability/prepared execution suites |
| Salesforce semantics not acquisition custody | Catalog closure; opaque ManagedQuery; generic row-source API | Existing Salesforce Host suites |
| DAG/Host no transitive concrete dependency | Common production closure and public leakage checks | Existing common completion tests |
| Common execution no Connector dependency | Nine common production closures | Existing common execution suites |
| Product no conformance dependency | Production-scope policy; test/wbtest and later-unscoped negative controls | Not a runtime claim |
| Query comparison/material no concrete acquisition | Planning closure and opaque material handles; dependency direction | Existing query planning/acquisition suites |
| Neutral physical Ledger | Resource production/public dependency policy and opaque handles | Existing physical_resources suites; no new resource limits |
| DAG no backend attempt table | Opaque TaskExecution and common lifecycle API, no concrete public attempts | Common completion/dispatch owner suites |
| Shared retained-output completion | No public publish_task_completion or legacy authority API | Host Common-completion oracle; `physical_strategy/host_task_success_wbtest.mbt` |
| Common synchronous dispatch not Local sequence | Opaque SynchronousCompute signature and no GeneratedSequence public API | Existing synchronous completion suites |
| Owned materializing preparation / no completion hooks | Opaque PreparedExecution and materializing operation signature | Existing prepared execution / Host task success suites |
| Concrete DuckDB lifecycle in driver | Common dependency/public payload policies | Existing DuckDB driver completion suites |
| Common cleanup not SQL compilation | No public SQL cleanup; no concrete common dependency | Owner cleanup suites; new retry-custody oracle |
| One common prepared dispatch owner | Opaque DispatchDriver/Ticket/Work/PreparedTaskDispatch; no provider payload | Existing prepared dispatch suites |
| Local installed bounded preparation | Opaque LocalComputeModule; no common GeneratedSequence API | Existing Local driver suites |
| Concrete capacity formula Connector-owned | Capacity operations exposed only by concrete compute API | Existing concrete capacity suites |
| Host join no SQL / request swapping | Opaque concrete preparation/selection, no public raw request/ProducerRead rebinding | Existing Connector dispatch/request ownership suites |
| Connector-owned configuration/resource start | Configuration opaque in driver, absent from composition API | Existing Connector driver suites |
| Offer selection not work-slot classification | Provider-free Host closure/API and opaque capability registrations | `connector_sdk/capability_implementations_wbtest.mbt`; existing offer selection suites |
| Resident output not SQL/table naming | No concrete common closure or public SQL; opaque concrete resident output | Existing retained output/capacity suites |
| Resident borrowers not concrete SQL | Common dependency/API boundary, opaque concrete resident read | `host-node/completion-custody.test.mjs`; existing resident borrow suites |
| Fixed-input engine excludes acquisition even in tests | Explicit all-scope policy through shared scoped reader | Existing engine suites retain independent composition |
| Query facade no engine internals | Public engine/facade forbidden representations; backend semantic traversal gate | Existing execution_query/execution_relation tests |
| Same adopted filesystem-free bodies | Read-only ordinary `lowering-registry-vectors.mjs` against normative inputs | No runtime claim; no private function-body parser |

## Parallel owner coordination

- A/R4: Checker/static packages may move; policy follows production closure and
  public opaque surfaces, not the original source filenames.
- C/R1: Site preflight/create/cleanup behavior stays in C's Site installation
  suite. R2 does not edit Site implementation or assert its helper names.
- D/R7: Lifecycle/action and grouped driver arguments are D-owned. The small
  Host test adapter follows the adopted internal signature; no public injection
  option is introduced.
- E/R5: SDK internal observations/transport/readers may move freely; its public
  ownership and recovery suites remain authoritative. No index import list is
  pinned by R2.
- F/R3+R6: Cloud fixed-runtime binding and codecs remain F-owned. Cloud custody,
  resume-claim, original-material and codec suites are separate evidence.
