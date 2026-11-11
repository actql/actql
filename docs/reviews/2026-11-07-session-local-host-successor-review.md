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

The current successor at `e99acee7bc3ea3a5b0ae3e71ce64aa7c958f2bf4` adds only
`"original_values_text_working_js_wbtest.mbt": [ "js" ]`. Its descriptor SHA256 is
`0974fff42f958477654738b726f07d929aeccd274463404fc86206545fff2f00`.
Removing exactly that clause reconstructs the complete descriptor at
`d3aed5e30374353163fe2beb3f7a8b4f784b2ea9` (SHA256
`508773432a6b071bb057fc41d51008054462a6f8006f862ce6638e91e448d00e`).
The Values fixture already contains an `extern "js"` callback; this clause selects
its actual backend without changing imports, Native options or runtime settings.
The current map accepts only these exact JS/toolchain-scoped bytes. The fixture
and every other immediate package member remain bound as source inputs regardless
of target selection. Earlier descriptors, altered selectors, hooks and foreign
targets/toolchains remain unreviewed; full-source fallback and mandatory proof,
source-restoration and receipt checks are unchanged.

This establishes source/configuration correspondence only. It does not qualify
compiler execution, runtime ABI, resource admission, physical cleanup, Native
behavior or reuse eligibility. The extractor, isolated experiment contract and
acceptance rules are unchanged.
