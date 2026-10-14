# Exact filesystem read-layout configuration review

This extends the existing `literal-native-options-with-bound-source-membership`
review to the already adopted source
`93a7f22cc369e17b985436fbec3a3f9dddaa71fb`, whose sole parent is
`fa968102a08ad0bf183ba9f35afe4fe89390a599`. Both remain genuine ancestors.
The manifest `src/platform_native/filesystem/moon.pkg` is mode `100644`,
Git blob `6be8d2efc30f2fd7779b8ea66ccc3516e0f7e578`, SHA256
`bb816061434a3d23d1446366e137d3e64539cd0ef6ae191bea81f71f93400a86`.

The entire manifest delta consists of four literal target selectors:

```text
"read_layout_native.mbt": [ "native" ]
"read_layout_native_wbtest.mbt": [ "native" ]
"read_layout_unsupported.mbt": [ "not", "native" ]
"read_layout_unsupported_wbtest.mbt": [ "not", "native" ]
```

Removing these four lines restores the exact parent bytes, Git blob
`88862f3da79f28814061ad0b159abca6e451e281`, SHA256
`765802bc29d68ff7e87d427d3e68555fb648387de56ad49b2052fdff412f376b`.
The [original package-observation review](2026-10-14-session-package-observation-config-review.md)
and its six-selector introduction assertions remain historical and unchanged.
Imports, aliases, supported targets, Native stub declaration, prior selectors,
and the absence of build hooks or external resolvers retain their exact bytes.

The new Native body reads three representation fields from the existing C
implementation; its unsupported body returns `None`. The portable type and
all four selected files are immediate Git members, mode `100644`. Neither
backend issues a capacity, authorization, descriptor-custody, retirement or
allocator-charge witness. This metadata registration establishes no execution
of the Native body, installed provider, scoped allocator or public product.

The exact path/digest is registered only for JS verification, Moon `94521db`,
toolchain.json SHA256
`8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a`.
Every source member, generated interface, C/header byte, mode and literal
transitive import remains bound by the existing selector. Old digests, changed
selectors/imports, foreign paths/targets/toolchains and unknown options remain
unreviewed and require fresh work. The parser, validator, review rule and other
configuration identities are unchanged. This is no whole Foundation/Proof,
compiler/OS, numerical funding or public acceptance result.
