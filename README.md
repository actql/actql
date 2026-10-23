# ActQL

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

**The SQL-based data & workflow engine for AI agents.**

Read across SaaS, databases, and files, join and transform the data, and
write results back. When a judgment is needed, an LLM makes it inside the same
program. What used to take a workflow SaaS and glue code, you write in SQL and
run reliably as-is—from the CLI, by you or by a coding agent, or embedded in
your TypeScript or Python app as a library.

**ActQL lets you work with the systems you connect—a CRM, files, SaaS APIs, a
warehouse—as if they were one database.**

## 1. What can you do with ActQL?

Take meeting notes in Google Drive and the deals they belong to in Salesforce.
Read each deal's latest notes, let an LLM decide whether the stage or the next
step has changed, and write the update back to Salesforce—in one SQL pipeline.
It's plain SQL, plus `INFER` to call an LLM and `EFFECT` to write to an
external system. This example uses both; a query that only returns a table, or
a workflow with no LLM in it, is the same kind of program without those steps.

```sql
SELECT o.id AS id, o.StageName, o.NextStep,
       c.content AS notes
FROM salesforce.opportunities AS o
JOIN drive.files AS f ON f.name = o.name
JOIN drive.contents AS c USING (resource, version)
|> INFER `model-task:deal-review.v1`
     INPUT (StageName, NextStep, notes) AS review
|> WHERE review.outcome = 'ok' AND review.value.changed
|> RESULT updates
|> EFFECT UPDATE salesforce.Opportunity
     ID id SET (
       StageName = review.value.stage,
       NextStep = review.value.next_step
     );
```

```text
salesforce.opportunities ─┐
                          ├─► JOIN ─► INFER ─► WHERE ─► EFFECT ─► Salesforce
drive.contents (notes)   ─┘             │                 │
                                        │                 └─ paused at Checkpoint
                                        │                    until approved
                                        └─ typed result
```

- **One program across SaaS APIs, warehouses, and databases.** No separate
  workflow to build for each integration.
- **SaaS rows, warehouse rows, and LLM output share one type system.** Join
  and filter them with plain SQL, and catch mismatches before anything runs.
- **Writes are approved from what will actually be written, and you decide
  how.** Route by record count or target: let low-impact writes run straight
  through, approve some by rule, and send only high-risk ones to a person
  ([see below](#ai-native)).
- **If it crashes halfway, it resumes safely.** The Run (one execution) never
  repeats completed work, and writes with an unknown outcome are never blindly
  resent.
- **Open source, and it starts on your machine.** Apache 2.0, so
  authentication, retries, resuming, and the checks before a write are all
  code you can read here. Like SQLite or DuckDB, it runs from the CLI or as a
  library: no server to stand up, no account to create.

## 2. Get started

### 2.1 Run the deal-review example from the CLI

Install the CLI, create the example project, and run it against mock
Salesforce and Google Drive Connectors and a mock model—no credentials needed:

```sh
npm install -g actql
actql init --template deal-review-mock deal-review && cd deal-review
actql run deal-review.aql --stop-before commit
```

<a id="checkpoint-example"></a>

The Run pauses before writing to Salesforce and shows exactly what it is
about to change:

```text
Run run_...
  Status      waiting_checkpoint
  Checkpoint  ckpt_...
  Effect      update  (Salesforce Opportunity)
  Items       2
  Changes
    Acme Corp - Renewal   StageName  Proposal      → Negotiation
                          NextStep   (empty)       → Send revised pricing by Friday
    Globex - Expansion    StageName  Negotiation   → Closed Lost
                          NextStep   Legal review  → Revisit next fiscal year
```

Approve it, then check the Run's status:

```sh
actql approve '<checkpoint-id>'
actql status '<run-id>'
```

This is the same loop a coding agent uses. Before running, `check` validates
the program and `explain` shows the plan (`--json` for structured output). To
teach a coding agent how to write ActQL, give it the ActQL skills with
`npx skills add actql/skills` and ask it to "Start ActQL setup", or point it
at the [Writing Programs](docs/authoring.md) guide; for every command, see
the [CLI reference](docs/cli.md). The
[Quickstart](docs/getting-started/quickstart.md) walks through every file
and step.

### 2.2 Embed it in your app

Run the same deal-review example from inside your application, as a
library—no workflow server required.

**TypeScript**

```sh
npm install @actql/node
```

```ts
import {readFile} from 'node:fs/promises';
import {connect} from '@actql/node';

const client = await connect({mode: 'local', installation: {directory: '.actql'}, profile: 'mock'});
try {
  const source = await readFile('deal-review.aql', 'utf8');
  const execution = await client.startSource(source, {format: 'aql', stopBefore: 'commit'});
  const state = await execution.wait();
  console.log(state.status); // 'waiting_checkpoint'
} finally {
  await client.close();
}
```

**Python**

```sh
pip install actql
```

```python
import actql

with actql.connect(mode="local", installation=".actql", profile="mock") as client:
    source = open("deal-review.aql").read()
    execution = client.start_source(source, format="aql", stop_before="commit")
    state = execution.wait()
    print(state.status)  # "waiting_checkpoint"
```

Both stop at a Checkpoint just like the CLI example, and a Run started from
code can be approved from the CLI by its Run ID. `.actql` holds the
application's durable state; keep it out of version control. See
[TypeScript and Node](docs/guides/node.md) and [Python](docs/guides/python.md).

## 3. Why build another engine?

ActQL started from four questions about how iPaaS, ETL, and workflow engines
are used today.

### Q1. Why do different data sizes and use cases need different products?

Syncing a few records between SaaS apps calls for an iPaaS. Moving terabytes
calls for ETL. Pushing warehouse data back into SaaS calls for Reverse ETL.
Running something that might fail halfway calls for a workflow engine. Yet
underneath, they all do the same thing: read, compute, write—and keep it
running reliably. One record and a few terabytes need different physical
execution. But do they really need separate products?

### Q2. When AI writes the workflow, why are we still wiring nodes by hand?

Workflow UIs were built for people wiring nodes together in a GUI. When an
agent writes the program, the canvas is no longer where the work happens. And
nodes grow more complex the more you stack them. A handful is easy to follow;
dozens of node settings, mixed with each API's authentication and paging
quirks, make it impossible to see what the whole thing does.

### Q3. Why is embedding a workflow such a big job?

Want SQL in your app? Embed SQLite or DuckDB. Want your app to act on a few
SaaS systems? Suddenly you are running a separate workflow server or SaaS—or
hand-building authentication, state, retries, and recovery yourself.

### Q4. When AI writes the workflow, who checks it?

With AI, workflows and scripts take seconds to write. But no one can read
every one of them to confirm what it will change—or, when something fails,
what was committed and what is unknown.

**Agents write fast, and people read slowly.** That gap does not close by
reading faster. It closes by expressing work in a form machines can check,
run, and authorize—so a person is asked only when a decision actually needs a
person.

## 4. ActQL's answer: five design choices

ActQL answers the four questions above with the following design choices, in
the same order. The fifth goes a step further.

### 4.1 Any scale: the same program, whatever the data size

In SQL, you describe what data you want, and the database works out how to
get it—optimizing and executing it for you. ActQL extends that to computation
and action across systems: a **Program** says only what you want done; the
engine decides the **Plan**—where each part runs.

There is one planning mechanism. A warehouse like Snowflake, a SaaS API like
Salesforce's, and DuckDB all declare what they can compute as Capabilities,
and the engine hands each part of the work to a place that can run it
(**pushdown**). When an API is as flexible as Salesforce's, the engine uses
its Capabilities to the fullest to build the best overall plan. Work no single
source can do, like a JOIN across Salesforce and Snowflake, runs on your
machine: in the built-in engine, or in DuckDB for larger inputs when you use
the package that bundles it. The join itself needs no new warehouse; large
work stays where the data already is, by pushdown.

Take a program that joins Salesforce accounts with usage data in Snowflake,
judges churn risk with an LLM, and writes the result back (the
[Quickstart](docs/getting-started/quickstart.md) example). `actql explain`
shows a plan like this; the join's engine is chosen during the Run, once the
row counts are known:

```text
$ actql explain churn-risk.aql

[1] READ  salesforce.accounts
    Site: connector:salesforce
    Pushdown: selected

[2] READ  snowflake.usage_30d
    Site: connector:snowflake
    Pushdown: selected

[3] JOIN  [1] + [2]
    Site: host:local (fixed)
    Engine: deferred
      Candidates: ActQL RelA, DuckDB

[4] INFER  churn-risk.v1
    Site: model provider

[5] WHERE  on risk
    Site: host:local
    Engine: deferred
    Pushdown: not eligible
      Reason: depends on INFER output

[6] EFFECT UPDATE  salesforce.Account
    Site: connector:salesforce
    Checkpoint: conditional
```

Wherever work moves, the program means the same thing and never slips past
permission boundaries.

With ActQL Cloud, the same program runs in a managed environment—no Host of
your own to operate—and takes on work too large for your local machine.

**The way it runs changes as the data grows. The program you write doesn't.**

### 4.2 Cross-system: a program you can read, instead of nodes

You write data acquisition, transformation, model inference where you need
it, and external writes as one program, top to bottom. To see what the whole
thing does, you read the program.

A text program is also the format agents handle best. You can review it as a
diff, keep its history in Git, and check changes in a pull request—things
that were hard to do with nodes on a canvas.

Each API's authentication, paging, rate limits, and write semantics are
handled inside its Connector. All the program sees are names like
`salesforce.opportunities` and `drive.contents`, so API differences never
leak through the whole program. See [Connectors](#5-connectors) for what is
available.

### 4.3 Embeddable: in your app, no server needed

Just open the engine as a library from TypeScript or Python; the same API
also connects to a remote engine. The core runs on JavaScript, WebAssembly,
and native code, so the same engine goes anywhere from a server to the edge.

You don't build authentication, state, retries, or recovery yourself. Runs
are persisted in your app's directory, so they resume where they left off
even if the process dies. Credentials and policy belong to whatever runs the
engine—the **Host**: your app, the CLI, or a server—never to the program.

- **Product features:** run cross-system actions inside your own app, only
  when a user triggers them. No dedicated workflow platform needed.
- **Local development:** reproduce failures with test Connectors and local
  state, instead of using a production SaaS as a debugger.
- **CI:** check types and contracts on every pull request, and confirm with
  test Connectors that results come out as expected.
- **To production:** move the same program from your machine to a production
  Host. Only the connections, credentials, and policies change.

<a id="ai-native"></a>

### 4.4 AI-native: AI writes, the engine checks, the Host decides

**AI writes.** The syntax is GoogleSQL plus natural extensions to it, so
agents already write it fluently. Supported GoogleSQL syntax works as-is.
Whichever agent framework writes it, it goes through the same model.

**The engine checks.** ActQL is not a DSL that merely looks like SQL. It is
built on relational algebra, defines typed operations for graphs, vectors,
and event sequences as well, and treats data acquisition and external writes
as explicit operations. It is deliberately not Turing-complete, choosing
guaranteed termination and ahead-of-time checkability instead. That is why
types, required permissions, and possible changes can be checked before
anything runs, while input-dependent conditions and actual authorization are
confirmed at run time.

**The Host decides.** Whether any write to an external system (an
**Effect**) runs is always decided by Host policy: let it through, deny it,
or hand it to a decision. For a decision, your code receives the preview and
chooses, per use case, whether to approve it by rule or route it to a person
or an approval application. It decides only whether the write goes ahead; it
cannot change what is written. An agent can never grant itself permission.

A write sent for approval stops at a **Checkpoint** (as in the
[Get started](#checkpoint-example) example), and the reviewer approves the
records and values that will actually be written—not the agent's
description. **What gets written is derived from recorded results, so the
approved writes cannot change before commit.** And a write with an unknown
outcome is never blindly resent; it is confirmed through the Connector before
moving on.

Handing over trust step by step—a person checks everything at first, and
stable programs move to unattended runs—works on this same model.

### 4.5 Beyond tables: vector search and graphs in the same program

Vector search, graph traversal, and event-sequence matching also produce
typed rows, so they compose directly with ordinary joins, filters, `INFER`,
and `EFFECT`. For example, find the three most similar knowledge-base
articles for each urgent case and hand them to `INFER` to draft a reply:

```sql
SELECT c.id, c.description AS question, c.embedding AS query_vec
FROM salesforce.cases AS c
WHERE c.priority = 'urgent'
|> NEAREST kb.articles USING (query_vec) K 3 AS hit
|> AGGREGATE ARRAY_AGG(hit.body ORDER BY hit.rank) AS refs
     GROUP BY id, question
|> INFER `model-task:draft-reply.v1`
     INPUT (question, refs) AS draft
```

That is retrieval-augmented generation, with no separate search stack or glue
code.

Just as tables follow GoogleSQL, graph traversal adopts graph-pattern syntax
informed by the ISO standards GQL and SQL/PGQ, so relationship
graphs—customers, accounts, products—and business ontologies modeled as
graphs can be queried alongside ordinary SQL. (Under the hood, relations,
graphs, vectors, and event sequences are handled as one system through four
algebras: RelA, SGA, VecA, and TEA.)

## 5. Connectors

Every Connector below both reads and writes.

| | |
| --- | --- |
| Databases & warehouses | Snowflake · BigQuery · DuckDB |
| SaaS | Salesforce · HubSpot · Slack · Notion · kintone · GitHub · Tableau |
| Google | Google Sheets · Google Drive · Gmail · Google Calendar |
| Storage & files | Amazon S3 · Google Cloud Storage · local files |

Each Connector's sources, Effects, operations and setup are on its page under
[Connectors](docs/connectors/README.md). Need another system? Build the
Connector from the [Building a Connector](docs/connectors/authoring.md)
guide—yourself, or with a coding agent and the Skills that reference it.

## 6. How ActQL relates to existing tools

ActQL's relationship to existing tools falls into three kinds: tools to
choose between, tools to combine with, and tools to hand work to.

### Choose between

| Tool | When it fits | When ActQL fits |
| --- | --- | --- |
| Custom scripts (Python, TypeScript) | Quickly writing a one-off, small integration | Running it over time, with retries, recovery, approval, and permissions handled |
| iPaaS (n8n, Zapier) | Quickly connecting a few SaaS apps in a GUI | Keeping the whole picture clear as integrations grow, letting agents write it, embedding it in your own app, running writes with approval |
| Reverse ETL (Census, Hightouch) | Regularly syncing modeled warehouse data to SaaS in a fixed shape | Joining with SaaS data or deciding with an LLM before writing back with approval |

### Combine with

| Tool | How they work together |
| --- | --- |
| Workflow engines (Temporal) | Not a replacement for Temporal. Temporal manages long-running jobs that last days; ActQL handles the cross-system reads and writes as one step inside them |
| dbt | Models, dependencies, and tests stay in dbt. ActQL programs use the modeled data alongside SaaS data, for cross-system queries and writes; the planned dbt-actql adapter will also let dbt run supported models through ActQL |
| Agent frameworks (LangGraph, Mastra) | Build the agent itself with the framework; hand the checks, approvals, and execution of the work it writes to ActQL. ActQL programs can be called as tools from an agent |

### Hand work to

| Tool | How they work together |
| --- | --- |
| Data warehouses (Snowflake) | Not replaced—large-scale computation is pushed down to the warehouse |
| Embedded databases (DuckDB, SQLite) | The same embedding model, extended to cross-system work. DuckDB is also a pushdown target for work no single source can do |

## Documentation

- [Install](docs/getting-started/install.md) and
  [Quickstart](docs/getting-started/quickstart.md)
- [Concepts](docs/concepts/overview.md): the ideas behind Programs, Runs,
  Effects, and Hosts
- [Writing Programs](docs/authoring.md) and the
  [Syntax reference](docs/reference/syntax.md)
- [CLI reference](docs/cli.md)
- [Connectors](docs/connectors/README.md)
- [Implementation status](docs/reference/status.md): what runs today, and
  [Runtime limits](docs/reference/limits.md)
- [Specification](docs/spec/README.md): the normative definition of ActQL 0.1
- [Development](docs/contributing/README.md): the repository, its rules and
  how it is implemented; [building from source](docs/development.md)

The same documentation is published at [actql.com/docs](https://actql.com/docs).

## Status

ActQL is in v0.1 stabilization (`v0.0-alpha`). The documentation describes the
0.1 language; [Implementation status](docs/reference/status.md) records
which parts run in each environment today.

## Contributing

Issues are open: bug reports, passages of the specification that were hard to
read, and facts about a Connector's system are the most useful contributions
right now. Pull requests are not accepted during v0.1, while the maintainers
concentrate on stabilising the Core; [Development](docs/contributing/README.md)
has the details. The ecosystem around ActQL (Connectors, SDKs, templates,
tools) is where contributions are welcome broadly.

## License

Apache License 2.0. See [LICENSE](LICENSE).
