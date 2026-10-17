# Original record target observations

`prepare_record_read_request` and `project_record_read_observation` extend the
existing HubSpot Catalog/Decode owner. They supply complete bounded batch-read
DATA to the existing Effect caller; they do not create a Preview, a write
authorization, an apply claim or a second recovery owner.

The [provider batch-read protocol](https://developers.hubspot.com/docs/api-reference/legacy/crm/objects/objects/batch/get-objects)
accepts record IDs or a unique `idProperty`, selected properties, and returns
record IDs, properties, `updatedAt` and a batch status. The request uses only
selectors already admitted by `prepare_record_target`: real top-level record
IDs or positively enforced unique metadata. Company domain names, lookup
support and sampled response equality do not establish uniqueness.

The complete response is correlated by each original typed selector, not
array order. Custom selectors are explicitly requested and decoded through
the original Common property Contract. Two record IDs for one selector are a
refusal. Actual record IDs, selected typed values and normalized `updatedAt`
are retained in original target order. `updatedAt` is an observation, not a
conditional write token or a substitute for the particular modification
property a full-diff caller must explicitly select from the original Catalog.

Only a complete batch with every requested record and no error is admitted by
this entry. Missing, pending, canceled, partial, malformed, archived or foreign
records are never converted into an absent-target proof or an upsert-create
decision. A later caller must separately establish any missing-target route
through the original provider protocol and existing recovery responsibility.

## Physical boundary

- Responsibility: `readHubSpotRecordTargets` sends one original batch-read
  candidate through the existing Credential transport. Its caller remains the
  Host/Effect owner; there is no write send or grant in this module.
- Inputs and outputs: the same provider-runtime Catalog/request, original
  portal, independently authorized nominal operations, Credential binding,
  current callbacks and explicit bounds produce a private typed observation
  and original physical responses. No raw credential crosses this boundary.
- Identity: initial account verification, schema observations and batch read
  use the same acquisition binding and full generated invocation scope. The
  original request retains its Catalog and typed selectors. Rechecking DATA
  does not confer current Account, Reviewer, Workspace, credential or Site
  permission.
- Ownership: the original caller retains and retires its Credential binding,
  accounted RowRun and responses. `HubSpotTargetReadFailure` preserves complete
  observed responses after projection, accounting or current-check failure.
  No local finish/capture or cleanup-success assertion is introduced.
- Synchronization: identity and current schema precede the target read. Each
  await is fenced, including the physical send; received bytes are charged
  before projection. Final schema and current checks precede returning the
  observation. There is no cached Allow or replacement credential lookup.
- Failure: a lost reply retains the original nominal Unknown. HTTP rejection,
  incomplete response, property drift, duplicate/foreign target and current
  denial retain their original classification and custody. Nothing retries,
  infers unsent, or returns a partial/absent record as success.
- Cancellation: abort/current checks fence each operation. Physical binding
  retirement remains with the existing Credential owner; cancellation and a
  returned observation are not a socket-close ACK or resource release.
- Resources: positive request, response, parse/value, complete output and
  request-count limits are independent. Request Catalog/target/name backing
  and encoded document stay live with the request/observation. The original
  response buffer, admitted page, second bounded envelope decode, selector
  map/order/timestamps and output writer overlap during projection; current
  and prior observations may overlap during comparison and error retention.
  The Host must fund that original lifetime and confirmed cleanup. These
  limits or successful test quantities do not adopt a normal numerical
  profile or replace existing Site/Run reservations.
- Extension: POST is the provider's read protocol, not a write grant. Identity,
  property schema and record read require separately pre-registered operations
  under existing read authorization. No new origin, redirect, retry, schema
  mutation or unsupported-profile fallback is permitted.
- Verification: `record_read_wbtest.mbt` checks complete correlation, typed
  values, bounds and substitution; `hubspot-target-read.test.mjs` exercises
  actual Common/Credential/Account/SQLite/TLS success, refusal, loss and cleanup
  with fresh synthetic namespaces. Those component cases do not establish a
  normal installed Effect, full Connector write support or live API success.

The remaining Effect caller must retain these observations under its original
sealed Preview, recheck targets and current authority before the original
nominal write claim, save the exact request and marker, and reconcile uncertain
writes without resending. Batch trace IDs remain correlation DATA, not a
provider idempotency guarantee or write outcome.
