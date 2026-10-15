# ActQL — Action Query Language

**The SQL-based data & workflow engine for AI agents.**

Read across SaaS and databases, join the data, decide with an LLM, and write
back. What used to take a workflow SaaS and glue code, you write in SQL and
run reliably as-is. Let a coding agent drive it from the CLI, or embed it in
your TypeScript or Python app as a library.

**In SQL, you describe what data you want, and the database works out how to
get it—optimizing and executing it for you. ActQL extends that to computation
and action across systems.**

## What can you do with ActQL?

ActQL lets you work with the systems you connect—a CRM, a warehouse, files,
SaaS APIs—as if they were one database. For example, join Salesforce accounts
with product usage in Snowflake, let an LLM judge churn risk, and write the
result back to Salesforce—in one SQL pipeline. It's plain SQL, plus `INFER` to
call an LLM and `EFFECT` to write to an external system.

```sql
SELECT a.id AS id, a.description AS notes,
       u.active_users, u.trend
FROM salesforce.accounts AS a
JOIN snowflake.usage_30d AS u ON a.id = u.account_id
|> INFER `model-task:churn-risk.v1`
     INPUT (notes, active_users, trend) AS risk
|> WHERE risk.outcome = 'ok' AND risk.value.level = 'high'
|> RESULT updates
|> EFFECT UPDATE salesforce.Account
     ID id SET (
       Churn_Risk__c = risk.value.level,
       Risk_Reason__c = risk.value.reason
     );
```

- **One program across SaaS APIs, warehouses, and databases.** No separate
  workflow to build for each integration.
- **SaaS rows, warehouse rows, and LLM output share one type system.** Join
  and filter them with plain SQL, and catch mismatches before anything runs.
- **Writes are approved from what will actually be written, and you decide
  how.** Route by record count or target: let low-impact writes run straight
  through, approve some by rule, and send only high-risk ones to a person.
- **If it crashes halfway, it resumes safely.** The Run (one execution) never
  repeats completed work, and writes with an unknown outcome are never blindly
  resent.

## Get started

Install the CLI and try a query:

```sh
npm install -g actql
actql sql "SELECT 1 AS id, 'hello' AS greeting"
```

The [Quickstart](docs/getting-started/quickstart.md) runs the churn-risk
example above against mock Salesforce, Snowflake, and model Connectors—no
credentials needed. The Run pauses before writing to Salesforce and shows
exactly what it is about to change:

```text
$ actql run churn-risk.aql --stop-before commit
Run run_…
  Status      waiting_checkpoint
  Checkpoint  ckpt_…
  Effect      update  (Salesforce Account)
  Items       2
  Changes
    Acme Corp     Churn_Risk__c   low     → high
                  Risk_Reason__c  (empty) → falling usage and a competitor evaluation
    Globex Inc    Churn_Risk__c   medium  → high
                  Risk_Reason__c  (empty) → support tickets about pricing
```

Approve it with `actql approve ckpt_…`, then follow the Run with
`actql status run_…`. This is the same loop a coding agent uses; give the agent
the ActQL skills with `npx skills add actql/skills` and ask it to "Start ActQL
setup".

To embed the engine in your app instead, install `@actql/node` or the `actql`
Python package. See [Install](docs/getting-started/install.md),
[TypeScript and Node](docs/guides/node.md) and [Python](docs/guides/python.md).

## Design principles

- **Any scale.** A Program says only what you want done; the engine decides
  the Plan—where each part runs—just as a database chooses an execution plan
  for your SQL. Each Connector declares what it can compute, and work moves to
  the source (pushdown) without changing what the Program means.
- **A program you can read, instead of nodes.** Acquisition, transformation,
  model inference, and external writes are one text program, top to bottom.
  It diffs, versions, and reviews like code. Authentication, paging, and rate
  limits stay inside each Connector.
- **Embeddable.** Open the engine as a library from TypeScript or Python, with
  no workflow server. Runs persist in your app's directory and resume after a
  crash. Credentials and policy belong to the Host that runs the engine, never
  to the program.
- **AI writes, the engine checks, the Host decides.** The syntax is GoogleSQL
  plus Pipe syntax and a few extensions. Types, required permissions, and
  possible changes are checked before anything runs. Whether a write to an
  external system (an Effect) proceeds is decided by Host policy; a program
  cannot grant itself permission.
- **Beyond tables.** Vector search, graph traversal, and event-sequence
  matching produce typed rows, so they compose with ordinary joins, filters,
  `INFER`, and `EFFECT`.

The [Concepts](docs/concepts/overview.md) pages explain each of these in full.

## Documentation

- [Install](docs/getting-started/install.md) and
  [Quickstart](docs/getting-started/quickstart.md)
- [Concepts](docs/concepts/overview.md): the ideas behind Programs, Runs,
  Effects, and Hosts
- [Writing Programs](docs/authoring.md) and the
  [Syntax reference](docs/reference/syntax.md)
- [CLI reference](docs/cli.md)
- [Connectors](docs/connectors/README.md)
- [Limits and compatibility](docs/reference/limits.md): what runs today
- [Specification](docs/spec/README.md): the normative definition of ActQL 0.1
- [Contributing](docs/contributing/README.md) and
  [Development](docs/development.md)

The same documentation is published at [actql.com/docs](https://actql.com/docs).

## Status

ActQL is in 0.1 stabilization (`v0.0-alpha`). The documentation describes the
0.1 language; [Limits and compatibility](docs/reference/limits.md) records
which parts run in each environment today.

## Contributing

Issues and design proposals are welcome. During 0.1 stabilization, please open
an issue before implementation so language and compatibility impact can be
agreed before code is written.

## License

Apache License 2.0. See [LICENSE](LICENSE).
