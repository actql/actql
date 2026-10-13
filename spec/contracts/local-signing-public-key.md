# Local signing public-key identity

This adopted additive identity contract belongs to the existing Credential
Owner. Its opaque Common producer/reader identifies public bytes only. It
does not retain a private key, validate an Ed25519 point, prove private/public
correspondence, supply an issuer/Host original or confer current permission.

The closed canonical body contains exactly three fields in UTF-16 key order:

```json
{"algorithm":"ed25519","public_key":"<canonical padded standard base64 of exactly 32 public-key bytes>","version":"actql-local-signing-public-key/0.1"}
```

The existing ordered value-preserving JSON encoder produces the exact UTF-8
body. Its CID is `sha256:` plus the lowercase SHA-256 digest of those bytes.
The reader admits only the exact canonical body and separately expected CID.
It rejects omitted/duplicate/unknown fields, wrong type/algorithm/version,
noncanonical order/whitespace/escaping, alternate base64 alphabets, missing
padding, nonzero pad bits, incorrect raw length and mismatching CID. The
[schema](actql-local-signing-public-key.schema.json) describes the closed shape;
byte/CID admission remains the Common reader's responsibility.

The constant-size codec ceilings are 256 body bytes, 8 input/decode nodes,
depth2 and 128 bytes per decoded string/256 total. The producer uses the
existing writer with 256 output bytes, 16 nodes and depth2. These ceilings
are codec framing bounds, not a Host/Run funding profile. The producer requires
raw32 before encoding; the reader bounds text before UTF-8/base64 allocation.
No caller-owned mutable array is retained; raw32 access returns only a bounded
fresh public-byte copy.

Equal algorithm/public bytes have equal identity across different PEM layouts.
The CID excludes Host, issuer, key configuration/generation, role and purpose.
Those original bindings remain separate in the existing
[Local signing grant/use contract](local-signing-credential.md). Its historical
closed bodies, signed preimages, vector CIDs and pins are unchanged.

Only trusted explicit installation may bind this producer output to the same
adopted issuer, Host, selected Account/key configuration, physical private-key
projection/generation and purpose. Existing journal/HMAC/counter/transaction
Owners retain that binding. Current issuer issue authority, Reviewer resolve,
Host sign authority, original Checkpoint preimage and finite durable claim
remain distinct operational requirements. Parsing an original or comparing
its CID cannot issue a grant, sign, repair missing custody or resolve Unknown.

Restoration verifies the authenticated original binding; it does not hash
current PEM/file/configuration or recapture a missing original. Before key use,
the selected private key must correspond to the admitted public-key original
through the existing crypto/key Owner. The Native raw32 helper is a
comparison/export primitive and does not own a different CID law.

The [fixed vectors](fixtures/local-signing-public-key-vectors.json) retain
authored raw32 bytes and independent Python standard base64/JSON/hashlib
body/CID expectations, including RFC8032 public bytes. The
[pins/domain inventory](fixtures/local-signing-public-key-pins.json) fixes
this schema, contract and vectors together. These portable identity fixtures
do not execute Native signing, operational installation, public Approval or
installed E2E. D/F connect their existing installation/signing callers
separately; this component adds no Registry, key, grant, capacity or Run Owner.
