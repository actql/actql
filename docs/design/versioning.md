# Versioning and identity consistency

Specifications, machine contracts, identity domains and adopted AoA contracts
owned by this repository are maintained here, not immutable third-party version
assignments. Their current initial contract baseline is **0.1**.
Reference code is useful implementation material but does not override this
repository's specification, identifiers or canonical preimages.

## Version domains

- Owned specification and contract versions describe the adopted semantic or
  wire contract. Use its declared spelling, such as `actql/0.1`, rather than
  introducing a different baseline from reference code.
- Identity-domain and individual law versions identify their specific contracts.
  They are not package versions and do not imply that an implementation conforms.
- Package release versions describe distributable software. A package may use
  `0.0.1` while implementing a `0.1` contract; releasing the package does not
  automatically change the contract, and a contract version does not select a
  package release. Follow the package ecosystem's version syntax.
- External standards, dependencies and toolchains keep the versions actually
  selected for them. Unicode 16.0, YAML 1.2.2, compiler/core pins and dependency
  package versions are not renamed to match our baseline. Upgrade their actual
  contents and applicable pins together when intentionally changing them.

Git commit IDs and theorem names are separate identifiers, not release or
contract version fields. Neither implementation maturity nor a number found in
reference code is sufficient reason to change an owned contract version.

This is the current initial baseline, not a rule that every future incompatible
contract must remain at 0.1. A future change of version requires an explicit
decision, compatibility analysis and coordinated updates of affected checks and
this policy. Evaluate each contract's compatibility independently; do not infer
compatibility or force all version domains to advance in lockstep.

## AoA identifier conventions

Versioned AoA contract identifiers use `/0.1`, including the kernel, pipeline,
RelA scalar and primitive manifests, nested exact-decimal and closed-construction
contracts, and the decimal-value identity domain. Versioned individual AoA law
identifiers use `.v0.1`, for example
`aoa.pipeline.effect-plan.terminal-boundary.v0.1`.

The pipeline IR remains `aoa-pipeline/0.1`. Nested scalar, decimal and
construction contracts follow the same owned baseline.

## Canonical identity

For any contract, a version or law-ID string included in its canonical preimage
affects the CID. Renaming it changes the CID even when the operational rules
are unchanged. Recompute affected identities and their dependent pins instead
of retaining identifiers calculated from a different body. Conversely, a
package release version outside the preimage does not automatically affect it.

Do not preserve reference-implementation CIDs after changing their preimages,
silently accept aliases for former versions, or claim byte/CID equality with
a differently versioned implementation. Align the comparison inputs explicitly.

### AoA dependency bodies

The exact adopted law manifests are available locally:

- [Kernel laws](../../spec/dependencies/aoa-kernel-laws.json)
- [Pipeline laws](../../spec/dependencies/aoa-pipeline-laws.json)
- [RelA scalar laws](../../spec/dependencies/aoa-rela-scalar-laws.json)
- [RelA primitive laws](../../spec/dependencies/aoa-rela-primitive-laws.json)

Their complete canonical JSON bodies hash to the corresponding pins in
[the AoA contract](../../spec/contracts/actql-aoa.json). Version and law-ID strings
are included: renaming either changes the CID even when the operational rules
are unchanged. The decimal-value domain is likewise included in typed value
preimages, so its version affects enclosing Parameter value identities.

Manifest proof labels, theorem names and conformance-case paths describe law
evidence; copying a manifest does not establish that the current MoonBit
implementation passes those cases or supports every operation. Keep those
claims separate from repository test results.

The operation registry and target-module pins are separate bodies; a law-ID
rename does not change them when their bytes are unchanged.

## Change and verification procedure

Update the owned bodies and consuming code together, recompute dependent schema
and registry CIDs, refresh document metadata and generated identity tests, and
verify independent fixed expectations. Never use MoonBit output as the source
of its own expected CID. Run `npm run check:docs`, then format, public-interface
and check/test gates on JS, Wasm and native.

History rewrites require explicit approval; they are not a routine version
update mechanism. Keep recoverable history and coordinate any remote rewrite
separately.

`check:aoa` verifies all four manifest pins, the selected version conventions
throughout source/specification/tooling/fixtures, and the declared Effect law's
membership in the pipeline manifest. Its regression tests reject stale pins,
renamed or missing law bodies, and legacy version strings. The check is part
of `check:docs`; it is dependency/identity verification, not runtime conformance.
This guard is AoA-specific, not a claim to validate every version domain.
Specification-family, schema, metadata and identity-fixture checks cover their
own contracts; package/toolchain checks remain separate. Extend the applicable
checks when adding or changing a versioned surface.
