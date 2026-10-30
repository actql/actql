# SDK / Node release preparation

The formal version and finished product artifact cohort remain unselected.
Legacy version numbers and retained fixtures below are historical inputs,
not proposed replacement versions or publication instructions. Preparation
commands produce local candidates. Staging, publication, tags and promotion
still require the independently protected executor and the owner's explicit
decision on the exact final version, bytes, scope and evidence.

The standard cohort is `@actql/client-wire`, `@actql/sdk`,
`@actql/local-node`, and `@actql/node`, with one explicitly selected complete
version and exact internal dependencies. The legacy `0.0.1` cohort file does
not select a new release or authorize replacing an existing public version.
`@actql/sdk` remains a remote Client with no Local runtime or
DuckDB. `@actql/node` includes the standard Local implementation; consumers do
not assemble internal packages. `@actql/otel-node` is optional and independent.
Host implementation packages are not dependencies of this initial cohort.

Development manifests stay private. A release uses normal prepack from clean
source HEAD, followed by a checked metadata-and-LICENSE transform of those
tarballs. Every other payload byte and file mode must remain identical. There
is no install-time compiler, downloader, daemon or implicit Connector install.
Package version is independent of the wire and semantic contract versions.

The Local runtime package preserves the pinned MoonBit Core `LICENSE` and
`NOTICE` verbatim as `MOONBIT-CORE-LICENSE` and `MOONBIT-CORE-NOTICE`; these are
normal prepack payload files, not a replacement for ActQL's own license. The
lightweight SDK also retains its existing Standard Schema license. Updating
the Core pin must update the matching upstream notice files together.

The current epoch-bound installed Host deliberately refuses pre-Run delegated
approval (`ACTQL_E_DELEGATION_UNAVAILABLE`). Release installation acceptance
checks the typed refusal, original submission lookup after process restart and
zero physical dispatch. This is not successful pre-Run approval acceptance.
Run-scoped Effect approval is a separate, implemented path. Its finite installed
acceptance uses the existing public Host, Client, Checkpoint and Effect owners:

```sh
node scripts/test-package-release-effect.mjs /absolute/path/to/fixed-rc
```

It checks approval before sending, Host restart, the original Run and submission,
independent Result/provider expectations, cancellation and unknown response
recovery without resending. Only independent local HTTPS provider fixtures are
used; this does not establish live-service acceptance. Retained RCs are allowed
only when package/runtime inputs are unchanged, with artifact and fixture SHAs
recorded separately. Distribution tooling does not introduce an alternative
Owner or restore bare request-ID submission. Standard pre-Run delegated approval
remains dependent on its complete shared response/cancel/recovery contract.

Run preparation under the existing local heavy guard, with the repository's
Node and MoonBit toolchain pins. Use a unique, absent RC destination:

```sh
node scripts/package-release.mjs prepare /absolute/path/to/rc <explicit-cohort.json>
node scripts/package-release.mjs verify /absolute/path/to/rc
node scripts/test-package-release-install.mjs /absolute/path/to/rc
node scripts/package-release.mjs plan /absolute/path/to/rc
```

The consumer-only source-free query entry uses those same four release archives:

```sh
node scripts/test-package-release-sourcefree-query.mjs /absolute/path/to/rc /absolute/path/to/new-receipt.json
```

It selects the existing general-element, array-field, conditional-array and
lazy-array-branch IN/UNNEST inputs plus the six existing refusals, through
installed Local and SDK HTTPS. Authored rows, ordered schemas and parameters
remain unchanged. The original five-development-package query harness and its
Source-backed cases retain their defaults. No runtime/adapter overlay, second
pack, replacement evaluator or new capability is used. A later fixture commit
may consume the RC only with ancestor binding and unchanged runtime/package
inputs. Product refusal remains a failing acceptance, not a fixture rewrite.

Admission is observed through the same read-only request journal used by the
existing public harness. Provider observation is limited to an empty Source
inventory and forbidden process, non-ingress-fetch and secret-resolution
attempts; it is not arbitrary Provider or filesystem I/O coverage. Actual
installed acceptance must run separately from the Node-only selection tests.

`release.json` binds full source SHA, recipe, toolchain, original prepack
digests, public tarball SHA256/SHA512, exact dependencies and file inventory.
Retain this manifest, development originals, public tarballs, acceptance
receipts and failed-run evidence. `verify` checks both original and release
bytes; it never builds, repairs or changes package versions.

The external consumer starts with an empty directory and private npm cache.
It installs only the selected exact `@actql/node` or `@actql/sdk` version, using a read-only
loopback registry that serves the fixed RC. npm resolves dependencies, and
the acceptance audits exports/types and executes the existing Local/restart
and short-query/HTTPS cases. This establishes registry installation mechanics,
not public npm availability, live Cloud operation or every Provider feature.

After the selected versions are actually published, the **same** harness has
an explicit public npm mode:

```sh
node scripts/test-package-release-install.mjs <original-RC-directory> --public-registry <externally-retained-release.json-SHA256>
```

For the owner-review release set, explicitly bind both the same original Node
cohort and the selected fixed upper target:

```sh
node scripts/test-package-release-install.mjs <original-RC-directory> \
  --public-registry <externally-retained-release.json-SHA256> \
  --release-set <fixed-release-set-directory> <externally-retained-upper-SHA256> \
  --target <original-node-target-id>
```

The upper digest does not replace the original child digest. The launcher
requires the same complete four-package Node cohort, exact source/version,
child-manifest bytes and all original archive identities. Its existing full
cohort verifier still reads the retained `development` manifest and original
development tarballs. The flat fixed set does not contain that supplier lineage;
do not reconstruct missing originals, copy a different cohort into their place,
or weaken verification to final payload hashes. A missing original refuses
before consumer installation. Native, Python and optional Explorer targets do
not inherit this consumer's scope.

The resulting receipt binds `releaseSetBinding.manifestSha256`, `targetId` and
`cohortManifestSha256` plus exact artifact identities and requested platform/profile
DATA. Actual executed cases and the observed Node/OS remain separate; this
association does not certify every requested platform/profile or owner approval.
The legacy child-only public mode remains available with a null upper binding,
and cannot be reported as acceptance of an owner-approved upper digest.

The digest selects the exact original Node cohort child manifest retained by
the approved upper set. It is not a new version choice or approval. The
existing complete cohort verifier and anonymous npm byte reader run before
consumer creation: each original name/version/SRI and actual streamed archive
size/SHA256/SRI must match. The separate historical public observation is saved
even when a version is absent, unknown or conflicting; any such state refuses
installation, with no loopback fallback, local tarball substitution or resend.

Public mode creates a fresh HOME, a separate fresh cache for each entry and user/global configuration,
without forwarding publisher credentials, source profiles or Node injection.
Only the exact `@actql/node` or `@actql/sdk` entry is installed, using
`--save-exact --ignore-scripts --engine-strict` against
`https://registry.npmjs.org/`. Its
[npm lockfile](https://docs.npmjs.com/cli/v11/configuring-npm/package-lock-json/)
must retain the selected public dependency graph, official registry origins,
exact versions and fixed SRI. Every installed ActQL payload byte/mode is
compared to its original archive inventory before the existing package-graph
and consuming-interface audits. npm's nested third-party dependency directory
is separate from the package payload; bundled dependency payloads are refused
until their own consumer scope is selected.

The README, Local/restart, short-query, explicit pre-Run refusal and SDK
own-HTTPS cases and their original oracles remain unchanged. Public mode does
not start a private package registry. Its final receipt names both the initial
and final actual public-byte observations, fixed cohort digest, lockfile digest,
optional exact upper binding and actual installed payload audits, while
retaining the incomplete pre-Run approval scope. The original cohort and supplied
upper set are reverified after consumption; a changed or unavailable public
artifact does not become successful acceptance or permission to rerun old state.
A public package download is
not live Cloud or Provider acceptance. The actual public mode remains
unexecuted until the real candidate/version is selected and published; its
inert component fixtures do not qualify that runtime boundary or a release.

Both private and public harness modes now explicitly retain their owned
consumer directory after success as well as failure, including the original
software, lockfiles and Run/DB/WAL/key/state evidence. This uses the existing
scratch Owner's preservation selection; it does not waive the requirement to
confirm that every started process, Host and Store has ended. No previous
consumer state is opened, replayed or removed by selecting the new mode.

Give the integration reviewer the source SHA, PR, manifest, exact archives,
digests, commands and receipts. Independent acceptance must consume the same
archives outside the repository. A changed RC needs a new unique directory
and acceptance of affected paths; old receipts are never relabelled.

## Publication and recovery

Public publication requires the owner's explicit approval of the exact names,
versions, digests, registry, tag and evidence through a separate protected
executor. Authentication checks, local JSON and preparation do not grant
approval. The legacy `--publish` CLI is disabled before any credential or
upload subprocess. Keep the existing hosted CI opt-in conditions unchanged.

The existing tarball-only publisher library retains dependency order and
same-byte resume for a future protected executor; it is not an authorized
entrypoint on its own. Before any write, all existing versions are inspected. A 404 is
absence; transport failure, registry failure and mismatched integrity are
errors. Only an existing identical version is skipped. Publication command
success and later registry confirmation are separate facts; immutable local
receipts preserve successful commands even if confirmation is unavailable.
After partial failure, a protected executor must inspect the same approved
fixed manifest and actual registry state. The existing library will not
republish confirmed bytes, overwrite a version, choose a new version, or infer
that an unconfirmed command never executed. Never publish mutable package
directories instead of these archives.

Before a next release, choose a new cohort version in the reviewed recipe,
prepare and independently accept new archives, inspect existing versions, and
obtain a new owner approval. An incorrectly published immutable version is not repaired by
overwriting it: stop publication, disclose the affected version and scope,
then obtain review for deprecation/tag correction and a new fixed version.
The tool does not automatically unpublish, deprecate or change tags.

Current authentication is not established by a public maintainer name or
registry 404. Confirm the real npm identity and scope/package publication
rights separately. An authentication failure does not prevent RC or Native
CLI packaging work.

## Consumer entrypoints after publication

Local standard installation:

```sh
npm install "@actql/node@${ACTQL_VERSION:?Set the owner-approved exact version}"
```

Set `ACTQL_VERSION` to the owner's exact approved public version. A missing
version, an unqualified package name or a local loopback acceptance does not
identify the fixed public release. Use the resulting lockfile for repeatable
installation.

```js
import {open} from '@actql/node';
const db = await open({stateDir: '.actql'});
try {
  console.log(await db.sql('SELECT 1 AS id').all());
} finally {
  await db.close();
}
```

Remote Client only:

```sh
npm install "@actql/sdk@${ACTQL_VERSION:?Set the owner-approved exact version}"
```

```js
import {connect} from '@actql/sdk';
const client = await connect(process.env.ACTQL_URL);
try {
  console.log(await client.sql('SELECT 1 AS id').all());
} finally {
  await client.close();
}
```

The remote Host must already exist and authorize the workspace and operation.
Connecting to it does not install or register a Connected Runner. Runner
deployment/registration/update is a separate operator procedure. Browser
authenticated execution and untested OS/CPU/libc/Node combinations are not
claimed by this RC acceptance. Declare a support row only after that exact
environment consumes the fixed artifacts successfully.

Native CLI distribution follows separately as **Native Remote CLI**. It does
not block the SDK/Node release, and it does not complete the adopted future
standard Local CLI requirements. `actql@0.0.1` is an occupied placeholder;
the real CLI uses a new immutable version.


## Optional standalone Explorer cohort

Explorer is separately installed at the selected exact version; it is not
added to the initial Node/SDK release gate. `release/explorer-cohort.json` fixes
the existing four packages followed by `explorer-ui` and `explorer`. Select it
explicitly while keeping the normal clean-HEAD prepack and immutable digest flow:

```sh
node scripts/package-release.mjs prepare <unique-explorer-RC-directory> release/explorer-cohort.json
node scripts/package-release.mjs verify <unique-explorer-RC-directory>
node scripts/test-explorer-release-install.mjs <unique-explorer-RC-directory>
```

The UI library keeps React/React DOM as peers and exports built CSS. The
standalone package supplies one browser application/runtime and the
`actql-explorer` binary, never another `actql` binary. Internal dependencies and
peers receive the exact cohort release version; no consumer resolves development,
file or workspace references. Normal prepack emits the actual SPA and a bounded
SHA-256 asset inventory. Metadata/license staging preserves those runtime bytes
and modes. Third-party UI/server dependencies use ordinary registry resolution;
the private acceptance registry serves only the fixed ActQL archives.

The finite installed profile reads a real static Plan, original existing Run
and Named Result metadata through the public Client. It submits no business
work, exposes no controls/Samples/payloads and grants no new authority. Empty
consumer acceptance must verify actual built asset delivery, original refs/ports,
unavailable capability states and closure without cancelling borrowed work.
It does not complete the Cloud adapter, Full Explorer or formal npm publication.

## Sharing one normal prepack across exact cohorts

A normal Explorer six-package cohort and a normal Node four-package cohort
retain their separate exact manifests. After verifying the six-package source,
normal-prepack receipt and complete `verifyPackageRelease` result, a producer
may set `ACTQL_PACKED_CLIENT_PACKAGES` to that cohort's `development` directory
and invoke ordinary `package-release.mjs prepare` for the four-package cohort
in a fresh directory at the same clean HEAD. The existing shared-pack owner
checks the source revision and both the original and copied archive digests.
A missing package, changed archive or different/dirty source is a refusal;
it never silently repacks a rejected shared input.

This uses the original normal prepack once and then ordinary metadata/license
staging. It creates new four-package development and release manifests; it
does not edit the six-package manifest or relabel a former RC. Both complete
manifests must verify. Shared final release archives additionally require the
same chosen package version and metadata inputs; different release versions
are not identical archives even when their development payload is shared.
For the checked-in Node/Explorer cohorts, independently compare every common
`originalSha256`, final `sha256`/integrity and payload byte/mode inventory.
Normal consumers keep their exact cohort and source checks. This mechanism
is not formal registry publication or evidence of an installed E2E result.
# Initial and continuing release preparation

The common entry `node scripts/release.mjs plan <release-request.json>` validates
an explicit candidate request without building, obtaining credentials, staging,
uploading, creating tags or changing channels. `release-request.schema.json`
describes its input; `release-policy.mjs` checks the cross-field rules. No real
release request or version is selected by the synthetic test fixtures.

The initial allowed package line is `0.0`. Complete final, alpha, beta and RC
versions are explicit inputs; no patch/minor/major bump or next-version update
exists. The shared parser maps those versions to Python metadata, and rejects
unknown prerelease forms and build metadata rather than normalizing them.
Package versions do not rename language, protocol, ABI or CID identity domains.

Candidate policy and request files are DATA, not publisher authority. The old
Node and Native CLI `--publish` entries are disabled before their credential or
upload subprocesses. The reusable existing pack, digest, registry comparison
and receipt functions remain available. A separately protected owner-approved
executor is still required; a local `approved: true`, actor name, successful
check, CI opt-in or merge cannot provide that authority. This code does not
claim that externally usable owner credentials or arbitrary Release APIs have
been isolated by repository code alone.

`acceptance.json` retains all 26 release requirements and their outstanding
evidence. No candidate artifact, platform support, public install, protected
publisher setting or external acceptance is established by a valid plan.
The existing ecosystem instructions below retain their artifact-verification
details; their direct CLI publication examples are held until the protected
execution path is connected and the owner approves a fixed release set.

## Freeze existing artifacts

`node scripts/release.mjs freeze <request.json> <cohorts.json> <new-directory>`
connects existing ecosystem outputs without building or publishing. The cohort
file is an explicit array of `{targetId, kind, directory}` records. Supported
kinds are `node-npm`, `native-npm`, `python-wheels` and `native-standalone`.
Native npm launcher packages and standalone archives retain separate manifests
and acceptance. The standalone connection reuses an existing Native npm OS
payload and does not compile another binary. The existing Python wheel verifier currently selects only
its actual macOS-arm64 layout and refuses other platforms.

Each selected target must retain its complete, dependency-ordered child cohort,
exact source/version and explicitly selected cohort tag. The existing ecosystem
verifier runs before output is created. The new directory retains child-manifest
bytes and copies the exact public artifacts; it does not preserve arbitrary
build caches or rebuild missing files. Partial local output after a failed copy
is not a completed candidate and is never silently reused.

The upper `release-set.json` binds request, candidate policy, child manifest
digests and all artifact names, versions, sizes, SHA256s and npm SRI. Its digest
is detached in `release-set.sha256`, never stored inside its own hashed body.
The detached file is local integrity DATA, not an approval. Use
`node scripts/release.mjs verify <directory> <externally-retained-SHA256>` or
`summary` with those same arguments to reobserve the fixed bytes. The Markdown
and JSON summary come from that same manifest. A changed digest is a new
candidate; it does not inherit any previous approval.

`resume-plan <directory> <SHA256> <observations.json>` only classifies explicitly
supplied registry observations. An observation identifies `targetId`, `file`
and `state` (`absent`, `present`, `unknown`, `conflict`); a present observation also carries
the exact artifact `identity` (name/version/bytes/SHA256 and npm integrity).
Identical bytes may be reused, absence names the same missing bytes, unknown
or conflict blocks the plan and any identity mismatch stops it. This input is not authenticated
registry reobservation or owner authority, and the command never sends bytes.
Protected execution, authenticated Native draft recovery, channel arbitration
and release acceptance remain separate unfinished work.

All sets from this layer remain explicitly `unaccepted`. The existing Python
checker reused here establishes wheel metadata and frozen-byte correspondence,
not original engine execution, normal install, Linux support or public registry
acceptance. Synthetic metadata fixtures contain no usable engine. Real
candidate assembly and acceptance wait for the selected coherent product
source and owner-selected version/scope.

## Bind the review evidence and proposed execution scope

The preparation manifest alone does not contain a complete approval
presentation. After collecting the original build and acceptance records, use
the same fixed-set owner to retain them in a **new** directory:

```sh
node scripts/release.mjs review <preparation-directory> <externally-retained-SHA256> <review-request.json> <new-review-directory>
node scripts/release.mjs summary <new-review-directory> <new-externally-retained-SHA256>
```

The new upper manifest retains the exact preparation manifest, raw review
request and original evidence bytes with sizes/SHA256s. Artifact and child
manifest bytes remain exact. The original preparation is unchanged; enriching
an already enriched set or overwriting a destination refuses. Changed evidence
or proposed execution scope creates a different upper digest and therefore a
different candidate for any later approval. The detached digest is not an
approval record.

The request has schema `actql-release-review-request/0.1` and exactly these
fields, validated by the existing `release-set.mjs` owner:

- `manifestSha256`: the original preparation digest.
- `evidence`: original `{id, kind, file, bytes, sha256}` records. `file` is
  relative to this request's directory, with no traversal or symlink. Kinds
  are `recipe`, `toolchain`, `build`, `acceptance`, `diff` and `signing`.
- `provenance`: one ordered `{targetId, recipeEvidence, toolchainEvidence,
  build}` entry per selected target. A supplied GitHub build records kind
  `github-actions`, `repository`, decimal-string `runId`, positive `attempt`,
  decimal-string `artifactId`, `artifactSha256` and build `evidence` id. A
  local build instead records `{kind: "local", run, artifactId: null,
  evidence}`. A local receipt cannot invent a hosted immutable artifact id.
- `environments`: one ordered `{targetId, platforms, profiles, node, python,
  abi, limitations}` entry per target. Platforms/profiles must equal the
  original selection; runtime range text or `null` and ABI declarations are
  supplied claims for review, not certified support.
- `acceptance`: two ordered entries per target, phases
  `prepublication-install` then `public-install`, each containing
  `{targetId, phase, status, evidence, limitations}`. Status is `not-run`,
  `passed` or `failed`. An executed result requires original acceptance
  evidence ids; `not-run` has none. A reported pass does not establish that
  its scope, source, bytes, runtime or oracle has been independently verified.
- `changes`: `{previousSource, diffEvidence}`, both `null` if none is supplied;
  otherwise an exact prior commit and original diff evidence id.
- `executionScope`: `{publish, promote, resumeIdenticalMissing}`. Publish and
  resume are explicit target-id arrays. Proposed promotions are
  `{targetId, channel}` entries already selected in the request. Resume cannot
  exceed the proposed publication targets. This data grants no operation.

The request is bounded to 1 MiB, with at most 128 original evidence files,
64 MiB each and 256 MiB total. Every input is checked before output creation;
all retained evidence is reobserved during cold verification. These bounds
apply to release-review records, not product or runtime limits. A copy failure
leaves failed partial output for inspection rather than rebuilding or repairing.

Both JSON and Markdown summaries include the same bound provenance, runtime
declarations, reported results, evidence digests, limitations and proposed
scope. They continue to say `unaccepted`. The protected reviewer must inspect
the original evidence and actual trusted run/artifact identity, source and
branch rules, policy and complete acceptance; local JSON, `passed`, actor text
and hashes do not establish those facts. No line permission, publisher role,
registry mutation, public install or owner approval is created by this step.

## npm staging protocol and protected execution

```sh
node scripts/release.mjs npm-stage-plan <fixed-directory> <externally-retained-SHA256> <target-id>
```

This command only describes the exact original npm target and proposed
arguments. Mutation CLI commands remain disabled. The reusable
`stagePackageRelease` function in the existing publisher module has no default
runner, credentials or owner reader. A separately protected executor must bind
the owner's approval to this complete fixed set, the permitted identical-byte
recovery scope, immutable validator/workflow revisions and an exact npm pin.
It must enforce one exclusive execution across repositories and keep publisher
credentials outside source-controlled validation. Supplying a callback or a
local approval field does not establish any of these properties.

[npm staged publishing](https://docs.npmjs.com/staged-publishing/) requires
Node 22.14 or newer and npm 11.15 or newer. Stage-only trusted-publisher tokens
cannot list, view or download pending stages; a separate protected owner read
port is required. Approval/rejection retains npm's owner and 2FA duties.
Staging an unused name creates a public `0.0.0-stage` placeholder, so this
protocol requires a distinct owner operation for that initial-name send.
Neither port presence nor a version probe proves the external permission
configuration. The [stage command](https://docs.npmjs.com/cli/v12/commands/npm-stage/)
retains its selected tag through approval. Select a new staging tag explicitly;
`latest`, maintenance tags and proposed final promotion channels are refused
here. Final channel movement remains a separate protected operation.

The protocol cold-verifies the fixed set and every complete original package
inventory, refuses lifecycle preparation, then checks the whole target before
any send. Public versions need exact remote bytes. Pending versions need a
complete owner inventory, the exact name/version/tag/stage identity before and
after downloading, and the actual length/SHA256/SRI of the pending tarball.
An occupied tag, changed bytes, ambiguous stage, incomplete inventory or denied
read blocks execution. Neither actor text nor a registry `shasum` is a byte
proof. These observations do not provide a lock or CAS.

Each new attempt retains private, immutable receipts below the manifest digest
and target. The exact artifact is copied into a private read-only payload;
the intent is synced before the send. Only `npm stage publish` with explicit
registry/access/tag/provenance and ignored lifecycle scripts is issued. Raw
command output and command success remain distinct from owner byte readback.
A lost reply or unavailable confirmation remains unknown. Later recovery
reobserves the originals, reuses an exact public/pending version without sending
again, and sends only missing bytes within the separately approved scope.

The runner must settle only when its original child is terminal. If observation
is lost while the child remains live, the protected executor retains that same
handle; it must not invoke this protocol again. File or descriptor cleanup
failure retains the original cleanup duty. Receipts and synthetic component
tests do not establish registry trust, provenance, owner approval, actual
staging/publication or consumer acceptance. All acceptance conditions stay
pending until their independent evidence exists.

## Read-only public registry observation

The [Native Draft publication protocol](native-cli.md#exact-byte-native-draft-publication-protocol)
uses the same full Native archive and registry byte owners, but requires separate
protected owner read/mutation ports with no default credentials or executable
publish CLI. Complete draft visibility, immutable settings and exact asset
recovery are distinct from the anonymous public observer below. Final channel
promotion, owner authority and real public installation remain unaccepted.

```sh
node scripts/release.mjs observe <fixed-directory> <externally-retained-SHA256>
```

This explicit command makes anonymous GET requests, without reading publisher
credentials, staging, uploading or changing a channel. It verifies the local
fixed set before and after the observation and returns a separate report; the
fixed manifest is never updated with registry state. Save the report at a new
original receipt location. A report is historical observation DATA, not an
owner approval or a lock against later registry changes. The actual authorized
executor must reobserve at its own publication boundary.

For npm, the existing exact name/version/SRI reader remains the identity owner.
The observer additionally downloads and streams the original tarball to compare
size, SHA256 and SRI. For PyPI, it compares the exact release, file, size and
SHA256 from the [release JSON API](https://docs.pypi.org/api/json/), using the
standard [project-name normalization](https://packaging.python.org/en/latest/specifications/name-normalization/),
and streams the wheel to verify its actual bytes. Unselected files, a yanked
file or an occupied empty release cannot authorize appending a new platform or
replacing an old placeholder. PyPI has no npm-style channel promotion.

For npm and PyPI, only a 404 from the original version metadata route is absence. Authentication,
rate-limit/server/transport failures, malformed metadata, failed artifact GETs
and interrupted streams remain unknown. Different occupied identities/bytes
remain conflicts. Both states block resume; neither causes a resend, version
bump, rebuild or `--skip-existing`. Responses are bounded. npm/PyPI redirects
are not followed; artifact downloads stay on the selected public registry origins.

Standalone Native archives use the same `observe` command with their fixed
upper manifest. The anonymous [release-by-tag reader](https://docs.github.com/en/rest/releases/releases#get-a-release-by-tag-name)
requires a visible immutable published release and the exact prerelease flag.
It resolves the actual [Git reference](https://docs.github.com/en/rest/git/refs#get-a-reference),
including a bounded annotated-tag chain, to the fixed source commit;
`target_commitish` alone is not source proof. The complete paginated
[asset inventory](https://docs.github.com/en/rest/releases/assets#list-release-assets)
must contain exactly the selected archive and checksum filenames and metadata.
The observer downloads each actual asset through the public binary API and
compares size/SHA256, even when a legacy API record has no digest. A bounded
HTTP 302 may reach only the selected HTTPS GitHub asset CDN origins; signed
query strings are used for that GET and omitted from the observation receipt.

An anonymous GitHub 404 remains **unknown**, because it cannot establish that
an invisible draft does not already exist. A mutable/different public release
or an immutable release missing a selected asset blocks adoption. This port
does not append assets, authenticate to a draft, create a tag, publish a draft
or perform partial-draft recovery. Those duties still require the separately
approved executor and its actual current observations.

These checks are not a public fresh-install or runtime acceptance. Native npm
launcher artifacts use the npm route. No observer grants publication authority
or substitutes for the separate approved executor.

The separate [standalone Native Remote consumer](native-cli.md#public-standalone-remote-consumer)
retains that same checked public stream for a fresh external extraction and
executes the original direct Native path. Its external Remote test Host is a
separate exact public Node installation; Native children have no Node search
path. Inert HTTP/payload and own-process observation controls qualify only that
consumer mechanism. A selected actual public Native candidate, platform/profile
behavior, standard CLI/README and Local bootstrap remain separate acceptance.

## Channel transition review

```sh
node scripts/release.mjs channels <fixed-directory> <externally-retained-SHA256>
node scripts/release.mjs promotion-plan <fixed-directory> <SHA256> <explicit-moves.json> <channel-report.json>
```

`channels` reads the selected npm packages' current dist-tag maps anonymously.
Only a successful map can establish an absent tag; an unavailable map, including
HTTP 404, stays unknown. The report is separate historical DATA. PyPI has no
dist-tag route, and standalone GitHub Latest is not connected by this npm port.

Each explicitly proposed move contains exactly `targetId`, `name`, `channel`
and `expectedVersion` (a complete literal version, or null for an absent tag).
The destination version comes from the fixed artifact, not another command
argument. The plan binds the fixed manifest and the exact channel-report bytes,
refuses stale expected values, unknown observations and unselected scope, and
records an already-identical value separately. Normal promotion cannot move
backward. Stable `latest` and `release-X.Y` cannot relabel a prerelease as final;
a maintenance tag must match the candidate's actual parsed release line.
An older maintenance line therefore cannot replace a newer stable latest.
An intentional rollback is a separate owner recovery decision, not a normal
promotion or automatic retry.

Every plan remains `execution: unavailable`, pending exact public-install
acceptance, independent owner approval and one protected exclusive executor.
A prior GET followed by a PUT is not atomic CAS. The inspected npm CLI
[dist-tag implementation](https://github.com/npm/cli/blob/latest/lib/commands/dist-tag.js)
reads tags and writes a bare version without a conditional-update argument.
The final execution design must also exclude other writers and recheck actual
values under its authority. A GitHub concurrency name is repository-scoped;
separate repositories must route through the same actual executor. No workflow,
registry role, channel or exclusive-writer setting is configured by these plans.

### Separate post-freeze promotion evidence

A public installed receipt names its original frozen upper digest. Inserting
that receipt into the same manifest would change the digest and create a
self-reference. Do not rewrite the frozen set, its earlier `not-run` result,
or an approval record to make later facts look pre-existing. Prepare a separate
immutable review bundle under the existing release-review owner instead:

```sh
node scripts/release.mjs promotion-review \
  <original-fixed-directory> <original-upper-SHA256> \
  <exact-promotion-plan.json> <original-channel-report.json> \
  <public-evidence-request.json> <new-review-directory>
node scripts/release.mjs verify-promotion-review \
  <original-fixed-directory> <original-upper-SHA256> \
  <promotion-review-directory> <externally-retained-promotion-review-SHA256>
node scripts/release.mjs promotion-summary \
  <original-fixed-directory> <original-upper-SHA256> \
  <promotion-review-directory> <externally-retained-promotion-review-SHA256>
```

The request has schema `actql-release-promotion-review-request/0.1` and exactly
`manifestSha256`, `publicInstallEvidence` and `limitations`. Every evidence
record is `{id, targetId, kind, file, bytes, sha256}`. IDs are unique lower-case
review identifiers, and files are relative to that request without traversal
or links. The existing review bounds apply: 128 records, 64 MiB per original,
256 MiB total. Every promoted target needs evidence; unselected targets refuse.

The currently connected kind is `node-public-install`, from the existing
four-package Node public consumer with an explicit upper/child binding. The
reader compares only its exact original release-set, target, child, source,
version, public-origin and artifact identities. It retains the original actual
Node/OS and declared business/approval scope without promoting those claims.
Legacy child-only, private-loopback, foreign-child or substituted-cohort records
cannot acquire a new upper binding. There is no Native-npm/Python-to-Node cast;
their missing corresponding consumer routes are not silently certified here.

The exact supplied plan is recomputed through the existing promotion owner and
its original raw channel report, retaining expected prior values, source/version,
pre-release and maintenance safeguards. Every move must be in the fixed review's
original proposed promotion scope. Reports are historical DATA, not fresh CAS.

All inputs validate before output. Only the original plan/report/request and
raw evidence are copied, with a separate header and detached digest; original
artifacts are neither copied nor changed. The destination must be physically
outside the original fixed set. Cold verification still needs the exact original
fixed files and independently reobserves every copied input. Missing originals,
changed bytes or an existing output refuse; there is no reconstruction, new
version, recursive enrichment or overwrite.

JSON and Markdown summaries show the same original candidate/artifacts, prior
and proposed channel values, evidence identities and preserved limitations.
Changed evidence or expected values creates a different review digest while
the original artifact digest stays fixed. Both remain `unaccepted`; raw receipt
JSON and a local digest cannot prove a trusted run, actual install/current/close,
owner identity or authority. The separate protected owner decision must bind
this bundle and original fixed set. A future exclusive executor must reobserve
actual public bytes and channel values under its real authority. No credential,
2FA, stage approval, channel mutation or workflow is supplied by these commands.

## Source and maintenance review

```sh
node scripts/release.mjs source-plan <request.json> <repository> [branches.json]
node scripts/release.mjs maintenance-plan <request.json> <repository> <review.json> [branches.json]
```

`release/branches.json` initially selects only the already-permitted 0.0 line
from `main`, with no maintenance cut. It does not grant another release line.
Every allowed line needs one explicit source choice. Before a concurrent next
line begins, the owner selects the maintenance cut and `release/X.Y` branch;
after that selection, candidates for that line must name that branch rather
than current main. No branch or tag is created by inspection. Policy, branch
configuration, validators and workflows still need external protected review;
candidate files cannot establish their own trust.

The source plan reads exact local Git objects, checks branch membership and
the fixed cut, captures original `cherry-pick -x` markers, and reports actual
parents and changed paths. It detects original development commits merged
across the maintenance cut. The maintenance plan refuses that broad history
even if its author labels it a bug fix. This does not authenticate remote Git
hosting or prove that a marker's patch is semantically correct.

The maintenance request names `sourceCommit`, `line` and one record for every
actual change commit, including merge/conflict work. Each record contains its
`commit`, `category`, `originalPR`, affected `contracts`, `regressionEvidence`
(description and SHA256), `adaptation`, and a `forwardPort` decision with
`needed` and `reason`. Ordinary categories are bugfix, distribution, dependency,
regression and docs. Feature, breaking and new optimization-project categories
are refused. Source/commit mismatches and missing records or evidence refuse.
Main backports retain their original PR and need no duplicate forward-port;
line-only/emergency work must record the decision explicitly.

These are complete review-DATA requirements, not semantic certification. The
protected reviewer must inspect actual hunks, originals, claimed regression
evidence and compatibility. A self-authored bugfix label, evidence hash or
`approved: true` cannot replace that review. Use dedicated `cherry-pick -x`
backport PRs and commit-level forward-ports; do not merge whole main into the
maintenance branch or promise a support window implicitly. Maintenance merges
do not pick a number, build a candidate or publish anything.

Python's [exact-byte publication protocol](python-local.md#exact-byte-python-publication-protocol)
uses `release.mjs python-publish-plan` and the same publisher/receipt Owner.
It prepares one project per protected job, keeps the facade behind exact public
SDK/runtime bytes, and distinguishes lost response, terminal success, raw
attestation output and public confirmation. No executable CLI, configured
workflow, OIDC credential, owner approval or actual publication is supplied by
that plan or its inert component controls.
