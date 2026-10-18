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

Exact supported contracts are STRING, INTEGER/INT64, finite FLOAT/FLOAT64, BOOL/BOOLEAN, DATE,
JSON, representable NUMERIC/DECIMAL and BIGNUMERIC/BIGDECIMAL parameters, and
recursive RECORD/STRUCT and REPEATED fields composed entirely of supported
contracts. Unparameterized NUMERIC is decimal(38,9); a declared precision without
scale has scale zero. Invalid parameter combinations refuse rather than widen.
For parameterized metadata, GoogleSQL's domain admits `P=S` when `S>0`:
`0<=S<=9, max(1,S)<=P<=S+29` for NUMERIC and
`0<=S<=38, max(1,S)<=P<=S+38` for BIGNUMERIC. The narrower `P-S>=1`
REST field-reference wording does not become an extra read restriction. This
interpretation does not establish live REST acceptance or increase Common's cap.
An unparameterized BIGNUMERIC or parameterized precision beyond the existing
Common decimal38 law has no substitute contract. BYTES, TIME,
DATETIME, microsecond TIMESTAMP and provider-formatted read-only types also remain
explicitly unsupported here until their existing Common/physical suppliers are
connected. A selected unsupported record cannot emit a partial object schema.
An independent supported column can still be selected from the same observation.
These refusals are unfinished Connector support, not changes to the full v0.1
type/read/write target.

`maxLength` and `collation` remain exact provider metadata. This unit neither
chooses a length-unit law for writes nor authorizes collation-dependent pushdown.
The metadata projection does not dispatch SQL, create/poll a Job, acquire credentials,
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

## Query-result page admission

`project_query_page` admits a bounded `jobs.query` / `jobs.getQueryResults`
response against the **same original** `ReadProjection` and explicitly selected
Job project/id/location. Its `QueryJob` is routing DATA, not an adopted Job,
request, credential, current authorization, launch permit or durable record.
Missing Job location has only the provider's documented `US` default; it does
not borrow another region. The returned page retains nominal projection/Job
identity, exact response digest, declared total and opaque next-page token.
A complete page is not completion of all pages, physical stop or a Store ACK.

The result schema must match selected names/types and recursive structure.
Query nullability metadata cannot widen the original Common contract. Numeric
parameters omitted from result metadata use the original contract, never a
new decimal default; explicit parameters must match that effective contract.
`f`/`v` wrappers preserve SQL NULL versus missing cells, JSON null, string data,
RECORD field order and REPEATED element boundaries. INTEGER and INT64 metadata
select the existing Common `int64` contract. Result cells use its canonical
signed decimal text admission through the original contract, preserving the
entire signed 64-bit range, including adjacent values beyond binary64's exact
integer range. Numeric JSON cells, noncanonical spellings and overflow refuse;
there is no float or Decimal substitution. The same rules apply recursively
inside records and repeated fields, with the original nullability and aggregate
node/text budgets. Common admits exact decimal
text, finite floats, dates, booleans and recursive objects/arrays. There is no
binary64 decimal conversion, schema replacement or partial-schema acceptance.

JSON data uses the existing Common JSON-literal rules, including first-key
retention and bounds on discarded duplicate values. Machine response/object
keys remain duplicate-rejecting. Pending responses and nonempty diagnostics
have separate typed refusals; diagnostic presence alone is not Job failure.
The physical caller keeps the original response/custody and must interpret the
actual Job observation. Input, recursive schema, aggregate value nodes/text,
row/total counts, Job text and page-token bytes all have finite caller bounds.
Those are logical limits, not physical reservations or a normal funding profile.

This page parser does not create, retry, poll or cancel a Job, send an HTTP
request, issue a Source grant, charge an unobserved body, publish a Result or
acknowledge physical cleanup. The same existing Row/Host Owner must still bind
its original request/charge/RowRun, accumulate pages and confirm their end.
Unsupported Common types listed above remain unfinished rather than being
advertised as strings or floats. Full physical/public BigQuery acceptance and
Python Local remain separate unfinished work.

Sources: [query results](https://docs.cloud.google.com/bigquery/docs/reference/rest/v2/jobs/getQueryResults),
[JobReference](https://docs.cloud.google.com/bigquery/docs/reference/rest/v2/JobReference),
and [JSON type](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/data-types#json_type).

## Original query Job observations

`prepare_query_job_material` emits bounded GoogleSQL for only the original
selected fields and table. Each original identifier is quoted, including
backslash, backtick and control-character escaping; names are not normalized.
The one original Job ID/location, explicit GoogleSQL mode and
`maximumBytesBilled` are in the same immutable request material. These fields
are routing and request DATA, not permission, billing credit or physical funding.

`project_query_job_observation` uses the same bounded preserving parser. It
requires the same Job reference and original submitted query configuration.
PENDING/RUNNING/DONE are observations, not a new scheduler: DONE says execution
ended, while final errorResult still forbids successful Source publication.
The original material remains nominal when observing state; an equal other
material cannot substitute it. Physical transport and response correspondence
remain with the original read/Host; these codecs do not issue cleanup ACKs.
