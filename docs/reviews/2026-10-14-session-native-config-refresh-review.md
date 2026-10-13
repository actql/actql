# Finite Session JS Native configuration refresh

Reviewed immutable Source: `55ea9534de476e7e9308da349b8afd072bc8426d`.
This carries forward the Native options review at
`9f2bfdb42dcfeac26104c160ed1c5b1770542f3f` and the original
[same Owner configuration boundary](2026-10-12-session-native-custody-configuration-review.md).
The unchanged toolchain SHA256 is
`8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a`.

The exact scope is six manifests and seven reviewed deltas: the six original
manifest deltas observed at `ff7475fd0a1f1b5655c51e57259a7eed4efaf4a3`, plus
one later Native-only SQLite failed-open-custody WB predicate within the same
SQLite manifest. No seventh manifest or new configuration kind is admitted.

| Manifest | Exact reviewed change | Current SHA256 |
| --- | --- | --- |
| `src/platform_native/filesystem/moon.pkg` | Native-only reader_kind_native_wbtest.mbt | `845c8578bc9643e6a1b7567f3694af5066adec681aa8ed148f9c6b42528d050b` |
| `src/platform_native/http_client/moon.pkg` | Native-only diagnostic_ceiling_native_wbtest.mbt | `cc26506c7f246eaa061a9642b09d28e1317be7040338135bc0756b254182f443` |
| `src/platform_native/remote_client/moon.pkg` | Literal actql/actql/remote_bundle import | `4ab04b27d2c7be75c9d5521f3e2e0d53d8cc8d8d612cb6cbb13115b240eafb6e` |
| `src/platform_native/runtime_bundle/moon.pkg` | Native-only retention_native.mbt and retention_native_wbtest.mbt | `bf180bc9b2bb454dc0b2fc7e6553a630d6b0d523eddeed95c800fde9f7bed94e` |
| `src/platform_native/signature/moon.pkg` | Native-only diagnostic_ceiling_native_wbtest.mbt | `7d5f82f21d707d93d0ad352324cbdc65b7b4eebe6c8456413430699ff084eab3` |
| `src/platform_native/sqlite/moon.pkg` | Native-only diagnostic_ceiling_native_wbtest.mbt, readback_retirement_native_wbtest.mbt, and open_failure_custody_native_wbtest.mbt | `92f1a01552e82ba65b56f680cf82e048505b83625c9c13c9cfb3f202c19d3996` |

Eight added literal Native predicates select seven WB sources and the existing
runtime-bundle retention product source. Every named source exists as an
immediate keyed package member. Supported targets, original predicates, Native
stub names and compiler/link settings are unchanged. There are no new build
hooks or external resolvers. Complete member bytes/modes, including Native-only
sources and C stubs, remain independent inputs; unchanged declarations do not
claim unchanged C implementations or Native correctness.

The remote-client import reaches the existing remote_bundle codec/type Owner.
Its complete immediate members and local imports stay keyed. Non-Native
remote-client methods and runtime-bundle retention methods continue to return
UnsupportedTarget. No Native implementation is promoted to JS execution.

The extra SQLite WB retains the same original failed-open Database and primary
issue until checked-close ACK, retries without reopening, and refuses missing
originals and invalid limits before creation. It is a Native-only fixture with
per-Database whitebox fault control. Its existing Native 3/3 evidence belongs to
`4f2141d8ee91cc95a7d6dc744b9da2f28c44ec50`, run-oZSnTd, not to this refresh;
the WB bytes match that Source. No Native/runtime/physical test is executed by
this configuration review, and arbitrary outstanding SQLite handle retirement
is not established.

The other eleven exact Native digest entries are byte-identical. The separate
JS foreign-library review stays at
`9f2bfdb42dcfeac26104c160ed1c5b1770542f3f`, with its original digest. The generic
validator, literal parser, membership/import traversal, supported-target and
wrong-target/toolchain gates, unknown-option refusal and full-source fallback
remain unchanged. This review cannot accept a different foreign-library
configuration, unknown package path or changed digest.

At the reviewed Source the unchanged selector observes 185 packages and 5820
immediate source paths before fallback. The historical ff read of 185/5815 and
its actual 42/43 Node result remain separately qualified. The newest Worker
change to connectors_builtin_node/moon.pkg has a distinct unreviewed
foreign-library identity; this Native-only refresh deliberately does not admit
it. That residual preserves unresolved reuse and full-source fallback. Changing
policy bytes requires fresh input identity; no prior isolated execution/image,
Foundation, compiler correctness, public/Provider or packed acceptance is
transferred to this Source.
