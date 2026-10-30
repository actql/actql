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

## Standalone archive preparation

```sh
node scripts/native-standalone-release.mjs prepare <request.json> <native-target-id> <verified-native-npm-cohort> <new-directory>
node scripts/native-standalone-release.mjs verify <directory>
```

Preparation calls the existing complete Native npm cohort verifier first. It
uses only the selected original OS-package tarballs, with the same source and
explicit package version. It does not compile or patch an executable. The
standalone `actql-<version>-<platform>.tar.gz` contains the original payload at
unchanged relative paths, bytes and modes, plus `build-info.json`,
`STANDALONE.md` and `CONTENTS.sha256`. The direct executable is
`bin/actql-native-client`. The original `package.json` is provenance DATA; it
is not a Node dependency or an installation lifecycle script.

Build information records the package version, actual binary/source/toolchain
and ABI identities and original npm cohort/package hashes. It does not put
the archive's final digest inside its own body. `CONTENTS.sha256` covers the
other members; the external final `SHA256SUMS` covers all archives. An existing
destination/archive cannot be overwritten. Verification reopens the archives,
checks every original member and exact generated metadata/checksum inventory,
and reuses the original Native artifact/Local metadata readers. Its cold
packaging/source-byte scope is separate from the full original producer gate.

The request target uses ecosystem `native`, the exact selected platforms and
requested profiles. Its package identities are `actql-<platform>` in platform
order followed by `actql-checksums`; these identify GitHub archive assets, not
new npm names. Feed the result to the upper fixed release set as
`{targetId, kind: "native-standalone", directory}`. Both archives and
`SHA256SUMS` are fixed artifacts, while the complete original Native npm
manifest stays bound as raw provenance in `native-standalone.json`.

Requested profiles are not accepted profiles. A Local request requires the
original admitted runtime material and the existing darwin-arm64 producer
route. Linux Remote packaging does not qualify Linux Local. The separate
Native installation/bootstrap connection, actual CLI/README entry, real
`--version`, successful Local/Remote behavior, close/failure handling and a
Node-free environment must be accepted from the actual selected artifacts.
The current compiled command version is not rewritten to the distribution
version by packaging. Local asset presence does not supply a new bootstrap or
fallback engine.

This wrapper does not perform signing, notarization or publication. If signing
is selected, the final signed input bytes and their verification must precede
the fixed release set and owner approval. Real GitHub Draft/immutable release,
asset reobservation, attestation, public download and Latest remain separate
executor/acceptance duties. Header-only fixtures or an archive check never
establish those outcomes.
