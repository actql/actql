# Graph identity and storage migration

The admitted Graph is the sole model: definition-scoped typed node keys,
independent edge keys, static label sets and presence-aware properties. Core
types, constructor APIs and public Program fields use Graph names. There is no
second model, compatibility reader or fallback execution path.

The public constructor uses the closed `graph` Program field and
`actql-graph-constructor/0.1`. Text retains the standard `PROPERTY GRAPH`
keywords; that spelling does not select another runtime representation.

## Identity boundary

The definition domain hashes the `actql-graph-definition/0.1` preimage,
including the current constructor version and the ordered admitted producer
definitions. Renaming this vocabulary is an intentional identity migration.
The same semantic definition receives a new domain compared with the previous
release, and therefore new node and edge identities. No alias equates the old
and new identities. Within the new contract, repeated issuance from the same
definition is stable, and properties and endpoints remain content rather than
identity. Key component order, scalar descriptors and definition spelling
retain their existing meaning.

User property names, values and definition names are not renamed. The issuer
uses the ordinary checked value codec; it does not replace text in user data.

## Stored data and recovery

The Graph contract, snapshot tag and law identifiers change together, with
their dependent CIDs and pins. Snapshots keep the complete current definitions,
typed identities, keys, properties and endpoints. Previous snapshots are
rejected, not translated into current identities. A previous Delta cannot be
applied to a new Graph: its contract and base/target CIDs belong to the old
storage generation. The Delta owner retains complete-before matching,
atomic application and exact target-CID verification.

Stored Programs and Runs containing previous constructor fields or contract
pins cannot be resumed as new Graph executions. Before upgrading an installation
with unfinished Runs, finish its recovery and release obligations with its
pinned previous executable, or keep that installation and its original
journals under the previous owner. Do not overwrite old receipts, rewrite
identities in a journal or discard cleanup custody to make an upgrade pass.
The new installation starts with separately admitted current Programs and
current storage. No in-place storage migration is supplied by this refactor.

## Evidence boundary

Historical fixtures retain their exact source revisions, bodies and CIDs.
Current contract references are regenerated from their own normative owners;
historical evidence never inherits a current pin just because the old hash also
appears elsewhere. Migration checks compare fixed previous evidence with new
behavior: the identity/storage changes are explicit, while value types, key
components, label meaning, presence, row correspondence, logical work and
resource custody remain subject to their existing checks.
