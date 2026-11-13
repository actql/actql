# Local Host File task-boundary selector review

This finite successor covers only `src/client_local_host/moon.pkg` at
`58ebdec4d074bc3d1f70779eca237f904fa2a47e`: 10893 bytes,
SHA-256 `c0e298e3407e0d4b966926b7e4054d269a86c74e18ddd5552d5d119370b79695`.
The complete prior descriptor at
`5d46f7839bab1146ce3763d6e8b08f57f5daab6c` remains retained: 10836 bytes,
SHA-256 `f6711ed47a6251f7f3c6bc75191c1f4b4215b050ee05594b24f70a683aa1972b`.

Removing exactly this 57-byte literal selector reconstructs the
prior descriptor byte for byte:

```text
    "native_file_task_boundary_js_wbtest.mbt": [ "js" ],
```

All imports, aliases, existing target predicates and other options remain
unchanged. The new whitebox test uses the existing JS-only fixture environment
and a fixed repository JSON Program. It reads no installation, state, business
Run, credential or provider. Its shared authored Program is
`scripts/fixtures/native-file-task-boundary.json`, SHA-256
`60796aa128a1c4812fbb6e75cd90aaa1a9ed309f868181cae2ade6374829df48`.
This fixture supplies only source/checking evidence; the separate ordinary CLI
collector must execute real File input to establish Native acceptance.

The existing `literal-target-selectors-with-bound-source-membership` rule stays
restricted to JS and the unchanged pinned toolchain. The current map admits
only the exact successor digest. Previous descriptor preimages stay intact;
they cannot qualify the new input. Changed selectors, imports, options, paths,
targets or toolchains remain refused or independently rekeyed. Every immediate
source member, mode, byte and import closure remains an input. This review
adds no wildcard, build hook, resolver, runtime permission, historical evidence
promotion, compiler/runtime acceptance or proof-reuse authorization.
