# Exact String values and canonical identifiers

This change separates decoded data from grammar-owned names. It is a common
contract prerequisite for the selected GoogleSQL literal profile; it neither
adds an INFER executor nor completes the full lexical profile.

## Contract

- A String value retains its well-formed Unicode scalar sequence. CR, LF,
  CRLF, and composed/decomposed Unicode are different values. Source escape
  decoding happens once; storage, hashing and replay do not decode again.
- Object member names use Unicode 16.0 NFC, then CRLF/CR to LF, with collision
  rejection and UTF-16 ordering. Grammar-owned identifier readers retain their
  normalization/admission rules separately. String keys in a data relation,
  Graph IDs and parameter values are data, not identifier spellings.
- String extents use the retained value's scalar count and UTF-8 byte count.
  Explicit text transformations keep their selected laws. In particular,
  regex source text and historical quoted machine-expression identifiers keep
  their explicit profiles; this PR does not silently change them.
- Canonical JSON writes exact scalar values using the existing escaping rules.
  Serialization syntax is not part of the decoded value. No contract version
  is raised above 0.1.

## Bytes, identities and compatibility

The kernel and relation scalar law bodies now declare these separate domains.
The REL.values execution contract, selected pipeline registry, AoA contract,
compiler pins, generated fixtures and requirement references follow those
bodies. Structural JSON schemas still describe ordinary well-formed String
values and identifier positions; their shapes do not need a second String
representation or new field. Semantic law pins, not row sampling, select the
String interpretation.

ASCII and already canonical LF/NFC data retain their canonical bytes. Other
values now retain different bytes, and may have different value, parameter,
Program and artifact CIDs. Unit contract closure changes also change Unit,
Result Plan, compiled Plan, capacity witness and Run identities even for an
ASCII-only Program. The independent fixed identity tests reconstruct the old
baseline first, then hash the changed normative dependencies and dependent
preimages; expected identities do not come from a new compiler dump.

Old law pins are explicitly rejected against the changed adopted bodies.
Existing retained baseline fixtures remain historical; no stored record is
rewritten, repinned or deleted. A formerly normalized payload only contains
its saved value: lost CR or decomposed spelling is not reconstructed. Reusing
an old execution's evidence with a newly compiled identity is not supported.
No non-fixture stored data is migrated in this work.

The frozen Frontend PR-0 baseline and imported fixtures remain unchanged. Its
historical parameter oracle is retained byte-for-byte in
[an archival fixture](../../spec/frontend/historical/parameter-identities-pr0.json).
The active corpus changes only two old CRLF expectations and adds six exact
String vectors. The baseline check verifies the original archive digest and
that every unrelated active expectation is unchanged; it does not rewrite
the frozen baseline to match product output.

The following scalar vectors are hand-authored JSON spellings, hashed with
independent SHA-256. Hex is the decoded value's UTF-8 bytes, not JSON bytes.

| Value | UTF-8 hex | SHA-256 of canonical JSON scalar |
|---|---|---|
| CR | `0d` | `8eb852fe331310caa37e80df8a4d52ee8deb3ddc0a5143b52c662d984d9e8018` |
| LF | `0a` | `d7a5e915306d21dc1937ad5616f1dc9682e759e75ef51dd05fd9ddc98a078ea1` |
| CRLF | `0d0a` | `645e13cf9b57d854c950a571c2fb9e25a0aea0d8cf2c4b020a8faa4dad6e16c5` |
| composed | `c3a9` | `f2886017e9c7abacf804b54d64787dce2b611c9544ba21f3affdd126a6e50086` |
| decomposed | `65cc81` | `3d68ce21f2899a475713cdbe7562ba9bdb6b1dfde8af1f221bdff4a0935b53b2` |
| backslash+n | `5c6e` | `63096527de30c146fbca1b5c649d164d7e36849e4a0620609b4d5ff6b445233f` |

## Verification boundaries

- Source JSON/YAML, bounded source builder, canonical JSON, parameter binding,
  runtime value admission and retained row conversion preserve these values.
  Invalid Unicode, duplicate canonical names and exact byte ceilings remain
  checked. Source spans refer to decoded source, including preserved CRLF.
- SDK Checkpoint canonicalization uses the same value/name distinction;
  existing signed-answer behavior remains covered by its tests.
- The packed acceptance sends a source-free SQL Program through the ordinary
  SDK/Host path on Embedded Local and HTTP, reads Named Result rows and
  describe metadata, repeats the request and attaches without accepting a new
  Run. A separate process restores the saved Result on both transports after
  the original process has exited. No compiler is used to rebuild the Result.
- The quoted GoogleSQL lexical expansion is a separate Frontend change.
  This common PR is not evidence that raw/triple/bytes literal forms, all
  scalar functions, every backend, or the whole language are supported.

Reproduce with the repository's pinned toolchain and dependencies:

```sh
node scripts/local-checks.mjs run core --target js
node scripts/local-checks.mjs run core --target wasm
node scripts/local-checks.mjs run core --target native
node scripts/local-checks.mjs run lint
node scripts/local-checks.mjs run spec
node scripts/local-checks.mjs run workers
npm run check:distribution-client
node scripts/test-packed-public-query.mjs --source-free-only
```

On macOS, native SQLite tests use the installed SQLite library via
`ACTQL_TEST_NATIVE_SQLITE_LIBRARY`. Packed evidence records the source SHA,
tarball digests and command results. Successful runs remove their own expanded
installation; `--keep-artifacts` is reserved for investigation. An uncommitted
run is development evidence only. Fixed-SHA and CI results belong in the PR
validation section and the task's local evidence record.
