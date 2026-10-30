# Native Remote CLI artifact and publication procedure

This is the limited implemented Remote transport distribution, not the
subsequent standard CLI with embedded Local execution. SDK/Node publication
does not wait for CLI acceptance. The existing `actql@0.0.1` placeholder stays
immutable. The owner selects a complete version explicitly; the source
package's development metadata does not select the next published number.

Build from a clean fixed HEAD with the repository-pinned MoonBit compiler,
under the existing local heavy guard. On each actual candidate platform:

```sh
node scripts/native-cli-artifact.mjs .artifacts/native-cli-<platform>-<sha>
```

The producer records the source SHA, compiler/toolchain pin, generated C
digest, executable digest and size, and actual ABI inspection. Keep the record
and executable together. Linux must use a real x64 Linux environment; emulation
must be disclosed. Host-side package-selection simulation is not acceptance.
Set `MOON_HOME` to the pinned toolchain. Each binary package preserves its
Core license/notice files verbatim, checked against that compiler's installed
Core and bound to the artifact record.
The executable's greatest required GLIBC symbol version is its minimum bound,
not a guarantee for arbitrary separately installed libcurl/transitive libraries.
The tested OS/glibc/library set and an older untested bound are distinct.

After both platform artifacts have the same clean source SHA:

```sh
node scripts/native-cli-release.mjs prepare .artifacts/cli-rc-<sha> <explicit-cohort.json> \
  .artifacts/native-cli-darwin-arm64-<sha> \
  .artifacts/native-cli-linux-x64-gnu-<sha>
node scripts/native-cli-release.mjs verify .artifacts/cli-rc-<sha>
node scripts/native-cli-release.mjs plan .artifacts/cli-rc-<sha>
```

Preparation can accept a single platform to continue other distribution work
when the other environment is unavailable. Missing platforms remain unverified
and are not declared supported. No build or download runs during installation.
The `actql` launcher uses npm optional OS binary packages and checks target,
source, executable digest, macOS deployment bound and Linux glibc before starting Native. It never
chooses another binary or executes a Node fallback engine.

The cohort file has exactly `packageVersion`, `registry`, `access` and `tag`.
Use the explicitly selected complete version, the public npm registry URL,
`public` access and the selected candidate tag. The shared version parser
supports final, alpha, beta and RC spellings. These are local candidate inputs,
not owner approval, registry availability or platform acceptance. Preparation
clones metadata into its unique staging directory and preserves source files.

Use the same fixed tarballs for independent external installation, global
`npm install -g actql`, help/version, actual mTLS Host operations and failure
tests. Run from outside the source tree. Save command, source, tarball and
executable digests with results; platform support follows successful acceptance.
Record shared-library dependencies and libcurl requirements alongside each
platform's receipt. Updating installs the new fixed cohort; it does not mutate
saved submission, Run or cancellation references. Unknown responses require
lookup with the original reference, never an automatic resend.

Supply names, versions, registry, digests, source and acceptance to the
owner for an explicit publication decision. Authenticated npm identity/ownership and
both tested platform declarations must be settled before public publication.
The old `--publish` CLI is disabled before credentials or upload subprocesses.
Publication also needs the separate protected executor and registry-side
stage-only identity; a local cohort or a successful build cannot authorize it.

The same SDK cohort publisher performs whole-cohort preflight, confirms exact
immutable integrity, preserves command-success receipts and resumes only
unpublished versions. Registry failure is not absence. An occupied different
version stops publication; choose a reviewed new cohort rather than overwrite.
No workflow or install hook publishes anything. See the
[SDK/Node procedure](README.md) for partial publication and erroneous-release
handling. No unpublish, tag correction or public release is automatic.
