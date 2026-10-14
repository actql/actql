# Native Store failure custody: target and exact configuration review

Reviewed implementation Source `91c7cb60640b311d110181f0748d4a0fed3be4b8`;
previous main is `469194ec4de744660c19ac60a18472bdf4b8d8e9`. The previous
[constructor configuration review](2026-10-14-session-native-constructor-config-review.md)
and its Sources/results remain historical.

The failed-open state has concrete Root, Lock and Database fields only where
those constructors run: Native. Unsupported targets retain the same nominal
opaque failure type and `issue`/`retry_cleanup` signatures. No failure value is
acquired there; existing open functions continue refusing before acquisition
with UnsupportedTarget. No external field, constructor, warning suppression,
dummy acquisition, cleanup ACK, authority or alternate Owner is added.

The private missing-custody marker now records presence as Unit rather than
unused Root/Lock variants. Original issue and child-first cleanup bodies are
unchanged; missing custody remains sticky CleanupPending. The one factory is
Native-only, with six existing production call sites and its existing Native
WB use. The portable synthetic model's assertions and original issue are kept
verbatim and selected as a **Native model-only case**, not physical evidence.
The existing three real Native custody cases remain a separate scope. Earlier
JS model success and strict failures are not transferred to either scope.

An explicit-public/all-private struct trial still produced the pinned
struct-never-constructed diagnostic on JS; that trial is not the adopted
representation. Target separation preserves the original opaque API form.
Compiler-generated API comparison and selected tests remain separately
source-qualified; this source review does not assert they ran.

| Manifest | Exact reviewed SHA256 | Git blob, mode100644 |
| --- | --- | --- |
| `src/platform_native/publication_store/moon.pkg` | `da2ed748a2cee398537d8be64de7e695446009fcdce04a6cf09ec69f0d9f0fa0` | `9572833c6a3f8d2ca9f68841283c15960dd5cd63` |

The only manifest difference is the literal
`"open_failure_gap_wbtest.mbt": [ "native" ]` predicate. Removing that line
restores the entire previous manifest. Normal/WB imports, aliases, supported
targets, stub, linker settings, other predicates and absence of build hooks or
external resolvers remain exact. Pinned JS cannot invoke the Native linker/stub
through this predicate. Complete normal/Native/WB source membership remains
bound to actual Git bytes and modes, even for source not executed on JS.

Refresh this one exact digest and its reviewed implementation reference under
the existing literal-native-options-with-bound-source-membership rule. Other
Native configurations and the separate JS foreign-library review remain
unchanged. Unknown digest/path/option, other target/toolchain and full-source
fallback refusals are not weakened. Changed configuration/source inputs require
fresh source/staging identity; they supply no Native runtime, installed/public
acceptance, capacity funding or release-artifact provenance.
