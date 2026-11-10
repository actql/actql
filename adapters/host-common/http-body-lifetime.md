# Scoped HTTP body ownership

The existing Connector, installed Common Effect/Source, Credential journal and
physical HTTPS owners remain authoritative. These same-process byte fields are
not public JSON wire, a ContentRef issuer, an installed capability, an apply
receipt, a new resource owner or evidence that an original holding is funded.

## Two explicit shapes

The original `body: String` request keeps its existing method/body rules and
JSON framing. It is not changed to accept arbitrary arrays or byte objects.

The separate byte shape requires `bodyBytes: Uint8Array`, `bodyMediaType` and a
finite explicit `maxBodyBytes`. The scoped invoker takes that ceiling from its
explicit `maxRequestBytes`. The physical receiver rechecks that the operation's
ceiling does not exceed the call's ceiling before copying. Empty bytes are an
actual zero-length body, not an absent body. GET and DELETE remain bodyless.

`bodyMediaType` is the exact bounded ASCII HTTP field value, not a replacement
for the existing semantic media descriptor owner. The physical adapter owns
Content-Type and Content-Length framing; ordinary provider headers cannot set
either. No normalization, implicit JSON encoding, UTF8 decoding, base64
conversion or a String fallback is applied to the body.

## Original use and currentness

`ownHttpByteRequest` uses intrinsic view length/backing accessors and copies the
selected unshared Uint8Array range into dedicated backing. Caller-written
`byteLength`/`buffer` properties cannot hide shared or over-limit backing. A
shared or detached source refuses; the request cannot acquire an inconsistent
concurrent snapshot. The original caller may retain its own view and backing.
Metadata admission can invoke caller query/header getters. The same intrinsic
view extent is rechecked immediately before copying, so a resized source cannot
leave an uninitialized tail or substitute a larger snapshot. An unchanged
resizable view is not rejected merely for having resizable backing.

The invoker snapshots its body before yielding to the physical port. The
Credential receiver independently snapshots its registered operation before
the secret-resolution await. Mutating the original view cannot replace bytes
after that await. The same original journal still claims, rechecks current
authority and finishes each use. No await is inserted between its final
authorization and physical request construction. No new authority is inferred
from the copied bytes or media value.

Lost responses retain the same nominal Unknown use. Neither a payload match,
the transport's succeeded observation nor a completed body copy is an Effect
apply receipt. This layer never automatically resends a claimed use. Bound
cleanup retains its existing pending state through the real request/socket
retirement; it does not start another request or resolve credentials again.

## Simultaneous inventory

These are representation facts, not adopted numerical capacity coefficients:

- The original input view can retain backing larger than its selected range.
  Charge that backing under its actual original Owner, once per real storage,
  and keep all distinct view/control references until their actual retirement.
- For an N-byte scoped call, the invoker snapshot and independent physical
  receiver snapshot are two distinct dedicated N-byte backings. Their Buffer
  wrappers, operation Map/record, immutable request/header/scope/limit envelopes,
  media String references and pending callback/Promise frames overlap. Direct
  physical calls omit the invoker snapshot; they do not erase the original
  caller's input or the receiver snapshot.
- The physical snapshot overlaps the original request and socket operation,
  response chunks/concatenated response, journal claim/current/finish state and
  any pending failure/cleanup. Response arrival or Promise settlement does not
  retire caller-escaped operation records, original Store holdings or their
  independent cleanup duties.
- Five additional module bindings retain the typed-array prototype, view length
  getter, backing getter, ArrayBuffer length getter and byte-copy function.
  Their module/control/code lifetime remains in the existing Host bootstrap
  inventory, not a new SDK-static/native coverage exemption or a free baseline.
- Zero-length payload does not mean zero record, scope, Buffer wrapper,
  journal, Promise, native adapter or cleanup cost. The payload clamp does not
  bound headers, total network traffic, heap, native TLS or the whole phase.

The actual installed caller must fund these simultaneous holdings in its
existing original envelope before the new allocation. This transport API does
not supply a normal numerical profile, increase a limit or discharge the
unconnected GCS ContentRef/STORE or four-role M1 supplier obligations.

## Verification boundary

The exchange/invocation tests exercise exact range copying, non-UTF8/empty bytes,
explicit limits, forged JS properties, shared/detached input and reserved
headers. The physical tests additionally use real localhost HTTPS, a signed
original Core Credential grant and actual SQLite journal for currentness,
response loss, same-use refusal and cleanup during secret resolution. The
selected compiled Core runtime has its own source/hash qualification; combining
it with changed adapters is not a normal installed cohort, public STORE,
live-service, Model funding or whole-product acceptance.


## Funded query construction

The default HTTP helper accepts at most 32 query pairs and 4096 encoded query
bytes. These constructor defaults are separate from request-body limits and
credential authorization. An installed managed Reader may instead retain a
finite `maxQueryBytes` with its same original `readSequenceConstruction` quote.
The installation service captures that original once; provider request DATA and
reader policy scalars cannot replace it. The existing RowRun reserves the complete
MoonBit quote before request projection, including failed constructor overlap.

`installed_native_source_reader_capacity` adds the selected query's retained
exact target and map/encoding/join workspace under that same parent. Other
readers keep their original default recipe. HubSpot passes its existing finite
`target_units` to both this Core quantity and the service bound, preserving every
selected property and the original metadata/account/current checks. The path is
bounded separately by the same finite extent; it cannot smuggle an unbounded
locator into this selected constructor.

JavaScript measures physical RFC 3986 encoding demand before allocating encoded
components, then assembles the original ordered pairs without truncation or
projection. The pair-count, key/value shape, method/body and reserved-header
checks remain in force. The credential Resource still validates the whole exact
target, original authorization, currentness and cancellation before sending.
A numerical construction quote grants none of those duties or a body allowance.
