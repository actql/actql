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

The private Node bridge uses a closed zero-or-one-element array for cursor
presence. Its same-owner validation is DATA projection only, independent of
compiler Option representation. It supplies no permission, current fence,
capacity, completion certificate or cleanup ACK.

Official provider boundaries:

- [REST API overview and method override](https://kintone.dev/en/docs/kintone/rest-api/overview/kintone-rest-api-overview/)
- [Get Records request and limits](https://kintone.dev/en/docs/kintone/rest-api/records/get-records/)
- [Get Form Fields](https://kintone.dev/en/docs/kintone/rest-api/apps/form/get-form-fields/)

## Remaining physical obligations

These projections do not implement the physical installer by themselves. That
caller must bind the original App and Form to the actual current Site, obtain
the separately authorized read uses, retain one original credential binding,
charge every response including refusals and preserve Unknown/no-resend.
The generic Host remains responsible for finish, capture and root cleanup.
Normal numeric-column history, unsupported carriers and whole-phase funding
remain separate obligations; no default numerical profile is inferred here.
