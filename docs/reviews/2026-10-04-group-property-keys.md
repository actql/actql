# Nullable object property keys in SQL and Pipe grouping

## Existing requirement and baseline

This independent Frontend unit starts from main
`3c443c5bf3483170aa941feac767650a76b532f2`. It does not depend on the
pending ORDER property or aggregate-argument property repairs.

The adopted Frontend implementation specification requires group expressions
to stay within existing types. The repository's [query contract](../spec/query-text.md#scope-and-lowering)
uses parsed common expressions, input snapshots, SELECT alias/ordinal rules,
and an ordinary grouped output scope. The [common group contract](../spec/language.md#group)
accepts derived fields as keys, including NULL keys. These are existing
requirements, not a new constructor, object type or grouping law.
Google's [groupable-expression reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#group_by_clause)
also permits groupable expressions. No Google service differential execution
or general STRUCT compatibility is claimed by this unit.

The smallest sources are:

```sql
SELECT payload.score AS score, COUNT(*) AS n
FROM objects GROUP BY payload.score;

FROM objects AS before
|> AGGREGATE COUNT(*) AS n GROUP BY before.payload.score;
```

At the baseline, two source-to-Program tests fail while the complete handwritten
derive → group → select Program passes the ordinary checker (**1/3**,
`run-MHbzdK`, `focused-test-9LkmKX`). Group lowering treated every parsed
Reference as a fully resolved column and rejected an object property path before
using the common expression lowerer.

## Repair and scope

Fully resolved fields retain their direct-key path. Other property/computed keys
use the existing bounded property-aware expression lowerer in a derive before
grouping. The grouped key slot is reused by SELECT and HAVING; the object itself
does not become visible again after grouping. Pipe AGGREGATE exposes the key's
public name and its aggregate outputs, with no preceding range variables.

SELECT and GROUP BY can spell the same receiver differently. Reuse requires
matching expression operators/literals and the same longest resolved input
prefix, physical slot and property suffix. Unknown receivers or different slots
cannot establish equality. This comparison uses one pre-GROUP input snapshot;
it does not expand output aliases, evaluate SELECT expressions again or build
an alternative evaluator. Property typing and NULL propagation remain common
checker/runtime responsibilities.

The change is limited to Frontend grouping and expression comparison. There
are no common checker, strategy, provider, Host, SDK, wire, schema, grammar,
law, contract-version or stored-data changes. Grouping ordinal, WHERE,
parameter, HAVING, ORDER and LIMIT declarations remain ordinary Program inputs.
CTE/assert/Effect assembly is untouched. This does not close all grouping
subexpression rewrites, all object fields, whole-object keys or Frontend r1.

## Independent expectations and executed checks

Five authored rows have property scores `10,20,NULL,20,NULL`. One NULL is a
NULL receiver and the other is a nullable field. The independent expected
groups are `(NULL,2)`, `(10,1)`, `(20,2)` in explicit ascending NULLS FIRST
order. SET to a different non-NULL receiver produces five distinct keys,
while an old range snapshot still produces the original three groups.

The [MoonBit fixture](../../src/query_program/group_property_keys_test.mbt)
contains a complete handwritten Program and tests SQL/Pipe, qualified and
quoted paths, alias/ordinal keys, computed key reuse, SET snapshots, removed
input/alias refusals, common property type rejection and work-limit origins.

- Focused JS GROUP tests: **30/30**, including nine new property-key tests
  and existing ordinal/input-scope callers (`run-FyXRlU`,
  `focused-test-1aaxOY`).
- Affected existing HAVING callers: **8/8** (`run-Z59nZx`,
  `focused-test-zk67ut`). The selections are separate; this is not full Core
  or all aggregate coverage.
- Changed MoonBit formatting passes. JavaScript syntax and diff checks are
  performed before the source commit.

The [public fixture](../../scripts/fixtures/group-property-source-input.mjs)
authors a separate JSON control, eight positives and five preparation refusals.
It is registered in the normal packed corpus and in the existing focused
`--group-property-only` selection. Authored text uses ordinary DATA, typed
parameters and values. No test patches a lowered Program or injects a checker.
Named Result values, full ordered type contracts, stream completion,
same-Run resend/attach, hidden-column exclusion and zero additional acquisition
must be verified on both Embedded Local and authenticated HTTP. Invalid
properties, ungrouped receivers and displaced aliases must fail before Run
admission or provider I/O.

The first clean packed source `bd2e72fcad5dcc87260012fd77e842b35cb65a88`
(`public-query-evidence-RLAZd3`) passed all eight positives and five preparation
refusals on both Embedded Local and authenticated HTTP. The selected command
then failed in an unrelated String restart consumer: its retained String Run
file did not exist because this selection does not create String cases. The
new focused flag was missing from the driver's narrow-selection lists. This
was a harness registration error, not a grouping execution failure, and the
campaign receipt remains failed/incomplete. Logs, identities and digests were
retained; its disposable installation was removed with no evidence errors.

The flag is now registered consistently for related-only consumers and early
return. Full/default and source-free selections retain their existing String
restart behavior. The final focused clean-source receipt and submitted-HEAD
CI remain pending until recorded below. Full Core, all targets, native, proof
and performance are not local checks for this unit. No PR merge or manual CI
rerun is requested.

## Final focused packed evidence

Clean source `f086d100135d6be0f076414e967f245d417be107` passed
`node scripts/test-packed-public-query.mjs --group-property-only`
(`public-query-evidence-XXRbp7`). Its receipt is **passed, complete**, with
`dirty:false`, no evidence errors and disposable artifacts removed.
Eight positive cases and five preparation refusals passed **per Embedded Local
and authenticated HTTP**. The JSON control and text produce the independently
specified rows and complete ordered contracts. Empty Result descriptions retain
the nullable key type. Same-request resubmission returns the same Run; rereading
and attach do not add admission or acquisition. Refusals leave both counters
unchanged and have no registered request. Hidden group slots appear in neither
rows nor the public schema. README Local/HTTPS and missing-asset controls passed
separately. No adapter overlay, local Program correction or substitute owner
was used.

Normal producer prepack built these external packages. Consumers ran without
MoonBit on PATH. The initial failed campaign remains historical evidence and
is not rewritten as success.

| Package | SHA-256 |
|---|---|
| `actql-client-wire-0.0.0-development.tgz` | `52fe3218df346cfb9dae0adc248071563fe68918bded16f8d733415e65584fc0` |
| `actql-sdk-0.0.0-development.tgz` | `f81bf27c3bb42a007bc16b6f89a15542a89c7fb844e2893870d1161a8e8abc6d` |
| `actql-run-host-core-0.0.0-development.tgz` | `65b6408c2bb93597b8c92fc424b010b5e1d3e8b75ba414ad006bd30d57999a86` |
| `actql-local-node-0.0.0-development.tgz` | `2894f05380e26bc7a6f935cd547b1bf1c0c0e1d04cacb81a9ef688296c130a34` |
| `actql-node-0.0.0-development.tgz` | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Only this evidence document changes after the clean packed source. Submitted
HEAD and its automatic CI observation are recorded separately in the PR;
the local focused result does not establish full required CI or Frontend
completion. An Actions budget refusal is unexecuted coverage, not a product
failure or successful validation. No manual rerun is requested.
