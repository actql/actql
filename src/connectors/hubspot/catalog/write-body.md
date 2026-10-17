# Bounded write-value projection

`prepare_write_body` admits one complete mapped row under the original
`PropertyCatalog`. It uses the existing positive writability facts and Common
property contracts. Missing, extra or duplicate fields, unknown options and
unrepresentable values fail without returning a partial candidate. The
provider bridge forwards the explicit bounds; it does not reconstruct these
contracts in JavaScript.

The opaque candidate retains its original catalog and independent copies of
the selected names, canonical Common value JSON and provider property JSON.
Only DATA strings cross an independently compiled Common boundary. Its
metadata recheck calls the existing complete catalog comparison, including
the original object type and all admitted property metadata. This comparison
does not replace current Account, credential or target-state checks.

## Representation

Decimal values remain exact decimal38 strings. Boolean, date and timestamp
spellings come from the existing Common scalar Owner. Enumeration choices use
observed internal values, not display labels. Checkbox arrays use replacement
spelling with semicolon separators; empty elements and embedded separators
are refused rather than interpreted as append instructions or changed values.

The existing object read decoder must reconstruct each spelling as a value
completely equal to the original admitted value. This keeps numeric clears
distinct from empty strings and empty checkbox arrays. In particular, a null
string or null checkbox array currently has no lossless spelling under that
decoder and is refused; an empty string and an empty array remain exact
values. This is a local representation check, not evidence that a future
provider mutation succeeded or returned the approved postcondition.

The provider references are the [properties guide](https://developers.hubspot.com/docs/api-reference/legacy/crm/properties/guide)
and [batch update API](https://developers.hubspot.com/docs/api-reference/legacy/crm/objects/objects/batch/update-objects).
These explain property spellings; they do not establish global uniqueness,
current permission or successful application.

## Bounds and lifetime

Positive caller limits cover input bytes, parse nodes/depth, selected fields
and names, value nodes/text, complete-equality work and each full output's
bytes/nodes/depth. The input/parsed tree, original catalog, field contracts,
current checked cell and its readback, equality state, temporary property
spelling, name arrays and both output writers can overlap. The two returned
strings coexist with the retained catalog and copied names. JavaScript
argument arrays and returned name copies are additional caller retention.
These bounds are not a heap charge, a normal numerical profile or a grant;
the actual installer must account for simultaneous retention in its original
funding scope before selecting a physical write path.

## Existing responsibilities still required

This candidate is not a prepared or executable Effect. The original operation
and unique target selection, account/portal binding, sealed full-diff Preview,
current authorization, original request journal, nominal credential use,
send/result classification, reconciliation and cleanup remain with their
existing Owners. No request, retry, new Run, permission or provider success is
issued by projecting these strings. Normal installed/public write acceptance
and the complete Cloud Effect path are separate from this projection.
