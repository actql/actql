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

Run preparation under the existing local heavy guard, with the repository's
Node and MoonBit toolchain pins. Use a unique, absent RC destination:

```sh
node scripts/package-release.mjs prepare /absolute/path/to/rc
node scripts/package-release.mjs verify /absolute/path/to/rc
node scripts/test-package-release-install.mjs /absolute/path/to/rc
node scripts/package-release.mjs plan /absolute/path/to/rc
```

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
