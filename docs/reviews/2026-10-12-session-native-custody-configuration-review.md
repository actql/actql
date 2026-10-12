# Session JS Native custody configuration review

Reviewed source: `22174e19f86b8bf8d56b434f344118d99d004d72`.
The prior review at `aae65b850faa3a6d02247c40f8270c8b5bd2d62c` remains in
[its original record](2026-10-11-session-local-import-configuration-review.md).
The unchanged toolchain manifest digest is
`8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a`.

The complete seven-manifest delta contains literal imports and Native-only
file predicates. Native Values adds a whitebox Source frontend import.
Filesystem and HTTP select existing Native implementations and their
non-Native refusals. SQLite adds the literal filesystem dependency and
Native-only database custody tests. Publication Store and remote Journal
add literal credential/resource/codec dependencies and Native custody
implementations with corresponding non-Native refusals. Result Access adds
a literal whitebox filesystem import and three Native-only tests.
Existing stub filenames and Native compiler/link flags are unchanged; there
are no build hooks, dynamic imports, linker expressions or toolchain changes.

On the pinned JS target these predicates select existing bound source files,
while Native stub and linker settings cannot run the Native toolchain.
Literal imports are still followed independently of the finite configuration
review, and every transitive package member, byte and mode remains an input.
This review does not assert Native execution, physical custody or compiler
correctness. It adds Result Access to the same exact-byte JS policy and
refreshes the six changed entries; it does not accept arbitrary native options.

| Manifest | Reviewed SHA-256 |
| --- | --- |
| `src/native_values_integration/moon.pkg` | `7e6c593d713e34a6c57ef95eae7e29f483b63a9f7f4ab2804e0d5106b1d009c5` |
| `src/platform_native/filesystem/moon.pkg` | `1fdf8e1c135a437697a90792af0cfce232676d69b087fdcc7815dd035379007e` |
| `src/platform_native/http_client/moon.pkg` | `15810606a042f2a8b203acb9a4190a83f880447bc317980db43ca3cfeeafd9e2` |
| `src/platform_native/publication_store/moon.pkg` | `171bfbbd3ea85ba7e87108148946abdb175d6f4667161db9c9127c6171e2fdf7` |
| `src/platform_native/remote_journal/moon.pkg` | `a16cc63e68918f4208620e6137d0d55fbb128c42b0d80723a43c6f0c86bf9602` |
| `src/platform_native/result_access/moon.pkg` | `0ed904ab54effb2f116b1eb3b7b285f20c94ec75ce099b93f47f4a08377a0d37` |
| `src/platform_native/sqlite/moon.pkg` | `85f4441481063cc7ac5a9cd2e7e277216dc3100513a6de632bff6174d9efedc3` |

The existing actual-Git source test must narrow, stage and compare the real
source closure and original restoration snapshot. Mutating any of the seven
reviewed configurations retains the explicit unresolved reason and full-source
fallback. Native/Wasm targets, a different toolchain, unknown configurations
and changed bytes remain unreviewed. Changed policy bytes also invalidate
old execution identities; this is not a claim of reusable old acceptance.

The fixed `02def1be` checkpoint's original 37/38 isolated-boundary result and
seven unresolved configurations remain unchanged. This source review repairs
the later current input policy; the real mutation campaign and authenticated
Actions evidence remain separate obligations.
