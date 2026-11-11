# Store scalar admission import configuration review

This current JS Source review changes only the existing
`src/platform_native/publication_store/moon.pkg` entry. The descriptor at
`5c1a8935e03bfaf9bb95d04e0f6d6d5bb03d82df` is 2734 bytes, SHA-256
`cd70efa7cfa79c9a765b602ed3550ba518ab66ad6bd3ec7766f00e9e4301818b`.
Removing its one 39-byte `decode_scalar @scalar` import reconstructs the
2695-byte descriptor at `3feeecd4936fcf156d8b5293354332813913e59f`, SHA-256
`dfaf6105d166e28289190c97a9aae16bf4eff037da5cbcd5fa767aeb2ebc8598`.
All previous imports, aliases, Native selectors and options remain byte-exact.

The actual `private_evidence_custody_wire_construction` consumer calls the
pure `admit_utf8_length` reader on the original String before constructing
UTF8. The full scalar package and Store source/test memberships, bytes and
modes remain keyed. This adds no external resolver, compiler hook or grant.

The existing JS-only, pinned-toolchain rule remains unchanged. Historical
preimages and default revisions stay intact; old current bytes, altered
imports/aliases/options, foreign targets and toolchains remain refused.
Unknown inputs retain full-source fallback and unresolved reuse. Scientific,
restoration and authenticated archive prerequisites remain mandatory. This
review supplies Source correspondence only, not runtime, proof or reuse evidence.
