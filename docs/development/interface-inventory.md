# Distributed interface coverage

The inventory is a coverage and review index. Existing normative contracts and
operation owners remain authoritative. A role label, a source digest, or a
reference to a test does not prove semantic correctness or that the test ran.
Actual compiled target and installed product receipts retain their own source
and artifact qualifications.

## Discovery

`distribution-interface-roots.mjs` discovers manifests from the repository's
tracked and nonignored new files, without a fixed product-directory list. Every
export condition, declaration entry and CLI bin is an entrance. The packaging
resolver retains the complete local JavaScript closure before policy checks.
An outside-directory helper is not dropped by the adapter packaging projection.
Bare external dependencies retain the existing package dependency audit.

`python_interface_inventory.py` reads actual wheel members through their normal
RECORD, verifies member digests, and parses every shipped Python module with the
standard AST parser. It never imports product modules. This includes dormant
helpers and modules outside the familiar SDK directory. Source-only discovery
does not qualify an unbuilt wheel, generated executable, or Cloud deployment.

`runtime-package-inputs.mjs` is also consumed by the ordinary runtime builder.
`source-interface-closure.mjs` follows its real compiled inputs, the bundled
Workers entry, local-node source copies and checked Host-manifest assets. Python
assets use the same stdlib AST reader as wheels. Extensionless Node/Python
commands remain code; unknown executables require an explicit artifact binding.

`vite-interface-inventory.mjs` reads the configured production bundler's actual
module/output metadata with writing disabled. It preserves emitted Worker source
assets and their original filenames. A normal workspace library build may be
needed before an application can resolve that library's ordinary export. Bundled
outputs retain their source and digest correspondence rather than becoming a
handwritten list of compiler-private operations. Source closure accepts those
configured output references, checks any existing output digest, and still
requires the normal packaging validators for artifact admission. Neither an
unresolved generated entrance nor a source-only report is installed coverage.

The existing production MoonBit manifest reader distinguishes production from
test and whitebox-test imports. Its closure is reused; test dependencies do not
become production authority merely because they occur in the same manifest.
Existing dispatch, backend, connector-addition, owned-contract, generation and
distribution checks retain their individual policies and actual target tests.

## Owner reference projection

Each owner supplies a projection of existing declarations, rather than another
copy of types, action numbers, state transitions, or permission rules. A module
record has the following fields:

- `module`, `sha256`: the discovered module and reviewed implementation bytes.
- `role`: one of `common-semantics`, `connector-semantics`, `physical-io`,
  `generated-binding`, `public-wire-codec`, `observation-presentation`.
- `owner`: the existing responsible owner.
- `responsibilityFacet`: `primary` for the original functional responsibility,
  or `supplemental` for an additional representation reference. A supplemental
  facet cannot replace a missing primary responsibility.
- `exports`, `operations`: generated syntax inventory, including private helpers.
- `contracts`: explicit groups of operation names and exports with references.

Each contract group explicitly lists `operations` and `exports`. The special
`<module>` operation covers initialization and module-level data. An operation
or export must occur in exactly one group; a module-level reference is not an
implicit contract for every operation in that file. Helpers sharing the same
existing contract may be grouped, with their names enumerated. The ten entries
under `attributes` are:

`responsibility`, `inputsOutputs`, `identity`, `ownership`, `synchronization`,
`failure`, `cancellation`, `resources`, `extension`, `verification`.

Each value is a nonempty array of `{path, anchor}` references into the owner's
existing source, contract, documentation or test. An inapplicable attribute is
instead `{notApplicable: "specific reason"}`. Referenced paths and anchors must
exist. Semantic adequacy, including whether a real owner was exercised, remains
subject to the independent tests and review; an anchor match proves neither.

New modules, exports, helpers and changes within existing functions require an
updated owner projection. Refreshing inventory after a safe extraction or rename
does not change an independent behavior oracle. Never regenerate expected values
or accept Unknown as success to make inventory fresh.

Compiler representation access additionally requires the generated-binding role
and a matching owner-verified generated output digest, generator reference and
read-only freshness reference. A `.generated` filename or comment is not proof.
The caller must execute `interfaceGenerationFreshness(root)`. Only that actual,
immutable result in the same process and for the same source root can qualify
compiler outputs. Omitted, `undefined`, or `null` input supplies no qualification;
serialized sidecar DATA, copied proof records, and generator/freshness references
cannot approve themselves. The reader does not execute commands embedded in
declarations. Existing generated action projections retain their own original
Owner references and actual action-generator freshness.

Module-union `complete` and `primaryComplete` are distinct. Diagnostic
`requireComplete: false` may report an incomplete set. Required admission uses
`requireComplete: true` and refuses either missing registration or missing primary
responsibility, even if a supplemental facet still mentions every module.

## Required normal commands

Run `npm run check:interfaces` for source-side admission from actual package and
Python manifests, the ordinary builder inputs, and configured Vite metadata.
`-- --manifest packages/sdk/package.json` selects an actual manifest and follows
its declared workspace dependencies. This is a source/generation check, not an
installed-product or all-interface completion receipt. A normal library build
must precede a dependent application check when the ordinary export resolves a
compiled library; a stale existing output is refused rather than silently used.

The command requires exact reviewed source hashes, exports, all private
operations, ten-attribute references and primary responsibilities. A newly
reachable helper, new Python distribution, unresolved dependency, stale source,
missing export or operation, and removal of a primary facet are failures of the
ordinary command itself. Safe extraction may update the existing Owner's
projection without changing its independent behavior oracle.

`check:spec`, runtime-package builds and normal npm prepack paths require this
admission. Python's ordinary product-wheel builder and the Native CLI artifact
and release builders select their actual manifests through the same command/API.
These are checkout build-tool requirements, not runtime install hooks for users.
Normal staged release metadata still removes development prepack hooks. Native
binary package staging retains its existing no-lifecycle-script policy.

The Native CLI release builder checks the real staged members before packing,
and normal verification repeats the same correspondence on unpacked members.
Launcher copy bindings come from the ordinary staging inputs; an unexpected
authored helper or changed original body refuses. Native binaries and bundled
libraries stay with the existing artifact/header/local-runtime validators and
their original Source identity. An unchanged authored copy may retain its older
artifact Source only when it also matches the current checked source input;
this is not current-Source Native execution or compiler-provenance evidence.

Runtime-dependent imports are never silently dropped. Lexical single-write
references only provide candidate targets; the existing manifest/builder or
installation Owner must map them to its actual dependency or artifact inventory.
Unknown expressions, shadowed bindings and replaced targets remain unresolved.
This does not prohibit a product's dynamic-loading API or prove its runtime
behavior. Compiled modules stay bound to their compiler and production-source
inputs rather than gaining a handwritten private-operation inventory.

## Verification layers

Coverage controls deliberately add an outside-directory SDK/CLI/helper, a new
export and a private decision helper in an already classified file. They assert
the specific registration or dependency refusal. Compiler-field and old-output
controls assert the generated-binding policy. These are architecture controls,
not public Host execution results.

Action swaps, same-typed argument swaps, omitted scope fields and Unknown outcome
mutations use the relevant owner's real boundary tests. A fixture startup error
does not establish that the intended semantic assertion caught a mutation.
The existing third Compute acceptance remains separate from the independent
Source and Command extension acceptances supplied by the connector owner.
