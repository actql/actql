# Local signing public-key identity proposal

Status: **approval pending**. This proposal is not an adopted identity rule,
normative specification, registered schema, installed Core API or signing path.
The accompanying MoonBit files are unapplied source candidates. Source base:
`97828fc4d42b2fd7a30acaaff679df3ec1f95111`.

The existing Local signing grant references `key_public_key_cid` without an
operational identity producer. This proposal would place that pure producer
and reader within the existing Common Credential package.

The proposed closed body has exactly three lexically ordered fields:

```json
{"algorithm":"ed25519","public_key":"<canonical padded standard base64 of exactly 32 bytes>","version":"actql-local-signing-public-key/0.1"}
```

Its CID would be `sha256:` followed by the lowercase SHA-256 digest of those
exact canonical UTF-8 body bytes. The proposed reader rejects duplicate,
unknown or missing fields, another algorithm/version, noncanonical JSON,
nonstandard base64, missing padding, nonzero pad bits, wrong byte length and
independent expected-CID mismatch. Codec framing limits are fixed for this
constant-size identity, not a Host capacity profile.

The body would identify only algorithm/public bytes. Equal public bytes from
differently formatted PEMs would have the same identity. This does not validate
an Ed25519 point, prove public/private correspondence, retain a private key,
identify a Host/issuer/generation/purpose or grant permission. Existing
authenticated installation originals, current authority, original Checkpoint
preimage and finite credential claim remain separate and required. The Native
raw32 helper remains a comparison/export primitive, never a CID issuer.

No existing grant/use schema, signed bytes, vector, issuer permission, key,
registry, operation or numeric profile is changed. The source candidate has no
operational caller. It cannot turn parsed metadata into signing eligibility.

The two fixed body/CID vectors use authored raw32 bytes and independent Python
base64/JSON/hashlib calculations. Node rechecks the fixed vectors and the
proposed schema. The PEM-layout test concerns only fixed public SPKI framing;
it neither invokes Native key validation nor signs a message.

After explicit approval, the separate adoption patch would add the candidate
files and base64 import to `src/remote_credential`, generate/check the current
three-target API and select its six direct portable identity cases plus existing
grant/use regressions. The schema/domain inventory and normative Owner import
would then be registered through existing mechanisms with the new fixed pins.
Historical grant/use/vector pins must remain byte-identical. Those adoption and
operational caller changes are intentionally absent from this proposal.

Automatic approval review rejected the attempted adoption notification because
the exact persistent security identity rule lacked trusted user approval.
The former adoption decision was withdrawn. This document/source prepares a
concrete reviewable proposal; it does not bypass that rejection. Native signing,
actual Approval and installed E2E remain unaccepted.
