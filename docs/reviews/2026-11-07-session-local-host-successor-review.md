# Local Host package configuration successor review

This finite JS configuration review updates only `src/client_local_host/moon.pkg`
in the current map. Historical reviews and retained receipts are unchanged.

The reviewed source is `ff880c0fee559efd6d6f2d4fe86a6c229ad86979`.
Its 9,460-byte descriptor has SHA256
`73b0cddc426eb97a56302dc76c8e9438fb113508302532dd29e34157c8186969`.
Removing exactly the literal `capacity_policy` import under `@capacity` and the
JS selectors for `preparation_request_native_document_js_wbtest.mbt` and
`preparation_request_native_intake_js_wbtest.mbt` reconstructs every byte of the
9,285-byte descriptor at `65dd1da4c260610e9a88e430665fdc8f6106bc94`
(SHA256 `8596c0cb5e158a33b98214e9d09a6185dbce3925b3d947def6036ec75bb7dfda`).
All other imports, targets, options and Native settings are identical.

The capacity package has literal imports and target selection, without an external
resolver, build hook, linker setting or package kind. The existing input extractor
retains its complete literal import closure, immediate source/test membership,
file modes and bytes. Both added selectors refer to checked-in JS callback tests;
their Native-oriented names do not constitute Native execution or acceptance.
No listing selector is added: the listing test uses declaration-level JS guards.

The existing `literal-target-selectors-with-bound-source-membership` rule remains
restricted to JS and toolchain SHA256
`8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a`
(Moon revision `94521db`). Unknown bytes, altered aliases/selectors, hooks,
other targets and foreign toolchains remain unreviewed. The old descriptor is
not a current review. The configuration map and review source are action inputs,
so this update requires fresh evidence rather than promoting old receipts.

This establishes source/configuration correspondence only. It does not qualify
compiler execution, runtime ABI, resource admission, physical cleanup, Native
behavior or reuse eligibility. The extractor, isolated experiment contract and
acceptance rules are unchanged.
