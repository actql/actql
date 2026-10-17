# Original HubSpot request marker

The existing public HubSpot contract requires each physical batch to retain
its original request identifier and write that identifier to a connection-named
property such as `actql_request_id`. `objectWriteTraceId` remains response
correlation only; it is not that persisted marker or an idempotency promise.

The existing Catalog/Request Owner validates a bounded `RecordRequestMarker`
against positive writable string metadata. Its caller supplies the identifier
already associated with the original Effect items: preparation issues no new
identifier, ledger row, authorization or provider property. `hasUniqueValue`
is not required for this non-key metadata and is never inferred from it.

A marked request retains the original Catalog, original inputs and business
`WriteBody`/selectors plus the same marker and its complete physical Encoder
document. The marker cannot also be a business field or selector. The business
value projection remains exact; the separately bound physical body contains
both the original provider spellings and the marker. The unmarked API keeps
its original bytes and refuses/accepts exactly its prior inputs. It is not an
implicit fallback for an installed Effect requiring a marker.

The marked encoder reads only its own complete Encoder-produced object of
string properties through bounded Source/Decode, then emits those exact
strings plus the marker in checked UTF-16 order. It does not parse business
numbers through binary64 or reconstruct opaque values. Caller-selected
existing write-body and request byte/node/depth limits cover complete input
and complete output; overflow returns no truncated request. Original business
strings, UTF-8/parse/cursor copies, sorted names, marker control and final
request document can overlap. The old request now also has a private optional
marker reference. The actual JS marker-fields projection additionally holds a
two-reference array and boxed Option; the two original value/target String
projections are unboxed references in this selected compiled runtime, not a
universal Option convention. Callers use the existing generated binding and
check the original batch count/index before interpreting an absent target. These are explicit inventory inputs, not a funded normal
profile or zero-cost diagnostic/baseline claim.

Before sending, the existing physical path still checks the original portal,
current Catalog, current Account/credential and original nominal use. A lost
reply retains the original request/marker and Unknown without another send.
A matching marker value alone proves neither application nor permission:
reconciliation still needs the original target's complete property-history
entry, app/source, request time window and the same original claim under the
existing Host owners. This unit does not supply that history observer, a
sealed Preview, claim, receipt, recovery ACK or installed Host completion.
