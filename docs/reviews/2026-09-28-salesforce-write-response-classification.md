# Salesforce write response classification

This records how a Salesforce REST write response becomes an Effect row
outcome: success (`applied`), a failure known not to have been saved
(`failed`), or `unknown`. It covers single-record create, update by Id and
upsert by external key, and sObject Collections with `allOrNone=false`. The
common Effect owner, Checkpoint and public entries are unchanged.

## Rule

A `failed` outcome needs documented evidence that Salesforce rejected the
request. Anything without that evidence stays `unknown`: the row keeps its dispatch
head, the Run keeps reconciliation responsibility, and nothing is resent.

The evidence used is limited to two kinds, both from Salesforce's official
documentation.

1. **The REST status definitions**, whose meaning is a rejection of the
   request (REST API Developer Guide, "Status Codes and Error Responses"):
   - 400 "The request couldn't be understood, usually because the JSON or XML
     body contains an error."
   - 401 "The session ID or OAuth token used has expired or is invalid."
   - 403 "The request has been refused." It includes `REQUEST_LIMIT_EXCEEDED`.
   - 404 "The requested resource couldn't be found."
   - 428 "The request wasn't executed because it wasn't conditional."

   Only these statuses count, and only with the structured error body the
   guide documents for them: `{message, errorCode, fields}`, alone or in an
   array.
2. **The sObject Collections guarantees:**
   - "If the request isn't well formed, the API returns a 400 Bad Request."
   - With `allOrNone=false`, objects are processed independently, and results
     come back "in the same order" as the request.

This is not a claim that every error Salesforce returns means nothing was
saved. A reply outside these definitions, such as a 5xx, a timeout, a lost
reply or an unrecognized body, is not treated as evidence either way.
Salesforce's own integration guidance treats such cases as possibly executed.

## Table

| Operation | Response condition | Basis | Outcome | Regression test |
|---|---|---|---|---|
| create, update, upsert | Typed success (201 create; 204 empty update; upsert 201 `created:true` or 200 `created:false`) | Existing success contract | `applied` | `write_single_response_wbtest.mbt` |
| create, update, upsert | 400, 401, 403, 404 or 428 with a well-formed error body: one error object or an array of them, each with an enumeration `errorCode` and a `message` | REST status definitions (rejection of the request) | `failed`, code `SalesforceWriteRejected`, `details.http_status` and `details.errors[{error_code, fields}]` | `write_rejection_wbtest.mbt` "documented single-record rejections"; `installed-salesforce-effect.test.mjs` "non-success Salesforce write replies" (403 request limit, 400, 404) and "a rejected row fails" |
| any | Error body carrying `SERVER_UNAVAILABLE`, `UNKNOWN_EXCEPTION`, `QUERY_TIMEOUT` or `REQUEST_RUNNING_TOO_LONG` | These report provider failure or timeout, not a rejection of the request | `unknown` | wbtest "stay unknown"; e2e "400 uncertainty code" |
| any | 5xx; 409, 410, 412 (no precondition was sent), 420, 429, 405, 415; any other status | Not documented as unsaved | `unknown` | wbtest; e2e 500 and 503; `effect-run.integration` rate-limit scenario (429) |
| any | Malformed or unrecognizable body (proxy page, empty body, empty array, missing or non-enumeration code, missing message, non-name fields, over the bound) | Not evidence | `unknown` | wbtest; e2e "400 proxy page" |
| upsert | 300 (external id matched several records) | Documented as "the record isn't created or updated", but the credential transport refuses every 3xx as a redirect before the body is read | `unknown` (transport gap, below) | e2e "an upsert 300 stays unknown" |
| any | Lost reply, connection reset, transport timeout | Not evidence | `unknown` | e2e "a lost write reply is kept unknown" |
| Collections | 200: per row `success:true` or `success:false` with errors whose `statusCode` is an enumeration name | Existing per-row contract; independent rows | Per row `applied` or `failed` (`SalesforceRowFailed`); never collapsed to the whole Set | `write_collection_request_wbtest.mbt`; wbtest "Collections row errors publish only enumeration codes"; `effect-run.integration` collection-partial scenario |
| Collections | 200 with a row error whose `statusCode` is not an enumeration name (free text, lower case, spaces, a newline, over 100 characters) | Not evidence; nothing of it is published | Every row `unknown` | wbtest "Collections row errors publish only enumeration codes" |
| Collections | 400, 401, 403, 404 or 428 with a well-formed error body | Collections: a malformed request is answered 400; the same REST status definitions | Every row `failed`, `SalesforceWriteRejected` | wbtest "a request-level Collections rejection"; `salesforce-catalog-sync.test.mjs` 400 case |
| Collections | Any other non-200, or a malformed 200 | Not evidence | Every row `unknown` | wbtest; catalog-sync 500 and 429 cases |

## Published details

A failed outcome publishes each provider `errorCode` (for Collections rows,
`statusCode`), but only when it is an upper-case enumeration name; a reply
with any other code is not classified at all. It also publishes the error's
field names, but only those declared for the written Resource: the write projection's fields,
its described fields and its external target. Undeclared names are dropped.
Provider messages are never published: they can contain record values. The
raw response stays in the private Effect Ledger evidence under its existing
rules.

The Collections per-row failure wire changes accordingly:

- `details.errors[].status_code` is renamed `error_code`;
- `message` is dropped;
- the outcome message becomes "Salesforce did not save the row".

This changes the outcome CIDs of new Runs only. No contract version changes.

## Resend and the end state

A `failed` row does not permit a resend. The existing common owner ends the
row, and a later attempt is a new Run under its then-current authorization
and approval. Under `halt`, rows after a failed row are not sent. Rows
already sent keep their outcome. The Set and Run end states follow the
existing common rules: any `unknown` makes the Run `needs_reconciliation`;
otherwise any `failed` or unattempted row makes it `failed`. A partial
Collections success keeps its applied rows.

## Gap: an upsert 300 cannot be classified

- **Reproduction:** `installed-salesforce-effect.test.mjs`, "an upsert 300
  stays unknown: the transport refuses it as a redirect".
- The mock org answers an upsert with 300 and a list of two matching record
  URLs.
- `callHttpsCredentialResource` throws `RemoteCredentialRedirectRejected`.
  The body never reaches the classifier.
- The row stays `unknown` and is never resent, and the Run stays
  `needs_reconciliation`.
- Salesforce documents this case as saving nothing. Classifying it requires
  the common credential transport (`site-node`) to deliver a 300 response
  body for writes instead of treating it as a redirect. Until then it stays
  unknown.
