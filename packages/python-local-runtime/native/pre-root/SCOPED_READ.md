# Derived same-provider read allocation

This review unit makes the tested physical allocator patch reproducible from
pinned inputs. It does not select a new default producer, replace the installed
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
pins 18 input files and 20 derived files. The exact patch SHA256 is
`f85133840d3b8fe074a95a7f04d6cd4f50466b474a2257ebfe0df86ce7f41615`.
Changed inputs, patch, derived bytes, symlinks and existing destinations are
refused. Only copied bytes are patched. Completion metadata is written last;
partial output is not a usable stage. This is a source closure, not a receipt
for a compiled artifact or a trusted funding grant.

## Build and lifetime obligations

Every generated-C and runtime consumer of `MOONBIT_MALLOC_RAW`,
`MOONBIT_FREE_RAW` and `moonbit_free` must use the same copied header with
`MOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC` and
`ACTQL_SCOPED_READ_ALLOCATOR`. Include the original C provider exactly once.
The original `libmoonbitrun.o` supplies its original mimalloc implementation,
including its load initializer. Reusing stock-header objects with the derived
free route is invalid. New generated C, provider, ABI, library and image must
have their own complete derived identities; this unit does not relabel retained
artifacts. F's separate filesystem caller patch is not included here.

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

## Source-qualified evidence

The copied patch and `fixtures/scoped_read.c` were consumed under clean parent
`7cc1866bbea6ee1c3128a39cca5495a02901ffc1` by `run-IIAMdL` using the selected
macOS SDK/clang, C11/O0, 64-page disposable arena, non-Heavy outer60/TERM5 and
cumulative child50/j1. Five runtime C sources, two fixture variants and two
executables were built. The earlier `ec0744c8` variant failed the real fork
counter; the fixed variant discovered/executed/passed **9/9**. These results
qualify the original derived bytes, not a new current-source runtime build.

The cases cover child stock free, actual MoonBit Bytes/RC aliases after scope
exit, same-owner cleanup, nested/foreign/closing rejection, exhaustion without
fallback, original extent retirement retry, inherited arena refusal,
foreign-PID refusal and context retirement retry. Retirement failure is an
explicit fixture `mprotect` fault on the exact original extent. Test fork/wait
children are not product workers. The optional `ACTQL_F_CALLER_CASES` fixture
branch was not selected: Root/Reader caller execution is **0** here.

The raw evidence remains in workspace reviews under
`2026-10-10-python-client/scoped-native-read-conformance`: input/actual dependency
hashes, original failure, new success, commands, binaries, complete guard output
and Owner/group/lock release. `runtime-reuse.json` qualifies the five runtime
objects and derived header for F's matching caller diagnostic. The old/new
fixture objects contain test main and are not reusable provider objects.

The compiled object's DWARF records context48/extent48/capacity136 bytes. These
are structure sizes, not allocator charges, a complete retained inventory or
accepted numerical profile. Common paired funding, F's caller, complete layout,
DLL/Engine/worker, ordinary installed wheel/public Python execution remain
separate and unaccepted. Fuel100M, transfer12MiB and VM16MiB are unchanged.
