# Development

## Setup and verification

With Node.js 22 or newer and Python 3.10 or newer:

```sh
npm ci
npm run check:docs
```

Node.js is used for documentation and toolchain setup. Product implementation
is developed in MoonBit; see the [implementation guide](design/implementation-port.md).

### MoonBit

Development supports Apple Silicon macOS and x86-64 Linux, with Linux CI on
Ubuntu 24.04. Git, curl and tar are required. Install the exact stable toolchain
and matching core from [toolchain.json](../toolchain.json):

```sh
node scripts/setup-moonbit.mjs
export MOON_HOME="$PWD/.toolchains/moonbit-$(node -p "require('./toolchain.json').version")"
export PATH="$MOON_HOME/bin:$PATH"
moon version --all
moon fmt --check
moon check --deny-warn
moon test --deny-warn
```

Setup verifies archive SHA-256 pins before extraction and installs only inside
the ignored `.toolchains/` directory. It does not modify a global installation
or shell startup files. Downloads remain in `install-*` directories for inspection.
Reuse checks the installation marker, tool versions, executable files, core
manifest and three prelude bundles. This is a health check, not a full integrity
scan of installed core sources. If it fails, move only the named toolchain
directory aside and rerun setup; an existing installation is never overwritten.
Use the same environment variables in the editor's launch environment.
Do not run `moon upgrade` inside this installation: update the reviewed version
and archive pins together, then reinstall and run all checks.

The root `moon.mod` defines the single `actql/actql` module. JS is the default;
common-core packages support JS, Wasm (not Wasm GC), and native. JS is the
daily development default for the shared core, not a restriction on CLI or Host
deployment. Wasm GC is outside the initial validation scope; adding it requires
toolchain setup and target tests, not just a metadata change. Run the same
checks as CI with explicit targets:

```sh
for target in js wasm native; do
  moon check --target "$target" --deny-warn
  moon test --target "$target" --deny-warn
done
node scripts/check-moonbit-api.mjs
node --test scripts/moonbit-environment.test.mjs
```

Use `moon info` to regenerate `.mbti` files and review and commit them when the
public API intentionally changes. The API guard rejects cross-target differences,
modified files and newly untracked interfaces. Its report parser is tested
against the pinned build tool with a real backend-specific signature mismatch;
rerun that test on toolchain upgrades. Keep
host-specific packages separate from the common core rather than weakening its
target checks or narrowing a common-core package's supported targets. The initial
test is only an environment smoke test, not language
conformance. Implementation migration, AoA linkage and distribution packaging
are separate work.

The checks are read-only:

- `check:contracts`: contract pins, requirement ownership and generated registry freshness.
- `check:links`: Markdown local files and anchors, plus JSON syntax.
- `check:examples`: YAML Program fixtures, valid-example root layout, example registration and acceptance-case references.
- `test:docs`: validator regression tests.
- `check:nest`: independent Python lowering and JavaScript identity-preimage checks for the authored nest fixture subset.
- `check:encoding`: kernel manifest pin, fixed scalar spelling expectations and generated encoding-test freshness.
- `check:canonical`: canonical JSON corpus, existing contract CIDs and generated identity-test freshness.
- `check:value-contracts`: fixed contract vectors, generated-test freshness and embedded schema consistency.

Dependencies are pinned in `package-lock.json`. External URL availability is
not part of the deterministic local checks.

Case definitions contain expectations, not execution results. Execution evidence
belongs in separate reports tied to case IDs and the implementation revision.
YAML parsing does not establish ActQL semantic validity. The MoonBit checker and
runtime must verify these same fixtures as implementation becomes available.

## Updating specification metadata

For normative edits, preserve or explicitly assign `requirement-block` IDs.
Run `npm run check:metadata` to inspect added, changed and removed obligations
and document-import pins, then `npm run update:metadata` to apply reviewed
updates. Changed obligations become pending and do not inherit execution evidence.
Review the Git diff and run `npm run check:docs` before committing.

`npm run generate:requirements` regenerates only the combined registry from
owner-local records. It does not approve changed statements or produce evidence.

The metadata updater refreshes owner-local records and document references to
machine bodies. It does not rewrite machine contracts, internal registry
identities or external dependency pins. Those require their contract-specific
generation and identity rules; a matching hash alone is not approval.

`npm run generate:nest` regenerates nest expectations from the independent
reference lowering. Review identity preimages and graph changes before accepting
updated goldens; production output is not their source of truth.

## Versioning

Implementation packages start at `0.0.1` and advance through `0.0.x` during
development. The first formal release is `0.1.0`, after the release scope is
implemented and verified under the [conformance requirements](spec/conformance.md).

Language and machine-contract version identifiers remain independent of package
versions. The implementation targets `actql/0.1`; exact contract contents are
pinned by CID. Changing contract contents changes their CID. Package releases
do not rename contracts or imply compatibility between different pins.
Supported profiles and verification evidence are reported separately.

## Implementation materials

Before algebra implementation, resolve the normative bodies referenced by the
AoA contract: kernel, pipeline, scalar and primitive laws, pipeline registry and
target module contract. The portability/operation-semantics contract and bound
transfer laws also need resolvable bodies. CID pins alone are not those bodies.

For each dependency, record its role, exact version and CID, local path or pinned
retrieval location, hash preimage rule and required profiles. Verify the retrieved
body against its pin before using it; do not infer a replacement from an implementation.
The current document checks do not establish this transitive dependency closure.

The kernel law-name manifest is available locally with its existing CID verified.
See [JSON encoding](design/json-encoding.md) for its exact preimage, resolved scalar
spelling rules and Writer boundaries. `npm run generate:encoding` regenerates
MoonBit tests from fixed vectors; it does not replace expected text with product
output. Run the generated tests on all three targets to verify execution.

[Canonical JSON and CID](design/canonical-json.md) documents the normalization,
ordering, ownership and explicit budget contracts. `npm run generate:canonical`
regenerates identity tests from fixed corpus expectations and existing contract
pins. These tests hash supplied envelopes; they do not validate their domain meaning.

[Structural and scalar decoding helpers](design/decode-foundation.md) define
exact-key checks, primitive readers and their local failure ordering. They do
not replace a text parser, tree admission or caller-owned resource limits.

[JSON source parsing](design/json-source.md) adds strict UTF-8 and String inputs,
normalized values with original source spans, and explicit byte/node/depth limits.
Its tests do not establish YAML, Program or canonical-artifact conformance.

[YAML source parsing](design/yaml-source.md) adds explicit YAML text and byte
entry points with shared `ParseLimits`, normalized values and original spans.
Its structural parsing tests do not establish Program or execution conformance.

[Program and stage structure](design/stage-syntax.md) validates closed envelopes,
ordered predecessors and named cross-stage ports over owned source cursors.
Automatic JSON/YAML selection does not retry semantic or resource failures.
Local operation and type checking remain separate.

[Value contracts](design/value-contracts.md) admits distinct authored and checked
type grammars, expands fixed machine members and implements shared equality,
assignability, nullability join and key-domain compatibility. `generate:value-contracts`
regenerates tests from the fixed contract corpus. This is not Parameter binding,
runtime value admission or whole-Program type checking.

[Owned tree decoding](design/decode-core.md) admits editable Nodes into bounded
opaque cursors, with exact-key checks, source spans and primitive readers.
It preserves raw values; canonical and domain validation remain separate.

Unicode 16.0.0 inputs for NFC, normalization cases and the Unicode license are pinned in
[vendor/unicode/16.0.0/manifest.json](../vendor/unicode/16.0.0/manifest.json).
`npm run check:unicode` verifies the input pins, both committed generated files,
and the generator regression tests without updating implementation files.
Run `python3 scripts/generate-unicode-tables.py` to regenerate the tables and NFC
tests; review the changes before committing. `--verify-inputs` checks only the
inputs, and `--output-dir <directory>` allows isolated generation.

The canonical-value tests separate pure NFC from ActQL's NFC-plus-LF normalization.
Pure NFC covers the listed normalization cases and assigned scalar values outside
Part1, using the pinned UCD ranges rather than the host's Unicode database.
CI runs these tests on JS, Wasm and native. Input verification and generation alone
are not NFC execution conformance. Generated files are excluded from formatting;
their exact contents are checked by the generator. Preserve the Unicode license
in distributions that include the derived tables.

Add foundational packages in dependency order: SHA-256, canonical values,
encoding, canonical JSON, then structural and scalar decoding. Each addition
includes its tests and public interfaces, with JS, Wasm and native checks.
Code dependency isolation does not remove normative dependencies. Before canonical
JSON, resolve the kernel laws for canonical bytes and CID computation, and test
against pinned identities and independent number-spelling vectors. Before
canonical values, derive identity and normalization vectors from the current
specification. Resolve other contracts before their consuming packages; do not
update specification pins merely to match implementation output.

Remaining independent corpora are still implementation inputs to supply.
README operation excerpts need typed fixture contexts before
compiler conformance checks; parsing complete Programs does not validate excerpts.
