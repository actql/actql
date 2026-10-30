# Python Local fixed artifact preparation

This is a maintainer recipe for the selected macOS11-or-later arm64 profile,
not public Local Client or wheel acceptance. The standard product is `actql`
with exact `actql-sdk` and `actql-local-runtime` dependencies; the lightweight
SDK does not have a Local extra. Users install a selected exact product version;
they do not build source, supply a Wasm path, or run these producer commands.
The ordinary public Local Client entrance must be completed and independently
accepted from installed wheels before the profile is delivered.

## Original physical inputs

Use one committed clean source SHA for the public SDK, producer, module and
receipts. Select the repository-pinned MoonBit toolchain, an isolated Python
environment with Wasmtime38.0.0, and the standalone DuckDB1.4.3 library.
Do not substitute a Node/Python extension's library or an older module receipt.
The producer imports the existing `LOCAL_CORE_ABI`; it maintains no ABI table.

Under the coordinated Heavy lane, obtain the existing Core physical receipt:

```sh
ACTQL_PYTHON_LOCAL=/absolute/producer-venv/bin/python \
  node scripts/check-python-local-core.mjs --physical-boundary
```

This retains `_build/python-local-core/artifacts/<full-sha>/client_host_wasm.wasm`
and `physical-boundary-receipt.json`, with original source, module SHA256,
pinned compiler and actual buffer/bridge/workspace results. The bridge fixture
uses the existing Core loader, including its ABI check. This is private
physical evidence, not public Local acceptance or a complete ABI campaign.

In that same clean checkout and reserved physical lane, retain the existing
standalone DuckDB fixture's original JSON output:

```sh
/absolute/producer-venv/bin/python scripts/fixtures/python-local-duckdb-physical.py \
  /absolute/standalone/libduckdb.dylib --digest <original-sha256> \
  --version v1.4.3 > /absolute/owned-evidence/duckdb-physical.json
```

The fixture must exit0 and report20 actual standalone cases, matching source,
arm64/macOS, exact library digest and observed version. An interrupted, skipped,
workspace-only or synthetic record is not physical acceptance. Preserve the
command/exit/log and original JSON in the producer's execution evidence.

## Component assembly and wheel staging

With both original physical receipts retained:

```sh
python scripts/produce-python-local-runtime.py \
  --core-receipt /absolute/fixed/physical-boundary-receipt.json \
  --duckdb-receipt /absolute/fixed/duckdb-physical.json \
  --image-receipt /absolute/fixed/compiled-image.json \
  --destination /absolute/new/artifact-directory
python scripts/prepare-python-local-runtime.py \
  --artifact-directory /absolute/new/artifact-directory \
  --destination /absolute/new/runtime-package-stage
```

Assembly uses the existing installed-component, Mach-O target/dependency and
original-notice checks. It hashes and copies the selected unchanged module,
library and four repository notices, then rechecks the copied artifact. It
does not compile, load Wasm/DuckDB, execute a Run, make an ACK, build a wheel,
download or publish. `producer.json` binds artifact/toolchain/receipt digests;
keep its referenced original receipts. Failed output is retained for review,
and an existing destination is never overwritten.

The stage remains source-qualified component material. A release uses the
existing complete product/SDK/runtime wheel builder with a required explicit
SemVer input:

```sh
python scripts/build-python-product-wheels.py \
  --artifact-directory /absolute/fixed/artifact-directory \
  --destination /absolute/new/versioned-cohort \
  --version "$ACTQL_VERSION"
```

Set `ACTQL_VERSION` to the complete owner-selected candidate version. The
shared Node build-time parser supplies the PEP 440 spelling; the installed
Python consumer never requires Node. Native-owned runtime preparation also
needs its original explicit binding/library inputs. Version choice alone
does not select an allocation profile, approve publishing or establish a
working Local installation.

Only the isolated three project manifests, their internal exact dependencies,
and the two package-version fields in staged runtime metadata are projected.
The source artifact stays unchanged. The original component reader admits the
source before projection and reinspects the staged result afterward. Module,
image, native library, engine settings, recipe and source identities must stay
exact. The SDK binding and optional capacity envelope use the resulting fixed
release context. The cohort records both source and projected metadata hashes;
they are provenance DATA, not physical execution or owner approval. A final
version is separately built and accepted; an RC filename cannot be relabelled.

Verify wheel/member digests and install
them into an empty consumer outside the repository. Installation, imports,
public Local execution, Result, recovery and wheel portability remain separate
checks. No physical receipt, synthetic assembly test or header check substitutes
for that installed public consumer campaign.

## Fixed public consumer acceptance

After the owner has selected the complete version and a finished, verified
cohort has been frozen, the existing installed consumer fixture can be run
against the exact public release:

```sh
node scripts/test-python-release-install.mjs \
  /absolute/fixed/release-set "$ACTQL_RELEASE_SET_SHA256" python \
  /absolute/selected/python /absolute/new/external-consumer

# A separate fresh consumer using uv's project interface:
node scripts/test-python-release-install.mjs \
  /absolute/fixed/release-set "$ACTQL_RELEASE_SET_SHA256" python \
  /absolute/selected/python /absolute/other/new/external-consumer \
  --uv /absolute/selected/uv
```

`python` is the original target id, not a default or a replacement interpreter.
The last directory must be new and outside the repository/fixed artifacts.
This launcher never produces a wheel or image, publishes, selects a version,
repairs a missing artifact or resumes a failed acceptance state. The current
normal runtime remains macOS arm64 only; Linux/other platforms refuse before
installation. The review-only Linux pre-root source does not qualify a Linux
engine, normal provider, image or wheel.

The complete original wheel reader runs on the retained fixed layout. Anonymous
PyPI metadata and actual remote wheel bytes must match every selected artifact
before installation. The same read owner runs afterward. Unknown, missing,
yanked or different bytes stop the campaign. Neither a metadata hash nor an
HTTP success is consumer acceptance.

The launcher creates separate fresh venvs for the lightweight SDK and product.
Each install names only `actql-sdk==<exact-version>` or `actql==<exact-version>`
at the official index. It allows binary wheels only, disables caches/source
builds, and records pip's stable installation report. Fresh HOME and
[`PIP_CONFIG_FILE=os.devnull`](https://pip.pypa.io/en/stable/topics/configuration/)
exclude inherited pip configuration; source paths, publisher credentials and
proxies are not forwarded. Only the new venv's executable directory is on the
consumer PATH. The pip mode checks absent Node/npm/ActQL CLI before and after
installation and consumption; uv uses an empty installer PATH and checks its
new environment after installation and consumption. Build-time validation may use Node; installed
Python operation may not.

The [pip report](https://pip.pypa.io/en/stable/reference/installation-report/)
is observed output, not a lock or approval. The audit requires official public
wheel URLs, exact original versions/hashes and exactly one requested entry.
It compares every installed ActQL payload's bytes and modes with the original
wheel, checks the complete raw RECORD plus pip's generated metadata, and refuses
source links or surplus namespaces. Missing RECORD rows cannot be hidden by
`importlib.metadata.files`. The installed audit runs before and after the
business fixture without importing the product itself.

The explicit uv mode uses `uv add` for the same one exact public entry. It
creates separate fresh projects and `.venv` environments, selects the absolute
Python interpreter without managed-Python downloads, and refuses an enclosing
project before invoking uv. Its empty installer PATH, fresh HOME/temp directory,
`--no-config`, `--no-sources`, `--no-build`, `--no-cache`, disabled keyring and
copy link mode exclude shared caches, workspace sources and source builds.
The selected uv executable's real path, original file identity, hash and version
are retained and reobserved; the launcher does not install or update uv.

uv's [project lock](https://docs.astral.sh/uv/concepts/projects/layout/#the-lockfile)
is resolution evidence, **not** pip's download transaction report. The audit
accepts only its selected version-1/revision-3 format, the exact one-entry project,
the official PyPI registry, and the original ActQL wheel filenames/hashes/sizes.
Only the explicitly persisted official default index is permitted as project
configuration. Unknown revisions, forked resolutions, alternate ActQL artifacts,
local/direct sources and workspace bindings require separate review and refuse.
Third-party universal resolution entries do not mean every listed artifact was
installed or executed. Independent actual PyPI byte observation and the complete
installed ActQL payload audit remain required before and after consumption.
uv's installer marks every installed package `REQUESTED`; the one requested
public entry is therefore established by the actual project and lock rather
than those markers. The same payload owner checks uv's exact installer metadata,
complete raw RECORD and full namespace. A uv lock is never synthesized as a pip
report, and local-index/injected-lock controls do not establish public acceptance.

The original fixture checks SDK-only absence of Local packages, then runs the
sync and async Local scenarios in separate fresh HOMEs. Each initial Run's
public reference is retained before wait. Successful scenarios write a distinct
receipt only after their original close; another process looks up and attaches
that same Run without submitting again. Repeated Result reads use the original
integer-row oracle. All four Local processes hold after close for a scoped
state-descriptor observation and acknowledge it while still alive. Process exit
alone supplies no close ACK or live-descriptor proof.

All commands, reports/locks/projects, references, HOME/state and outcomes stay at the original
consumer path, including failures. A failed initial receipt cannot be reused
to submit again. Inert wheel/report tests and a local-index pip mechanism check
qualify only those components; they do not establish public availability,
normal engine execution, Linux support, recovery or release approval. No real
version or finished B cohort is selected by these test fixtures.

## Exact-byte Python publication protocol

The existing publisher Owner exposes a read-only preparation command:

```sh
node scripts/release.mjs python-publish-plan <fixed-directory> <externally-retained-SHA256> <python-target-id> <absolute-verifier-python> <protected-PyPA-action-commit>
```

This calls the original complete frozen-wheel verifier, preserves the shared
SemVer-to-PEP440 projection and requires the original three-project target.
Only its actually verified platform may be selected; an extra Linux platform
cannot inherit a macOS cohort. The plan is DATA with execution unavailable.
No product version or action revision is chosen automatically.

`publishPythonReleaseProject` in the existing publisher module is a reusable
protocol for the separately protected executor. It has no default job runner,
credential or CLI execution route. Actor names, `approved` fields, callbacks and
supplied acceptance labels are not authority. The independent owner must verify
the exact source, evidence, version, proposed scope and bytes using the actual
protected immutable validator and exclusive execution service.

Each invocation addresses one project and one original fixed manifest. SDK and
runtime have separate jobs; a new facade upload requires both dependency wheels
to be public with their exact original bytes. This dependency graph is not
permission for concurrent mutations: the protected executor still serializes
actual release operations across repositories. Whole-target preflight and a
fresh before-send observation stop on unknown/conflicting or foreign files.
Already-identical public bytes are not sent again. An earlier attempt requires
the original explicit same-byte recovery scope; a changed version, source,
wheel, digest or scope needs a distinct candidate and owner decision.

The same private receipt writer used by npm records an immutable attempt,
read-only exact wheel copy and synced intent before invoking the supplied
project job. Its payload directory must be in the original mounted publisher
workspace and use a literal Unix path accepted by the selected action. Exactly
one project's wheel enters that directory. There is no source build, new wheel,
`--skip-existing`, bump, overwrite or alternate index. A lost response remains
Unknown. The executor retains the SAME live job/handle until terminal; it cannot
start another job because observation timed out. On later authorized recovery,
original public bytes are reobserved before any possible send.

Original terminal output, command success, public-byte confirmation and raw
attestation output are separate records. The wheel is checked again after the
job, and only its newly generated bounded regular attestation sidecar is allowed.
A sidecar digest does not verify its signature, publisher identity or PyPI
provenance. A successful command without exact public readback does not finish
the attempt. Failed attempts, outputs and original intents remain unchanged.

The official [PyPA action guidance](https://github.com/pypa/gh-action-pypi-publish/blob/dc37677b2e1c63e2034f94d8a5b11f265b73ba33/README.md)
requires one invocation per top-level Linux publishing job, separate from build
work. Each actual job needs its own owner-approved Environment and project
Trusted Publisher; job-scoped OIDC replaces supplied passwords. The protocol
requests metadata checking and attestations, and keeps skip-existing disabled.
These settings do not configure trust or obtain a credential.

The inspected [action trampoline](https://github.com/pypa/gh-action-pypi-publish/blob/dc37677b2e1c63e2034f94d8a5b11f265b73ba33/create-docker-action.py)
selects a GHCR image tag derived from the action ref. A full source-commit pin
alone therefore does not establish the executed container's immutable digest.
Actual image/tool correspondence, signature/provenance verification, project
settings, exclusive execution, owner approval and genuine publication remain
unaccepted. Local inert-wheel/injected-port controls are not PyPI, signing,
Trusted Publishing, product/runtime or public-install acceptance.
