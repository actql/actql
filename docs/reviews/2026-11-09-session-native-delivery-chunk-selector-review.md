# Native delivery chunk fixture target configuration review

This finite current JS input review updates only the existing review entry for
`src/platform_native/publication_store/moon.pkg`. Historical review tables,
preimages and default revisions remain unchanged.

The immutable descriptor at `3feeecd4936fcf156d8b5293354332813913e59f` is
2695 bytes with SHA-256
`dfaf6105d166e28289190c97a9aae16bf4eff037da5cbcd5fa767aeb2ebc8598`.
Its sole change from the 2641-byte descriptor at
`213f671c7ab7c0fb31c1e8a6c99407fe8e50ce69`, SHA-256
`14135602cf019169768a0ebcf33e59a1795c1553b672d6347d34c10fc2ff9618`,
is the 54-byte clause selecting `delivery_chunk_native_wbtest.mbt` on Native.
Removing exactly that clause reconstructs every previous byte. The same
previous descriptor is retained at the prior review revision
`f86f409e62d39511380497cb0fe5639d5259f191` and the author's genuine parent
`268d1d9bfd6bf2c97f396172a12cfa38d24b8306`.

The Native-only delivery test has no JS stub or execution fallback. This
selector adds no import, alias, default, compiler/linker hook or resolver; every
other option and target clause is unchanged. The full immediate source/test
membership, bytes and modes remain inputs on JS, including the Native test.
Existing historical custody/import selector reconstructions remain independent.

The existing `literal-native-options-with-bound-source-membership` rule remains
restricted to JS and toolchain SHA-256
`8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a`
(Moon revision `94521db`). Previous current bytes, changed selectors/imports,
additional options or selectors, and foreign paths, targets or toolchains remain
refused or unresolved. Unrelated dependency closure qualifications remain
unchanged; this review does not admit other unreviewed inputs.

This review establishes configuration Source correspondence only. It supplies
no compiler, Native runtime, proof-reuse, normal-package or performance acceptance
and promotes no historical execution receipt.
