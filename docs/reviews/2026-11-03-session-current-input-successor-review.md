# Current Session manifest successor review

Reviewed source: `66e7845f75c4eef5ebbb8d59d5fb4b652f73aa0c`.
This is a finite JS input-identity review. It does not establish compilation,
Host execution, physical custody, evidence reuse or Native correctness. Every
historical review and captured corpus retains its original source identity.

The five complete manifests below were read against their preceding per-entry
review. Each import is a literal local `actql/actql/...` package or pinned
`moonbitlang/core/...` package. Transitive imports, every source/test member,
modes, membership and toolchain remain separately keyed by the existing
extractor. No package-language interpretation or fallback rule is added.

| Manifest | SHA-256 | Reviewed difference |
| --- | --- | --- |
| `src/client_local_host/moon.pkg` | `4c1eff238ebdad084307b08ded8a57684faeac8d6af0d5e01b40ccf8aeef469c` | Against `523ada3259bf9e8147f746727fbfd56065036fd5`, seven named JS WB selectors are added; one duplicate check-boundary selector and one duplicate Effect-provider selector are removed while their original selections remain. Imports, supported targets, production JS/portable selectors and all other options are unchanged. No command, resolver or linker is introduced. |
| `src/connectors_builtin_node/moon.pkg` | `707ebd62113403d8c1a08c3db9ea28d5e899c3c80d6ac7dc5cfadd545045ac38` | Against `523ada3259bf9e8147f746727fbfd56065036fd5`, only literal GCS and HubSpot catalog imports are added. They enter the same recursive source closure. The exact JS target and `foreign_library` kind retain their separate existing rule; this does not admit arbitrary package kinds or native linking. |
| `src/connectors/kintone/host/moon.pkg` | `85ba3f07ed79308b595b1c00cf085a87f2d7ec9f9f40c88be4ffc1c264d216bd` | Against `523ada3259bf9e8147f746727fbfd56065036fd5`, only the literal `source_value` import is added. The existing JS WB selector and supported targets are unchanged. No build hook, external resolver, stub or linker exists. |
| `src/platform_native/runtime_bundle/moon.pkg` | `1d8c003fea820e24835d1b6539d0e42e5908103e8d776a7c91b525b64dee02e4` | Against `38e95bfac2907700456de6c53ed0cad3620bb72d`, only `store_trust.mbt` and its WB test receive explicit Native selectors. All imports, unsupported counterparts and other selectors are unchanged. JS cannot select these Native bodies; their bytes remain inputs. This does not qualify Native Store trust behavior. |
| `src/query_integration/moon.pkg` | `179d0c70d9c11c032372634cef98528fdebe13e3afb97a1e917c51bf0d1515fe` | Against `38e95bfac2907700456de6c53ed0cad3620bb72d`, only the named `strategy_cleanup_current_js_wbtest.mbt` JS selector is added. Literal WB imports and the original Native-only `cc`, `stub-cc` and SSL/crypto link flags are unchanged. That Native branch does not execute on this reviewed JS path. |

The existing map has the same eighteen paths. These five exact digests receive
this review revision; the thirteen unaffected entries retain their complete
previous descriptors. Ten entries now have explicit successor revisions. The
original default and archived descriptors are not rewritten or inferred from
current files at admission time.

The target remains JS and the toolchain digest remains
`8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a`
with Moon revision `94521db`. An unrecognized digest, option, path, target,
toolchain, dependency expression or additional nested fixture stays unresolved
under the original rules. Native-only link/stub configuration retains its
original literal path and source membership; no linker execution is claimed.
The three previously reviewed inert nested C fixtures are unchanged. No source,
compiler, policy, runtime, collector acceptance or mutation verdict is modified
by recording these five successor inputs.
