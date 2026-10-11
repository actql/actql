# Session JS Local import configuration review

Reviewed source: `aae65b850faa3a6d02247c40f8270c8b5bd2d62c`.
Previous configuration review: `58710094a4698c16587c6cfffac25f050d93c92d`.
The unchanged pinned JS toolchain has manifest SHA-256
`8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a`.

The complete `src/query_integration/moon.pkg` delta adds only three literal
whitebox imports: `client_local_preparation`, `client_local_run`, and
`client_host_buffers`. Its existing `link.native` compiler, stub compiler,
and SSL flags are byte-identical. No target selection, build hook, import
expression, compiler pin, or configuration policy changes. The pinned JS
target does not execute the Native linker path. Literal imports continue to
be followed independently of the finite configuration allowlist.

The reviewed manifest SHA-256 is
`386b2001819b39580db802f96d0daf0bf0e43453d404b4330a11aac60bcf8cc3`.
All immediate members of these Local packages, including whitebox tests,
generated interfaces, bytes and modes, remain actual keyed and staged inputs.
The real-Git fixture checks the expanded closure, physical filesystem
correspondence and original restoration snapshot. It also requires the new
interruption helper to be both keyed and physically staged. Unreviewed
configuration bytes still require broad-source fallback with an explicit
unresolved reason; changed targets/toolchains still refuse the finite policy.

The original finite isolated experiment contract is unchanged. The changed
mutation entry/helper does not inherit execution or reuse evidence for old
experiment bytes. Filesystem/input correspondence and Node regressions are
distinct from the real thirteen-mutation MoonBit campaign, compiler closure,
and complete integrated verification. No assertion, recipe, output bound,
timeout, runtime Owner or foundation declaration is weakened by this refresh.
