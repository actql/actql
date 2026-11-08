# Native keyed Plan fixture target configuration review

This finite current JS input review updates only the existing review entry for
`src/client_local_host/moon.pkg`. Historical preimages, their hashes and the
default review revision remain unchanged.

The immutable descriptor at `db039dc07a845fc420be9f95b750fe5208183735` is
9850 bytes with SHA-256
`1ce3256e4f3b1dc32ee5136fcbbe5076fd996ad0a05c901a5cd175a3b16af326`.
Its only change from the previous reviewed descriptor at
`70ab00c1fae78c176ac34e65857f7332d6619aa7` (9793 bytes, SHA-256
`64220f07f198e537a6d9c785fd6abd93a2a3293f3959a24fc313f63135ae1d66`)
is the literal JS selector for `request_native_keyed_plan_js_wbtest.mbt`.
Removing exactly that 57-byte clause reconstructs every previous byte.

The fixture calls the original `registration_parent_fixture` from
`preparation_program_check_source_js_wbtest.mbt`, which is already selected only
on JS. Its authored Native Plan input does not make that Node Request parent
portable to Native or Wasm. This descriptor change adds no dependency, alias,
default, build hook or resolver; all other target and option bytes are exact.

The existing `literal-target-selectors-with-bound-source-membership` rule stays
restricted to JS and toolchain SHA-256
`8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a`
(Moon revision `94521db`). The full literal import closure and immediate
source/test members, bytes and modes remain keyed. Restoring the previous
descriptor, changing the selector, adding another target, changing imports or
options, or selecting a foreign target/toolchain remains refused or unresolved.

This review binds only current Source configuration. It supplies no runtime,
compiler, proof-reuse or normal-package acceptance and promotes no historical
receipt. Existing action prerequisites and source-restoration checks remain.
