# Implicit names for typed property projections

## Requirement and baseline

The independent branch starts at main
`3c443c5bf3483170aa941feac767650a76b532f2`. It has no unmerged dependency.
This is a Frontend connection to existing property expressions and ordinary
projection, not a new object type, inference path or execution owner.

The adopted GoogleSQL [implicit alias rule](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/query-syntax.md#implicit-aliases)
gives a path expression its final identifier as an implicit name. The local
reference checkout is pinned to that exact revision. The existing
[query text contract](../spec/query-text.md#decoding-and-expression-rules)
retains authored output spelling while resolving columns without ASCII case.
The existing common property expression owns receiver typing, member typing
and nullable receiver propagation.

At the baseline, these ordinary forms were rejected:

```sql
SELECT payload.score, id FROM objects;
FROM objects |> SELECT payload.score, id;
```

The same expression with explicit `AS score`, or in the already implemented
scoped Pipe SELECT path, could lower through the common property expression.
`output_name` instead required the whole path to resolve to an input column.
It also returned that physical column's spelling rather than the authored
implicit name for ordinary identifier projection.

The new baseline tests passed **1/3**: the complete handwritten JSON Program
passed the normal checker; SQL and Pipe lowering failed (`run-to4HXp`,
`focused-test-R6Jxbt`). The expected Program was written independently before
changing the implementation and is not generated from compiler output.

## Repair and boundary

`query_program/compile.mbt::output_name` now uses the final authored identifier
for a reference. It validates the receiver through the same longest-prefix
resolution order used by the existing property lowerer. Missing or ambiguous
receivers retain their Frontend diagnostics. The existing SELECT path derives
the value once into a private slot and projects that slot under the public name.
The common checker still rejects missing properties and non-object receivers;
the naming helper does not invent a member's type or presence.

SQL SELECT retains its original input snapshot. Pipe SET can replace the
current receiver while an existing range still denotes its earlier value.
Pipe AS does not restore displaced ranges. Duplicate public leaf names remain
rejected under the existing Result field rules. This unit does not add anonymous
computed-expression labels or change aggregate, analytic, JOIN, CTE or Graph
execution support. The keyed Property Graph source path already implements
explicit public projection names and is not reimplemented here.

There is no grammar, law, wire, schema, saved-data or contract-version change.
Previously rejected property projections now generate ordinary Programs. An
identifier reference whose authored spelling differs from its input field now
publishes that authored spelling, as the query text contract requires; this can
change that generated Program's identity and Result field name. It is not a
rewrite of an existing Program, saved Artifact or canonical contract preimage.

## Independent acceptance obligations

[Public fixtures](../../scripts/fixtures/implicit-property-source-input.mjs)
include a complete independent JSON control and eight authored text positives.
The four-row input includes a NULL object receiver, two equal score values,
a NULL nested object and a nullable nested member. Ordered expectations retain
both equal scores. The schema is declared independently and is checked even
for the empty Result.

The cases cover SQL and Pipe implicit projection; qualified/backtick paths;
nested nullable access; typed empty input; original SELECT receivers despite a
sibling output alias; Pipe current versus retained snapshot receivers; and
authored identifier spelling. Five preparation refusals cover unknown receiver,
unknown member, scalar receiver, duplicate leaf names and displaced range alias.

The existing packed public app compares Named Result rows, ordered full type
contracts via `Result.describe()`, stream completion and absence of private
columns. It checks same-Run resubmit/lookup/attach with no additional acquisition.
Refusals must leave zero Run admissions, zero provider reads and no accepted
request. Both transports use the same existing Host and Client owners.

These cases are registered in the normal packed corpus. The focused command
`node scripts/test-packed-public-query.mjs --implicit-property-only` selects
them without invoking unrelated planner, native, String restart or SGA campaigns.
Normal prepack and a fresh external installation are required; the acceptance
app does not modify a lowered Program, install a substitute checker or infer
expected contracts from rows.

## Executed checks

- New focused JS cases: **6/6** (`run-cVkTPc`, `focused-test-Uatglz`).
- Existing and new projection callers: **22/22** (`run-lKNtYu`,
  `focused-test-kqAhWA`).
- SQL callers: **19/19** (`run-SgjnEs`, `focused-test-zp7vYR`). These selections
  overlap; they are not a combined count or complete SQL conformance claim.
- Changed MoonBit formatting, three JavaScript syntax checks and diff checks pass.
- An intermediate ambiguity test altered only Context visibility and was
  correctly rejected as an inconsistent Context. Its fixture was corrected to
  include both actual case-colliding receiver fields; no product check was relaxed.
- The first clean packed attempt at `96665feaa4c53cdc71588f0681935bf6ae3ab3fb`
  (`public-query-evidence-naa0VV`) stopped before Run admission at the independent
  JSON control. Its authored nested string declaration incorrectly included
  checked-only `max_utf8_bytes`, forbidden by the existing
  [Value contract declaration rules](../spec/language.md#value-contracts).
  The fixture now uses the declared string contract, without inventing admitted
  size evidence. Rows, order, NULL expectations and product code are unchanged.
  Logs and the failure receipt were retained; disposable installation artifacts
  were removed. Text positives, refusals and HTTP were not reached in that run.
- Fresh packed source `7c08da22b6eb510aa83bd7d54a166bc1740392b6` passed **nine
  positives and five preparation refusals per Embedded Local and authenticated
  HTTP** (`public-query-evidence-CT6UKf`). Independent rows, declared column
  order, complete checked contracts, nullable nested members, empty schemas,
  duplicate values and absence of private columns matched. Result streams
  completed; resubmit, lookup and attach retained the same Run and acquisition
  counters. Refusals retained zero Run admission and provider reads.
- The packed receipt identifies a clean source tree, completed success, no
  evidence errors and removal of disposable tarballs, installation and Host
  Store. Twelve captured commands ran; unrelated planner, native, SGA and
  String restart campaigns were not invoked. The README quickstart and
  missing-runtime-asset control passed separately from these nine positives.
- The evidence commit changes only this review document after the packed source
  above. Submitted-HEAD CI remains a separate obligation. Full Core, all targets,
  native, proof and performance campaigns were not run locally. No Google service
  differential execution was performed.

| Normally packed tarball | SHA-256 |
| --- | --- |
| `actql-client-wire-0.0.0-development.tgz` | `52fe3218df346cfb9dae0adc248071563fe68918bded16f8d733415e65584fc0` |
| `actql-sdk-0.0.0-development.tgz` | `f81bf27c3bb42a007bc16b6f89a15542a89c7fb844e2893870d1161a8e8abc6d` |
| `actql-run-host-core-0.0.0-development.tgz` | `65b6408c2bb93597b8c92fc424b010b5e1d3e8b75ba414ad006bd30d57999a86` |
| `actql-local-node-0.0.0-development.tgz` | `a8f500c239169bbc37b048894bfec7842292fb3fd04a3af1cde19af4b6039982` |
| `actql-node-0.0.0-development.tgz` | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

This closes neither pending aggregate execution support nor all Frontend r1
coverage. Their independently recorded blockers remain separate from this unit.
