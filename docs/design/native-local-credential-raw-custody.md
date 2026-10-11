# Original Native Local preparation response custody

A raw observation is a private transport fact owned by the existing credential
use journal and private Store. It is distinct from an admitted Catalog,
checked projection, Result, Model capture and semantic Effect outcome. Retaining
HTTP status and exact body does not grant current read, Provider send, approval,
retry or disclosure authority.

## Host assembly and independent authority

Live preparation transport uses the explicitly adopted original Host journal's
database for credential-use records. It does not initialize another database
when originals or terminal rows are absent. The original Run's retained
publication binding must match the actual Store authority, namespace and
original opened database identity before assembly and at each current check.
The Host restores the authenticated original installation; assembly cannot
adopt a freshly observed credential file or issue a grant.

The existing acknowledgement's current Work, target and separate issuer
authority remain required for `claim` and `send`. Raw `query`, `return`,
`raw-query` and `raw-return` instead require current Run and checked-target read,
the same exact original scope/request/grant, and committed grant custody with
its original reservation. Issuer issuance permission does not authorize raw
disclosure. Both paths recheck original Work and Store binding after callbacks;
the credential Owner additionally validates the original use, trusted lifetime
and durable revocation. A live acknowledgement connection does not supply a
post-closure Work token or recreate one from an identity-only reference.

Original raw recovery has a separate borrowed read view of the same credential
journal and private Store. The credential Owner shares its original-use,
outcome, durable revocation and trusted-clock readers between live transport
and this view. No HTTP client, secret installation, issuer or claim method is
required to retrieve retained bytes. The Host still supplies authenticated
original Run/grant/Store custody and current checked-target read; the reference
and read-view binding are not authority. Query and return recheck current
permission, the original use's lifetime and durable revocation after callbacks.
Closing a Work does not create a replacement send fence. Missing use/response
custody, denied disclosure or expired/revoked material refuses without repairing
the original outcome or allocating another use.

The original Account resource is retained privately beside a Preparation grant
under its existing operation row key. Its supplier is the original checked
member/target and selected Provider through the live preparation fence. The
closed record binds the operation, grant, original request scope, Host adoption,
Run invocation, checked occurrence, issuer selection, Provider file/selection
and Account resource. The existing original private epoch key authenticates the
closed payload with HMAC-SHA-256 before it is stored or consumed. It changes
neither public grant bytes nor the operation
identity. Fresh grant and target inserts share the same original journal
transaction. An exact replay verifies both immutable rows; a retained grant
without its target cannot be backfilled. Foreign targets, changed Providers,
orphan target rows and altered originals refuse. Missing legacy target material
remains unavailable for disclosure rather than causing reacquisition.

Both rows count toward the existing 65536-byte original-grant bucket for that
Run, including their actual encoded byte lengths. The 64-grant per-Run bound,
Host record-count bound and physical database ceiling remain unchanged. No raw
Store reservation or payload pool is created by target retention. The target payload is at most 3072 bytes, before base64 and its 64-character
authentication tag. The authenticated envelope uses the existing bounded setting codec: at most 8192 input/output bytes,
64 syntax/encoding nodes, depth four, 4096 bytes per decoded string and 8192
total decoded string bytes. These are separate tree/control workspace bounds,
not ciphertext sizes. Checked resource/file strings are borrowed until the
original bucket is reserved. The simultaneously retained grant/payload/envelope buffers are
bounded by 49152 grant bytes + 3072 payload bytes + 4183 envelope bytes =
56407 bytes; custody audits decode one row at a time
and retain only the existing bounded per-Run usage map. Additional base64 strings are bounded by 4096 characters, the tag by 64, and
codec buffers by their selected 3072-byte payload/8192-byte envelope limits.
Authentication/base64 decode also uses at most 3072 payload bytes; each decoded
target and envelope tree has at most 64 nodes and depth four. These buffers and
tree/control bounds are workspace costs, separate from retained Store payloads.
Database record limits,
physical file identity and Store workspace limits still apply independently.

A post-closure reader accepts only the exact original grant reference and an
already-open Store matching the original Run publication binding. It validates
the saved target and currently adopted configuration, then independently checks
current Account permissions for the original Run and resource. It obtains no
issuer issue authority, Work, installation secret or HTTP client. Missing grant
and target originals are typed unavailable conditions; neither can be repaired
by a lookup. Current authorization and Store custody bracket each credential
read-only lookup and the final return. Original use/outcome/raw-envelope checks,
expiry, revocation and cleanup custody stay with the credential and Store Owners.

The private raw Store AES key is derived as HMAC-SHA-256 using the existing
authenticated private epoch key. The UTF-8 message is the closed, value-preserving
JSON object, in this order: `adoption_cid`, `domain`, `store_binding`.
The domain is `actql-native-local-preparation-raw-key/0.1`; the other fields are
the actual original Host adoption CID and exact existing installed-publication
binding. This derivation creates neither a public grant identity nor another key
Owner. Missing or corrupt epoch custody refuses rather than regenerating a key;
the key is never returned to callers. Existing grant/use, Remote and Resume
preimages and private envelope AAD remain unchanged.

## Original binding and representation

The initial operation is the existing typed Local Preparation
`salesforce:record:observe` GET. A valid original
`LocalPreparationCredentialGrant` and its admitted
`LocalPreparationCredentialUse` supply the original Host adoption, account,
principal, Run invocation, request intent/scope, preparation fence, checked
operation occurrence, unit definition, provider binding, exact request path and
empty request-body identity. Another grant's valid use is not interchangeable.
The Store's actual authority is independently bound.

The original slot preimage is the ordered string array:

1. `actql-native-local-preparation-raw-response/0.1`
2. actual Store authority CID
3. original grant CID
4. original use CID
5. exact canonical original grant wire
6. exact canonical original use wire

The holding CID is SHA-256 over the UTF-8 preimage. Neither the response nor a
later capacity choice creates another slot for the same original use. This CID
is an identity, not authority or evidence that the operation was unsent.

The preparation descriptor appends the decimal response ceiling originally
projected by the existing HTTP Client. The raw observation appends that same
ceiling, the exact nonnegative physical status in decimal, `sha256:` plus the
exact-body digest, and canonical base64 of the original body. Closed decoding
requires ten string fields and exact re-encoding. Empty and non-UTF-8 bodies,
Unicode composition and CR/LF/CRLF are preserved. Non-2xx responses and responses
rejected by a later Catalog projection remain raw observations; no projection
is synthesized to make them admissible.

## Physical role and compatibility

The additional closed physical AAD role is `credential_raw_observation` in the
existing `actql-private-publication-evidence/0.1` envelope. Its AAD is the
unchanged UTF-8 template:

```
actql-private-publication-evidence/0.1 NUL credential_raw_observation NUL holding_cid
```

The closed role admission in the Native signature Owner, existing Node private
holding adapter and Node Store must agree. All prior roles, their envelope
bytes, semantic identities and AAD preimages remain unchanged. A raw envelope
cannot authenticate as Catalog, capture, Model or another private role. These
physical adapters do not themselves issue a semantic raw binding or permit.

## Reservation, persistence and restoration

Before physical GET entry, the existing `publication_payload` capacity Owner
must durably reserve the original descriptor and maximal raw envelope costs,
including two held records, against the same original slot. No later dispatch
budget, fresh grant or new pool is borrowed. The actual HTTP response ceiling,
Store record limit, cipher plaintext limit and existing Store capacity remain
binding. An insufficient bound refuses before send.

For this unchanged cipher representation, an envelope's byte count is
`128 + 4 * ceil(plaintext_bytes / 3)`. The response plaintext bound includes the
fixed original fields, maximal decimal status, body digest and base64 expansion
of the original response ceiling. The descriptor envelope cost is separate and
must also be reserved. Computing that finite requirement is not proof that a
reservation or physical entry occurred.

The raw observation must be durably saved and read back before a successful
response ACK or terminal outcome. Current policy and the existing preparation
fence bracket callbacks and durable boundaries. Protected retrieval applies
current authorization independently of cleanup responsibility.

An empty raw slot, missing original credential DB, missing terminal row, unknown
physical entry or lost ACK is not proof of non-execution. The existing credential
use's atomic entry and reconciliation remain authoritative. Restoration never
claims a new ordinal, starts another GET, renews a grant, resets expiry/uses or
constructs another Run. Missing or corrupt original custody is a typed refusal.

Cleanup retires the retained descriptor and response through the existing
Store responsibility before returning their exact reservation. Failure retains
that Owner and its retry handle; successful retirement cannot revive evidence
or return capacity twice. Current read denial does not erase cleanup custody.
