# Parenthesized JOIN equality keys

## Existing contract and minimal defect

The admitted expression AST distinguishes grouping parentheses from evaluation.
The existing equality-key JOIN profile already resolves qualified columns and
scalar value-table receivers. Grouping either operand must not change that
mapping: `ON (l.id) = ((r.id))` has the same key pair as `ON l.id = r.id`.
GoogleSQL's [operator grouping rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators#operator_precedence)
are the external reference; this is not a new JOIN operation or general computed-key support.

Adopted main: `76916b2b57ca8e06d9e74099349b17c263ccb411`.
The local branch normally merges that main at
`579ebd78f9d00c62c32bff0af9d8cbf513c4abf7`; its product tree is identical.
The two intermediate normal merges only reconcile fixture registration and
retain main's policy tests. No history is rewritten.

At that unmodified compiler baseline, `run-VMAXvh` passes 1/4 and fails 3/4
of the authored JOIN parentheses regressions. The unparenthesized specialized
query matches the complete independent Program before the grouped query fails.
The negative-control test passes. The retained baseline source is
`/private/tmp/actql-b-parenthesized-join-579ebd78f-baseline.mbt`.
`run-5DlkEf` is a test-development compile failure (private helper access),
not product execution evidence.

## Minimal correction

One private `join_key_reference` helper strips only `Parenthesized` AST nodes
before existing JOIN reference resolution. Both `join_keys` and
`join_chain_keys` call it. It neither evaluates an operand nor strips unary
signs, arithmetic, casts or dynamic properties. The admitted AST is acyclic
and bounded by existing expression depth/node/work limits.

Existing range/value receiver precedence, key comparability, NULL matching,
JOIN kinds, output bounds, physical execution, resource ownership and identity
contracts remain unchanged. Bare ordinary rows remain unsupported object keys;
this change does not reinterpret them as same-named number columns.
No common Owner, compatibility path, parser vocabulary or grammar pin changes.

## Independent expectations and verification

The MoonBit fixture contains a complete hand-authored Values/Stage/JOIN Program,
including key pair, output ceiling and Named Result. SQL specialized lowering
must match it exactly, including reversed equality operands. Shared derived,
quoted CTE, Pipe and scalar value-table variants preserve their ungrouped
meaning. A conjunction preserves both independently specified key pairs.
Precise `UnsupportedJoin` assertions retain ordinary-row and arithmetic/sign
refusals.

The public JSON control independently declares nullable number keys, four
matching pairs from duplicate keys, excluded NULL pairs, explicit ceiling 10,
ordered `id, tag` columns and output order. Source SQL/Pipe must preserve those
rows, types and column order. Separate cases exercise quoted ordinary CTE,
derived scalar receivers and one acquired Source session. Three typed refusals
retain zero durable Run admission and zero provider I/O. The fixtures are in
the ordinary registered corpus and existing composition selection; the harness
must not repair generated Programs.

- Initial correction and directly affected JS callers: 21/21, `run-4DNEOa`.
- Final focused JS callers: 21/21, `run-CchA9t`; no product or MoonBit
  fixture changes after that execution.
- Node fixture/inventory checks: 50/50, `run-qjcUk4`.
- Read-only spec-family freshness: 10 documents, 1,423 requirements; document
  links and formatting/diff checks pass. No contract preimage is changed.
- Exact-SHA packed evidence is recorded in the PR after normal package production;
  it is pending at document creation.
- Authored registration: 3,832 occurrences (2,422 normal, 1,360 refusal,
  50 expected execution failure). Counts are registration, not execution.
- No full Core, Wasm/Native execution, full packed campaign, hosted CI or vendor
  differential test is claimed. No PR merge is performed.

## Separate follow-up: CTE value-table binding

A new CTE-UNNEST scalar-receiver probe rejects its plain, unparenthesized
query before the grouped comparison (`run-0248Bu`, 3/4). Its expected single
row remains `{value:2}`. This is separate from the parentheses defect; no
public wrong-row claim or precise rejection cause has yet been established.
Source and observation are retained in
`/private/tmp/actql-b-cte-unnest-value-table-followup.json`. Do not count it as
supported CTE scalar binding or weaken its expectation. The present public
unit instead tests ordinary CTE columns and already-admitted derived scalar
receivers independently. CTE binding ownership is coordinated separately.
