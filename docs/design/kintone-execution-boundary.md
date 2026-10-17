# kintone original metadata and execution boundary

The kintone Connector uses the existing installed Row Source, RowRun,
Credential Site and Row Effect responsibilities. Its vendor-specific metadata,
record wrappers, query encoding, revision handling, attachments and process
operations do not introduce another acquisition engine or authority owner.

## Original Form Fields metadata

`connectors/kintone/catalog` projects a complete supplied Form Fields response
under explicit positive caller byte, node, depth, field-count and total
field-code bounds. These are finite physical projection bounds, not language
limits or an adopted numerical profile. An over-limit or malformed response
returns no partial catalog.

The original property key must equal its field code. Labels do not rename a
field. Subtable paths preserve their original parent association. Option-map
keys are external values; they remain exact Unicode text rather than normalized
source identifiers, and option labels cannot replace those keys. Projection
getters return copied path and option arrays. Missing required/unique metadata
remains unconfirmed, distinct from an explicit false value. Unknown native
types can be retained as metadata without claiming a readable or writable
ActQL carrier.

The App ID supplied to this pure projection is a caller label: the Form Fields
response does not echo it. The original settings revision and response digest
are data, not credentials or proof of live deployment. The physical caller
must retain the actual authenticated request and distinguish the live
`/k/v1/app/form/fields.json` endpoint from its preview counterpart through the
same existing Site, nominal use and current authorization. A matching metadata
revision or a successful field comparison does not grant I/O or publication.

The supported custom update-key shape requires original `unique: true` on a
top-level Text or Number field. A configured name, a label, false/missing
metadata or apparently distinct sample records cannot establish that provider
constraint. This static eligibility does not perform a lookup, inspect row
duplicates, approve a write or replace current revision and authority checks.

Number `displayScale` and calculation `format` remain original metadata.
Neither provides an invented Decimal precision or permission to round a
provider value through binary64. Time needs the shared checked logical Time
contract; it is not replaced by String, Timestamp or Decimal.

The complete metadata bytes, parsed source/decode trees, field records,
subtable-path arrays, option references, response-hash workspace and returned
projection can overlap within the original caller's acquisition lifetime.
The parser bounds do not reserve that lifetime or settle its custody. Physical
secret membership, current checks, Account/funding, transport and retained
cleanup remain with their original owners.

## Provider references

- [Get Form Fields](https://kintone.dev/en/docs/kintone/rest-api/apps/form/get-form-fields/)
  defines original field codes, types, settings revision, nested table fields,
  required/unique flags and option metadata, with separate live and preview
  endpoints.
- [Update Records](https://kintone.dev/en/docs/kintone/rest-api/records/update-records/)
  requires the duplicate-prohibition option for Text or Number update keys;
  record revision checks and additional create permission for upsert remain
  distinct requirements.

These metadata projections are not registration or installed acceptance of a
complete Connector. Record acquisition/conversion, content, writes, operations,
approval, restoration, Unknown/nonresend and physical cleanup still require
their real existing-owner execution paths.
