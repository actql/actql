# Committed Result descriptions

`Result.describe(options)` projects retained publication evidence. It does not
sample rows, open the payload, start a delivery attempt, or submit a Program.
An empty Result has the same description semantics as a nonempty Result.

The Client–Host operation is `result-describe`. Its closed request and response
shapes are registered in
[the Client–Host contract](../../spec/contracts/actql-client-host.json).
The recursive column contracts come directly from the existing
`canonical_value_contract` in
[the protocol schemas](../../spec/contracts/actql-protocol-schemas.json).
The SDK contains generated validation and transport code, not a compiler or a
separate type system.

## Identity and column order

The response binds the exact Run reference and Result name to their existing
Program Definition, Result Definition, Result Artifact, and Result schema CIDs.
`columns` contains names and full checked value contracts in Result declaration
order, including nullability, nested fields, numeric precision and scale, and
vector dimensions where applicable. The schema CID identifies the canonical
schema map; canonical map ordering does not replace column declaration order.
The publication exporter preserves the checked occurrence's declaration order
in the existing durable binding's `result_fields`. Payload row keys and the
execution receipt's canonical schema enumeration are unchanged.

Existing immutable bindings are not rewritten. Descriptions use each retained
binding's field order. New exports with a noncanonical declaration order have
different binding and dependent publication CIDs; the canonical schema map and
its CID are unchanged by this presentation-order correction.

The common publication owner checks the index, Manifest, exact durable binding,
Result Definition, and schema body. The SDK checks the requested Run/name/profile
and recomputes the schema, Definition, and serialization contract identities.
An Artifact CID is a reference to the published Artifact, not an access grant.

## Publication, retention and authorization

Only a confirmed publication commit can be described. The installed Host admits
the distinct current description/read and egress permissions once for this
public operation, before protected access. Its trusted internal reads consume
those same immutable facts instead of evaluating the same tuple again. Actual
application callbacks or relevant authorization changes retain their current
checks; a new public operation observes current Deny independently. Unavailable
authority denies access. Unpublished, publication-unknown, and unauthorized
Results do not expose a description through this operation.

The physical Store returns retained immutable metadata without opening or
rehashing a payload generation. Existing Manifest read grants authorize and
account for the metadata response. Existing retention owners validate metadata
deadlines and any exact-base retention extension. An expired or deleted payload
does not prevent description while metadata remains retained and currently
authorized. Description success is not a payload-read guarantee and does not
change Result availability or the historical Run outcome. Expired or deleted
metadata is not reconstructed by recomputing the Run.

## Delivery profile and bounds

`format` defaults to `jsonl`. The current public delivery owner admits `json`,
`jsonl`, and `csv`; other formats are rejected explicitly. The returned
`serialization` describes the requested delivery contract (`actql-jsonl/0.1`,
for example), not the internal storage codec. Describing a profile does not
change the SDK row reader's format or promise every value is losslessly readable
through a different consumer.

The whole response, including its Run reference, is bounded by UTF-8 JSON wire
bytes, structural nodes, and structural depth. Defaults and hard ceilings are
1,048,576 bytes, 10,000 nodes, and depth 64. Callers may tighten each ceiling.
Containers and scalar values count as nodes; object keys count as additional
nodes. Root depth is one. Oversized responses fail without truncating columns or
contracts. These limits do not constitute a general process-memory guarantee.
Aborting description stops that metadata request and never cancels the Run.

Confirmed denial, including an absent or reclaimed public index, is
`ResultAccessDenied`. Expired metadata or missing evidence behind a retained
index is `ResultDescriptionUnavailable`; caller bounds produce
`ResultDescriptionTooLarge`. Unsupported caller formats produce
`UnsupportedResultDescriptionFormat`. Malformed or mismatched Host responses
produce `InvalidHostResultDescription`. Transport failures remain read failures;
the SDK never converts description into a new submit.

## Clock commit and current authorization

A returned `sampleTrustedClock` value is durably accepted, not merely a wall
clock observation. Local Store samples after reading the same serialized floor.
Each public Result operation accepts one durable clock sample. Its existing
owned request retains that floor through internal authorization stages and
trusted Store reads; getters and awaits do not commit another observation.
Synchronous time and expiry checks still reject rollback or expiration before
dispatch and after physical I/O or application callbacks. A new public operation
accepts its own observation. Generic explicit-observation Stores use the same
operation boundary without weakening their original commit/Unknown handling.

Local clock records keep their original names. First creation, legacy-record
replacement and size changes commit both file data and the directory entry.
Equal-size updates of an already confirmed checksummed record keep the same
inode and fsync its data before acknowledgment; they change no directory entry.
A torn record refuses instead of selecting an older floor. Failed fsync or
close is not acceptance, and Store retirement waits for the original operation
and any retained failed-close duty. Existing two-field clock records remain
readable; configurations too small for the checksum use atomic replacement.
