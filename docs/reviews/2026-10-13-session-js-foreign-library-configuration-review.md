# Session JS package configuration review

Reviewed source: `9f2bfdb42dcfeac26104c160ed1c5b1770542f3f`. The pinned Moon revision remains `94521db`, with toolchain manifest SHA-256 `8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a`. This finite configuration review establishes neither product acceptance nor an isolated mutation execution. The original `ee7cae5a` isolated-source diagnostic remains 41/42, with its three configuration refusals retained.

## Complete configuration differences

Filesystem adds only the literal Native predicate for `reader_custody_native_wbtest.mbt`. Query Integration adds two literal whitebox imports, `client_infer_host` and `model_execution`; its Native linker/stub settings are unchanged. The existing JS-only review follows every literal import and binds every transitive member, byte and mode. It does not infer that the two packages are absent merely because the selected tests do not use them.

The now-reachable Node connector manifest contains `supported_targets = "js"`, the literal `pkgtype(kind: "foreign_library")`, and literal imports. Relative to the prior reviewed source, its import delta adds capacity policy and moves the existing Value contract alias. It contains no pre-build hook, custom command, dynamic package expression or linker option. This manifest receives a **separate JS foreign-library review**, rather than inheriting the Native-options rule. Unknown paths, bytes, targets, package kinds and toolchains remain unresolved.

A foreign library force-links an artifact for foreign consumers; it is distinct from an executable package. See the [official package configuration documentation](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html#package-type). The actual pinned toolchain, complete current manifest and selected source/execution boundaries remain the evidence here; contemporary documentation is not a replacement toolchain pin.

| Manifest | Exact SHA-256 | Rule |
| --- | --- | --- |
| `src/platform_native/filesystem/moon.pkg` | `c08530c366b004cb0f83d17a705adce8dc28ae78cdd6ff0ce795abbd54ebb8af` | Existing literal Native options, JS target only |
| `src/query_integration/moon.pkg` | `eeeb572afaf8f9b708362db6308b080cc715e65601d54f3ff53d8e1a01f65966` | Existing literal Native options, JS target only |
| `src/connectors_builtin_node/moon.pkg` | `9f8297db67163f7cdef315af82fe878048caea4586363ae5d9ef1f63455e8971` | Literal JS foreign library with bound source membership |

## Selected execution boundary

The original thirteen mutation recipes, targets and filters are unchanged. They select Session/Local adapter correspondence and the Local managed Set/Nest cases. Those actual cases use the existing captured DAG, Local dispatch, retained outputs and cleanup; they do not select the Node journal whitebox test or invoke its SDK adapter loader. The foreign package imports the fixed Node built-in `node:module`; the model journal adapter is loaded only inside its explicit invalidation/whitebox functions. This review does not claim the SDK/journal loader's external input closure for a different test selection.

The complete package members, original recipe bytes, module format and Node/toolchain runtime identities remain keyed. No parser rule accepts arbitrary `pkgtype`; the actual source/staging test must narrow and compare real Git/filesystem bytes, and modified configuration or foreign source bytes must prevent reuse. A separate original-target diagnostic records only the positive cases it actually executes, without mutating source or claiming thirteen mutation kills.

Native/Wasm execution, authenticated Actions evidence, actual isolated images and the complete product/runtime cohort remain separate. This input-policy change invalidates old execution identities; it does not relabel historical receipt success.
