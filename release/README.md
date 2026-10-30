# Fixed SDK / Node release

The first standard cohort is `@actql/client-wire`, `@actql/sdk`,
`@actql/local-node`, and `@actql/node`, all at `0.0.1` with exact internal
dependencies. `@actql/sdk` remains a remote Client with no Local runtime or
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
node scripts/package-release.mjs prepare /absolute/path/to/rc
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
It installs only `@actql/node@0.0.1` or `@actql/sdk@0.0.1`, using a read-only
loopback registry that serves the fixed RC. npm resolves dependencies, and
the acceptance audits exports/types and executes the existing Local/restart
and short-query/HTTPS cases. This establishes registry installation mechanics,
not public npm availability, live Cloud operation or every Provider feature.

Give the integration reviewer the source SHA, PR, manifest, exact archives,
digests, commands and receipts. Independent acceptance must consume the same
archives outside the repository. A changed RC needs a new unique directory
and acceptance of affected paths; old receipts are never relabelled.

## Publication and recovery

Public publication requires integration-owner GO for the exact names,
versions, digests, registry, tag and evidence. Authentication checks and
preparation do not grant that GO. Keep Hosted CI stopped.

After GO, an authenticated operator invokes:

```sh
node scripts/publish-package-release.mjs --publish /absolute/path/to/rc
```

This publishes frozen archives in dependency order, with lifecycle scripts
disabled. Before any write, all existing versions are inspected. A 404 is
absence; transport failure, registry failure and mismatched integrity are
errors. Only an existing identical version is skipped. Publication command
success and later registry confirmation are separate facts; immutable local
receipts preserve successful commands even if confirmation is unavailable.
After partial failure, inspect the same RC and rerun the command. It will not
republish confirmed bytes, overwrite a version, choose a new version, or infer
that an unconfirmed command never executed. Never publish mutable package
directories instead of these archives.

Before a next release, choose a new cohort version in the reviewed recipe,
prepare and independently accept new archives, inspect existing versions, and
obtain new GO. An incorrectly published immutable version is not repaired by
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
npm install @actql/node
```

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
npm install @actql/sdk
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

Explorer is separately installed with `npm install @actql/explorer`; it is not
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
kinds are `node-npm`, `native-npm` and `python-wheels`. Native npm launcher
packages are not standalone Native archives; no standalone adapter is connected
at this layer yet. The existing Python wheel verifier currently selects only
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
and `state` (`absent`, `present`, `unknown`); a present observation also carries
the exact artifact `identity` (name/version/bytes/SHA256 and npm integrity).
Identical bytes may be reused, absence names the same missing bytes, unknown
blocks the plan and any mismatch stops it. This input is not authenticated
registry reobservation or owner authority, and the command never sends bytes.
Live PyPI/Native observation adapters, protected execution, channel arbitration
and release acceptance remain separate unfinished work.

All sets from this layer remain explicitly `unaccepted`. The existing Python
checker reused here establishes wheel metadata and frozen-byte correspondence,
not original engine execution, normal install, Linux support or public registry
acceptance. Synthetic metadata fixtures contain no usable engine. Real
candidate assembly and acceptance wait for the selected coherent product
source and owner-selected version/scope.
