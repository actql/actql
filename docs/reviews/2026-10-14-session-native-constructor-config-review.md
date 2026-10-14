# Exact Native constructor-custody configuration review

Reviewed immutable cohort Source: `4736480dd98542420d83fe205589fc33e2d038ba`.
The cohort is normally integrated in main
`49db953fcbef61c4f86862f35db13d2a28735f8d`. The previous
[Native configuration review](2026-10-14-session-native-config-refresh-review.md)
remains historical. This uses the same existing
`literal-native-options-with-bound-source-membership` rule for the pinned JS
target, Moon revision `94521db`, and toolchain manifest SHA256
`8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a`.

| Manifest | Exact reviewed SHA256 | Actual Git blob, mode 100644 |
| --- | --- | --- |
| `src/platform_native/filesystem/moon.pkg` | `eef78cb8d41b54e003391bae5336ae10282debcce65f40f2f1be96e7f87bc837` | `b076255bca0f555a843763d2ea1fbc8cac26424f` |
| `src/platform_native/publication_store/moon.pkg` | `b3f6489410a0807c2d0aafddc8b30be18658d6ff395c824e7f9b83bd5e172f8c` | `c0b40433816d706e3e6e131e46be136236631e06` |

Each manifest adds exactly one literal Native-only predicate for its immediate
`open_failure_custody_native_wbtest.mbt`. Removing that exact line restores the
entire manifest at both bases `1f032fe92d8f4719057223303fcc911eb751e4e1` and
`d989652c351dabe53afbacb8e51f95ccb99e2c90`. Imports and aliases, supported
targets, existing predicates, stub filenames, linker settings and the absence
of build hooks/external resolvers are unchanged. The files are not selected for
JS execution. Complete C and source bytes/modes remain separately keyed;
unchanged configuration declarations do not claim unchanged C implementations
or Native correctness.

The Filesystem WB retains original failed Root/Lock custody and diagnosis,
does not release the competing genuine Lock owner, and tests a consumed close
whose observation is made Unknown while a reused FD writer remains live. This
is whitebox observation loss after a real close, not an observed kernel
EIO/EINTR. Store's WB keeps the same Root/Lock while same Database cleanup is
pending, refuses missing existing schema without repair, and rejects invalid
capacity before acquisition. Its portable missing-custody gap model is distinct
from physical Native observation.

Existing matching evidence remains source-qualified: Store's three cases at
`91ae277d6e5b99ef50ecc9d2ffac61ed69303272`; Filesystem's three cases and the
portable case at `5ef53271ee82fad415785cece70be870990ca753`; three-target
generated API projections at `b70b24d9c9264f77aa2664ef8bde511847318526`.
The final cohort formatting/source qualification does not execute those tests
again. This configuration review supplies no whole constructor retirement,
outstanding-handle retirement, capacity-return receipt, normal funding,
installed/public product or physical Provider acceptance.

The unchanged selector observes 185 packages and 5823 immediate source paths
before fallback at this cohort. All 16 Filesystem and 26 Store immediate members
and every transitive normal/WB literal import are bound to actual Git
bytes/modes. The earlier 185/5820 and ff 185/5815 records remain historical.
Fresh bounded actual-Git staging, byte/mode/restoration and existing refusal
controls verify only their source/input/fixture scope.

Only these two Native digest values and their Native review reference change.
Of the previously carried eleven values, Store is the deliberate refresh and
the other ten remain exact; Filesystem is the sole change among the previous
six refresh entries. All other fifteen Native values remain unchanged. The
separate JS foreign-library review/digest remains at
`55ea9534de476e7e9308da349b8afd072bc8426d` /
`1e8b80ac31bd7af9eb61dd9b0dc1b1f40542083217ffea09be4a7e7cfcf4f43c`.
The generic parser/validator, target/toolchain gates, unknown-option/digest/path
refusal, source membership and full-source fallback remain unchanged. No new
namespace, kind, target or source authority is admitted. Changed policy bytes
require fresh input identity; no historical execution, compiler, runtime,
isolated-image, pack or public acceptance is transferred.
