# Kintone original record acquisition

The vendor Catalog and record reader are metadata and response projections
inside the existing Row Source Owner. `RecordDeclaration` retains the original
Form catalog and its Common declaration. `PreparedRecordRead` retains the
original checked requirement's acquisition. `RecordRead` borrows that same
already-accounted RowRun; it cannot create, finish, capture or close its root.

## Original Form and response custody

`recheck_record_read_form` charges the complete response to that RowRun before
bounded decoding. The observed App, revision, field paths and native field
definitions must match the original Form. A changed or malformed observation
aborts logical admission, preserving the original charge and cleanup duty.
The retained Form is not proof of current authorization or authenticated App
identity; those facts belong to the installed Credential Site and Account.

Record values are admitted against the acquisition's original Common Contracts,
not independently admitted equal Contracts. Response bytes, checked cells and
metadata remain under the original response borrow. A physical stop callback
returning false keeps the reservation and original observations. Only its
confirmed acknowledgement retires those aliases. Request return, timeout,
abort and logical failure are not physical release.

## Bounded request parameters and seek traversal

`record_form_request_body` and `record_page_request_body` encode bounded JSON
parameters from the original App and selected fields. They do not send requests
or issue grants. The intended physical projection is the vendor's documented
POST request with the fixed `X-HTTP-Method-Override: GET` header. This preserves
the exact selected fields without falling back to all readable fields or
changing the shared GET-body prohibition. The actual Site must register and
authorize each metadata/data read separately.

The records request includes `$id` and `$revision` plus the original selected
fields, within the vendor's 1000-field and 500-row request limits. It uses
`$id` ascending seek traversal, avoiding offset truncation. Original API ID
strings are never converted through a JavaScript Number, stripped or replaced
as ResourceRefs. Numeric comparison for traversal is separate from identity.
The next cursor is the exact last original ID. Duplicate, reordered or repeated
IDs abort that acquisition. Only a short original page ends this traversal;
`totalCount`, transport completion and timeout cannot substitute for it.

The original App declaration carries the existing conditional relation key
`["$id"]`. This lets the Common publication-order Owner order typed Results
without trying to order an Array-valued data column. It is not a new lookup
permission, uniqueness observation or completion acknowledgement. The actual
reader must still reject duplicate/reordered API IDs, and a native
`RECORD_NUMBER` field is never substituted for that key. Public query aliases
are projected only from this admitted declaration's original view/schema
evidence; the submitted SQL cannot fabricate them.

The private Node bridge uses a closed zero-or-one-element array for cursor
presence. Its same-owner validation is DATA projection only, independent of
compiler Option representation. It supplies no permission, current fence,
capacity, completion certificate or cleanup ACK.

Official provider boundaries:

- [REST API overview and method override](https://kintone.dev/en/docs/kintone/rest-api/overview/kintone-rest-api-overview/)
- [Get Records request and limits](https://kintone.dev/en/docs/kintone/rest-api/records/get-records/)
- [Get Form Fields](https://kintone.dev/en/docs/kintone/rest-api/apps/form/get-form-fields/)

## Installed Credential Site

`installed-kintone-source.mjs` is the installed source entry. One configured
App/resource keeps its exact original metadata, native field codes, API origin,
optional guest-space route and Site generation. Multiple installations remain
the existing Host composition's responsibility. The bounded metadata file
contains original Form bytes, not fabricated checked values or read permission.
The live authenticated Form must match before the first record page and after
every page, including the final one.

The registered loader requires the original loader-bound Source initialization,
configuration reader and Host services before reading metadata. It captures
its original Core methods and receiver before the first await. The same
initializer reserves base64 decode/comparison overlap before Buffer creation,
then the configured parser/value/declaration constructor envelope before the
native Form, record declaration and original declaration serialization. Nodes,
decoded text and wire bounds remain distinct inputs to the existing Source
quantity; no output buffer, new policy bound or permission is issued by it.
The returned nominal record declaration, Form catalog and Environment are
retained on that parent and passed unchanged to the actual RowSource constructor.
Registration/finish and original Source retirement precede initial-parent close.

Managed identity reads use the same observed-FD CA byte reader; those exact
bytes reach the original Site. The standalone identity utility retains its
separate DATA-hashing purpose and cannot construct an installed Source. A
missing initializer refuses before raw configuration or native entry. Malformed
binary input or native Form refusal keeps the same original failure beneath
the existing initialization cleanup carrier, including pending-close duties.

The installer delegates Account/Credential Site/current/grant issuance to the
existing bound `openRowSite` service. Form access uses its separately configured
read Resource; the record grant and App identity observation cannot supply it.
`prepareAcquisition` retains the same typed original preparation by its exact
acquisition handle. The vendor driver borrows that already-accounted RowRun;
the generic Host keeps finish, capture and root cleanup.

`readKintoneRecords` retains one opaque credential binding for the acquisition.
Each metadata/page request has its own counted nominal use. Current read
authorization, full generated scope correspondence and original material are
checked for every send. Credential replacement refuses without using the new
token or probing another App. Secret material is applied only by the existing
HTTPS boundary's private kintone token presentation, never exposed to the
Connector or represented by a digest/public token reference.

Complete response bytes are charged before another awaited current callback.
Non-200 bodies consume an observation charge and refuse; they do not become
rows. A lost reply remains Unknown without request retry. Cancellation cannot
acknowledge the driver's still-active response/current frame. The bound Core
cleanup observer needs the actual original socket retirement and frame exit
before the generic Host can return that Root's reservation.

All decoder/request/page/request-count and secret ceilings are explicit
positive installer inputs. They are finite physical preparation bounds, not a
language restriction, read grant, default fuel or adopted normal numerical
profile. API-ID/RECORD_NUMBER separation and original field codes stay intact.
Normal numeric-column history, unsupported carriers and whole-phase funding
remain separate obligations; no default numerical profile is inferred here.

## Interface responsibility references

These are references to the existing contracts and owners, not another
execution contract or proof of an installed artifact's provenance.

| Attribute | Existing boundary |
| --- | --- |
| Responsibility | `loadInstalledKintoneSource` delegates to `createInstalledRowSource`; `readKintoneRecords` supplies vendor I/O only. |
| Inputs/outputs | `checkInstalledKintoneSourceProfile`, original metadata `inputs`, typed `client_kintone_read_bridge.mbt` and `RecordDeclaration`/`PreparedRecordRead`. |
| Identity | Original App/Form/resource/native field codes, Site/runtime binding, nominal acquisition handle and generated `invocationBindingsMatch`. |
| Ownership | Original Source initial parent and constructor context; same `RecordRead`/`RowRunResponseBorrow`, private credential binding and generic Host root; partial initialization returns existing cleanup custody. |
| Synchronization | Separate Form/data read decisions, pre-send/current-after-await fences and final Form recheck precede generic finish/capture. |
| Failure | Changed Form, typed decode/order failure and HTTP refusal stop capture; transport loss preserves `AcquisitionOpenError` Unknown and original credential journal. |
| Cancellation | Original signal aborts the actual HTTPS request; processing-frame exit and original binding close are both needed for retirement. |
| Resources | Complete response charge on the same RowRun; positive caller bounds and retained pending reservation; no normal numeric funding claim. |
| Extension | Existing host manifest/table generator, canonical Node/RelA bridge generator and existing Source/Scope owners; no second reader/ledger/scheduler. |
| Verification | `installed-kintone-source.test.mjs` uses actual initial Resource/Source registration/retirement, Common, Account, SQLite and loopback TLS. Its standalone prefix component uses the original installed sequence-contract issuer. Read components retain explicit RowRun/Ledger bounds; none certifies a pristine normal distribution, ordinary Request/Plan funding or real SaaS acceptance. |
