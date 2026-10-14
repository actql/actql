# Bounded Root custody: exact test target configuration review

Reviewed source `f089341cd29c2989c1e462333ca2e382fc9c9e55` normally retains
base `7d80451371eb1890932758e59d4af9634e091c01`. The bounded-file manifest is
mode `100644`, Git blob `2c73bd52e13a0d559fdf69cb81aa15adc478b021`,
SHA256 `d3226436c6183cae948253152b6f49c386881ae9f3653c7e970183d7d1b99f57`.

The only new configuration is the literal `moonbitlang/core/env` whitebox-test
import and two literal test selectors:

```text
"root_open_custody_native_wbtest.mbt": [ "native" ]
"root_open_custody_unsupported_wbtest.mbt": [ "not", "native" ]
```

The ordinary imports, supported targets and all product/linker settings retain
their parent bytes. The Native fixture requires a fresh absolute Root and
cannot silently skip; the non-Native fixture checks UnsupportedTarget even
when an input path is configured. No build hook, external source resolver,
compiler argument, linker option or physical permission is introduced.

The existing `literal-native-options-with-bound-source-membership` rule is
registered only for this exact path and digest, JS verification target and
toolchain.json SHA256
`8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a`.
All immediate package members, including both test files and generated
interface, and all literal transitive imports remain bound to actual Git
bytes/modes and directory membership. Changed digests, paths, toolchains and
targets remain refused; unknown options retain the existing fresh-action
fallback. The parser and all previous reviews are unchanged.

This configuration review establishes no compiler or OS correctness, new
Native execution, whole Foundation/Proof success, funding or public result.
Original JS4/Native3/API3target/CLI type results remain at their actual f089
source. The added failure reference still needs the existing lifetime/funding
inventory; normal profile remains None and legacy issue-only facades are not
custody carriers.
