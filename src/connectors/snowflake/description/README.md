# Snowflake table description projection

This package connects an admitted Snowflake SQL API `INFORMATION_SCHEMA.COLUMNS`
result to the existing Common relation declaration owner. It retains the nominal
original result and every additional partition; it does not authorize a read,
issue a Source, send SQL, adopt credentials or report a provider outcome.

`table_target` retains exact database, schema and table spelling. The description
requires the selected ten metadata columns in order, the complete original row
count, ordered same-original partitions, exact target names, explicit nullability,
unique column names and strictly increasing positive ordinals. Ordinal gaps are
valid. Missing or foreign material is rejected. An empty metadata response is not
treated as evidence that an object exists or that the caller may read it.

`prepare_read_projection` selects only observed columns. Identifier quoting
preserves their spelling and doubles embedded quotation marks. Output byte bounds
are checked before building SQL. The SQL field order follows the selection; the
schema field order and field contracts come from Common canonical encoding.
`generate_read_declaration` delegates Catalog and SourceView construction to
`client_row_source_host.generate_relation_row_declaration`, including its schema,
connector registration, version, evidence and capacity checks.

Supported contracts are exact decimal (precision up to 38), finite number,
string, Boolean and JSON, with the original nullable flag. Temporal and binary
columns remain explicitly unsupported; they are not disguised as string or JSON.
Their metadata may coexist with a projection selecting other supported columns.
The original precision, scale and character maximum remain metadata, rather than
new scalar semantics or a claim about physical allocation.

The Host/Site must still bind metadata requests and responses to the current
installed provider, account and selected object, authorize Source access, retain
material and issue the existing acquisition/publication evidence. A candidate
SQL statement or declaration is not that authority. Provider execution, write
concurrency, installed product behaviour and Local runtime funding are separate
boundaries.

## Interface responsibilities

- Responsibility: the Snowflake description adapter projects admitted metadata;
  Common owns value contracts, canonical schema encoding and declaration issuance.
- Inputs and outputs: an original ResultSet, complete nominal partitions, exact
  table target and bounded selection produce an opaque description/read candidate.
- Identity: physical original/target identity is retained; the schema CID hashes
  exact Common-encoded bytes. Equal copies do not become the original observation.
- Ownership: response material is retained, array inputs/outputs are detached,
  and current authorization and physical custody remain with the Host/Site.
- Synchronization: this is synchronous immutable projection; it starts no provider
  request, transaction, background worker or retry.
- Failure: closed DescriptionIssue cases preserve foreign/incomplete/unsupported
  distinctions. No local refusal creates a provider response or Unknown resolution.
- Resources: explicit column, name, output byte, node and depth bounds are logical
  limits. They do not fund a VM, provider buffer or process allocation.
- Extension: unsupported temporal/binary contracts remain named refusals pending
  the existing Common type owner; no implicit string or JSON conversion is used.
- Verification: independent white-box vectors exercise original identity,
  partitions, target spelling, exact decimal38, canonical schema CID, Common
  declaration issuance, quoted SQL, unsupported types and tighter bounds.
