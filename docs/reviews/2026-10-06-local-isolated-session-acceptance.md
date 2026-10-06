# Local isolated Session physical acceptance

The scoped source change in #412 needs actual image execution, not only Git and
filesystem correspondence. This entry point prepares and executes the existing
13 JS mutations locally without impersonating GitHub Actions. It introduces no
new mutation campaign and changes no selector, workflow or acceptance policy.

The CI collector still uses the guarded Actions-only entry points. The local
entry uses a separate `org.actql.local.owner` label and UUID owner. Local image
records cannot pass the Actions image-owner check. Both entries share source
staging, distribution/loader observation, the scratch Dockerfile, execution
restrictions and the actual scientific input/result validators.

## Explicit preparation and execution

Use the candidate's pinned Linux x64 MoonBit/core archives from `toolchain.json`;
verify their SHA-256 before extraction. Set the executable modes as the existing
setup script does. Bundle only core JS with the pinned Moon:

```sh
moon -C "$MOON_HOME/lib/core" bundle --target js --warn-list -a
```

On a non-Linux host, do that preparation in an explicitly inspected Linux/amd64
builder. Obtain Node at the candidate workflow's pinned version and record its
immutable Docker image ID. The local runner rejects another architecture and
checks the actual Node, Moon and moonc versions during preparation. Supply the
immutable ID, never the registry tag, to the acceptance command:

```sh
node proofs/ci-evidence/local-isolated-acceptance.mjs run \
  --engine /absolute/path/to/docker \
  --builder-image sha256:<inspected-linux-amd64-builder-id> \
  --moon-home /absolute/path/to/pinned-linux-x64-moonbit
```

Preparation uses a read-only candidate mount and read-only toolchain mount. Git
object identities independently bind every source read. Its only writable host
mount is its newly allocated output directory. The actual mutation container is
a separate scratch image with no host mounts, network or inherited credentials,
a read-only root, fresh tmpfs workspace and user 1000. The four installed core
build metadata files are absent from its observed physical inputs.

The existing bounded local supervisor serializes this deliberately selected
physical action and records its 1,200-second outer budget; the unchanged inner
mutation execution retains its 600-second budget. This is not a full local CI
campaign. Compilation errors, zero assertion failures, incomplete logs, failed
restoration, changed runtime inputs or changed host source cannot pass the
shared consumer.

## Evidence and remaining boundaries

`_build/local-isolated-*/acceptance.json` records the clean full source revision,
immutable builder/image identities, actual manifest, 13 original mutation logs,
byte-restoration result, original observation and scoped consumer acceptance.
The record is exclusively created, carries `authority: local-physical-acceptance`
and `reuseAuthorized: false`. The outer bounded wrapper retains its own receipt.
Preparation/inspection/build/execution/cleanup costs are recorded independently.

The local profile explicitly binds `UV_USE_IO_URING=0`, observed in OrbStack's
amd64 execution. This field is present in the Dockerfile, image config, manifest
and actual child observation. Missing/changed fields fail locally, and the CI
input consumer rejects the `localDiagnostic` marker; its original environment
contract is unchanged. No injected value is erased or treated as irrelevant.

Local kernel/CPU/emulation and builder distributions remain actual observed
inputs. A local pass does not clear runtime residuals, qualify an authenticated
main origin, issue a reuse certificate or establish hosted CI/net savings.
Existing Actions-origin final acceptance remains unchanged. A local physical
pass can close the image execution boundary in #412 while those distinct
operational/economic obligations remain open.

Cleanup authenticates exact container/image IDs and local owner labels. It
never prunes shared resources or removes the supplied builder image. Failed
preparation retains its directory and CID custody for diagnosis; if the outer
supervisor itself is killed, inspect that custody and the exact owner before
manually removing anything. Preserve logs/manifests/receipts before discarding
reproducible image-context bytes.
