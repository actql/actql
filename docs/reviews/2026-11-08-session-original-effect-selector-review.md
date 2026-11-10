# Original Effect fixture target configuration review

This finite current JS input review updates only the existing review entry for
`src/client_local_host/moon.pkg`. Historical reviews, their hashes and the
default review revision remain unchanged.

The immutable descriptor at `70ab00c1fae78c176ac34e65857f7332d6619aa7` is
9793 bytes with SHA-256
`64220f07f198e537a6d9c785fd6abd93a2a3293f3959a24fc313f63135ae1d66`.
Its only change from the previous reviewed descriptor at
`e99acee7bc3ea3a5b0ae3e71ce64aa7c958f2bf4` (9726 bytes, SHA-256
`0974fff42f958477654738b726f07d929aeccd274463404fc86206545fff2f00`)
is the literal JS selector for
`preparation_request_effect_original_js_wbtest.mbt`. Removing exactly that
67-byte clause reconstructs every previous byte. The fixture uses an actual
JS callback; its name does not establish Native or Wasm execution.

The literal `moonbitlang/core/encoding/utf8` whitebox import is already present
in the previous descriptor. It and every other import, alias, target, option
and Native setting are unchanged. No resolver, build hook, package kind or
permissive configuration parser is introduced.

The existing `literal-target-selectors-with-bound-source-membership` rule is
still restricted to JS and toolchain SHA-256
`8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a`
(Moon revision `94521db`). The complete literal import closure, every immediate
source/test member, file mode and byte remain keyed. Previous preimages,
changed imports or selectors, unknown options, foreign targets and foreign
toolchains retain the existing refusal/unresolved behavior.

The map and this review bind source configuration only. They do not promote
old receipts, close runtime boundaries, qualify a compiler or normal package,
establish proof reuse, or replace actual original action and final-consumer
checks. Existing epochs, source-restoration checks and acceptance rules remain
unchanged.
