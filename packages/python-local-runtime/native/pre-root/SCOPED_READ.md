# Derived same-provider read allocation

The physical allocator patch is reproducible from pinned inputs. It does not select a new default producer, replace the installed
toolchain, or enable an ordinary Local supplier. The numerical profile stays
`None` until the original Common backed pair, caller closure and layout review
are complete.

From the repository root, prepare a new disposable source directory:

```sh
python3 packages/python-local-runtime/native/pre-root/prepare_scoped_read.py \
  --moonbit /path/to/selected/moonbit-0.10.12+1634b282e \
  --destination /path/to/new/derived-read-source
```

These are developer preparation paths, not public Python Client options. The
command never compiles, loads or installs a library. `scoped-read-source.json`
pins 21 input files and 23 derived files. Its patch and every derived output
have separate SHA256 identities.
Changed inputs, patch, derived bytes, symlinks and existing destinations are
refused. Only copied bytes are patched. Completion metadata is written last;
partial output is not a usable stage. This is a source closure, not a receipt
for a compiled artifact or a trusted funding grant.

## Explicit source target

The default source selection remains `aarch64-apple-darwin`. A selected Linux
arm64 consumer must pass `--target aarch64-unknown-linux-gnu` and supply the
pinned Linux toolchain inputs. The ten text inputs are shared; the original
runtime object and backtrace archive have separate Linux identities. A Darwin
binary cannot satisfy Linux preparation, or vice versa. Preparation does not
install a toolchain or compile either target.

Linux consumers must use the recorded `_GNU_SOURCE` and
`ACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN` definitions alongside the scoped
allocator definitions. The actual FD, mapping, extent, domain and Read context
still require their original acquisition and cleanup. The Linux selection does
not include Darwin image capture, Rust, Engine or VM support, or adopt an
installed supplier or a normal numerical profile. A bootstrap consumer imports
the single selected provider through `ACTQL_BOOTSTRAP_IMPORT_PROVIDER`; it must
not include another provider or the Darwin-only image implementation.

## Build and lifetime obligations

Every generated-C and runtime consumer of `MOONBIT_MALLOC_RAW`,
`MOONBIT_FREE_RAW` and `moonbit_free` must use the same copied header with
`MOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC` and
`ACTQL_SCOPED_READ_ALLOCATOR`. Include the original C provider exactly once.
The original `libmoonbitrun.o` supplies its original mimalloc implementation,
including its load initializer. Reusing stock-header objects with the derived
free route is invalid. New generated C, provider, ABI, library and image must
have their own complete derived identities; this unit does not relabel retained
artifacts. Filesystem callers must independently preserve the same original
Read context and cleanup ownership.

The existing Common Owner must bind the original reservation/backing/borrow
before creating an opaque context. C pointers and matching data are not grants.
Same-context entry uses the original provider; a foreign nested context,
inherited context, closing context or exhausted arena never falls back to a
system allocation. Ordinary non-target allocations retain their original
allocator. After fork, only pointers owned by that original stock allocator
take its free path; inherited arena pointers are refused before any inherited
context index/lock is read. No PID adoption or context reset occurs.

Leaving the call does not retire returned managed Bytes, error carriers or
other aliases. Actual last-reference free uses the original extent's provenance.
Existing logical closing denies new work. Physical closing waits for active
calls and original user acknowledgments so the same scope can finish cleanup.
Failed extent/context retirement retains the same slot and lease for original
cleanup retry; it does not retry a Run, read, COMMIT or external operation.
Full lease return is denied while a context remains. Unexpected managed OOM
uses the existing fail-stop path and is not a successful cleanup observation.

## Non-test Native provider production

The existing `scripts/produce-python-native-provider.py` has an explicit
maintainer-only `--scoped-read` selection. It prepares the verified copied
closure inside a fresh output directory, compiles every regular generated-C and
runtime consumer against the derived header, and includes that same provider
once through the bootstrap stub. The original toolchain and default stock
selection remain unchanged. A missing/changed source or failed derived build
never falls back to stock. Neither build selection nor a successful library
build adopts installed authority, numerical funding or an ordinary Local profile.

```sh
python3 scripts/produce-python-native-provider.py \
  --source <exact-clean-commit> --moon-home <selected-toolchain> \
  --clang <selected-clang> --sdk <selected-sdk> \
  --destination <new-output-directory> --seconds 300 --scoped-read
```

These paths are maintainer inputs, not Client options. Use the existing bounded
verification guard. The receipt records the patch/recipe/derived output digests,
actual compiler dependencies and library identity. The runtime sources are
compiled from the copied closure; diagnostic conformance helpers are excluded
from the library. Explicit code-root initialization, image/Wasmtime compilation,
Engine/worker startup, installation and public Python execution remain separate.
A following Wasmtime build must link this exact selected library and use a new
provider digest in its recipe; it must not embed another provider/TLS copy or
relabel a previous compiled image.

## Active cleanup result lifetime

An entered original cleanup frame retains allocation custody until it leaves,
even if Root/Reader close returns the last user within that frame. This permits
its managed result or failure carrier to be constructed in the same arena. It
does not permit a new entry without a user. Physical retirement still waits for
all active frames and aliases. The independent `cleanup-result-after-last-user`
C case fixes this boundary; its execution evidence is reported separately from
the retained nine-case source and any whole Root/Reader caller.

## Alias-only original cleanup entry

After the last Root/Reader user acknowledges close, a pending managed alias can
retain the same closing context. The existing Common stopped read-use may enter
that original carrier for cleanup without creating another user. Normal entry,
retain, fresh Root construction and the ordinary current-context projection stay
closed. The active cleanup frame owns its result until its last alias retires.
No new TLS, queue, Owner or allocator is introduced. The bootstrap C bridge
selects cleanup only after its original read user has returned; Common still
checks the nominal child/read-use before invoking it. Whole caller acceptance
and numerical profile adoption remain separate from the finite C conformance.
