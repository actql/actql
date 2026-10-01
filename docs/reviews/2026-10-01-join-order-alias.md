# ORDER BY aliases across SELECT and JOIN

## Scope

Initial baseline: `a526fe6e16c77d51ec180297e949a719b71e93d7`.
Adopted main after INFER source integration:
`0a7398e486b1547b41fa292385011fd844c59cad`.
The three committed implementation units were rebased onto this main.
Conflicts were limited to the packed mode selectors and appended bridge tests;
both INFER and ORDER acceptance paths were retained. No other worktree changed.
This fixes existing SQL/Pipe ORDER BY semantics, without changing grammar,
public API, wire contracts, provider execution or Run ownership. Affected generated
Program identities change; the Grammar Manifest and JSON/YAML Program admission
remain unchanged.

An unqualified reference inside ORDER BY resolves a SELECT alias first.
A qualified reference retains its input meaning. Expression equality permits
reuse of a selected slot only when reference bindings are also equal.
Several aliases of an equal SELECT expression are alternative evaluated
slots, not an ambiguous ORDER BY expression.

JOIN and CTE JOIN now evaluate SELECT before any alias-dependent ORDER
expression. ORDER expressions read evaluated slots; SELECT expressions are
not substituted into them. Equal ORDER expressions share one private slot.
Private slots are removed before the Named Result and never enter DISTINCT.
Independently declared SELECT occurrences keep their original evaluation
count. Existing unsupported DISTINCT orderings remain rejected.

## CTE acquisition connection

The first packed probe found an existing Frontend capture-shape gap, also
present without ORDER BY: a source CTE started with SELECT and could not
satisfy the common scan/filter/select acquisition contract. It fell through
to source-free Invocation admission and was correctly rejected by the issuer.

The Frontend now uses the same explicit capture builder as ordinary SELECT,
then evaluates the CTE over that captured Stage Result. Repeated CTE references
share the one producer. This preserves Source Evidence admission and does not
add a Host fallback or a second acquisition owner. The independent Program
fixture checks the capture and both producer references; the packed fixtures
require the same physical table statement count for shared CTEs as for the
ordinary SELECT control. Literal-true broad capture executes one table scan;
filtered native capture executes the existing pinned validation scan plus the
native query (two statements). See
`adapters/connectors/duckdb/node/native-acquisition.mjs`; neither validation
nor acquisition is bypassed to satisfy a counter.

## Independent acceptance fixtures

`spec/frontend/fixtures/join-order/cases.json` contains authored source rows,
expected rows, ordered column contracts and a DISTINCT refusal. It covers
normal SELECT, computed aliases, identical expressions with two aliases,
qualified input references, an alias changing an expression's reference
meaning, CTE JOIN and ordinary Pipe SELECT. Direct GeneratedValues Pipe JOIN is
covered by the shared compiler/checker regression. The currently unrouted
WITH-plus-Pipe combination is a typed refusal here, not a permanent language
restriction or a claimed execution success. The input order differs from the expected
alias order.

The installed Host supports these real-input JOIN cases through the existing
CTE acquisition boundary. Direct GeneratedValues JOIN is also tested through
the same projection/compiler helpers and normal checker. This change does
not add direct Source View JOIN support.

Run the focused packed test with:

```sh
node scripts/test-packed-public-query.mjs --join-order-only
```

The default packed public-query test also includes these cases. Both
Embedded Local and HTTP use the unchanged installed Client API, compare
Named Result rows and `Result.describe().columns`, and check that attach,
resubmission and rereading do not acquire again. The refusal must leave Run
admission and provider I/O unchanged. No frontend test bridge is loaded by
the external installation.

## Verification

Before the fix, the targeted regression file had four failures and one
qualified-reference control success. After integration, all 89 query_program
JS tests passed, including six new regression tests. Independent Program
bridge fixtures passed 7/7. Syntax checks and `git diff --check` passed.

Verified implementation source:
`ac488c91be022f4ce9fd0b28f7f82bda0a5894e3`.
The focused packed command passed all 14 authored success cases and two typed
refusals on each of Embedded Local and HTTPS. Rows, actual retained column
contracts, column order, hidden-column exclusion and table statement counts
were compared with the independent fixture. Attach, identical-request
resubmission and rereading did not add Run admission or acquisition.
Both refusal cases left Run admission and provider I/O unchanged.

The following affected jobs passed on that same source, one at a time:

```sh
node scripts/local-checks.mjs run lint
node scripts/local-checks.mjs run core --target js
node scripts/local-checks.mjs run spec
node scripts/local-checks.mjs run client
```

Core JS passed 7,126/7,126. The complete Client job included 311 Client/Host
tests, installed Node/browser and Checkpoint tests, native mTLS Client tests,
the default raw-source Local/HTTP and native SGA acceptance, packed Result
description tests, 277 Salesforce adapter tests, and the existing Effect
recovery/crash probes. Those Effect probes used simulated providers, not a
live Salesforce org. Recovery performed no replacement Source/Compute calls.
INFER refusals in this job are not successful inference execution evidence.

Focused packed artifact SHA-256 digests:

| Package | SHA-256 |
| --- | --- |
| `@actql/client-wire` | `c9882e6300c184e7086e86a56cc70b1be3f65e059d0b97364ea49b379eac3a86` |
| `@actql/sdk` | `823149a8d04223425d9752b29596b72e72d3401ef168e6d164b7ec1557b38cf3` |
| `@actql/run-host-core` | `6ad3039654b116729d329903d23479ffe59a2a9a0b5c6fe61cded0178e45a176` |
| `@actql/local-node` | `7eb535d0ca877599eac1a4e61a3dcd8f122a4b35f9311640b98623a6ea25b1ad` |
| `@actql/node` | `c72364973dd1ed42faea32425632b314de037c9b92035c9f5ec35b875914f225` |

The external evidence retains the source SHA, digests, exit results and logs;
its expanded installation and tarballs were reclaimed after success.
Local gate logs are retained under `_build/join-order-evidence/`.
The final validation-record commit changes documentation only.
Full Core Wasm/native were not repeated locally. Pushed-SHA Linux CI is
reported separately in the PR; local success is not CI success.
