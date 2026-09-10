# ActQL 0.1 Agent Guide

## Stage authoring

ActQL uses `stages`, not Effect declaration order, for
parent→child, upload→attach and update→notification dependencies. Each stage
imports only earlier published Results or typed receipts; default progression
waits for provider completion and imported data. Explicit `after: accepted`
permits an acceptance notification but never fabricates a completion-only Ref.
Fresh business reads occur in the stage that requests them. Partial stage
failure stops normal successors; recovery reuses completed items, while cleanup
is a separate explicit Program. Resolved allow permits unattended multi-Effect
stages with policy risk evidence rather than an extra human checkpoint.

See [the ten scenarios](../spec/product-decisions/SCENARIOS.md) for complete
Programs. Fragments below show stage-local inputs, steps, Results or Effects;
parameter and binding declarations belong at the Program root.

For search→create, first generate candidates, then use a complete scoped keyed
fetch to establish absence and retain the write-side conflict guard. A search
no-hit alone is insufficient. Incremental reads may occupy an early stage, but
their cursor remains pending until dependent stages succeed. Separate read
Programs need durable downstream handoff before acknowledgement.

For expected conversion failures, choose a registered `try_*` repair explicitly;
it changes failure into null. A proposed `top_k` similarly changes business scope
and requires a deliberate order. Ordered `derive` arrays support input shadowing
and prior outputs while retaining all input fields. Map derive retains its
snapshot/add-only semantics. Use a following `select` to close intermediate
shape, or Result.fields for publication only; selecting too early can remove
required inputs. No new `project` operation is adopted. Parameter defaults apply
only to missing values once, not to explicit null or missing object fields.
Infer outcomes are explicitly filtered on `ok` before reading successful value;
strict all-row publication is opt-in. Floating sum/avg replay uses captured
numeric observations; choose exact decimal for money.

Scheduling/watch and arbitrary code stay outside ActQL. Use registered profiles
or explicit Host tasks rather than an unregistered UDF. SDK single-row/value
access verifies arity; progress is not a Result. Private inspection requires
read authority independently of approval authority. Human export presets create
explicit new artifacts and do not alter canonical CSV silently.

This guide covers the canonical source syntax used by people and coding agents.
It focuses on writing a Program that passes `actql check`; compiler and AoA
implementation details are in the language specification.

Use `check` for static validation, `explain` for a non-executing description of
an execution request, and `run` for execution. `explain` and `run` share
parameters, opaque bindings, local inputs, environment flags, and repeatable
`--deliver result=format:file` selections. Never invent estimates when statistics
are absent. `run` checks again and accepts a Program, not a saved explanation or
Plan. To inspect concrete Effects, use `--stop-before commit` and continue the
same Run through its Checkpoint; reads and inference may already incur costs.
Retry delivery with `result`, not by rerunning successful Effects.
For destination requests, read the JSON response's `run` and `delivery_status`
separately: a nonzero delivery exit can still contain a successful Run.
Completed deliveries are not resent by status polling. `--source-state-in`
is shared by explain/run; explain only describes its unverified locator.

Check resolves the required algebra, acquisition and Artifact profiles before
execution. HTTP transport and Run Graph are separate companion protocols.

Start from this shape:

```yaml
version: actql/0.1
id: customer.open_orders
stages:
  - id: main
    inputs:
      orders:
        carrier: relation
        schema:
          id:
            type: string
            nullable: false
          customer_id:
            type: string
            nullable: false
          status:
            type: string
            nullable: false
          amount:
            type: number
            nullable: true
        primary_key:
          - id
    from: orders
    steps:
      - filter:
          eq:
            - field: status
            - literal: open
      - group:
          by:
            - customer_id
          aggregates:
            order_count:
              fn: count
            total_amount:
              fn: sum
              field: amount
      - top_k:
          k: 20
          by:
            - total_amount: desc
            - customer_id: asc
        as: customer_totals
    results:
      main:
        from: customer_totals
        fields:
          - customer_id
          - order_count
          - total_amount
        order_by:
          - total_amount: desc
          - customer_id: asc
results:
  main:
    from:
      stage: main
      result: main
```

## The writing model

1. Declare typed `inputs`.
2. Put one familiar operation in each `steps` item.
3. Omit step `from` for a linear pipeline; use `as` only when a result is
   reused or branched.
4. Name the additional input inside `join`, `append`, graph binary operations,
   and `nearest`.
5. Expose closed named `results`. Select names, formats, and destinations only at delivery (`--deliver` or SDK options); Program has no `output` member.

For a Connector source, always write the exact Catalog trio. The view owns the
Carrier, schema, read authority, and modes, so do not write a redundant
`carrier` declaration:

```yaml
inputs:
  threads: {connector: gmail/main, resource: mailbox/me, view: thread_messages}
```

Metadata, content, and binary are separate views. Select a content view when
you need an `artifact_ref`; metadata never upgrades itself to content.

Use `meta` on Program, Input, Parameter, Binding, Step, Result, or Effect
declarations, as specified by [Authoring Context](spec/language.md#authoring-context).
Do not place it inside expressions, predicates, value contracts, or operation bodies.
`description` says
what the node does, `rationale` says why, and `references` names opaque policy,
ticket, or document references. Metadata never supplies missing semantics,
authority, egress fields, bounds, or optimizer hints, and it is never sent to
a Connector or model. Do not put secrets or raw personal data in it.

For repeated Runs, declare typed values once and use parameter references in
the [admitted value positions](spec/language.md#parameters), including declared
object and array roles. For example, a scalar timestamp parameter:

```yaml
params:
  cutoff: {type: timestamp}
  threshold: {type: number}
steps:
  - filter:
      and:
        - {gte: [{field: occurred_at}, {$param: cutoff}]}
        - {gte: [{field: score}, {$param: threshold}]}
```

Do not parameterize operation names, fields, joins, metrics, connector targets,
mappings, permissions, approval, or effect scope. Those remain checked Program
semantics; concrete parameter values belong to Run identity.

Every predicate operand is explicit, so `check` never has to guess whether a
name denotes a field or literal:

```yaml
- filter:
    lt: [{field: score}, {field: required_score}]
```

Literal text with the same spelling stays explicit:
`{lt: [{field: score}, {literal: required_score}]}`.

Expressions in a map-form `derive` read only the incoming row and add fresh
fields. An ordered array-form `derive` evaluates slots in order: each slot may
read preceding outputs and shadow an input field. A later `derive` step also
reads outputs of completed steps. Use `select` to choose the final field set.

For ordinary messages and labels, use the closed string-template form instead
of spelling out `concat` and `to_string`:

```yaml
- derive:
    message: {template: "{customer_name} has {open_count} open orders"}
```

Placeholders name visible scalar fields. Use `{{` and `}}` for literal braces.
Unknown, non-scalar, empty, or malformed placeholders fail during `check`.

## Canonical vocabulary

The lists below summarize language operations. Source operation names are not
aliases for AoA registry identifiers; profile support is checked separately.

Operations use closed spellings. Expression strings decode to the same
canonical trees as structured expressions; they are not embedded SQL.
Use `value * 2`, `status = 'open' AND amount >= $minimum`, or
`coalesce(name, 'Unknown')`. Names retain case, strings use single quotes,
and `$minimum` references a declared parameter. For non-ASCII field names,
use double-quoted identifiers inside the expression. No implicit casts,
subqueries, arbitrary functions, or expression evaluation inside Effect
values is admitted. The target operator and signature list is in
[Expression text](spec/language.md#expression-text).

The expression 0.1 contract uses PostgreSQL-style notation, not an embedded
SQL engine. Structured and textual forms share the same typed semantics.

| Expression / name | ActQL | PostgreSQL 18 |
| --- | --- | --- |
| `5 / 2` | `2.5` (binary64) | `2` (integer division) |
| `split_part('a,b', ',', 1)` | `'a'` (one-based) | `'a'` (one-based) |
| `substring('abcd', 1, 1)` | `'a'` (one-based) | `'a'` (one-based) |
| `concat('a', NULL)` | `'a'`; non-null operands must be strings | `'a'`; also converts non-strings |
| Bare `Name` | Case preserved | Folded to lowercase |

AND/OR evaluate all operands from left to right; they are not failure guards.
Use a conditional to guard division or parsing. Effect selector operands are
fields and literal/bound values only. The target allows pure text-time function
composition wherever computation expressions are admitted, with per-expression
profile bounds and conditional demand. It does not grant external access.
Boolean expressions retain null as a value; only true selects a filter row.
Use explicit `CAST('0.1' AS DECIMAL(2,1))` for exact decimal values, not an
implicit binary64 conversion. Typed `customer.city` and `items[0]` access does
not inspect opaque JSON or references. `||` and templates remain strict even
though `concat` skips null. These additions require expression 0.1 runtime support.

Relation:

```text
filter  select  rename  drop  derive  sort  take  top_k  top_k_by  distinct
dedupe_rows  group  join  append  nest  unnest  row_window  window_group
lag  watermark_rows  pivot  unpivot  json_pick  assert_rows
```

Graph:

```text
graph  normalize_graph  match_nodes  match_edges  reach  traverse
shortest_path  components  graph_bounds  degree  graph_diff
graft_graph  union_graphs  subtract_graphs  node_rows  edge_rows
```

SGA is graph-value computation only. Node IDs are not canonical entities, and
`union_graphs` is not an entity merge. Canonical entities, source-record
bindings, merge/split lineage, persistent graph CAS, and graph mutation
receipts are outside ActQL 0.1. VecA may rank entity-resolution candidates but
never grants merge authority.

Events:

```text
row_window  to_events  window_events  session  watermark_events  dedupe_events
asof_join  sequence  events
```

Vectors:

```text
nearest  to_vectors  normalize_vectors  score_vectors  pool_vectors
merge_rankings  vectors
```

Optional production-integration profiles:

```text
actql-text-time/0.1  split/substring/UTF-8 truncation/UTC/portable-regex/NFKC/case-fold/try-timestamp
actql-lookup/0.1     internal bounded acquisition for a checked external join
actql-artifact/0.1   ordered Relation -> captured ArtifactRef Relation
ArtifactRef input   typed external SourceView join -> ordinary Relation
```

Authors declare an ordinary join against a keyed SourceView input:

```yaml
inputs:
  customers:
    carrier: relation
    expected_columns: [customer_id]
  risks: {connector: risk/main, resource: risk_record, view: by_customer}
from: customers
steps:
  - take: 100
    as: bounded_customers
  - join:
      with: risks
      kind: left
      on: [customer_id]
      null_key: fail
    as: customers_with_risk
```

The pinned SourceView contract owns the request/response roles, response
identity, completeness, and response cardinality. The join key names the exact
fields allowed to cross the boundary. For differently named or composite keys,
use ordinary explicit join pairs; never rely on positional matching. Put only
non-correlated static request fields under the SourceView input's `request`.
Connector inputs may otherwise contain only the Catalog trio, static
`request`, `minimum_classification`, and—only for a directly read
SourceView—optional `scan.mode`. A keyed external-join input
must not author `scan`; its access path is Contract-owned.
Do not repeat local carrier, schema, columns, or primary-key facts. Write
projection, filtering, ordering, limits, and deduplication as ordinary steps.

The left Relation must prove a finite row bound. The compiler deduplicates its
key tuples and lowers the join to an internal `actql-lookup/0.1` acquisition
barrier followed by an ordinary RelA join. Batch, page, request, retry, byte,
and deadline bounds come from that Relation bound, the SourceView contract, and
Host policy. The complete acquisition response bound is independent from the
logical join's optional `max_output_rows` guard. With omitted `null_key`, null
key rows are not sent to the provider and remain subject to ordinary join
semantics; `null_key: fail` rejects before dispatch. The named input's minimum
classification strengthens the response policy. If completeness, cardinality, or output bounds cannot be proved,
`check` fails instead of guessing. A keyed-only SourceView cannot be scanned
directly, and it cannot implement a full join.

These profiles are indivisible claims. Do not hide their computation in
Python, raw HTTP, a compound Connector view,
or output post-processing and call the result ActQL. Run Graph and Generic
HTTP are separate companion protocols, not operations in `steps`.

## Typed model acquisition

Keep model egress explicit:

```yaml
- infer:
    contract: model-task:work-item-triage.v1
    key: [source, source_id]
    input:
      title: {field: title}
      body: {field: body}
  as: triage
```

Omit `key` only when `check` can prove exactly one candidate key. `input` is
never inferred: it is the exact model-egress mapping. Write `max_items` only
when the request explicitly requires an independent fail-closed item guard;
never copy an upstream `take` or `top_k` value. Provider-call, byte, token, retry,
and duration limits are resolved into the canonical barrier from the ModelTask
and Host contracts. Infer returns typed outcomes by default; select successful
rows by `outcome = 'ok'` before consuming `value`. Explicit strict mode makes a
non-success fail the operation. See [infer](spec/language.md#infer).

When appending sources with local IDs, retain a distinct literal source field
on each branch and use the proven composite key, for example
`[source, source_id]`. Do not encode identity into display strings or use
`dedupe_rows` as an assertion. A null literal may join a typed peer into a
nullable field. It may also map to one explicitly named nullable ModelTask
input when that contract supplies the only type. Missing fields remain
explicit and unrelated base types never coerce.

## Expected invalid rows and runtime failures

Expected row invalidity is ordinary Relation data: use a total form such as
`try_number`, derive a stable rejection code, and create accepted and rejected
branches with `filter`. Do not silently discard rejected rows.

| Event | Treatment |
| --- | --- |
| Missing required value or expected parse failure | Classify in the Relation and branch with `filter` |
| Successful optional external acquisition finds no row | Follow its SourceView cardinality contract and authored join kind |
| External acquisition timeout, authentication failure, or response-schema mismatch | Preserve the acquisition-barrier failure |
| Infer refusal, truncation, or response-schema mismatch | Preserve the typed non-success outcome; explicit strict mode fails the operation |
| ArtifactRef fails live admission before external provider access | Preserve the acquisition-barrier failure; provider calls remain zero |
| Engine defect | Fail the Run |
| Effect fails or has unknown outcome | Preserve the Effect Receipt; reconcile the durable Run or use a later Run Graph continuation |

Failure classification names its originating boundary. External join admission
or acquisition failure fails its barrier. Infer exposes classified provider
non-success as outcomes unless strict mode is selected; authorization, invalid
request, capacity and engine failures still fail the barrier. Engine failure
originates at the Invocation boundary.
ActQL has no `try`, `catch`, `on_error`, Error Carrier, or general recovery
inside a Program.

Effects:

```text
create  update  upsert  delete  command  store
```

Effect declarations live in a stage's `effects` map, not in `steps` or at the
Program root. A stage may declare a finite unordered map of named Effects.
Each member uses one kind key and one
explicit named result; members cannot consume peer outcomes or imply
source-order execution. Write effect identity and scope; let the resolved
mapping contract supply evidence it already owns:

```yaml
effects:
  mark_review:
    update:
      target: connector://crm/main/Opportunity
      mapping: mapping:crm.opportunity.v1
      from: {result: crm_updates}
      id: opportunity_id
      set:
        NeedsReview: {literal: true}
        RiskScore: {field: risk_score}
```

`update`/`delete` require exactly one of `id`, `match`, `ids`, `external_id`,
or `where`. A field-valued `set` requires output correlation through `id` or
`match`. `upsert` requires `from: {result: name}`, a result-side `key`, and a non-empty
`set`; the mapping supplies the target primary key. `store` requires a named
result. `create` requires exactly one of `from: {result: name}` or an explicit
object `payload`. A command instead requires an output ResourceRef field and a
Connector-owned typed contract:

```yaml
effects:
  reply:
    command:
      from: {result: replies}
      target: {field: thread_ref}
      contract: command:gmail.reply.v1
      input:
        body: {field: reply_body}
```

Arbitrary URL/method/body commands are invalid. Preview never applies an effect.
Use `{literal: value}` for every constant and `{field: output_column}` for row
values; all bare values are rejected with a deterministic explicit repair.

The Connector Mapping Contract—not the author—defines target schema,
writable fields, conversions, and the exact permissions for the selected
effect/write-field set. `actql check --connectors connectors.json --json` reports the
resolved mapping-contract CID and authority summary. Required permissions are
checked Plan facts, not authoring vocabulary.
The value is always typed-qualified, such as
`mapping:crm.opportunity.v1`; in `mapping: mapping:crm.opportunity.v1`, the
left token is the field and the right prefix is the contract namespace.
Mapping or Command Contract and Host approval minima combine monotonically;
neither may weaken `required`. Omit `on_item_failure` for the fixed fail-fast
behavior; write only `on_item_failure: continue` when partial continuation is
intentional. A multi-Effect set commits only as a
complete disjoint set after all-member preflight and signed acceptance of
partial-application risk. Compensation and effect-to-effect orchestration are
not part of 0.1.

## Checked relation patterns

Use typed input schemas when data does not come from a connector contract:

```yaml
inputs:
  orders:
    carrier: relation
    schema:
      order_id: {type: string, nullable: false}
      customer_id: {type: string, nullable: false}
      items:
        type: array
        nullable: false
        items:
          type: object
          nullable: false
          fields:
            sku: {type: string, nullable: false}
            amount: {type: number, nullable: false}
    primary_key: [order_id]
```

Nested arrays, deterministic representative rows, and joins are explicit:

```yaml
- unnest: {column: items, as: item, with_index: item_index}
- json_pick: {column: item, path: [sku], output: sku}
- dedupe_rows:
    by: [customer_id]
    order_by: [{updated_at: desc}, {source_id: asc}]
- join:
    with: accounts
    kind: left
    on:
      - {left: organization_id, right: organization_id}
      - {left: account_id, right: id}
    cardinality: many_to_one
```

`take`, `array_agg`, `pivot aggregate: first`, and `dedupe_rows` require proven
stable order. A retained candidate key is sufficient for the compiler
to append an ascending identity tie-break and journal it; without one, write
the complete business tie-break explicitly. `dedupe_rows` always keeps the
first row under that order and fails unresolved ties; a join cardinality
assertion always fails on violation. Omitted `null_key` has the fixed SQL-style
non-match law; write only `null_key: fail` as an author safety choice. `cardinality` itself is an
optional assertion. `append` accepts only `{with: relation}`. Its complete
schemas must match by field name and base type; nullability joins safely toward
nullable. Bare `dedupe` is intentionally ambiguous—choose `distinct` or
`dedupe_rows`.

Less-common relation shapes are still regular one-operation steps:

```yaml
- watermark_rows: {time: occurred_at, max_skew: 5m, late_policy: mark}
- pivot: {index: [customer_id], column: status, values: [open, won, lost], value: amount, aggregate: sum}
- lag:
    partition_by: [customer_id]
    order_by: [occurred_at]
    field: amount
    output: previous_amount
- unpivot:
    columns: [jan, feb]
    name_column: month
    value_column: amount
    keep: [customer_id]
```

`watermark_rows` handles event-time lateness; it is not a latest-row-per-key
operator. Unknown parameter diagnostics include the operation signature and
all allowed keys. `actql op show` exposes the same operation information.

ActQL accepts only the canonical operation name shown by authoring tooling or
`actql op show`. For example, write `filter`, `select`, `sort`, `take`, `group`,
`reach`, and `nearest`; do not substitute SQL, DataFrame, or English synonyms.
A retired or merely similar word never executes. Check may return a complete
replacement when the intended canonical spelling is unambiguous.

## Row-local values and invariants

### Exact decimal

Declare an input field as `{type: decimal, precision: 18, scale: 2, nullable: false}`.
JSON input carries `"19.99"`, not binary64 `19.99`. Conversion of ordinary text
is explicit:

```yaml
- derive:
    amount: "to_decimal(amount_text, 18, 2)"
    rate: "to_decimal('0.10', 5, 4)"
- derive:
    raw_tax: "amount * rate"
- derive:
    tax: "quantize(raw_tax, 18, 2, 'half_up')"
```

Precision is at most 38 digits. Conversion does not round; rounding belongs to
`quantize` or `decimal_divide`. Decimal and binary64 do not mix implicitly.
Use `sum` and `count` followed by `decimal_divide` for an explicitly rounded
average. Currency codes, rates, and tax rules remain ordinary Contract data.

### Construct before acting

```yaml
- derive:
    contact:
      object:
        external_id: {field: customer_id}
        profile:
          object:
            name: {field: customer_name}
            segment: {field: segment}
        tags:
          array: [{literal: synchronized}, {field: segment}]
```

Objects have static, always-present keys; authored array constructors are non-empty and
homogeneous. Nullable means a present null, not omission. No spread, computed
keys, opaque JSON, or nested capability references are admitted. Expose the
constructed field in a named Result and pass that field to the typed Command.
Effect inputs do not evaluate scalar expressions. Use `array_agg` for variable
length arrays and `unnest` / `json_pick` to extract typed values.

To attach child collections without multiplying sibling rows, use `nest`:

```yaml
- from: customers
  nest:
    with: orders
    on: [{left: customer_id, right: customer_id}]
    into: orders
    fields: [order_id, amount]
    order_by: [{order_id: asc}]
  as: customer_tree
```

Both inputs need complete typed fields. Each parent survives; no matching child
produces a typed `[]`. Child failures never become empty collections. Optional
`max_items` fails on excess; select a subset explicitly before nesting.

Contract discovery uses `discovery describe/list/read`, not Program steps.
Pages help locate exact contracts; they are not complete checking evidence.
Independent optional reads use the [read collection companion](spec/protocols/collection.md#collection)
and explicit coverage evidence, not a join error handler or implicit null.

### Assert without dropping rows

```yaml
- assert_rows:
    where: {not_null: {field: customer_id}}
- assert_rows:
    unique_by: [account_id, external_id]
```

An assertion succeeds without changing rows, order, or identity. False,
unknown, null keys, and duplicate tuples fail atomically. A successful
uniqueness assertion supplies downstream candidate-key evidence; the checked
Plan retains the assertion before consumers of that evidence. An unconsumed
assertion branch is rejected instead of silently optimized away.

To retain invalid data, classify it using `try_*`, `case`, and separate named
Results. `filter` and deduplication are not substitutes for fatal invariants.
Provider timeouts and unknown Effect outcomes are not row-level invalid data.

### Unicode and total timestamp parsing

```yaml
- derive:
    compatible_name: {nfkc: {field: company_name}}
- derive:
    folded_name: {case_fold: {field: compatible_name}}
    parsed_at:
      try_timestamp:
        value: {field: timestamp_text}
        pattern: {literal: "yyyy-MM-dd HH:mm:ss"}
```

Unicode 16.0.0 tables and their CID are pinned; full default folding is
locale-independent, and both text operators return NFC. Expansion ceilings
are derived from the tables and checked Host policy. `try_timestamp` nulls
invalid input text, not bad patterns or exhausted bounds. UTC remains fixed.
These expressions require a Host claiming the complete text-time profile;
the public checking response reports `unsupported` when checking succeeds but
Host execution is unavailable, without a fallback.

### Complete invoice example

This local program combines exact values, payload construction, and a fatal
uniqueness assertion. It is checked by the documentation example gate:

```yaml
version: actql/0.1
id: row_local.invoice
stages:
  - id: main
    inputs:
      rows:
        carrier: relation
        schema:
          id:
            type: string
            nullable: false
          amount_text:
            type: string
            nullable: false
    from: rows
    steps:
      - derive:
          amount:
            to_decimal:
              value:
                field: amount_text
              precision: 18
              scale: 2
      - derive:
          line_item:
            object:
              invoice_id:
                field: id
              amount:
                field: amount
      - assert_rows:
          unique_by:
            - id
        as: checked_invoices
    results:
      main:
        from: checked_invoices
        fields:
          - id
          - line_item
        order_by:
          - id: asc
results:
  main:
    from:
      stage: main
      result: main
```

Typed Effect outcomes and human selections belong to new Observation/Receipt
artifacts and later Run Graph invocations. They do not mutate a sealed
Invocation or add Program-level `try_effect`, loops, or `catch`.

## Carrier rule

Choose the operation whose carrier matches the input. Relation rows use
`row_window`; event streams use `window_events`:

```yaml
- row_window:
    kind: fixed
    time: occurred_at
    size: 1h

- nearest:
    queries: query_vectors
    candidate_id: product_id
    candidate_vector: embedding
    query_id: request_id
    query_vector: embedding
    metric: cosine
    k: 20
```

Event windows are always closed-open and `nearest` is always exact. Those are
Plan facts, not authoring fields. Write fields
that select among real meanings—window `kind`, vector `metric`, join `kind`, temporal direction, and
business ordering. Do not repeat a one-value validation policy.

Join `cardinality` is normally omitted. The compiler derives `one_to_one`,
`many_to_one`, or `one_to_many` when candidate-key or SourceView Contract
evidence proves the join keys unique on both sides, the right, or the left. If
that evidence does not exist and the business relationship itself guarantees a
cardinality, write it as an assertion; a violation fails before the result is
accepted. Never write `many_to_many` merely because uniqueness is unproven.

Treat `max_items`, `max_output_rows`, aggregate `max_items`, and serialization
`bounds` as optional independent guards. Generate them only when the request
explicitly says “maximum N”, “fail above N”, “blast radius”, or another budget;
never mirror a bound the compiler can already prove from the Program, Contract,
or Host policy. A written guard is preserved even when it is currently
non-binding, and every breach fails atomically rather than truncating output.

Use `to_events`/`events`, `to_vectors`/`vectors`, or
`graph`/`node_rows`/`edge_rows` only when a later step must remain in that
Carrier. These are explicit ActQL operations, not another language layer.

An edge-list relation can become a graph without a separate node table. The
compiler derives the distinct node set from both endpoints:

```yaml
- graph:
    source: caller_service
    target: callee_service
  as: service_graph
- reach:
    start: api_gateway
    direction: out
    max_depth: 2
```

When node metadata matters, use the full `graph.nodes` and `graph.edges` form
from the language specification instead.

## Choices that must be explicit

ActQL never guesses:

- join kind and keys;
- fixed vs sliding window, size, and step; temporal boundaries are fixed by the language;
- vector metric and `k`; nearest-neighbor execution is exact in 0.1;
- graph source, target, traversal direction, or a node-vs-edge row conversion;
- stable business tie-breaks when no retained candidate key proves identity;
- effect operation, selector, target, mapping, and maximum scope;
- one of multiple compatible named inputs.

Use the exact declared operation spelling. Bare `search` and `dedupe` are
unknown operations and are rejected, not interpreted as ambiguity requests.

The complete normative operation inventory is exposed by `actql op
list/show/search` and the Grammar Manifest. Discovery distinguishes language
vocabulary from supported execution profiles. The full language rules are
in the [specification family](spec/README.md).
