# Checkpoint answer construction

## Shared document authority

The pure Common checkpoint_document constructor and the registered
checkpoint_answer_construction recipe describe the same candidate documents.
The existing execution_checkpoint schema supplies kind, subject, phase,
required-artifact and ordered-claim inventories. The recipe selects supported
candidate profiles and transports fields; it supplies no second kind table.
The Common profile functions and private candidate flags are generated from
those originals. The existing typed constructor consumes the generated flags.

These constructors produce candidate DATA. They do not create a sealed
Checkpoint, reviewer authority, current permission, Run or durable commit.
The Host independently checks its original Checkpoint and authorization,
signatures, current state and transaction before accepting an answer.

## Bounded capture and staging

The codecs take explicit wire-byte, value-node and container-depth bounds.
Capture owns the Summary, actor key/reviewer IDs, optional authority scope,
decision and time before any asynchronous digest. Field reads and crypto
primitive receivers are retained once. Changing the input or primitive
properties while a digest is pending cannot replace those originals.
Opaque stages belong to their creating codec and expose no mutable tree.

Identity Text paths come from the Common-owned recipe and are checked without
silent normalization. CID fields retain their registered strict domain.
Display and arbitrary data strings retain exact scalar contents; empty display
is distinct from missing/non-string display. The existing Gregorian
UTC-millisecond domain includes year zero.

JS uses the existing canonical JSON and byte-CID primitives; Python uses their
existing lightweight SDK counterparts. Neither loads a Local Host engine,
calls Node from Python or evaluates accounts. Actual signing, I/O and key
custody remain with the caller. Construction limits are not Ledger allocation
or authorization.

## Canonical frames and signatures

The retained stages are unsigned approval, unsigned Resolution with optional
signed Evidence, and complete signed Resolution. Each application signature
consumes the unsigned CID text's UTF-8 bytes, not raw JSON.

Attaching the existing Ed25519 proof checks canonical Base64 and pad bits; it
does not verify a signature. The signed self CID is computed after proof and
before adding its root self field. Evidence hashes the complete canonical body,
including compatibility approval and its self CID. Rejection has no approval
signature or Evidence; omission is not null. Final output keeps the original
Checkpoint CID and exact canonical wires. Supplied IDs/signatures confer no
authority.

## Refusal and original lifetime

Unknown shapes/profiles/claims, noncanonical identifiers, invalid windows,
signature representations and exhausted bounds refuse by a named candidate
error. No truncated artifact or partial Evidence is returned. Rejection's empty
Evidence wire is registered absence, never an encoding-failure fallback.

Stages keep original data and key identity through the application's awaited
signature. They do not refresh authority or retry approval. Durable storage,
exact saved-wire redelivery and Host verification keep their existing owners.
A process-local stage is not recovery or commit proof.

## SDK consumers

The SDKs delegate candidate selection, claims, time windows and document fields
to their generated codecs. The existing resolve-item ceiling bounds each
construction frame to 16 KiB; its byte ceiling also bounds value-node count.
The existing SDK JSON depth ceiling remains 64. These are local construction
bounds, not permission or a Host resource allocation.

The application signer and its original receiver are captured before the first
await. Only the generated unsigned CID text is passed to that callback. The SDK
attaches the actual returned signature to the same opaque stage. Cancellation,
Client close and lost-reply handling retain their existing operation owners;
saved signed wires are redelivered exactly without reconstructing or signing.

An installed original-answer callback still owns its independent Checkpoint,
key and current checks. The SDK compares its actual returned proof bytes by
constructing the expected candidate from the same admitted Summary and the
returned actor/time, then comparing complete bounded wires. It neither signs
again nor treats a matching candidate as Host authorization.

Fabricated noncanonical control identifiers that earlier SDK code accepted are
now refused before signing, matching the existing Host identity domain. Legal
display DATA keeps decomposed text, CRLF and empty strings. Invalid candidate
shapes or claims use the SDK's named `InvalidCheckpointAnswer` with the generated
issue retained as its cause; the SDK does not reread caller fields to classify
that error. Fixed tests keep their own original decision clock rather than
weakening the Common window.

## Generation and verification

The existing Client–Host generator emits Common profile selection and the JS
codec; the existing Python Client generator emits its codec from the same
recipe/protocol projection. Their read-only checks verify actual outputs.
Handwritten renderers remain implementation source; generated comments alone
prove neither source correspondence nor binary/runtime acceptance.

The same generator emits TypeScript declaration mirrors for the JS validator
and candidate codec. Resolution types expose conservative structural fields;
conditional field relationships, bounded canonical admission and identities
remain checks in the unchanged runtime validator. Candidate and resolution
stage brands distinguish the two stage kinds at compile time. They do not
establish which codec owns an original, its lifetime or any signing authority;
each runtime continuation still checks the original in its own WeakMap.

Independent signed vectors exercise Common and both language codecs. Consumers
check exact bytes/CIDs, captured inputs/receivers, signature omission, identity
versus display domains, strict bounds and lightweight Python import. These
boundaries are separate from normal installation, Host signature admission and
ordinary funded Checkpoint continuation.

## Review integrity DATA

The pure Common `review_bytes_match_cid` owns the two existing review identity
forms. Their versions and root self-field come from the registered Model and
Effect review schemas. The existing generator projects those profiles into the
small SDK codec; callers delegate rather than selecting a version or removing
fields themselves. Remote SDK imports require only their existing JSON and
digest primitives, never a Local Host engine or a sealed Checkpoint issuer.

The complete-byte digest is checked first, preserving legacy review transport
including non-JSON bytes. The semantic path requires exact canonical UTF-8,
the original requested self CID and root-only self-field exclusion. Nested
fields with that name remain in the preimage. Model retains the existing
identifier-key domain; Effect display DATA preserves exact keys, decomposed
strings, supplementary scalars and line endings. BOM or whitespace cannot
become a semantic identity by decoding it away. Unknown versions refuse.

Explicit byte, node and depth limits bound Common parsing and output. SDK
transport already limits received bytes; the Node caller derives its finite
structural bound from that extent, and Python retains its existing JSON node
and depth policy. These are integrity construction bounds, not a new Ledger,
allocation grant or Run budget. The Node codec copies bounded input bytes
before its first asynchronous digest so later mutation cannot substitute a
different original. Python captures the same immutable byte value before
parsing. Errors return false; they never authorize retrying an approval.

Integrity is DATA only. Host authorization, currentness, retained original
Checkpoint membership, signatures, cancellation and cleanup remain with their
original operations. No matching digest supplies any of those facts. Fixed
preimages and existing public review consumers independently check this
boundary; successful pure checks do not establish normal Host acceptance.
