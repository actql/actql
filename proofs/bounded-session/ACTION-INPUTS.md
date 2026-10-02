# Bounded Lean action inputs (Stage B, report only)

This inventory observes the existing bounded-session `check.mjs` action. It
never skips verification, supplies a cache result, changes a proof, or establishes
formal dependency completeness. Every report and comparison is **unknown for
reuse** and `eligibleForReuse: false`, including equal input keys. Stages C/D/E
and scheduling duplication analysis are separate work; consumers should reuse
this module rather than define another action key.

## Generate and compare

The existing `run.mjs` generates `.artifacts/bounded-session/action-inputs.json`
from the exact Node executable, argv, working directory and environment it then
passes to its unchanged Lean action. The existing CI artifact upload retains it.
Both ordinary invocations of `run.mjs all` rebuild the inventory. The existing
14-theorem check, typed Claims compilation, per-theorem axiom audit, broad source
snapshots, all targets, mutations and full CI gates still run. The existing
evidence fixture gate imports the small input-inventory tests.

For a standalone `node proofs/bounded-session/check.mjs` launch with the current
environment (not the MoonBit-augmented environment constructed by `run.mjs`):

```sh
node proofs/bounded-session/action-inputs.mjs inventory --source-sha FULL_SHA > before.json
# Generate after.json explicitly in the candidate execution context.
node proofs/bounded-session/action-inputs.mjs compare before.json after.json
node --test proofs/bounded-session/action-inputs.test.mjs
```

The SHA argument is optional; omission records unknown provenance (`null`). It
is an explicit provenance assertion, not a Git/clean-worktree verification. The
normal runner obtains its SHA from Git. No automatic prior-manifest search, old
inventory reuse, receipt reuse, remote writes or selector is implemented.
Comparison identifies changed/added/removed files and environment names plus
changed command, generated-source, path and platform sections. Malformed,
ambiguous or unknown-schema manifests produce unknown/refusal and CLI exit 1.
A successfully generated unknown report exits 0: reporting succeeded, but this
is **not** permission to skip or proof that verification passed.

## Exact observed boundary

- Current bytes of `check.mjs`, `Session.lean`, `Claims.lean`, `lean-toolchain`
- Current theorem inventory in checker order, full typed Claims text, generated
  `#print axioms` commands and exact UTF-8 stdin (including separating newlines)
- Node invocation and both Lean invocations, ordered arguments, cwd, UTF-8 I/O
  and output buffer bounds; `--short-version` remains an executed check, not an
  identity shortcut and not a command executed by the inventory itself
- Actual Node executable bytes and PATH-resolved Lean executable bytes, requested
  and real paths, and filesystem modes/kinds along their parent paths
- A fresh recursive enumeration of the resolved pinned
  `lean-4.30.0-rc1-linux` distribution: every directory, regular file and link,
  including `.olean` inputs and native libraries. There is no mtime-only shortcut
  or assumed-complete cached file list. Other layouts/wrappers are unresolved;
  the reporter never recursively inventories a generic `/usr` prefix
- Platform, architecture, OS release, absolute root/cwd/model/distribution paths
- A fixed allowlist of ordinary execution-configuration environment names and
  SHA-256 of their exact UTF-8 values: PATH/home/temp, locale, Lean/Elan, Node
  options and loader paths/options (see `environmentNames` in the module). Values
  are not emitted. Absence differs from empty; PATH order, empty/relative
  components and the allowlisted configuration are not normalized. Arbitrary
  inherited names, values and secret-derived digests are never serialized

The reporter deliberately overcaptures the pinned distribution. This may cause
false changes; it cannot establish a minimal dependency set. A standalone
launch and the runner's MoonBit-augmented launch usually differ. Environment
coverage is explicitly incomplete: non-allowlisted variables are omitted,
including CI metadata and possible secrets. Their names, values and guessable
hashes are not published. Equal keys therefore mean equal **observed** inputs,
not equal complete inherited environments or equivalent actions. The separate
provenance SHA is excluded from the key. An unrelated documentation edit plus
a provenance-only SHA change leaves otherwise identical observed inputs/key
unchanged. Absolute paths remain significant.

## Unresolved dependencies and conservative recognition

Recognition is pinned to the reviewed exact checker/model/Claims bytes. The
current files are always reread and hashed; fingerprints are a supported-grammar
boundary, not a saved inventory. A changed checker, new import, registry read,
file enumeration, dynamic JS/Lean action, or even an unreviewed comment change
makes structure unknown. Merely retaining 14 theorem names cannot establish
coverage. Unknown sources still affect the key and never gain reuse permission.

Even the recognized action has unresolved system loader/shared-library inputs,
Node built-ins, CPU/kernel behavior, external runtime/import paths, locale
configuration, non-allowlisted inherited environment, wrapper behavior and
external environmental effects. Hashing the
candidate Lean prefix does not prove it is the complete runtime dependency
closure. Symlinks are recorded with their literal target and make coverage
unknown; distribution directory links are not traversed. Resolved executable
bytes are separately recorded. Missing, unreadable, changing or special files
remain explicit unknown entries; FIFO/device inputs are never opened as files.

Regular-file reads use no-follow/nonblocking opens, stop after the observed
size plus at most one growth-detection byte, and compare inode/device, mode/size
and high-resolution timestamps before/after reading. Source text comes from
those same guarded bytes (at most 16 MiB each), without reopening an unchecked
path. External comparison manifests use the same guarded reader and a 32 MiB
limit; symlink, FIFO and oversized manifests are refused. Directories are
checked across enumeration. These observations are not an atomic filesystem
snapshot or a binding to the later process execution. The total distribution
inventory is bounded at 50,000 observed entries and 8 GiB of regular bytes;
exceeding a limit is unknown, never complete. Inodes/timestamps support race
checks but are excluded from content identity. None of these diagnostics close
the filesystem/runtime/environment boundary.

## Encoding and schema

Schema: `actql-bounded-session-action-inputs/0.1`.
Key: SHA-256 of UTF-8 `actql-bounded-session-action-key/0.1`, one NUL byte,
then the canonical encoding of `inputs` only. The manifest's provenance,
coverage explanations and actionKey are outside that preimage.

The encoding is compact JSON without BOM, whitespace or final newline. Object
keys are ordered by unsigned UTF-8 bytes; strings are JSON escaped, Unicode is
not normalized and lone surrogates are rejected. Numbers are safe integers;
negative zero, floats, unsupported values and sparse arrays are rejected.
Files (absolute path) and environment (name) are unordered sets with unique
identities, sorted before keying. All other arrays, particularly argv, theorem
order, import order and commands, retain execution order. Paths are absolute,
lexically resolved paths with separately recorded symlink/realpath semantics.
No repository-root replacement or case/Unicode normalization occurs. File mode
is the observed low 12 permission/special bits; file kinds and symlink target
text are part of identity. File bytes use SHA-256, never a displayed version.

Serialized manifests use the same canonical JSON plus one final LF. Parsing
requires exactly that representation, rejects duplicate keys and lossy UTF-8,
and validates the schema and recomputed action key. Reordering the semantic
file/environment sets retains their key. The tests include independently
authored UTF-8 encoding and SHA-256 vectors, rather than deriving expected keys
from the reporter. This is a deterministic report format, not a signed or
trusted execution receipt.

## Evidence scope

The initial source boundary is main
`bcbf77049fe4991c9b0f1a18541ac7a7952b01ad`, after #190's integration. Its historical
artifacts and foundation declarations are untouched. Focused fixtures cover
source/argument/environment/executable/distribution changes, provenance-only
documentation, newly discovered files, imports and dynamic reads, symlink
substitution, missing/special inputs, unordered entries, malformed schemas and
explicit comparison refusal. Fixture executable bytes do not claim actual Lean
execution. Actual theorem/type/axiom acceptance remains the existing hosted
pinned-Lean gate at the submitted final revision.
