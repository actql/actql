# Language design

ActQL's foundation is SQL. This page explains the choices behind its syntax
and what the language deliberately leaves out.

## SQL, read top to bottom

ActQL builds on GoogleSQL — the SQL dialect used by BigQuery — and its
**Pipe syntax**. A pipeline starts from a source and applies one step at a
time; every later step is introduced by `|>`:

```sql
FROM support.cases AS c
|> WHERE c.status = 'open'
|> AGGREGATE COUNT(*) AS open_cases GROUP BY c.account_id
|> ORDER BY open_cases DESC
|> LIMIT 10
```

People and agents build a query the same way: start from the data, then add
one transformation at a time. Pipes let you write it in that order, and each
step can be read, checked and explained on its own. Ordinary SQL —
`SELECT … FROM … WHERE …`, `WITH`, `JOIN` — works as well, and a query can
switch to pipes at any point. Existing SQL knowledge, and the ability to
generate SQL, carry over as they are.

A pipeline describes how the steps depend on each other, not the order in
which they physically run. ActQL keeps the meaning — results, permissions,
failure behaviour — and is free to reorder steps or hand them to a Connector:
a filter written after a join may well run inside the source system before
the join. That is how a Program stays readable from top to bottom without
giving up any room for optimisation.

## Standard spellings keep standard meaning

Where SQL already has a spelling for something, ActQL uses it with its standard
meaning: a `LEFT JOIN` is a left join, `NULL` behaves as SQL's `NULL`, and
grouping, ordering and set operations follow the selected GoogleSQL profile.
ActQL does not claim full conformance with GoogleSQL, SQL/PGQ or ISO GQL; it
claims that the parts it accepts mean what they mean there.

ActQL never changes the meaning of existing syntax. It adds only what its own
features and boundaries need:

- **Graphs** — `GRAPH (…)` builds a graph from tables, and `MATCH` patterns in
  the style of GQL query it. Beyond pattern matching, ActQL defines its own
  typed graph operations: reachability, path finding, connected components,
  and combining, comparing and diffing whole graphs. Their results can be
  turned into Relations explicitly and combined with ordinary SQL.
- **Vectors and events** — named operations over typed vectors and event
  streams, with signatures modelled on existing SQL extensions for vector
  and time-series data.
- **Models** — `INFER` calls a model through a versioned model task and
  returns a typed result.
- **Effects** — explicit changes to external systems. Every Effect is decided
  by policy, and waits for approval when policy requires it. You can write
  them as an `EFFECT` step, as in the [Concepts](overview.md#programs)
  example, or in the familiar SQL forms:

  ```sql
  UPDATE salesforce.Account
  SET Churn_Risk__c = 'high'
  WHERE Id = @account_id;
  ```

  Both forms are the same Effect: previewed, decided and recorded in the
  same way.

## One system of types and operations

ActQL defines data processing as typed algebraic operations. For each of its
four kinds of value — Relation, Graph, Vectors and Events — the available
operations and the meaning of their results are fixed. This is not SQL with
features bolted on: a graph match, a nearest-neighbour search and a window
over events are operations in the same system as a join.

Combining kinds is explicit. Turn a graph match into a Relation, and from
there on ordinary SQL applies: join it, aggregate it, hand it to `INFER`,
write it back with `EFFECT`.

All of these operations go through the same type checking and the same
planning. The engine can change where and how an operation runs precisely
because each operation's meaning is defined independently of its placement.

## Computation, observation and change are kept apart

ActQL distinguishes three kinds of work:

| Kind | Examples | Meaning |
| --- | --- | --- |
| Pure computation | `SELECT`, `JOIN`, `AGGREGATE` | Computes values from inputs it already has |
| Observation | Reading through a Connector, `INFER` | Brings new values in from an external system or a model, as they are at that moment |
| Change | `EFFECT` | Changes the state of an external system |

A computation is a function of its inputs. An observation is not: it is
recorded as a fact seen at that moment, which is what lets a Run reuse a
model's answer on recovery instead of asking again. A change goes through
the policy, preview and outcome machinery described in
[Concepts](overview.md#effects-and-policy).

Observations and changes cross a boundary where types, permissions, limits
and outcomes are checked. Because the boundary is explicit, the engine can
optimise computation freely while keeping approval and recovery exact for
everything outside it.

This also means SQL is never forwarded to an external system as text. A
Program is translated into one common typed representation and checked
there. When part of it is handed to a Connector, that happens only after the
Connector's capabilities and the preservation of meaning have been verified.

## One way to name intermediate results

`WITH name AS (…)` names an intermediate value of any kind — rows, a graph,
vectors or events — and later steps refer to it by name:

```sql
WITH open_cases AS (
  FROM support.cases |> WHERE status = 'open'
)
SELECT account_id, COUNT(*) AS n
FROM open_cases
GROUP BY account_id;
```

Naming, publishing and changing are three different things:

- `WITH` names a value inside the Program. Naming it reads nothing and
  publishes nothing; if the value is needed at run time, it is fetched then.
- `RESULT` publishes a value as a named output of the Program.
- `EFFECT` declares a change to an external system.

## Explicit where it matters, short where it is clear

ActQL fills in what you leave out only when the types and the definitions
involved determine it uniquely. `INFER` keeps the input columns and adds the
answer next to them, so you do not repeat the columns you want to keep; a key
may be left out when exactly one candidate can be proved. Where more than one
reading is possible, ActQL does not pick one — it asks you to say which. It
does not infer a key from a column's name, convert one kind of value into
another unasked, or turn one kind of join into another. An explicit clause
always overrides a default.

Unsupported features are refused at check time, with a stable, named error.
What can only be known from the data — an input value out of range, a limit
exceeded — is caught at run time, and stops the work rather than bending it.
In neither case does the compiler:

- invent an operation;
- silently drop an input or a field;
- replace exact computation with an approximation;
- substitute processing time for event time;
- return an empty result in place of unsupported behaviour.

## Meaning is identified independently of its text

ActQL translates the SQL you write into its common typed representation and
normalises it by fixed rules. The Program's meaning, one execution's concrete
inputs, the observations it made and its Run record each get their own
identifier.

This is what makes "what ran", "which inputs this Result came from" and
"which changes were approved" separate, answerable questions. The meaning of
a Program is defined apart from how its text is laid out and where it runs.

## No escape hatches

ActQL has no user-defined functions, lambdas, inline JavaScript or Python, or
raw HTTP. This is deliberate. ActQL is not Turing-complete: it allows no
arbitrary loops or recursion and no code whose meaning is decided at run time,
and it requires every operation to have a checkable definition and finite
resource limits. A Program therefore cannot create unbounded work by itself.
That is not a promise that every Run completes normally — external systems
may not answer, approvals may not come, limits may be exceeded — but
whatever happens is recorded and recoverable.

Every operation has a defined meaning for its types, its limits and its
ordering, so the planner can push it down to another system, the Run can
replay it, and a reviewer can see from the preview exactly which changes they
are approving — and ActQL checks the conditions again when applying, so a
stale approval is never reused. Opaque code would break each of those
guarantees.

Connectors and model tasks are how new capabilities enter: each comes with a
typed, versioned definition that the checker and planner understand.

## Limits are fixed before running and enforced while running

A runnable Program has a ceiling for everything that is a quantity — rows,
bytes, model calls, Effects. Some ceilings come from the systems involved,
some from the Host's policy, and authors can add their own (guards); you do
not have to write every limit into the Program yourself. All of them are
fixed before the work they apply to starts, and enforced while it runs:
exceeding a ceiling fails the protected work with an error, and never
silently truncates the data. Long-running, interactive or continuous
processing is out of scope for a Program: a Program is a finite unit of work
that can be checked, planned, approved and recovered.

## Next

- [Concepts](overview.md): Programs, Runs, Effects and Checkpoints.
- [Architecture](architecture.md): how a Program is checked, planned and run.
- [Query text specification](../spec/query-text.md): the exact SQL/Pipe grammar.
