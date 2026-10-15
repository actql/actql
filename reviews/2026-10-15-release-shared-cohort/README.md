# Exact normal cohorts from one shared prepack

B owns the minimal producer connection and copy-digest check. G performs the
independent source/prepack/manifest/payload read review. D owns the normal six
Explorer package producer and its installed consumer; B owns its normal four
package consumers. Existing source and exact-cohort consumer checks are not
relaxed. No runtime, language, profile, resource limit or ordinary package
metadata contract changes.

`preparePackageRelease` now uses the existing `packedClientPackage` owner for
its prepack callback. With no shared directory it retains normal npm prepack.
With a selected directory, that owner requires the same clean revision, an
existing named original archive and matching source/copy digests. Failure is
not converted into an independent repack. `stagePackage` and
`verifyPackageRelease` remain the only ordinary staging/verification paths.

The intended physical sequence is: one normal six-package prepack and stage;
independently verify its exact Source, original receipt and complete manifest;
select its immutable development archives; ordinary four-package preparation
copies the common original archives and stages a fresh exact four manifest.
No old manifest is rewritten. Both version selections and common original /
final SHA, integrity, and byte/mode inventories must match. A bare development
manifest alone does not prove the source's normal-prepack provenance.

## Independent counterexamples

The synthetic source runs actual npm prepack for tiny payloads, with a tracked
counter script and an ignored call log. It has no compiler, Host, Source,
Provider, Run or product runtime. Standard preparation also reads the pinned
Moon version for metadata; it does not compile MoonBit.

- `run-GuzwGC` at `004b839bbe044fcac49713df6f7ec3697ba6ef23` failed because the
  synthetic source omitted the recipe file read by normal preparation. This
  fixture setup failure is retained and is not the prepack counterexample.
- `run-GCEpH1` at `8fd1b7e475eaae81974e6045c74cfdb0c4870eb6` reached the actual
  counterexample: six prepack calls became ten when the exact four cohort was
  prepared, despite selecting the same normal shared source.
- `run-D7u0oU` at `b7ef38f1363bd22f542586542f72706ad235048d` executes twenty
  tests: eighteen pass and two fail. The second failure deterministically models
  different destination bytes after a successful copy, without changing the
  expected shared digest or adding a product test hook.

The existing bounded Node wrapper runs the synthetic shared-cohort test and
all packed-client source/copy controls, plus whitespace checking:

```sh
node reviews/2026-10-15-release-shared-cohort/prepared-checks.mjs <clean-sha>
```

Pinned Node22.22.0, outer60 seconds/TERM5, child30 are unchanged. A successful
component run does not prove a real ordinary six/four package producer,
installed Local/HTTPS consumer, Source execution or public E2E. Those remain
separate fixed-cohort evidence.
