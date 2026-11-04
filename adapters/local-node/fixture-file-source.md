# Declared fixture file DATA supplier

## Responsibility

`fixture-file-source.mjs` adapts an explicitly declared physical JSON relation
to the existing logical file-listing and keyed Content callbacks. Common owns
the single document parser, typed admission, listing protocol and keyed row
correlation. The installing Source owns ResourceRef issuance. The existing
Run-owned capture and Store own ContentRef issuance. No connector, compiler,
Run, Ledger or business-specific path is implemented here.

## Inputs and outputs

`createFixtureFileSupplier` captures the original runtime methods, physical
declaration, resource, items/key paths, Text identity, writable fields, physical
field roles and finite limits. `readListing` supplies standard file metadata;
absent path, size and modification metadata remain NULL. `readContent` supplies
the exact requested resource/version, issued Content and selected metadata.
The physical schema contains raw fields, not authored ResourceRef/ContentRef
objects. Parent-owned read, shared document projection, issuance, resolution
and current callbacks are required; supplying callbacks does not itself prove
their authority. After the raw body is charged, `projectOriginalDocument`
synchronously returns the selected original physical projection. The parent
binds that callback to the exact descriptor, admits one original document and
projects every declared relation under its shared cumulative budget. This
helper has no independent parser, copy or compatibility fallback. Row
observation still checks the exact selected physical declaration.

## Identity

The Common document owner checks declared key metadata, unique Text identities
and every selected row field. Only its original row getters select identities,
versions, metadata and text. File names remain join values and need not be
unique. The Source issues a resource from the admitted identity and resolves a
keyed request through its existing live issued inventory. Missing paths are not
replaced with IDs. The fixture's declared version field remains unchanged in
the data. Its exposed opaque provider version is SHA-256 over the common
value-preserving canonical JSON object with `declared_version` and
`row_version_cid`, the latter obtained from the original admitted complete row.
Listing and keyed capture use this same function. Replacing content or metadata
while reusing the declared label therefore invalidates an older lookup. This
does not replace the managed reader's original stat and byte-correspondence
fences. The separately computed Content SHA-256 describes the exact derived
UTF-8 bytes, not permission; equal row or version digests do not grant another
Source's ResourceRef authority.

## Ownership

The parent retains the same managed physical read, shared admitted document,
all sibling projections and original failure, close and retry duties. The
helper borrows returned bytes and opaque document and row originals only for
the active callback. It creates no global document
or resource inventory and acknowledges no physical cleanup. Source references
must remain available for actual captured-input borrowers until their existing
Run lifetime ends. Store-owned Content can outlive a temporary Source read.

## Synchronization

Configuration arrays, roles, limits and runtime methods are captured before
awaits. Read authorization, Source currentness and cancellation are checked
around physical reads, metadata projection and capture callbacks. The actual
original JSON body is charged before the parent document projection. Listing consumes that
same ticket with its logical envelope. Keyed content records a request first,
consumes the original body ticket, then passes bytes to the existing capture.
The parent still owns same-file identity checks and cross-read correspondence.

## Failure

Invalid configuration, absent fields, unissued resources, version mismatch,
invalid Core originals and exhausted bounds refuse. A failed parser/current
check leaves its received-body ticket and physical child with the original
RowRun/Source owner. Exceptions propagate without claiming stopped transport,
successful capture, retry permission or cleanup acknowledgement. A failed
capture cannot publish a keyed response row.

## Cancellation

The supplied AbortSignal is checked at the existing callback boundaries. An
abort is a refusal, not evidence that the parent-owned read or Store writer has
stopped. No helper cancellation owner, replacement child or automatic retry is
created; original close and pending-failure duties remain with their issuers.

## Resources

The parent admission uses explicit byte, node, depth, row and shared work bounds. The listing
envelope is bounded before admission. Content UTF-8 length is checked before
the Core getter allocates bytes; empty content is valid. Inline bytes are
derived DATA, not a second received response and not another transport charge.
The parent must fund simultaneous original/copy/parser/typed-row objects,
observed-row wire/hash, canonical provider-version preimage/digest, logical
envelope, UTF-8 bytes, Content digest and Store-writer
overlap on the same original reservation. Limits here do not grant capacity or
prove that integrated execution has supplied it.

## Extension

Physical roles are model data and contain no business names. The current slice
uses one declared non-null Text identity, inline UTF-8 content and a single
bounded fixture response. It does not infer schemas, add compound identities,
invent path aliases, normalize Unicode or select a second Content backend.
Additional representations require an explicit physical model and the same
Common admission and Source/Store ownership boundaries.

## Verification

`fixture-file-source.test.mjs` exercises callback sequencing, exact body-ticket
correspondence, Source-issued identity, duplicate names, missing paths, Unicode
and newline preservation, empty content, foreign resources and Source inventories,
stale versions, changed rows reusing the same declared version,
pre-allocation bounds, admission/current/abort refusal, foreign projections,
original cleanup-carrier propagation and captured static methods. These tests
use explicit Core and capture ports. They do not establish
real Core integration, physical-close completion, Store issuance, funding,
multi-source Content/Effect composition or normal Node workflow acceptance.
