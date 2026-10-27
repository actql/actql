# ActQL specification

The normative definition of ActQL 0.1: what a Program means, how it is
checked and executed, and the wire formats Hosts, Connectors and clients
exchange. This index says what each document owns and in which order to read
them. The public documentation defines the v0.1 target. This specification
defines the same behaviour normatively and is aligned to that target. A
difference is a specification defect until the owner decides otherwise.

## What the specification is

- **Normative and informative.** The documents listed under "Documents"
  are normative: their requirements carry identifiers, and conformance is
  claimed against them. Design notes and guides are informative.
- **Version 0.1.** Every document is `actql/0.1`. Machine contracts (schemas,
  grammar, laws) are pinned by content identity, separately from document
  versions and from package releases.
- **Authors write SQL.** The text surface — SQL with Pipe syntax — is defined
  in [Query text](query-text.md) and taught in [Writing Programs](../authoring.md)
  and the [Syntax reference](../reference/syntax.md). The YAML and JSON
  documents shown in [Language](language.md) are the serialization of the
  canonical Program model that the text lowers to, not a second authoring
  language.
- **Defined is not the same as released.** A behaviour defined here may not
  be executable in every environment yet. [Implementation status](../reference/status.md)
  records what runs today; [Conformance](conformance.md) defines how an
  implementation claims a profile.

## Documents

Read them in this order.

| Document | Owns |
| --- | --- |
| [Query text](query-text.md) | The SQL and Pipe surface authors write: statement heads, Pipe operators, lexical rules, scalar functions, and how each form lowers to the canonical model. |
| [Language](language.md) | The canonical Program model the text lowers to: source and Program structure, carriers and value types, expressions and predicates, operations, named Results and Effect declarations, checking and canonical planning, canonical identities. |
| [Execution](execution.md) | Capture and admission, the Run identity model, Run states, Checkpoints and Resolutions, account authorization routing, Effect preview, approval and application, outcomes and reconciliation. |
| [Conformance](conformance.md) | Claims, profile dependencies, corpora, evidence and release combinations. |
| [Protocols: contracts](protocols/contracts.md) | Catalog, SourceView, Mapping, Command and model task contracts; check environment; lock; static plan artifacts; diagnostics. |
| [Protocols: run](protocols/run.md) | The Run, Checkpoint, Resolution, Preview, apply-receipt and reconciliation-receipt wire forms; execution-account configuration. |
| [Protocols: artifacts](protocols/artifacts.md) | Result artifacts, manifests and delivery; Store admission; availability leases. |
| [Protocols: discovery](protocols/discovery.md) | Publication snapshots; describe, list and read; cursors and disclosure. |
| [Protocols: run graph](protocols/run-graph.md) | The finite process graph, typed activation, attempt lifecycle and cross-Run bindings. |
| [Protocols: http](protocols/http.md) | The typed HTTP binding Connectors use: origins, redirects, SSRF rules, bounded transfer. |
| [Protocols: collection](protocols/collection.md) | Collections: definition, execution, accounting, evidence, coverage and integration binding. |

[Reference Host](../design/reference-host.md) is an informative description
of how a Host meets these requirements.

## How to read a requirement

Each normative statement sits in a block with a stable identifier
(`requirement-block`). Evidence of conformance attaches to the exact
requirement it verifies, never to a document as a whole. Each document lists
the owner documents it imports normatively; other cross-references are
navigation and do not require implementing the referenced protocol in full.
Narrow schema and law references are pinned individually in each document's
machine-contract section.

Changing a normative statement is described in
[Development](../contributing/README.md#changing-the-specification).

## License

The specification is licensed under CC BY 4.0: it may be copied, translated
and adapted, including for other implementations, with attribution. Code
samples in it are under the Apache License 2.0. See [LICENSE](../LICENSE).
