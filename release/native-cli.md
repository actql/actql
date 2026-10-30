# Native Remote CLI artifact and publication procedure

This is the limited implemented Remote transport distribution, not the
subsequent standard CLI with embedded Local execution. SDK/Node publication
does not wait for CLI acceptance. The existing `actql@0.0.1` placeholder stays
immutable. The owner selects a complete version explicitly; the source
package's development metadata does not select the next published number.

Build from a clean fixed HEAD with the repository-pinned MoonBit compiler,
under the existing local heavy guard. On each actual candidate platform:

```sh
node scripts/native-cli-artifact.mjs .artifacts/native-cli-<platform>-<sha> \
  --package-version "$ACTQL_VERSION"
```

The producer records the source SHA, compiler/toolchain pin, generated C
digest, executable digest and size, and actual ABI inspection. Keep the record
and executable together. Linux must use a real x64 Linux environment; emulation
must be disclosed. Host-side package-selection simulation is not acceptance.
Set `MOON_HOME` to the pinned toolchain. Each binary package preserves its
Core license/notice files verbatim, checked against that compiler's installed
Core and bound to the artifact record.
Set `ACTQL_VERSION` to the complete explicitly selected candidate version before
this build. The shared package-version parser is the only grammar owner; the
Native literal has a 128-character initial-control bound. No source package
number, environment variable at runtime, argv value or adjacent metadata file
chooses the compiled banner. Unselected diagnostic builds display
`0.0.0-development` and have no release-version observation.

The existing argparse command retains its original help/version/error parsing
and no-Host-acquisition behavior. Its version text comes from one bounded
ordinary managed String containing immutable compiled DATA. The original
Command constructor copies it into the retained initial parser graph; no Read,
physical holding, Owner or permission is created by that text.

The ordinary explicit-version producer uses a fresh target directory and an
isolated compiler shim that changes only the original version stub's literal.
The scoped Local producer adds the same explicit literal to its existing exact
C plan. Completed-provider adoption checks that original C step, helpers and
source before consuming the existing completion; it cannot relabel an older
provider or start a replacement compilation. Compiler flags, allocator, ABI,
engine settings, physical/current and cleanup protocols otherwise stay selected
by their original owners.

Before writing a version-bound artifact receipt, the producer executes that
same binary's `--version` with no runtime/Node path and requires the exact
selected banner, exit0 and no stderr. It binds the observation to the original
binary length/SHA256 and version-build input digest. Historical artifacts remain
readable in their old byte-only scope. New npm preparation, standalone staging,
fixed-set admission and npm staging require the matching observed version;
metadata-only renaming cannot supply it. Inert observation records are only
component fixtures, never evidence that a real command ran.

Protect the Native version helper/stub, artifact readers and both compiler
connections alongside the existing version/policy/publisher controls. These
source checks do not configure that protection or establish owner approval.
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
Packaging does not rewrite the executable. Its matching build-time version
observation remains distinct from the actual Node-free installed command,
Local/Remote behavior and cleanup acceptance. Local asset presence does not
supply a new bootstrap or fallback engine.

This wrapper does not perform signing, notarization or publication. If signing
is selected, the final signed input bytes and their verification must precede
the fixed release set and owner approval. Real GitHub Draft/immutable release,
asset reobservation, attestation, public download and Latest remain separate
executor/acceptance duties. Header-only fixtures or an archive check never
establish those outcomes.


## Exact-byte Native Draft publication protocol

```sh
node scripts/release.mjs native-publish-plan <fixed-directory> <externally-retained-SHA256> <native-target-id>
```

This command verifies the complete original standalone archive/ABI inventory
and matching compiled-version record, then shows the exact proposed Draft and
asset set. It remains `execution: unavailable`. The fixed review must bind the
proposed publication scope. Declared `passed` evidence remains supplied DATA,
not an accepted installation, permission or owner approval.

The existing publisher Owner exposes `publishNativeRelease` only for a separate
protected executor. There is no default mutation runner, credential discovery,
executable publish CLI or workflow. The executor must independently establish
owner approval of the exact upper digest, trusted immutable validator/policy,
real accepted install evidence, permitted recovery, credential separation and
one exclusive current execution across repositories. GETs and local receipts
are not a lock or registry compare-and-swap.

Its separate owner API read port must actually see **all** drafts and releases
and have Administration-read permission for the immutable-release setting.
The reader requires enabled immutability before and after each observation,
complete paginated release/asset inventories, one selected release id, exact
tag/source and the fixed candidate's exact title/body/prerelease metadata.
An anonymous 404 cannot supply absence. Disabled/unavailable settings, duplicate
drafts, wrong source or presentation, foreign/partial assets and different bytes
block the operation. No repository setting is enabled or changed by this code.

API asset reads and their signed-CDN continuation use separate ports. API
credentials must remain inside the protected API-only reader; the CDN gets only
the normal public byte request. Signed query strings are not retained in
receipts. Every existing asset is checked through the original finite actual
length/SHA256 reader and its complete inventory is reobserved afterward.

The sequence creates a Draft only after complete owner-visible absence,
uploads only absent original assets, then publishes that same Draft id only
after all selected archives and `SHA256SUMS` match. Original immutable files
are copied to private mode-0400 request payloads; synced intent precedes each
mutation. The exact `make_latest: "false"` is explicit at creation and
publication. Final Latest/channel promotion and public consumer acceptance
remain separate owner-controlled duties. A complete existing immutable release
is reused without another send. A published incomplete or mutable release is
never repaired by adding, renaming, deleting or replacing assets.

The supplied mutation runner must settle only when its **original** request/job
is terminal. Lost live observation retains that same external handle. A thrown,
malformed or failed terminal reply leaves the synced intent Unknown and stops;
it is not absence and does not trigger an in-process retry. A later separately
authorized same-digest recovery reobserves the complete actual state and does
not resend a confirmed Draft or asset. If the original scope did not include
same-byte recovery, a later attempt refuses. Failed receipts and private original
payloads remain at their original paths. Missing/tampered fixed artifacts never
cause a rebuild or version bump.

After publication the reader requires the actual release's immutable flag,
actual Git tag commit and all original asset bytes. This is byte/settings
readback, **not** verification of a GitHub attestation, platform signature,
notarization, public runtime or complete release acceptance. Those evidence
and actual production trust/settings checks remain separate requirements.
Inert archive and injected API tests do not establish any real publication.

## Public standalone Remote consumer

After the owner has published the exact fixed set, use its externally retained
SHA256 and two original target IDs:

```sh
node scripts/test-native-standalone-install.mjs <fixed-directory> <release-set-SHA256> <native-target-id> <host-node-target-id> <new-external-consumer-directory>
```

This consumer downloads the original standalone target through the existing
anonymous GitHub release reader. It requires the exact immutable tag/source,
complete asset inventory, bounded public bytes and identical identities before
and after download. The same checked byte stream is written exclusively to its
fresh directory. Interrupted, missing, oversized or conflicting downloads keep
incomplete files and a failed receipt; they cannot become an install input or
trigger a retry, local archive substitution or rebuild.

Extraction reuses the full standalone verifier, original archive reader and
complete installed file/mode/ABI checks. Direct Native children have an empty
PATH and fresh HOME, without Node/npm, loader injection, profiles or credentials.
The same executable must display the exact version, help, and argument refusal.
Missing executable and changed-byte controls never select an alternative engine.

For Remote behavior the harness installs only the exact public `@actql/node`
entry of the separately selected original Node target, with isolated npm/HOME
and full public-byte/installed-payload audits. That process is the external test
Host, not a Native dependency. The unchanged Remote fixture submits once, saves
its original reference before wait, checks Result/lookup/delivery/cancellation
and prevents a second Compute. Native commands are independent direct processes.
The test Host's explicit client/Host close calls must return before an observation
of zero scoped state descriptors in that same still-live process, followed by
its acknowledgement. Native process exit is not promoted to a Host close ACK.

The receipt covers only actually completed operations on that platform. It does
not qualify Local bootstrap/execution/approval, the standard Project/README CLI,
other platforms, npm-launcher installation or the full fault matrix. Those
remain separate required acceptance. Component HTTP/inert-file and own-process
observation tests do not establish a real public Native install. This launcher
has no publication/owner-approval or credentials path, and retains its entire
fresh state on success or failure.
