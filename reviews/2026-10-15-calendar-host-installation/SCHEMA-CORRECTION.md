# Independent closed-object publication schema

The first normal-package Local run at artifact/fixture source abc23e4b passed
all three original series inputs, then failed the full-schema assertion before
bucket JSON row read (run-DsnGzg; Local 3/6, HTTPS unexecuted, complete=false).
The original RC, manifest/digests, consumer/DB/custody and raw failure are kept.
This does not prove bucket publication values or the entire matrix.

The prepared expected schema omitted additional_properties:false. This is a
fixture omission, derived independently from docs/spec/language.md's authored
object normalization and closed 0.1 Object meaning, calendar_typing/check.mbt's
original two-field object_contract, and value_contract/encode.mbt's Object wire
member. No product result is used to generate this expectation. The current
oracle declares only this missing machine member. Historical expected.json and
all original inputs, rows, types, nullability, field order, artifact and limits
remain unchanged.

The existing normal-release consumer permits a clean fixture-only descendant
when the original artifact Source is its ancestor and its runtime/package
inputs have no delta. The prepared recipe now records artifactSource explicitly
as an optional argument; verifyPackageRelease and the consumer's original
ancestry/runtime-delta/digest/clean checks are unchanged. A fresh consumer may
use abc's same four archives after this fixture-only correction. Its evidence
must state artifact source abc separately from current fixture source; it is
not a new-source producer or latest-main product pass. There is no manifest
rewrite, checkout overlay, lookup/replay/resend of the old Run or skipped schema
assertion. Subsequent implementation changes require a new producer.
