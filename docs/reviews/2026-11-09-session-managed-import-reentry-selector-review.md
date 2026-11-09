# Managed import current-hook fixture selector review

This finite current JS input review updates only the existing
`src/client_local_host/moon.pkg` entry. The default review revision and all
historical preimages remain unchanged.

The descriptor at `1d65ca8b449c6a6edae8ba0b5a0b0bfbed05a243` is 9904 bytes
with SHA-256
`e48db6b1683f6b841e56439452a65388f5298549e6c8b740e117a40359d8c8b5`.
Removing exactly the 54-byte literal selector for
`managed_import_reentry_js_wbtest.mbt` reconstructs the 9850-byte descriptor
at `db039dc07a845fc420be9f95b750fe5208183735`, SHA-256
`1ce3256e4f3b1dc32ee5136fcbbe5076fd996ad0a05c901a5cd175a3b16af326`.
All imports, aliases, previous selectors and other options are byte-exact.

The selected test uses the existing original Node Resource current callback
and the ordinary Node resource module through a JS-only typed import. It adds
no dependency, build hook, resolver, native option or runtime permission.
The existing `literal-target-selectors-with-bound-source-membership` rule stays
restricted to JS and the unchanged pinned toolchain. Every immediate source
member, byte, mode and the full literal import closure remains keyed.

The current map admits only this exact reviewed descriptor. The former
reviewed descriptor, changed selectors, foreign targets or toolchains,
additional options, altered imports and changed directory membership remain
refused, unresolved or independently rekeyed under the existing rules.
No historical receipt is promoted. This source-configuration review supplies
no runtime, physical backing, compiler output, normal package or proof-reuse
acceptance. Existing independent action, archive and restoration obligations
remain mandatory.
