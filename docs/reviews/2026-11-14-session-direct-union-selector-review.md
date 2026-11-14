# Local Host direct UNION Request selector review

This finite successor covers only `src/client_local_host/moon.pkg` at
`bad3df76f10ae158ab579b33a4b9d1232eee58cf`: 10957 bytes,
SHA-256 `73ce0addad1ed0fee070cd0ae738e91dc2e857c877e14e57951f4de4392cdcfb`.
The complete prior descriptor at
`58ebdec4d074bc3d1f70779eca237f904fa2a47e` remains retained: 10893 bytes,
SHA-256 `c0e298e3407e0d4b966926b7e4054d269a86c74e18ddd5552d5d119370b79695`.

Removing exactly this 64-byte literal selector reconstructs the prior descriptor
byte for byte:

```text
    "preparation_request_direct_union_js_wbtest.mbt": [ "js" ],
```

Imports, aliases, existing target predicates and all other options are unchanged.
The new whitebox test uses the existing local Request/query publication fixtures,
JSON reader and parent Ledger. It checks direct/CTE query preparation, original
Stage/work selection, retained task-sequence bounds, explicit tiny-policy
refusals, repeated entry and callback reentry. Its diagnostic helper renders the
existing typed failure. It adds no import, foreign function, build hook, external
source resolver, installation/state reader or provider operation.

The inspected test at the same revision is
`src/client_local_host/preparation_request_direct_union_js_wbtest.mbt`, SHA-256
`8336c8f54c1737db29e65eac6e569af697f20b580250820378bb1bbc3819d08b`.
This is source/configuration review only. It does not execute those MoonBit
cases, establish a normal Native query result, promote any failed fixture or
qualify the larger preparation implementation.

The existing `literal-target-selectors-with-bound-source-membership` rule remains
restricted to JS and the unchanged pinned toolchain. Only the exact new digest
is current; historical preimages remain bound to their own revisions and do not
qualify this successor. Changed selectors, options, imports, paths, targets and
toolchains remain refused or independently rekeyed. Every immediate source
member, mode, byte and transitive import remains an input. This review adds no
wildcard, permission, runtime acceptance or proof-reuse authorization.
