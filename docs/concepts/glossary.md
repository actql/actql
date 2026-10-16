# Glossary

The main technical terms, and the role names used to explain them, one line
each. The [specification](../spec/README.md) holds the precise definitions;
where the two differ, the specification is right.

| Term | Meaning |
| --- | --- |
| **Author** | The person or agent who writes a Program. |
| **Capability** | What a Connector can offer on behalf of its system: the reads and writes it supports, and what the system can compute itself. The basis for pushdown. Not a permission. |
| **Carrier** | A kind of typed collection that operations work on: Relation, Graph, Vectors or Events. See [Beyond tables](overview.md#beyond-tables). |
| **Checkpoint** | A durable stop where protected work waits for a decision, with what is being decided and how the Run continues both fixed. Can also occur during preparation, before a Run starts. |
| **CID** | An identifier computed from normalised content. Distinguishes a Program's meaning, a Plan, an observation and a Preview from one another. |
| **Connector** | The component that connects ActQL to one external system and declares its sources, capabilities and Effects. |
| **Core** | The part of ActQL that owns meaning: it checks, plans and computes, and runs the Run state machine. |
| **Decider** | Whoever answers a delegated policy decision: a person, an automatic rule, an approval application, or a combination. |
| **Effect** | A declared operation that changes the state of an external system — update, insert, delete, a typed command, a store. Applying it requires the Host's permission. |
| **Effect outcome** | What became of one operation sent for an Effect: `applied`, `accepted`, `failed` or `unknown`. Items never sent are `unattempted`; an item undone after a failure is `rolled_back`. An Effect with several items records one outcome per item and can end partly applied. |
| **Guard** | A limit the author adds to a Program on top of those set by the systems and the Host. |
| **Host** | The part that runs ActQL in your environment and holds policy, credentials and the Store. Embedded in an application, behind the CLI, on a server; ActQL Cloud is a managed Host. |
| **INFER** | The stage that gives each row's model-task inputs to a model and returns a typed answer per row. |
| **Invocation** | The semantic input to one unit of computation: its bound values, the definitions it relies on and the observations it has captured. A Program with several stages has one Invocation per stage. |
| **Limit** | A ceiling on a quantity — rows, bytes, calls, Effects — fixed before the work it applies to starts. Exceeding it fails the work with an error. |
| **Model task** | A versioned definition of what to ask a model: the instructions, the input types and the output types. A Program refers to it by name in `INFER`. |
| **Operator** | Whoever runs a Host and sets up its connections, credentials and policy. |
| **Plan** | The execution contract the Core builds from a checked Program: operations, types, the boundaries of external work and the limits. Where and how each part physically runs is chosen within that meaning. |
| **Policy** | Host configuration that answers, per user, connection, resource and operation, whether a read, model call or Effect is allowed, denied or delegated. |
| **Preview** | The targets and changes an Effect would apply, fixed from recorded results before anything is written. Whether the current values are shown too depends on the Connector. |
| **Program** | One piece of work written in ActQL: reads, computation, model calls, Results and Effects. |
| **Pushdown** | Handing part of the work to the external system that holds the data, when results, failure behaviour, permissions and the scope of observed data all stay the same. |
| **Reconciliation** | Resolving an unknown outcome — of a Run or of an Effect — from the evidence of the original operation. May remain unresolved; never resends without evidence. |
| **Result** | A named output a Program publishes. It is kept and can be read by the caller, or by later work, with the required permission. |
| **Run** | One execution of a Program and its durable record: what was read, which answers were received, what was sent and what was decided. |
| **Source** | Where a Program reads from: a Connector's SourceView, or typed data handed to the Program locally. |
| **SourceView** | A Connector's versioned contract for one resource: its types, how it is read, and its constraints. |
| **Stage** | A finite unit of work within a Program. A later stage can use the Results and receipts of earlier ones. |
| **Store** | Where the Host keeps what execution and recovery need: Run state, observations, Results, Checkpoints and the Effect ledger. |
