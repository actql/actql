# Install

ActQL lets you work with the systems you connect — a CRM, a warehouse, files,
SaaS APIs — as if they were one database: you read and join them with SQL, and
write back through Effects you can review before they are applied.

ActQL ships as a command-line tool, a TypeScript/Node library and a Python
library. They all run the same engine; pick the one that fits where you want
Programs to run. This page gets each of them onto your machine and tells you
where ActQL keeps its state.

## Requirements

| Surface | Needs |
| --- | --- |
| CLI and Node library | Node.js 22 or later |
| Python library | Python 3.11 or later |

The engine itself is bundled; there is nothing else to install, no server to
run and no account to create. Connectors for external systems need credentials
only when you configure a connection to a real system — the mock profile used
by the [Quickstart](quickstart.md) needs none.

## CLI

```sh
npm install -g actql
actql version
```

Try a query straight away:

```text
$ actql sql "SELECT 1 AS id, 'hello' AS greeting"
id  greeting
--  --------
1   hello
```

`actql sql` runs a read-only query and prints the rows. Programs that write go
through `actql run`, which can stop for approval. The
[CLI reference](../cli.md) covers both, along with approving Checkpoints,
following Runs and listing what your Connectors expose.

## TypeScript and Node

```sh
npm install @actql/node
```

`@actql/node` embeds the engine in your application. It also contains the
client for a remote Host, so the same code reaches a server or ActQL Cloud by
changing connection options. See [TypeScript and Node](../guides/node.md).

`open()` returns a handle you query like a database, which is why the examples
call it `db`. It only reads; Programs that write use the full client from
`connect()`.

```ts
import {open} from '@actql/node';

const db = await open({stateDir: '.actql'});
try {
  console.log(await db.sql('SELECT 1 AS id').all()); // [ { id: 1 } ]
} finally {
  await db.close();
}
```

## Python

```sh
uv add actql
# or
pip install actql
```

```python
import actql

with actql.open(state_dir=".actql") as db:
    print(db.sql("SELECT 1 AS id").all())  # [{'id': 1}]
```

See [Python](../guides/python.md).

## Skills for coding agents

If a coding agent will write Programs for you, give it the ActQL skills. They
teach the agent the language, the CLI and the review loop:

```sh
npx skills add actql/skills
```

Then ask the agent to "Start ActQL setup". The skills reference the
[Writing Programs](../authoring.md) guide and the [CLI reference](../cli.md).

## Where state lives

Every surface keeps its durable state — Runs, captured observations,
Checkpoints, Results — in a directory. The CLI uses `state_dir` from
`actql.config.json` (default `./.actql`); the libraries take it from
`installation.directory` or `stateDir`. Keep that directory out of version
control and back it up like a database: it is what lets a Run resume after a
crash and what `status` reads.

## Next

- [Quickstart](quickstart.md): run the churn-risk Program against mock
  systems, approve its Checkpoint and read the result.
- [Local and remote Hosts](../guides/hosts.md): connections, credentials and
  policy for real systems.
