# BigQuery table metadata and Common declarations

This package projects a bounded BigQuery REST `tables.get` body into the existing
Common value-contract and relation-declaration Owners. It retains exact configured
project/dataset/table names, the observed etag/type/body digest, recursive fields,
nullable/required/repeated modes, original numeric/length/collation metadata and
declared primary-key columns. The primary key is an **unenforced claim**. It never
becomes a uniqueness fact, row locator, write precondition or permission.

The response's `tableReference` must match the original target in all three
components. The preserving JSON parser and existing decoder reject duplicate
keys, malformed Unicode and bounded-input violations before projection. Missing
field mode has the provider's `NULLABLE` default; explicit null or another mode
does not. Duplicate sibling fields, invalid numeric constraints and malformed or
foreign primary-key references refuse. Unknown descriptive provider fields are
not a new closed response protocol and do not replace checked used fields.

`prepare_read_projection` chooses only actually observed fields. Common constructs
and emits the canonical closed schema; selected field order remains distinct from
schema order. The projection retains its nominal metadata observation.
`generate_read_declaration` calls
`client_row_source_host.generate_relation_row_declaration`; it does not construct
another Catalog issuer, checker or Source grant.

Exact supported contracts are STRING, finite FLOAT/FLOAT64, BOOL/BOOLEAN, DATE,
JSON, representable NUMERIC/DECIMAL and BIGNUMERIC/BIGDECIMAL parameters, and
recursive RECORD/STRUCT and REPEATED fields composed entirely of supported
contracts. Unparameterized NUMERIC is decimal(38,9); a declared precision without
scale has scale zero. Invalid parameter combinations refuse rather than widen.
An unparameterized BIGNUMERIC or parameterized precision beyond the existing
Common decimal38 law has no substitute contract. Full INT64, BYTES, TIME,
DATETIME, microsecond TIMESTAMP and provider-formatted read-only types also remain
explicitly unsupported here until their existing Common/physical suppliers are
connected. A selected unsupported record cannot emit a partial object schema.
An independent supported column can still be selected from the same observation.
These refusals are unfinished Connector support, not changes to the full v0.1
type/read/write target.

`maxLength` and `collation` remain exact provider metadata. This unit neither
chooses a length-unit law for writes nor authorizes collation-dependent pushdown.
It does not generate SQL, create/poll a Job, parse data rows, acquire credentials,
publish a Source, create a Preview, mutate a table or settle an Effect. Those
physical routes must retain the original request/response custody and existing
current/authority/resource checks. Metadata or a successful declaration does not
complete the BigQuery Connector or Python Local product.

Provider references: [TableSchema/TableFieldSchema](https://docs.cloud.google.com/bigquery/docs/reference/rest/v2/tables#TableFieldSchema),
[parameterized types](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/data-types#parameterized_data_types),
and [unenforced primary/foreign keys](https://docs.cloud.google.com/bigquery/docs/primary-foreign-keys).

## Interface responsibilities

- Responsibility: the BigQuery adapter interprets observed vendor metadata;
  existing Common Owners validate contracts and issue relation declarations.
- Inputs and outputs: exact configured target, original bounded REST bytes and
  explicit limits produce opaque metadata and selected schema candidates.
- Identity: target and description references remain nominal; etag and SHA256
  describe observed bytes and never establish authorization, freshness or custody.
- Ownership: provider request/body loans, authenticated installation, current
  authority and physical cleanup remain with the existing Host/Site. Returned
  key/child/field arrays are detached and cannot mutate the observation.
- Synchronization: projection is synchronous and starts no I/O, Job, worker,
  transaction, retry or recovery loop.
- Failure: typed issues distinguish target, shape, limits, schema and unsupported
  columns. Local metadata refusal never resolves Provider or COMMIT Unknown.
- Cancellation: no operation or resource is started; projection does not cancel
  a Run or acknowledge physical stop, close, cleanup or release.
- Resources: input bytes/nodes/depth, cumulative recursive fields/names and
  encoded-schema bytes are bounded. These logical limits do not fund a physical
  allocation, VM, process, network operation or provider quota.
- Extension: unsupported lossless types and physical read/write routes remain
  with existing Common and Connector Owners; no string/JSON disguise or grant.
- Verification: independent metadata and canonical-schema vectors exercise exact
  target binding, Common declaration issuance, nested modes, decimal constraints,
  duplicate keys, key claims, unsupported fields and aggregate bounds.
