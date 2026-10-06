# Current Native package inputs for the isolated JS action

Main `b98a50ff763d1367e344fdfa8aea380ec8749132` has two unreviewed
configurations in the `mutations-js` source closure:
`platform_native/remote_journal` and `platform_native/remote_standard_host`.
The conservative selector therefore includes all 4,428 source files. This is
a source-policy miss, separate from availability of an authenticated main run.

## Finite effect review

The journal manifest adds literal imports of filesystem, physical manifest,
encode/decode, source value and core string; physical manifest moves from
whitebox-only to the normal import group. It adds Native-only predicates for
`output_file_custody_native.mbt` and its whitebox fixture. Its existing Native
C stub and all other file predicates remain unchanged. On the pinned JS path,
these additions cannot execute a Native stub/compiler; their literal imports
and all package members still enter the independently keyed transitive closure.

The standard-host manifest adds the literal retained-task-file import and a
Native-only predicate for `retained_output_native_wbtest.mbt`. It introduces no
JS pre-build command or external dependency. The current manifest becomes the
fifteenth exact reviewed configuration. This is not general option parsing.

The policy records the current main revision, replaces the stale journal
digest and registers the standard-host digest. Other digests, the JS target,
toolchain pin, environment and runtime/CPU requirements are unchanged. Unknown
or changed bytes, another target or toolchain still refuse the narrowed scope.
No old-manifest compatibility path is added. Source selection is now 3,867
files in 168 packages, with zero unresolved source configurations.

## Actual local execution

Clean executed source: `9a083b1d32621b73a89e223c0c6cb1a0be3d3d29`.
The existing local-isolated entry used the pinned Linux amd64 Node 22.22.0
builder `sha256:e894118949319b479bfc3e16e545cb2f85b7a2194aa86ea9cd4e29538f2b13c3`
and the previously verified Linux MoonBit installation. It built scratch image
`sha256:f729f938d5af3813db1128cd68e315f6e20c277e8c19d409876c60905bf2e843`.

Bounded gate `run-i4cRgd` completed with exit 0, complete output and released
locks in 352,304 ms. All 13 independently registered mutations were killed
with exactly one running assertion failure each. Shell startup, read-only
root, exact image inputs, original restoration and scientific consumer checks
passed. Compile failures and timeouts do not count as detections. The owned
container/image were closed; the external supplied builder remains available.

The unmodified 4,035,155-byte original has SHA-256
`48db50ef669ce6ff8b92ad6d80f30b094a82619068a3791ac25e1e19448d21d7`.
It is retained losslessly in
[the original archive](evidence/2026-10-07-local-isolated-session-9a083b1d3.json.gz),
including logs, Git source inventory, loader/runtime observations and custody.
Its authority is `local-physical-acceptance`, `reuseAuthorized` is false, and
the local kernel/CPU/environment residuals remain. This is not authenticated
Actions provenance or a main comparison.

## Original evidence and current applicability

Historical physical records remain unchanged at their recorded revisions.
Their test-only replay loads nine explicitly listed module files from their
independently pinned Git revision; it executes neither archive-supplied code
nor a production fallback. The temporary module directory is owned and closed.
The production collector/consumer/selector does not import this helper.

The current consumer separately rejects applying each historical record under
the new source policy. The new image original is consumed by the current
consumer. Tampered assertion logs, failed restoration, missing observations,
compile-only failures, erased residuals and a changed product input reject.
This preserves the execution claim without relabeling its applicability.

At the executed SHA, the input/staging/frontier selection passed 34/34:
`inputs.test.mjs`, `isolated-runtime.test.mjs`, `package-frontiers.test.mjs`.
Gate `run-F86pz5`, receipt `focused-test-3LBHCX`, 52,123.206 ms. Stage equality
covers 3,898 total files and 36,083,081 bytes, including the audit/runner inputs.

After preserving the original, replay and contract tests passed 19/19 at
`7d1c7847bea6f54bda4970020dbe3aa7037f630c`, gate `run-24pDaf`, receipt
`focused-test-FlDtel`, 21,061.093 ms. Exact Git comparison confirms that all
3,898 staged paths, modes and bytes match the executed source. Source
reproduction commands and exact submitted-SHA results are in the PR body.

## Remaining objective

The input-policy update deliberately changes action keys. Old receipts cannot
authorize candidate reuse. Authenticated compatible main originals, actual
main comparison, normal PR reuse, related-change fresh execution and net
runner savings remain separate operational obligations. No time saving is
inferred from the number of files removed or the single physical execution.
