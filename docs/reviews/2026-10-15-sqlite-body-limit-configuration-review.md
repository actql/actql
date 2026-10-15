# Exact SQLite body-limit configuration review

Reviewed author Source: `9531187a12e25ec1f23ba9df8a27e53932af5c72`,
a genuine descendant of accepted `b09bd6b0b40b84d1e72fffed0365bca316281bef`.
The sole SQLite manifest delta adds
`"bounded_read_native_wbtest.mbt": [ "native" ]`.
Removing that one literal line restores the complete accepted preimage,
SHA256 `92f1a01552e82ba65b56f680cf82e048505b83625c9c13c9cfb3f202c19d3996`.
The new manifest is mode100644, blob `4f20650e5fb0d496e67ca92a17b9288be66f539b`,
SHA256 `f05438392188f1d1f2c08a6872f25e07c782ec6fbc3b9769c09b155b564face5`.

This exact refresh uses the existing
`literal-native-options-with-bound-source-membership` rule. Imports, supported
targets, the native stub, link settings, hooks and every previous predicate are
unchanged. The new whitebox file is an immediate keyed Git source member, and
all package members and imports remain inputs. The selector excludes its Native
FFI from JS execution; the SQLite JS implementation remains unsupported.

Only this one Native digest and its finite review revision/reference change.
The other seventeen Native digests, the separate JS foreign-library review,
toolchain and parser/validator are unchanged. Wrong path, target, toolchain,
changed import/selector and unknown-option inputs remain unresolved or refused.
No namespace or general package permission is introduced.

The added caller ceiling rejects before the C readback key/body allocation and
returned MoonBytes copy, after existing database/record validation. It does not
bound SQLite's internal row/cache allocation or issue a reservation, permit or
normal funding. Original Native13, JS4, Wasm4, API/type/C-syntax evidence remains
qualified to its actual Source; this configuration review proves none of those
runtime, allocator or physical-retirement properties. New public acceptance0.
