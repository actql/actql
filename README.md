# ActQL — Action Query Language

*Declare the work. Check the plan. Approve the effects.*

Agents write fast and people read slowly. Once an agent can touch production
systems, the bottleneck is no longer writing code, but understanding and
authorizing what it will read, send, spend, or change.

ActQL is a typed, declarative language for transforming data and taking action
across systems.

Instead of writing glue code that reads from APIs and databases, transforms
data, and writes back, you declare the whole operation as one program that can
be inspected before it runs.

Like SQL, ActQL separates meaning from execution and is built on an algebra. You
declare what should happen; the runtime decides how and where to do it. Unlike
SQL, that algebra covers graphs, vectors, and event streams as well as tables,
and one program spans several databases and APIs.

Changes to those systems are declared in the same program, as Effects. The
program is checked before it runs. During a Run, the runtime checks each
external boundary against current permissions and policy. When human review is
required, the Run pauses at a Checkpoint and resumes from the same point once
approved.

**Designed for programs an agent writes and a human approves.**

## Quickstart

Install the CLI into your project, and the Skill pack that teaches a coding
agent the same grammar the CLI accepts:

```bash
npm install @smoothhq/actql
npx skills add actql/skills
npx actql doctor
```

`doctor` checks that the CLI and installed Skill pack agree.

### Run a query

Save this input as `orders.jsonl`:

```jsonl
{"id":"o1","customer_id":"c1","status":"open","amount":120}
{"id":"o2","customer_id":"c1","status":"closed","amount":30}
{"id":"o3","customer_id":"c2","status":"open","amount":80}
```

Save this program as `query.aql`:

```yaml
version: actql/0.1
id: customer.open_orders
stages:
  - id: main
    inputs:
      orders:
        carrier: relation
        schema:
          id: { type: string, nullable: false }
          customer_id: { type: string, nullable: false }
          status: { type: string, nullable: false }
          amount: { type: number, nullable: false }
        primary_key: [ id ]
    from: orders
    steps:
      - filter: "status = 'open'"
      - group:
          by: [ customer_id ]
          aggregates:
            order_count: { fn: count }
            total_amount: { fn: sum, field: amount }
        as: customer_totals
    results:
      main:
        from: customer_totals
        fields: [ customer_id, order_count, total_amount ]
        order_by: [ { total_amount: desc }, { customer_id: asc } ]
results:
  main:
    from: { stage: main, result: main }
```

Optionally check it, then run it:

```bash
npx actql check query.aql
npx actql run query.aql \
  --input orders=orders.jsonl \
  --output answer.jsonl \
  --receipt run.json
```

`answer.jsonl` contains:

```jsonl
{"customer_id":"c1","order_count":1,"total_amount":120}
{"customer_id":"c2","order_count":1,"total_amount":80}
```

`check` validates the Program against supplied contracts without reading input
data. It is optional: `run` performs its own checking. Run accepts a Program,
not a saved Plan.

### Approve a change

The packaged local example adds one Effect and exercises the complete approval
loop without a provider account. It uses the bundled local JSONL Connector and
sets up a temporary local approval key:

```bash
cp -R node_modules/@smoothhq/actql/examples/actql/approval-quickstart .
cd approval-quickstart
node setup.mjs
```

The program publishes the requested record as its result and declares the
update separately as an Effect:

```yaml
version: actql/0.1
id: quickstart.approved_update
stages:
  - id: main
    inputs:
      desired:
        carrier: relation
        schema:
          id: { type: string, nullable: false }
          value: { type: number, nullable: false }
        primary_key: [ id ]
    from: desired
    steps: []
    results:
      main:
        from: desired
        fields: [ id, value ]
        order_by: [ { id: asc } ]
    effects:
      update_record:
        update:
          target: connector://quickstart/main/Records
          mapping: mapping:quickstart.records.v1
          from: { result: main }
          id: id
          set:
            value: { field: value }
results:
  main:
    from: { stage: main, result: main }
```

Optionally check the program, then start one durable Run:

```bash
npx actql check update-record.aql
npx actql run update-record.aql \
  --input desired=desired.jsonl \
  --json
```

The Run stops before changing `records.jsonl` and returns
`status: waiting_checkpoint` with its Run and Checkpoint IDs. Use those IDs to
inspect the exact review view stored at the Checkpoint:

```bash
npx actql status '<run-id>'
```

```text
Run run_...
  Status      waiting_checkpoint
  Checkpoint  checkpoint_...
  Phase       commit
  Reason      Review the complete 1-member Effect Set before commit.

Review
  Effect      update_record
    Operation update
    Target    connector://quickstart/main/Records
    Items     1
    Changes
      r1
        Before {"value":1}
        After  {"value":42}
  Permissions Records.write
```

Approve that Checkpoint and read the result:

```bash
npx actql approve '<checkpoint-id>' \
  --signer quickstart-approver \
  --wait \
  --json
npx actql result '<run-id>'
```

The final command prints:

```jsonl
{"id":"r1","value":42}
```

See the [CLI reference](docs/cli.md) for approval and recovery.

## Built for software written by agents

Today the usual way to let an agent run code at all is a sandbox: it constrains
arbitrary code inside an execution environment. That can protect the host, but
it does not by itself explain or govern what authorized code will do to
production systems. You can discard the sandbox; the production records it
changed remain changed.

A typed SDK can make each call well-formed, but it cannot say what a program
will have read, sent, or changed by the end; with loops and branches, that is
known only by running it. In ActQL, every read, every write, and every bound is
a declaration. The compiler checks all stage templates before execution and
materializes each stage's concrete Plan when its required inputs are available.

The compiler reads the whole program. A person reads only what the Run is about
to do when it pauses: what will be read, sent, spent, or changed. For an Effect,
that is which records, how many, and from what to what. It comes from the actual
Run, not from the agent's description of its code.

## A real-world program

That was a local query and one approved change. Here is the same language
across three systems: find the largest open Salesforce renewals, enrich them
with current product usage from Snowflake, update the opportunities at risk,
and notify Slack.

```yaml
version: actql/0.1
id: revenue.renewal_risk
stages:
  - id: main
    inputs:
      opportunities: { connector: salesforce/main, resource: Opportunity, view: open_renewals }
      account_usage: { connector: snowflake/main, resource: account_usage, view: latest_by_account }
    from: opportunities
    steps:
      - filter: amount >= 100000
      - top_k:
          k: 100
          by: [ { amount: desc }, { id: asc } ]
        as: renewal_candidates
      - join:
          with: account_usage
          kind: left
          on: [ account_id ]
          null_key: fail
          select:
            opportunity_id: left.id
            account_id: left.account_id
            opportunity_name: left.name
            amount: left.amount
            close_date: left.close_date
            active_users_30d: right.active_users_30d
      - filter: active_users_30d < 5
      - derive:
          risk_status: "'At risk'"
          slack_channel: "'C012RENEWALS'"
          slack_message: "opportunity_name || ' is at risk: fewer than 5 active users in 30 days'"
        as: renewal_actions
    results:
      response:
        from: renewal_actions
        fields: [ opportunity_id, opportunity_name, amount, close_date, active_users_30d ]
        order_by: [ { amount: desc }, { opportunity_id: asc } ]
      crm_updates:
        from: renewal_actions
        fields: [ opportunity_id, risk_status ]
      slack_alerts:
        from: renewal_actions
        fields: [ slack_channel, slack_message, opportunity_id ]
    effects:
      mark_opportunities_at_risk:
        update:
          target: connector://salesforce/main/Opportunity
          mapping: mapping:salesforce.opportunity-risk.v1
          from: { result: crm_updates }
          id: opportunity_id
          set:
            Renewal_Risk__c: { field: risk_status }
  - id: notify
    inputs:
      alerts: { result: { stage: main, result: slack_alerts } }
    from: alerts
    steps: []
    results:
      slack_alerts:
        from: alerts
        fields: [ slack_channel, slack_message, opportunity_id ]
        order_by: [ { opportunity_id: asc } ]
    effects:
      notify_revenue_team:
        create:
          target: connector://slack/main/Message
          mapping: mapping:slack.message.v1
          from: { result: slack_alerts }
results:
  response:
    from: { stage: main, result: response }
```

The author writes an ordinary join across systems. Because `top_k` proves the
left side is at most 100 rows, the compiler can turn the Snowflake side into a
bounded acquisition: deduplicate the keys, fetch them in batches or push the
filter down, then join locally. Call counts, paging, and limits live in the
Plan, not the source. If the bound cannot be proved, `check` fails before
contacting either system.

## Effects

An Effect is a declared change to an external system. ActQL supports checked
`create`, `update`, `upsert`, `delete`, `command`, and `store`. A `command` is
a typed operation the Connector owns, rather than a write to a record:

```yaml
effects:
  reply:
    command:
      from: {result: replies}
      target: {field: thread_ref}
      contract: command:gmail.reply.v1
      input:
        body: {literal: Thanks}
```

Effects are built from the Run's own results, not by reading the sources again,
and review-required Effects wait until their Checkpoint is approved. The data behind the
review view can contain production values, so production runtimes must store and
transfer it encrypted.

Each logical item has a stable identity for recovery. Dispatch uses the recorded
Preview and idempotency key, backed by a Connector's admitted idempotency or
reconciliation guarantee. A durable ledger alone cannot make an ambiguous write
safe to repeat. An intentional resend uses a new logical request identity.

## Beyond tables

Event sequences, graph traversal, vector search, and model tasks return
relations, so `filter`, `join`, and Effects work on their results like any other
step. Excerpts from an incident-response program:

**Event sequences.** Detect an alert followed by a remediation, per incident,
within two hours:

```yaml
  - sequence:
      by: [incident_id]
      time: occurred_at
      id: event_id
      pattern:
        - as: opened
          where: {eq: [{field: kind}, {literal: alert_opened}]}
        - as: remediation
          where: {eq: [{field: kind}, {literal: remediation_started}]}
      within: 2h
      contiguity: subsequence
      overlap: disallow
    as: detected_sequences
```

**Graph traversal.** Build a typed dependency graph and expand the downstream
blast radius from the services that alerted:

```yaml
  - from: services
    graph:
      nodes:
        from: services
        id: service_id
        fields: [service_name, tier]
      edges:
        from: dependencies
        source: upstream_service_id
        target: downstream_service_id
        label: dependency_kind
    as: service_graph

  - from: service_graph
    traverse:
      start: {from: impacted_services, id: service_id}
      edge_types: [calls, publishes]
      direction: out
      min_hops: 1
      max_hops: 3
      emit: nodes
    as: blast_radius
```

**Vector search.** Rank active runbooks against the original alert embedding:

```yaml
  - from: active_runbooks
    nearest:
      queries: incident_queries
      query_id: alert_event_id
      query_vector: embedding
      candidate_id: runbook_id
      candidate_vector: embedding
      metric: cosine
      k: 3
    as: runbook_rankings
```

All three return relations, so they join together in one program: which
incidents went from alert to remediation, what those services touch downstream,
and which runbook fits the original alert.

**LLM structuring.** Turn ticket text into typed rows under a versioned
model-task contract:

```yaml
  - infer:
      contract: model-task:ticket-triage.v1
      input:
        subject: {field: subject}
        body: {field: body}
    as: ticket_triage
```

The contract fixes the prompt, model selector, input and output schemas, and
data-handling policy. Its result is a separate relation keyed by the input
identity, so source fields return only through an explicit join.

## One program, different execution plans

ActQL describes the work without fixing where each step must run. The program
states its meaning and each Connector declares what it can compute, so a runtime
can tell which parts may be pushed down to the source: a filter or an aggregation
can run where the data lives instead of after it has been copied into the
application; what the source cannot compute runs in the runtime itself. You do
not rewrite the integration to move work closer to the data.

Which plan runs is the runtime's decision. Each runtime owns execution,
authentication, and provider scheduling. Whatever plan it picks must preserve
the same semantics, the same permission boundaries, and the same Checkpoints.
Checking and pushdown come from the same fact: the program says what it means,
so it can be inspected before it runs and moved without changing what it does.

The same runtime is designed to ship as the `actql` CLI and as TypeScript and
Python bindings, so a program runs from the command line or inside an
application. The core targets WebAssembly, JavaScript, and native code, so the
design also reaches browser, edge, and managed runtimes.

## Documentation

- [Language specification](docs/spec/language.md) — normative syntax and semantics
- [Agent authoring guide](docs/authoring.md) — canonical source patterns
- [CLI reference](docs/cli.md) — commands, durable Runs, and Checkpoints
- [Development](docs/development.md) — setup, document checks, and versioning

## Contributing

Issues and design proposals are welcome. During 0.1 stabilization, please open
an issue before implementation so language and compatibility impact can be
agreed before code is written.

## License

Apache License 2.0. See [LICENSE](LICENSE).
