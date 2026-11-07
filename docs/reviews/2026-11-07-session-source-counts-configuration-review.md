# Source normalization count dependency

This JS configuration review covers `src/source_value/moon.pkg` at
`3ce2057976a7c88a13246a6349fbd7a584d11478`, with SHA-256
`7924497475b1578e83add3ebe773c473b6eba23182ed7c8e9b54ec38ecfba44b`.

Compared with the previously reviewed body at
`523ada3259bf9e8147f746727fbfd56065036fd5`, the complete manifest differs only
by the literal `actql/actql/capacity_arithmetic` import under `@counts`.
The `+js+wasm+native` target declaration and the JS-only selector for
`native_json_js_wbtest.mbt` are unchanged. No package kind, build hook, external
resolver, native stub, linker option or additional file selector is admitted.

The new dependency supplies `checked_nonnegative_add_product` to the existing
native JSON construction-extent calculation. It rejects overflow in the
normalized backing addition. These are numerical checks, not Resource
admission, bounds evidence or permission. The existing `Ref` in the JSON frame
predates this manifest change; this review does not introduce a Ref import or
a new retained owner. `capacity_arithmetic` itself declares the same three
targets and has no further imports or options.

The single current configuration map identifies this exact manifest and
revision. Its previous preimage is not a current review. Historical input
records retain their original identities and are not rewritten.

All transitive package imports and source memberships remain keyed inputs.
Unknown or changed imports, aliases, options, selectors, paths, toolchains and
non-JS review requests retain the existing refusal or unresolved/full-source
fallback. This entry does not open archive reuse by itself: final-consumer,
scientific observation, original receipt and mandatory-action checks still
apply. Matching the manifest digest does not establish compiler, runtime or
physical acceptance.
