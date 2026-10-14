# Transfer Journal: exact Native WB selector review

Reviewed Source `35b919cbe3b4508108b3b49f124db17e7790847a` retains the prior
[Native configuration reviews](2026-10-14-session-native-store-failure-scope-review.md).
The Journal manifest change was introduced by
`01ce3a949932b5b6e55405c14dc04d69373626ae`, whose actual parent is
`3dfe5a2dc371b17ff06aa4d6eeddf5e9263b2918`; both are ancestors of this Source.

| Manifest | Reviewed SHA-256 | Git blob, mode `100644` |
| --- | --- | --- |
| `src/platform_native/remote_transfer_journal/moon.pkg` | `4af6a1f153011554ab829bb6b494cbd8a8cf32110ed39f66de7c7974993411b5` | `d8e86fc06048e7e981e749ee8b980260be2994e9` |

The only manifest delta is
`"open_close_custody_native_wbtest.mbt": [ "native" ]`. Removing that line
restores the complete parent bytes, SHA-256
`da01cf66f62a1632dce894f19a8d781d3b8c7f4d822aaf71e3e1cb1d07556ffd`.
Normal/WB imports, aliases, supported targets, all other predicates and linker
settings are unchanged. This WB file is excluded on JS; the pinned JS path
cannot execute a Native linker or stub through the added selector.

The existing `literal-native-options-with-bound-source-membership` rule applies
only to this exact path/digest, JS target and pinned `toolchain.json` SHA-256
`8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a`
(Moon revision `94521db`). All ten immediate Journal members, including the
Native WB file and generated interface, and literal transitive dependencies
remain bound to actual Git bytes, modes and directory membership. The transfer
reader's existing SHA-256 dependency remains included.

Only this configuration digest and the review's Source reference are refreshed.
Other registered digests, the separate JS foreign-library review, parser and
fallback/refusal logic are unchanged. Changed paths, bytes, imports, options,
targets and toolchains still require review and fresh input identity. Previous
Native-three, unsupported-JS-one and three-target API results retain their
original Sources; this registration and Node policy validation establish no
new Moon execution, mutation, Foundation, installed/public or numerical result.
